const std = @import("std");
const unicode = std.unicode;
const math = std.math;
const mem = std.mem;

const pinyin = @import("pinyin.zig");
const words = @import("gen/words.zig");
const CodepointArrayPeeker = @import("peeker.zig").CodepointArrayPeeker;

extern "buffer" fn write_output_buffer(ptr: [*]const u8, len: usize) void;
extern "buffer" fn clear_output_buffer() void;
extern "buffer" fn add_word(simp_ptr: [*]const u8, simp_len: usize, pinyin_ptr: [*]const u8, pinyin_len: usize) void;
extern "buffer" fn add_not_word(ptr: [*]const u8, len: usize) void;
extern "buffer" fn add_def(simp_ptr: [*]const u8, simp_len: usize, pinyin_ptr: [*]const u8, pinyin_len: usize, def_ptr: [*]const u8, def_len: usize) void;

pub fn writeOutputBuffer(text: []const u8) void {
    write_output_buffer(text.ptr, text.len);
}
pub fn addWord(simp: []const u8, p: []const u8) void {
    add_word(simp.ptr, simp.len, p.ptr, p.len);
}
pub fn addNotWord(text: []const u8) void {
    add_not_word(text.ptr, text.len);
}

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var alloc: mem.Allocator = undefined;
var dict: std.StringHashMapUnmanaged([]const words.WordDefinition) = undefined;

pub fn dictPinyinToString(allocator: mem.Allocator, pinyins: []const pinyin.DictionaryPinyin) ![]const u8 {
    var pinyin_text = std.ArrayList(u8).init(allocator);
    defer pinyin_text.deinit();
    var last_is_other = false;
    var first = true;
    for (pinyins) |def_pinyin| {
        switch (def_pinyin) {
            .pinyin => |inner| {
                if (last_is_other and !first) {
                    try pinyin_text.append(' ');
                }
                try inner.write(pinyin_text.writer());
            },
            .other => |inner| {
                if (!last_is_other and !first) {
                    try pinyin_text.append(' ');
                }
                try pinyin_text.appendSlice(inner);
            },
        }
        first = false;
    }
    return pinyin_text.toOwnedSlice();
}

export fn receiveInputBuffer(ptr: [*]const u8, len: usize) bool {
    const text = ptr[0..len];

    var peeker = CodepointArrayPeeker(words.LongestSimplifiedByteLen, words.LongestSimplifiedCodepointLen).init(text) catch return false;
    while (true) {
        peeker.fill();
        if (peeker.byte_buf.len == 0) {
            break;
        }
        var largest_def: ?words.WordDefinition = null;
        var iter = peeker.variationIterator();
        while (iter.next()) |slice| {
            if (dict.get(slice)) |defs| {
                // find the first non-proper definition, otherwise just use proper def
                largest_def = defs[0];
                for (defs) |def| {
                    if (def.pinyin[0] == .pinyin and !def.pinyin[0].pinyin.proper) {
                        largest_def = def;
                        break;
                    }
                }
                break;
            }
        }
        if (largest_def) |def| {
            // add entire word as word
            const pinyin_text = dictPinyinToString(alloc, def.pinyin) catch return false;
            defer alloc.free(pinyin_text);
            addWord(def.simplified, pinyin_text);
            // remove word from buffer
            peeker.removeFirstNCodepoints(iter.i + 1);
        } else {
            // add first codepoint as non-word
            const codepoint = peeker.firstCodepointInBuffer();
            if (codepoint[0] == '\n') {
                addNotWord("<br>");
            } else {
                addNotWord(codepoint);
            }
            // remove first codepoint from buffer
            peeker.removeFirstNCodepoints(1);
        }
    }
    return true;
}

export fn retrieveDefinitions(ptr: [*]const u8, len: usize) void {
    if (dict.get(ptr[0..len])) |defs| {
        for (defs) |def| {
            const pinyin_text = dictPinyinToString(alloc, def.pinyin) catch continue;
            defer alloc.free(pinyin_text);
            add_def(def.simplified.ptr, def.simplified.len, pinyin_text.ptr, pinyin_text.len, def.definition.ptr, def.definition.len);
        }
    }
}

pub fn launch() !void {
    //writeOutputBuffer("hello wrld!..<br>:(");
    gpa = .{};
    alloc = gpa.allocator();
    dict = try words.initMap(alloc);
}

export fn launch_export() bool {
    return !std.meta.isError(launch());
}
