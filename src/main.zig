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
extern "buffer" fn request_file(ptr: [*]const u8, len: usize) ?[*]u8;

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

var last_buffer_length: usize = 0;

export fn getBuffer(len: usize) ?[*]u8 {
    var buf = alloc.alloc(u8, len) catch return null;
    last_buffer_length = len;
    return buf.ptr;
}

export fn freeBuffer(ptr: [*]u8, len: usize) void {
    alloc.free(ptr[0..len]);
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

pub fn Rc(comptime T: type) type {
    return struct {
        value: T,
        references: usize = 0,

        pub fn init(val: T) !*@This() {
            var self = try alloc.create(@This());
            self.* = .{ .value = val, .references = 1 };
            return self;
        }

        pub fn clone(self: *@This()) *@This() {
            self.references += 1;
            return self;
        }

        pub fn release(self: *@This()) void {
            self.references -= 1;
            if (self.references == 0) {
                if (@hasDecl(T, "deinit")) {
                    self.value.deinit(alloc);
                }
                alloc.destroy(self);
                self.* = undefined;
            }
        }
    };
}

var custom_dict = std.StringHashMapUnmanaged(
    std.ArrayListUnmanaged(*Rc(words.WordDefinition)),
){};
var defines = std.StringHashMapUnmanaged([]const u8){};

fn freeCustomDict() void {
    {
        var iter = custom_dict.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |def| def.release();
        }
        custom_dict.deinit(alloc);
        custom_dict = .{};
    }
    {
        var iter = defines.iterator();
        while (iter.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        defines.deinit(alloc);
        defines = .{};
    }
}

pub const SplitCmdIterator = struct {
    cmd: []const u8,
    i: usize = 0,

    pub fn next(self: *SplitCmdIterator) ?[]const u8 {
        if (self.i >= self.cmd.len) return null;
        while (self.i < self.cmd.len and std.ascii.isWhitespace(self.cmd[self.i])) {
            self.i += 1;
        }
        if (self.i >= self.cmd.len) return null;

        if (self.cmd[self.i] == '"') {
            var j = self.i + 1;
            var escaped = false;
            for (self.cmd[self.i + 1 ..]) |c| {
                defer j += 1;
                if (c == '"' and !escaped) {
                    break;
                }
                if (c == '\\' and !escaped) {
                    escaped = true;
                } else if (escaped) {
                    escaped = false;
                }
            }
            defer self.i = j;
            if (self.i == j) return null;
            return self.cmd[self.i..j];
        } else {
            const start = self.i;
            while (self.i < self.cmd.len and !std.ascii.isWhitespace(self.cmd[self.i])) {
                self.i += 1;
            }
            if (start == self.i) return null;
            return self.cmd[start..self.i];
        }
    }
};

pub fn parseString(text: []const u8) ![]u8 {
    if (text.len > 0 and text[0] == '"') {
        var parsed = std.ArrayList(u8).init(alloc);
        errdefer parsed.deinit();
        var escaped = false;
        for (text[1..]) |c| {
            if (escaped) {
                try parsed.append(c);
                escaped = false;
            } else {
                if (c == '\\') {
                    escaped = true;
                } else if (c == '"') {
                    break;
                } else {
                    try parsed.append(c);
                }
            }
        }
        return try parsed.toOwnedSlice();
    } else {
        return try alloc.dupe(u8, text);
    }
}

pub const PreprocessState = enum {
    none,
    escape,
    hash,
    cmd,
    cmd_quote,
    cmd_quote_escape,
    cmd_end,

    pub fn feed(
        self: *PreprocessState,
        c: u8,
        text: *std.ArrayList(u8),
        current_cmd: *std.ArrayList(u8),
        comptime depth: comptime_int,
    ) !void {
        var state = self.*;
        defer self.* = state;

        switch (state) {
            .none => switch (c) {
                '\\' => state = .escape,
                '#' => state = .hash,
                else => try text.append(c),
            },
            .escape => {
                try text.append(c);
                state = .none;
            },
            .hash => switch (c) {
                '(' => state = .cmd,
                '\\' => {
                    try text.append('#');
                    state = .escape;
                },
                '#' => {
                    try text.append('#');
                    state = .hash;
                },
                else => {
                    try text.append('#');
                    try text.append(c);
                    state = .none;
                },
            },
            .cmd => switch (c) {
                '"' => {
                    try current_cmd.append(c);
                    state = .cmd_quote;
                },
                ')' => {
                    // execute command
                    var iter = SplitCmdIterator{ .cmd = current_cmd.items };
                    defer {
                        current_cmd.clearRetainingCapacity();
                        state = .cmd_end;
                    }
                    const action = std.meta.stringToEnum(
                        enum { word, define, use, include },
                        iter.next() orelse return,
                    ) orelse return;
                    switch (action) {
                        .word => {
                            const simp_str = iter.next() orelse return;
                            const trad_str = iter.next() orelse return;
                            const pinyin_str = iter.next() orelse return;
                            const def_str = iter.next() orelse return;
                            if (iter.next() != null) return;
                            const simp = try parseString(simp_str);
                            errdefer alloc.free(simp);
                            const trad = try parseString(trad_str);
                            errdefer alloc.free(trad);
                            if (simp.len == 0 and trad.len == 0) return;
                            var pinyin_buf: [words.LongestCodepointLen]pinyin.DictionaryPinyin = undefined;
                            const parsed_pinyin = try alloc.dupe(
                                pinyin.DictionaryPinyin,
                                pinyin.readPinyinCharacters(
                                    &pinyin_buf,
                                    try parseString(pinyin_str),
                                ),
                            );
                            errdefer alloc.free(parsed_pinyin);
                            const def_text = try parseString(def_str);
                            errdefer alloc.free(def_text);
                            const def = try Rc(words.WordDefinition).init(.{
                                .simplified = simp,
                                .traditional = trad,
                                .pinyin = parsed_pinyin,
                                .definition = def_text,
                            });
                            defer def.release();

                            if (simp.len > 0) {
                                var res_s = try custom_dict.getOrPut(alloc, simp);
                                if (!res_s.found_existing) res_s.value_ptr.* = .{};
                                try res_s.value_ptr.append(alloc, def.clone());
                            }
                            if (trad.len > 0 and !mem.eql(u8, simp, trad)) {
                                var res_t = try custom_dict.getOrPut(alloc, trad);
                                if (!res_t.found_existing) res_t.value_ptr.* = .{};
                                try res_t.value_ptr.append(alloc, def.clone());
                            }
                        },
                        .define => {
                            const name_str = iter.next() orelse return;
                            const val_str = iter.next() orelse return;
                            if (iter.next() != null) return;
                            const name = try parseString(name_str);
                            errdefer alloc.free(name);
                            const val = try parseString(val_str);
                            errdefer alloc.free(val);
                            if (try defines.fetchPut(alloc, name, val)) |kv| {
                                alloc.free(kv.key);
                                alloc.free(kv.value);
                            }
                        },
                        .use => {
                            const name_str = iter.next() orelse return;
                            if (iter.next() != null) return;
                            const name = try parseString(name_str);
                            defer alloc.free(name);
                            if (defines.get(name)) |val| {
                                try text.appendSlice(val);
                            }
                        },
                        .include => {
                            const name_str = iter.next() orelse return;
                            if (iter.next() != null) return;
                            const name = try parseString(name_str);
                            defer alloc.free(name);

                            var buf_ptr = request_file(name.ptr, name.len) orelse
                                return;
                            var buf = buf_ptr[0..last_buffer_length];
                            defer alloc.free(buf);
                            var processed_text = try preprocess(buf, depth - 1);
                            defer alloc.free(processed_text);
                            try text.appendSlice(processed_text);
                        },
                    }
                },
                else => try current_cmd.append(c),
            },
            .cmd_quote => switch (c) {
                '\\' => state = .cmd_quote_escape,
                '"' => {
                    try current_cmd.append(c);
                    state = .cmd;
                },
                else => {
                    try current_cmd.append(c);
                },
            },
            .cmd_quote_escape => {
                try current_cmd.append(c);
                state = .cmd_quote;
            },
            .cmd_end => switch (c) {
                '\\' => state = .escape,
                '#' => state = .hash,
                '\n' => state = .none, // idk
                else => {
                    try text.append(c);
                    state = .none;
                },
            },
        }
    }
};

pub fn preprocess(inp_text: []const u8, comptime depth: comptime_int) ![]u8 {
    if (depth == 0) return error.MaxRecursionDepth;

    var text = std.ArrayList(u8).init(alloc);
    errdefer text.deinit();

    var current_cmd = std.ArrayList(u8).init(alloc);
    defer current_cmd.deinit();

    var state = PreprocessState.none;
    for (inp_text) |c| try state.feed(c, &text, &current_cmd, depth);
    try state.feed(' ', &text, &current_cmd, depth);

    return try text.toOwnedSlice();
}

pub fn receiveInputBufferE(unprocessed_text: []const u8) !void {
    freeCustomDict();
    errdefer freeCustomDict();
    var text = try preprocess(unprocessed_text, 10);
    defer alloc.free(text);

    var peeker = try CodepointArrayPeeker(
        words.LongestByteLen,
        words.LongestCodepointLen,
    ).init(text);

    var not_word = std.ArrayList(u8).init(alloc);
    defer not_word.deinit();

    while (true) {
        peeker.fill();
        if (peeker.byte_buf.len == 0) break;

        var iter = peeker.variationIterator();
        blk: while (iter.next()) |slice| {
            if (custom_dict.get(slice)) |arr| if (arr.items.len > 0) {
                const def = arr.items[arr.items.len - 1].value;

                const pinyin_text = try dictPinyinToString(alloc, def.pinyin);
                defer alloc.free(pinyin_text);

                if (not_word.items.len > 0) {
                    addNotWord(not_word.items);
                    not_word.clearRetainingCapacity();
                }
                addWord(slice, pinyin_text);

                peeker.removeFirstNCodepoints(iter.i + 1);

                break :blk;
            };
            if (dict.get(slice)) |def_iter_c| {
                var def_iter = def_iter_c;
                // find next non-proper definition, otherwise just use proper def
                var pinyin_buf: [words.LongestByteLen]pinyin.DictionaryPinyin = undefined;
                while (try def_iter.next(&pinyin_buf)) |def| {
                    // if current is proper and there is another one, then go to the next one
                    if (def_iter.inner != null and
                        def.pinyin[0] == .pinyin and
                        def.pinyin[0].pinyin.proper)
                        continue;

                    // add entire word as word
                    const pinyin_text = try dictPinyinToString(alloc, def.pinyin);
                    defer alloc.free(pinyin_text);

                    if (not_word.items.len > 0) {
                        addNotWord(not_word.items);
                        not_word.clearRetainingCapacity();
                    }
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
                if (not_word.items.len > 0) {
                    addNotWord(not_word.items);
                    not_word.clearRetainingCapacity();
                }
                addNotWord("<br>");
            } else {
                try not_word.appendSlice(codepoint);
                //addNotWord(codepoint);
            }
            // remove first codepoint from buffer
            peeker.removeFirstNCodepoints(1);
        }
    }
    if (not_word.items.len > 0) {
        addNotWord(not_word.items);
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
    var retrieved = std.ArrayList(usize).init(alloc);
    defer retrieved.deinit();
    const cp_len = try std.unicode.utf8CountCodepoints(text);
    var i = cp_len;
    while (i > 0) : (i -= 1) {
        var j: usize = 0;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (j <= cp_len - i) : (j += 1) {
            const sub_text = iter.peek(i);
            if (custom_dict.get(sub_text)) |arr| {
                var k = arr.items.len;
                while (k > 0) {
                    k -= 1;
                    const def_rc = arr.items[k];
                    const def = def_rc.value;

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
            if (dict.get(sub_text)) |def_iter_c| {
                const current_ptr = @ptrToInt(def_iter_c.inner);
                var already_retrieved = false;
                for (retrieved.items) |ptr| {
                    if (ptr == current_ptr) already_retrieved = true;
                }
                if (already_retrieved) continue;
                try retrieved.append(current_ptr);

                var def_iter = def_iter_c;
                var pinyin_buf: [words.LongestByteLen]pinyin.DictionaryPinyin = undefined;
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
