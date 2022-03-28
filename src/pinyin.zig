const std = @import("std");
const enums = std.enums;

pub const PinyinInitial = enum {
    B,
    P,
    M,
    F,
    D,
    T,
    N,
    L,
    G,
    K,
    H,
    J,
    Q,
    X,
    Zh,
    Ch,
    Sh,
    R,
    Z,
    C,
    S,
    Y,
    W,

    const Self = @This();
    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .B => "b",
            .P => "p",
            .M => "m",
            .F => "f",
            .D => "d",
            .T => "t",
            .N => "n",
            .L => "l",
            .G => "g",
            .K => "k",
            .H => "h",
            .J => "j",
            .Q => "q",
            .X => "x",
            .Zh => "zh",
            .Ch => "ch",
            .Sh => "sh",
            .R => "r",
            .Z => "z",
            .C => "c",
            .S => "s",
            .Y => "y",
            .W => "w",
        };
    }

    pub fn fromText(text: []const u8) ?Self {
        inline for (@typeInfo(Self).Enum.fields) |field| {
            const test_str = field.name;
            if (text.len >= test_str.len and std.ascii.eqlIgnoreCase(test_str, text[0..test_str.len])) {
                return @field(Self, field.name);
            }
        }
        return null;
    }
};

pub const PinyinFinal = enum {
    A,
    O,
    E,
    I,
    U,
    V,
    Ai,
    Ao,
    An,
    Ei,
    En,
    Er,
    Ia,
    Ie,
    Iu,
    In,
    Ou,
    Ua,
    Uo,
    Ui,
    Un,
    Ve,
    Vn,
    Ang,
    Eng,
    Iao,
    Ian,
    Ing,
    Ong,
    Uai,
    Uan,
    Van,
    Iang,
    Iong,
    Uang,
    Ueng,

    const toneless = enums.EnumArray(PinyinFinal, []const u8){ .values = .{
        "a",
        "o",
        "e",
        "i",
        "u",
        "ü",
        "ai",
        "ao",
        "an",
        "ei",
        "en",
        "er",
        "ia",
        "ie",
        "iu",
        "in",
        "ou",
        "ua",
        "uo",
        "ui",
        "un",
        "üe",
        "ün",
        "ang",
        "eng",
        "iao",
        "ian",
        "ing",
        "ong",
        "uai",
        "uan",
        "üan",
        "iang",
        "iong",
        "uang",
        "ueng",
    } };

    const Self = @This();
    pub fn toString(self: Self) []const u8 {
        return toneless.get(self);
    }

    pub fn fromText(text: []const u8) ?Self {
        const fields = @typeInfo(Self).Enum.fields;
        comptime var i = fields.len;
        inline while (i > 0) {
            i -= 1;
            const field = fields[i];
            const test_str = field.name;
            if (text.len >= test_str.len and std.ascii.eqlIgnoreCase(test_str, text[0..test_str.len])) {
                return @field(Self, field.name);
            }
        }
        return null;
    }
};

pub const PinyinCharacter = struct {
    proper: bool,
    initial: ?PinyinInitial,
    final: PinyinFinal,
    tone: u3,

    pub fn write(self: PinyinCharacter, writer: anytype) !void {
        if (self.initial) |initial| {
            try writer.writeAll(initial.toString());
        }
        try writer.writeAll(self.final.toString());
        try writer.writeAll(switch (self.tone) {
            0 => "5",
            1 => "1",
            2 => "2",
            3 => "3",
            4 => "4",
            5 => "5",
            else => unreachable,
        });
    }
    pub fn size(self: PinyinCharacter) usize {
        return (if (self.initial) |initial| initial.toString().len else 0) + self.final.toString().len + 1;
    }
    pub fn toString(self: PinyinCharacter, alloc: std.mem.Allocator) ![]const u8 {
        var text = try alloc.alloc(u8, self.size());
        errdefer alloc.free(text);
        var stream = std.io.fixedBufferStream(text);
        try self.write(stream.writer());
        return text;
    }

    pub fn fromNumberedPinyin(text: []const u8, i: ?*usize) ?PinyinCharacter {
        const initial = PinyinInitial.fromText(text);
        const next_ind = if (initial) |initial_inner| initial_inner.toString().len else 0;
        if (next_ind >= text.len) return null;
        const final = PinyinFinal.fromText(text[next_ind..]) orelse return null;
        var tone_ind = next_ind + final.toString().len;
        const tone: u3 = if (tone_ind >= text.len) 0 else switch (text[tone_ind]) {
            '0' => @as(u3, 0),
            '1' => @as(u3, 1),
            '2' => @as(u3, 2),
            '3' => @as(u3, 3),
            '4' => @as(u3, 4),
            '5' => @as(u3, 0),
            else => blk: {
                tone_ind -= 1;
                break :blk @as(u3, 0);
            },
        };
        if (i) |i_inner| i_inner.* += tone_ind;
        return PinyinCharacter{
            .proper = std.ascii.isUpper(text[0]), // NOTE this will not 100% work for unicode?
            .initial = initial,
            .final = final,
            .tone = tone,
        };
    }
};

pub const DictionaryPinyin = union(enum) {
    pinyin: PinyinCharacter,
    other: []const u8,
};

pub fn readPinyinCharacters(comptime max_chars: usize, text: []const u8) !std.BoundedArray(DictionaryPinyin, max_chars) {
    var chars = std.BoundedArray(DictionaryPinyin, max_chars){};
    var i: usize = 0;
    while (chars.len < chars.buffer.len) {
        while (i < text.len and !std.ascii.isAlNum(text[i])) : (i += 1) {}
        if (i >= text.len) break;
        if (PinyinCharacter.fromNumberedPinyin(text[i..], &i)) |c| {
            chars.appendAssumeCapacity(.{ .pinyin = c });
            i += 1;
        } else {
            // hope that the next pinyin is separated by a space
            // find next space character
            const begin_i = i;
            while (i < text.len and !std.ascii.isSpace(text[i])) : (i += 1) {}
            chars.appendAssumeCapacity(.{ .other = text[begin_i..i] });
        }
    }
    return chars;
}

test "pinyin output" {
    const c = PinyinCharacter{
        .initial = .D,
        .final = .E,
        .tone = 0,
    };
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try c.write(buf.writer());
    try std.testing.expectEqualStrings("de5", buf.items);
}

test "pinyin input" {
    const c = PinyinCharacter.fromNumberedPinyin("yun4", null).?;
    //std.debug.print("{any}\n", .{c});
    try std.testing.expect(std.meta.eql(PinyinCharacter{
        .initial = .Y,
        .final = .Un,
        .tone = 4,
    }, c));
}

test "multiple pinyin characters input" {
    const chars_arr = try readPinyinCharacters(20, "ni3men dou1 bu4xing2 Z");
    const chars = chars_arr.constSlice();
    for (chars) |c| {
        std.debug.print("{any}\n", .{c});
    }
    try std.testing.expectEqual(@as(usize, 6), chars.len);
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{ .initial = .N, .final = .I, .tone = 3 } }, chars[0]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{ .initial = .M, .final = .En, .tone = 0 } }, chars[1]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{ .initial = .D, .final = .Ou, .tone = 1 } }, chars[2]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{ .initial = .B, .final = .U, .tone = 4 } }, chars[3]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{ .initial = .X, .final = .Ing, .tone = 2 } }, chars[4]));
}
