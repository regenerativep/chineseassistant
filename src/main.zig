const std = @import("std");
const unicode = std.unicode;
const math = std.math;
const mem = std.mem;

const pinyin = @import("pinyin.zig");
//const words = @import("gen/words.zig");
const words = @import("words.zig");
const CodepointArrayPeeker = @import("peeker.zig").CodepointArrayPeeker;

extern "buffer" fn write_output_buffer(ptr: [*]const u8, len: usize) void;
extern "buffer" fn clear_output_buffer() void;
extern "buffer" fn add_word(
    char_ptr: [*]const u8,
    char_len: usize,
    pinyin_ptr: [*]const u8,
    pinyin_len: usize,
) void;
extern "buffer" fn add_not_word(ptr: [*]const u8, len: usize) void;
extern "buffer" fn add_def(
    simp_ptr: [*]const u8,
    simp_len: usize,
    trad_ptr: [*]const u8,
    trad_len: usize,
    pinyin_ptr: [*]const u8,
    pinyin_len: usize,
    def_ptr: [*]const u8,
    def_len: usize,
) void;

pub fn writeOutputBuffer(text: []const u8) void {
    write_output_buffer(text.ptr, text.len);
}
pub fn addWord(chars: []const u8, p: []const u8) void {
    add_word(chars.ptr, chars.len, p.ptr, p.len);
}
pub fn addNotWord(text: []const u8) void {
    add_not_word(text.ptr, text.len);
}

pub fn writeOutputBufferVoid(self: void, text: []const u8) OutputBufferWriterError!usize {
    _ = self;
    write_output_buffer(text.ptr, text.len);
    return text.len;
}

const OutputBufferWriterError = error{};
const OutputBufferWriter = std.io.Writer(void, OutputBufferWriterError, writeOutputBufferVoid);

pub const std_options = struct {
    pub const log_level: std.log.Level = .info;

    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const scope_prefix = "(" ++ switch (scope) {
            .default => @tagName(scope),
            else => if (@enumToInt(level) <= @enumToInt(std.log.Level.err))
                @tagName(scope)
            else
                return,
        } ++ "): ";

        const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

        var writer = OutputBufferWriter{ .context = {} };
        nosuspend writer.print(prefix ++ format ++ "<br>", args) catch return;
    }
};

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var alloc: mem.Allocator = undefined;
var dict: words.WordMap = undefined;

var buf: []u8 = &.{};

export fn getBuffer(len: usize) ?[*]u8 {
    if (buf.len < len) {
        buf = alloc.realloc(buf, len) catch return null;
    }
    return buf.ptr;
}

pub fn dictPinyinToString(
    allocator: mem.Allocator,
    pinyins: []const pinyin.DictionaryPinyin,
) ![]const u8 {
    var pinyin_text = std.ArrayList(u8).init(allocator);
    defer pinyin_text.deinit();
    var last: ?pinyin.DictionaryPinyin = null;
    for (pinyins) |def_pinyin| {
        switch (def_pinyin) {
            .pinyin => |inner| {
                if (last != null) switch (last.?) {
                    .other => try pinyin_text.append(' '),
                    .pinyin => |last_inner| if (last_inner.final.isAmbiguous(inner))
                        try pinyin_text.append('\''),
                };
                try inner.writeToned(pinyin_text.writer());
            },
            .other => |inner| {
                if (last != null and last.? != .other) {
                    try pinyin_text.append(' ');
                }
                try pinyin_text.appendSlice(inner);
            },
        }
        last = def_pinyin;
    }
    return pinyin_text.toOwnedSlice();
}

pub fn receiveInputBufferE(text: []const u8) !void {
    var peeker = try CodepointArrayPeeker(
        words.LongestSimplifiedByteLen,
        words.LongestSimplifiedCodepointLen,
    ).init(text);
    while (true) {
        peeker.fill();
        if (peeker.byte_buf.len == 0) break;

        var iter = peeker.variationIterator();
        blk: while (iter.next()) |slice| {
            if (dict.get(slice)) |def_iter_c| {
                var def_iter = def_iter_c;
                // find next non-proper definition, otherwise just use proper def
                var pinyin_buf: [50]pinyin.DictionaryPinyin = undefined;
                while (try def_iter.next(&pinyin_buf)) |def| {
                    // if current is proper and there is another one, then go to the next one
                    if (def_iter.inner != null and
                        def.pinyin[0] == .pinyin and
                        def.pinyin[0].pinyin.proper)
                        continue;

                    // add entire word as word
                    const pinyin_text = try dictPinyinToString(alloc, def.pinyin);
                    defer alloc.free(pinyin_text);
                    //addWord(def.simplified, pinyin_text);
                    addWord(slice, pinyin_text);

                    // remove word from buffer
                    peeker.removeFirstNCodepoints(iter.i + 1);

                    break :blk;
                }
            }
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
}
export fn receiveInputBuffer(ptr: [*]const u8, len: usize) bool {
    receiveInputBufferE(ptr[0..len]) catch |e| {
        std.log.err("error while receiving input buffer: {any}", .{e});
        return false;
    };
    return true;
}

pub fn retrieveDefinitionsE(text: []const u8) !void {
    const cp_len = try std.unicode.utf8CountCodepoints(text);
    var i = cp_len;
    while (i > 0) : (i -= 1) {
        var j: usize = 0;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (j <= cp_len - i) : (j += 1) {
            const sub_text = iter.peek(i);
            if (dict.get(sub_text)) |def_iter_c| {
                var def_iter = def_iter_c;
                var pinyin_buf: [50]pinyin.DictionaryPinyin = undefined;
                while (try def_iter.next(&pinyin_buf)) |def| {
                    const pinyin_text = try dictPinyinToString(alloc, def.pinyin);
                    defer alloc.free(pinyin_text);
                    add_def(
                        def.simplified.ptr,
                        def.simplified.len,
                        def.traditional.ptr,
                        def.traditional.len,
                        pinyin_text.ptr,
                        pinyin_text.len,
                        def.definition.ptr,
                        def.definition.len,
                    );
                }
            }
            _ = iter.nextCodepoint() orelse break;
        }
    }
}
export fn retrieveDefinitions(ptr: [*]const u8, len: usize) bool {
    retrieveDefinitionsE(ptr[0..len]) catch |e| {
        std.log.err("error during definition retrieval: {any}", .{e});
        return false;
    };
    return true;
}

pub fn launch() !void {
    //writeOutputBuffer("hello wrld!..<br>:(");
    gpa = .{};
    alloc = gpa.allocator();
    std.log.info("initializing dictionary", .{});
    dict = try words.WordMap.init(alloc);
    std.log.info("dictionary initialized", .{});
}

export fn launch_export() bool {
    launch() catch |e| {
        std.log.err("error during launch: {any}", .{e});
        return false;
    };
    return true;
}
