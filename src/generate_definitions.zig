const std = @import("std");
const fs = std.fs;
const unicode = std.unicode;
const mem = std.mem;
const assert = std.debug.assert;

const pinyin = @import("pinyin.zig");

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
    lines: mem.SplitIterator(u8, .sequence),

    pub fn next(self: *DefinitionIterator) ?WordDefinition {
        var line: []const u8 = undefined;
        while (true) {
            const test_line = trim(self.lines.next() orelse return null);
            if (test_line.len > 0 and test_line[0] != '#') {
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

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const input_data_path = args[1];
    const output_data_path = args[2];
    const output_values_path = args[3];

    var file = try fs.cwd().openFile(input_data_path, .{});
    defer file.close();
    const file_data = try file.readToEndAlloc(alloc, 3999999999);
    defer alloc.free(file_data);

    var defs = std.ArrayList(WordDefinition).init(alloc);
    defer defs.deinit();
    var iter = DefinitionIterator{
        .lines = mem.splitSequence(u8, file_data, "\n"),
    };
    //var ind: usize = 0;
    while (iter.next()) |def| {
        //if (ind > 100000) break;
        //ind += 1;
        try defs.append(def);
    }

    //for (defs.items) |def, i| {
    //    std.log.info("def {}: {any}", .{ i, def });
    //}
    var longest: WordDefinition = defs.items[0];
    var longest_len: usize = 0; //try std.unicode.utf8CountCodepoints(longest.simplified);
    var longest_byte_len: usize = 0;
    for (defs.items) |def| {
        longest_byte_len = @max(longest_byte_len, @max(
            def.simplified.len,
            def.traditional.len,
        ));
        const len: usize = @max(
            try std.unicode.utf8CountCodepoints(def.simplified),
            try std.unicode.utf8CountCodepoints(def.traditional),
        );
        if (len > longest_len) {
            longest_len = len;
            longest = def;
        }
    }
    //std.log.info("longest: {}", .{longest_len});

    {
        var target_file = try fs.cwd().createFile(output_values_path, .{});
        defer target_file.close();
        try target_file.writer().print(
            \\pub const LongestCodepointLen = {};
            \\pub const LongestByteLen = {};
            \\pub const DefinitionCount = {};
            \\
            \\pub const bin = @embedFile("words.bin");
            \\
        , .{
            longest_len,
            longest_byte_len,
            defs.items.len,
        });
    }

    var data = std.ArrayList(u8).init(alloc);
    defer data.deinit();
    var buffered_writer = std.io.bufferedWriter(data.writer());
    var writer = buffered_writer.writer();

    for (defs.items) |def| {
        try writer.writeInt(u16, @intCast(def.simplified.len), .little);
        try writer.writeAll(def.simplified);
        try writer.writeInt(u16, @intCast(def.traditional.len), .little);
        try writer.writeAll(def.traditional);
        try writer.writeInt(u16, @intCast(def.definition.len), .little);
        try writer.writeAll(def.definition);
        var pinyin_buf: [50]pinyin.DictionaryPinyin = undefined;
        const chars = pinyin.readPinyinCharacters(&pinyin_buf, def.pinyin);
        try writer.writeInt(u16, @intCast(chars.len), .little);
        for (chars) |c| {
            const unpacked_c = if (c == .pinyin) pinyin.CharacterOrLength{
                .character = c.pinyin,
            } else pinyin.CharacterOrLength{
                .len = @intCast(c.other.len),
            };
            try writer.writeInt(
                u16,
                pinyin.PackedCharacterOrLength.pack(unpacked_c),
                .little,
            );
            if (c == .other) try writer.writeAll(c.other);
        }
    }
    try buffered_writer.flush();

    {
        var target_file = try fs.cwd().createFile(output_data_path, .{});
        defer target_file.close();
        try target_file.writeAll(data.items);
    }
}
