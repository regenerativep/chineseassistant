const std = @import("std");
const fs = std.fs;
const unicode = std.unicode;
const mem = std.mem;
const assert = std.debug.assert;

const pinyin = @import("src/pinyin.zig");

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
    return mem.trim(u8, text, &std.ascii.spaces);
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

    var data = std.ArrayList(u8).init(alloc);
    defer data.deinit();
    var buffered_writer = std.io.bufferedWriter(data.writer());
    var writer = buffered_writer.writer();
    try writer.print(
        \\const std = @import("std");
        \\const pinyin = @import("../pinyin.zig");
        \\const DictionaryPinyin = pinyin.DictionaryPinyin;
        \\
        \\pub const LongestSimplifiedCodepointLen = {};
        \\pub const LongestSimplifiedByteLen = {};
        \\pub const WordDefinition = struct {{
        \\    simplified: []const u8,
        \\    traditional: []const u8,
        \\    pinyin: []const DictionaryPinyin,
        \\    definition: []const u8,
        \\}};
        \\pub const Definitions = [_][]const WordDefinition{{
        \\    &[_]WordDefinition{{
        \\
    , .{ longest_len, longest_byte_len });
    var last_def: ?WordDefinition = null;
    for (defs.items) |def| {
        const same_as_last_def = if (last_def) |last_def_inner| std.mem.eql(u8, last_def_inner.simplified, def.simplified) else true;
        if (!same_as_last_def) {
            try writer.writeAll(
                \\    }, &[_]WordDefinition{
                \\
            );
        }
        try writer.print(
            \\        .{{
            \\            .simplified = "{s}",
            \\            .traditional = "{s}",
            \\            .definition =
            \\                \\{s}
            \\            ,
            \\            .pinyin = &[_]DictionaryPinyin{{
            \\
        , .{ def.simplified, def.traditional, def.definition });
        const chars = try pinyin.readPinyinCharacters(50, def.pinyin);
        for (chars.constSlice()) |c| {
            switch (c) {
                .pinyin => |inner| {
                    const initial_prefix: []const u8 = if (inner.initial != null) "." else "";
                    const initial_text = if (inner.initial) |initial| @tagName(initial) else "null";
                    const proper: []const u8 = if (inner.proper) "true" else "false";
                    try writer.print(
                        \\                .{{ .pinyin = .{{ .proper = {s}, .initial = {s}{s}, .final = .{s}, .tone = {} }} }},
                        \\
                    , .{ proper, initial_prefix, initial_text, @tagName(inner.final), inner.tone });
                },
                .other => |inner| try writer.print(
                    \\                .{{ .other = "{s}" }},
                    \\
                , .{inner}),
            }
        }
        try writer.writeAll(
            \\            },
            \\        },
            \\
        );
        last_def = def;
    }
    try writer.writeAll(
        \\    },
        \\};
        \\
        \\pub fn initMap(alloc: std.mem.Allocator) !std.StringHashMapUnmanaged([]const WordDefinition) {
        \\    var map: std.StringHashMapUnmanaged([]const WordDefinition) = .{};
        \\    for(Definitions) |defs| {
        \\        try map.putNoClobber(alloc, defs[0].simplified, defs);
        \\    }
        \\    return map;
        \\}
        \\
    );

    try buffered_writer.flush();

    const target_filename = "src/gen/words.zig";
    var target_file = try fs.cwd().createFile(target_filename, .{});
    defer target_file.close();
    try target_file.writeAll(data.items);
}
