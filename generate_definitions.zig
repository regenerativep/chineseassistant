const std = @import("std");
const fs = std.fs;
const unicode = std.unicode;
const mem = std.mem;
const assert = std.debug.assert;

const pinyin = @import("src/pinyin.zig");

const ExtraPacked = @import("extrapacked").ExtraPacked;

pub fn nextDelim(text: []const u8, delim: u8, from: usize) ?usize {
    var i = from;
    while (i < text.len) : (i += 1) {
        if (text[i] == delim) return i;
    }
    return null;
}
pub const WordDefinition = struct {
    simplified: []const u8,
    traditional: []const u8,
    pinyin: []const u8,
    definition: []const u8,

    pub fn fromLine(line: []const u8) ?WordDefinition {
        var def: WordDefinition = undefined;
        var nextSpace = nextDelim(line, ' ', 0) orelse return null;
        def.traditional = line[0..nextSpace];
        var start = nextSpace + 1;
        nextSpace = nextDelim(line, ' ', start) orelse return null;
        def.simplified = line[start..nextSpace];
        start = nextSpace + 2;
        assert(line[start - 1] == '[');
        nextSpace = nextDelim(line, ']', start) orelse return null;
        def.pinyin = line[start..nextSpace];
        assert(line[nextSpace + 1] == ' ');
        def.definition = line[(nextSpace + 2)..];
        return def;
    }
};
pub fn trim(text: []const u8) []const u8 {
    return mem.trim(u8, text, &std.ascii.whitespace);
}
pub const DefinitionIterator = struct {
    lines: mem.SplitIterator(u8),

    pub fn next(self: *DefinitionIterator) ?WordDefinition {
        var line: []const u8 = undefined;
        while (true) {
            const test_line = trim(self.lines.next() orelse return null);
            if (test_line[0] != '#') {
                line = test_line;
                break;
            }
        }
        return WordDefinition.fromLine(line);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 16,
    }){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();
    var file = try fs.cwd().openFile("data/cedict_ts.u8", .{});
    defer file.close();
    var file_data = try file.readToEndAlloc(alloc, 3999999999);
    defer alloc.free(file_data);

    var defs = std.ArrayList(WordDefinition).init(alloc);
    defer defs.deinit();
    var iter = DefinitionIterator{
        .lines = mem.split(u8, file_data, "\n"),
    };
    //var ind: usize = 0;
    while (iter.next()) |def| {
        //if (ind > 100) break;
        //ind += 1;
        try defs.append(def);
    }

    //for (defs.items) |def, i| {
    //    std.log.info("def {}: {any}", .{ i, def });
    //}
    var longest: WordDefinition = defs.items[0];
    var longest_len: usize = try std.unicode.utf8CountCodepoints(longest.simplified);
    var longest_byte_len: usize = 0;
    for (defs.items) |def| {
        longest_byte_len = std.math.max(longest_byte_len, def.simplified.len);
        var len: usize = try std.unicode.utf8CountCodepoints(def.simplified);
        if (len > longest_len) {
            longest_len = len;
            longest = def;
        }
    }
    //std.log.info("longest: {}", .{longest_len});

    {
        const target_filename = "src/gen/dict_values.zig";
        var target_file = try fs.cwd().createFile(target_filename, .{});
        defer target_file.close();
        try target_file.writer().print(
            \\pub const LongestSimplifiedCodepointLen = {};
            \\pub const LongestSimplifiedByteLen = {};
            \\pub const DefinitionCount = {};
            \\
        , .{ longest_len, longest_byte_len, defs.items.len });
    }

    var data = std.ArrayList(u8).init(alloc);
    defer data.deinit();
    var buffered_writer = std.io.bufferedWriter(data.writer());
    var writer = buffered_writer.writer();

    for (defs.items) |def| {
        try writer.writeIntLittle(u16, @intCast(u16, def.simplified.len));
        try writer.writeAll(def.simplified);
        try writer.writeIntLittle(u16, @intCast(u16, def.traditional.len));
        try writer.writeAll(def.traditional);
        try writer.writeIntLittle(u16, @intCast(u16, def.definition.len));
        try writer.writeAll(def.definition);
        var pinyin_buf: [50]pinyin.DictionaryPinyin = undefined;
        const chars = try pinyin.readPinyinCharacters(&pinyin_buf, def.pinyin);
        try writer.writeIntLittle(u16, @intCast(u16, chars.len));
        for (chars) |c| {
            const unpacked_c = if (c == .pinyin) pinyin.CharacterOrLength{
                .character = c.pinyin,
            } else pinyin.CharacterOrLength{
                .len = @intCast(u15, c.other.len),
            };
            try writer.writeIntLittle(u16, pinyin.PackedCharacterOrLength.pack(unpacked_c));
            if (c == .other) try writer.writeAll(c.other);
        }
    }
    try buffered_writer.flush();

    {
        const target_filename = "src/gen/words.bin";
        var target_file = try fs.cwd().createFile(target_filename, .{});
        defer target_file.close();
        try target_file.writeAll(data.items);
    }
}
