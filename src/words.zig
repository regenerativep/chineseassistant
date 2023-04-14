const std = @import("std");
const pinyin = @import("pinyin.zig");
const DictionaryPinyin = pinyin.DictionaryPinyin;
const ExtraPacked = @import("extrapacked").ExtraPacked;
const DictValues = @import("gen/dict_values.zig");

pub const LongestSimplifiedCodepointLen = DictValues.LongestSimplifiedCodepointLen;
pub const LongestSimplifiedByteLen = DictValues.LongestSimplifiedByteLen;
pub const DefinitionCount = DictValues.DefinitionCount;

pub const WordDefinition = struct {
    simplified: []const u8,
    traditional: []const u8,
    pinyin: []const DictionaryPinyin,
    definition: []const u8,
};

const data = @embedFile("gen/words.bin");

const StringLL = std.SinglyLinkedList([]const u8);
pub fn reverseLL(ll: *StringLL) void {
    var current_node: ?*StringLL.Node = ll.first;
    var last_node: ?*StringLL.Node = null;
    while (current_node) |node| {
        const next_node = node.next;
        node.next = last_node;
        last_node = node;
        current_node = next_node;
    }
    ll.first = last_node;
}

pub const WordMap = struct {
    inner: std.StringHashMapUnmanaged(StringLL) = .{},

    pub fn init(alloc: std.mem.Allocator) !WordMap {
        var self = WordMap{};
        try self.inner.ensureTotalCapacity(alloc, DefinitionCount);
        errdefer self.deinit(alloc);

        var stream = std.io.fixedBufferStream(data);
        var counting_reader = std.io.countingReader(stream.reader());
        var reader = counting_reader.reader();

        var i: usize = 0;
        while (i < DefinitionCount) : (i += 1) {
            errdefer std.log.info("i: {}", .{i});
            const begin = @intCast(usize, counting_reader.bytes_read);

            const simp_len = try reader.readIntLittle(u16);
            var ind = @intCast(usize, counting_reader.bytes_read);
            errdefer std.log.info("simp len: {}", .{simp_len});
            try reader.skipBytes(simp_len, .{});
            const simp = data[ind .. ind + simp_len];

            const trad_len = try reader.readIntLittle(u16);
            ind = @intCast(usize, counting_reader.bytes_read);
            errdefer std.log.info("trad len: {}", .{trad_len});
            try reader.skipBytes(trad_len, .{});
            const trad = data[ind .. ind + trad_len];

            const def_len = try reader.readIntLittle(u16);
            ind = @intCast(usize, counting_reader.bytes_read);
            errdefer std.log.info("def len: {}", .{def_len});
            try reader.skipBytes(def_len, .{});
            //const def = data[ind .. ind + def_len];

            const pinyin_len = try reader.readIntLittle(u16);
            errdefer std.log.info("pinyin len: {}", .{pinyin_len});
            {
                comptime std.debug.assert(pinyin.PackedCharacterOrLength.PackedType == u16);
                var j = pinyin_len;
                while (j > 0) : (j -= 1) {
                    const packed_data = try reader.readIntLittle(
                        pinyin.PackedCharacterOrLength.PackedType,
                    );
                    const unpacked_data = pinyin.PackedCharacterOrLength.unpack(packed_data);
                    if (unpacked_data == .len) {
                        try reader.skipBytes(unpacked_data.len, .{});
                    }
                }
            }

            const end = @intCast(usize, counting_reader.bytes_read);

            var node_s = try alloc.create(StringLL.Node);
            errdefer alloc.destroy(node_s);

            var res_s = self.inner.getOrPutAssumeCapacity(simp);
            node_s.data = data[begin..end];
            if (!res_s.found_existing) res_s.value_ptr.* = .{};
            res_s.value_ptr.prepend(node_s);

            if (!std.mem.eql(u8, simp, trad)) {
                var node_t = try alloc.create(StringLL.Node);
                var res_t = self.inner.getOrPutAssumeCapacity(trad);
                node_t.data = data[begin..end];
                if (!res_t.found_existing) res_t.value_ptr.* = .{};
                res_t.value_ptr.prepend(node_t);
            }
        }

        // reverse the LLs
        var val_iter = self.inner.valueIterator();
        while (val_iter.next()) |value| reverseLL(value);
        return self;
    }
    pub fn deinit(self: *WordMap, alloc: std.mem.Allocator) void {
        var iter = self.inner.valueIterator();
        while (iter.next()) |val| {
            var current_node = val.first;
            while (current_node) |node| {
                const next_node = node.next;
                alloc.destroy(node);
                current_node = next_node;
            }
        }
        self.inner.deinit(alloc);
    }

    pub const DefinitionIterator = struct {
        inner: ?*StringLL.Node,

        pub fn peek(self: *DefinitionIterator, buf: []pinyin.DictionaryPinyin) !?WordDefinition {
            const node = self.inner orelse return null;
            defer self.inner = node;
            return try self.next(buf);
        }
        pub fn next(self: *DefinitionIterator, buf: []pinyin.DictionaryPinyin) !?WordDefinition {
            const node = self.inner orelse return null;
            const value = node.data;
            self.inner = node.next;

            var stream = std.io.fixedBufferStream(value);
            var counting_reader = std.io.countingReader(stream.reader());
            var reader = counting_reader.reader();

            const simp_len = try reader.readIntLittle(u16);
            var ind = @intCast(usize, counting_reader.bytes_read);
            try reader.skipBytes(simp_len, .{});
            const simp = value[ind .. ind + simp_len];

            const trad_len = try reader.readIntLittle(u16);
            ind = @intCast(usize, counting_reader.bytes_read);
            try reader.skipBytes(trad_len, .{});
            const trad = value[ind .. ind + trad_len];

            const def_len = try reader.readIntLittle(u16);
            ind = @intCast(usize, counting_reader.bytes_read);
            try reader.skipBytes(def_len, .{});
            const def = value[ind .. ind + def_len];

            const pinyin_len = try reader.readIntLittle(u16);
            if (pinyin_len > buf.len) return null; // might want to return an error instead
            var i: u16 = 0;
            while (i < pinyin_len) : (i += 1) {
                const packed_data = try reader.readIntLittle(
                    pinyin.PackedCharacterOrLength.PackedType,
                );
                const unpacked_data = pinyin.PackedCharacterOrLength.unpack(packed_data);
                if (unpacked_data == .len) {
                    const begin = @intCast(usize, counting_reader.bytes_read);
                    try reader.skipBytes(unpacked_data.len, .{});
                    const end = @intCast(usize, counting_reader.bytes_read);
                    buf[i] = .{ .other = value[begin..end] };
                } else {
                    buf[i] = .{ .pinyin = unpacked_data.character };
                }
            }

            return WordDefinition{
                .simplified = simp,
                .traditional = trad,
                .definition = def,
                .pinyin = buf[0..pinyin_len],
            };
        }
    };
    pub fn get(self: *WordMap, word: []const u8) ?DefinitionIterator {
        var ll = self.inner.get(word) orelse return null;
        return DefinitionIterator{ .inner = ll.first };
    }
};
