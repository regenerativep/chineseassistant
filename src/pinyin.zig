const std = @import("std");
const enums = std.enums;

const ExtraPacked = @import("extrapacked").ExtraPacked;

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
    pub fn toString(self: Self, proper: bool) []const u8 {
        if (proper) {
            return switch (self) {
                .B => "B",
                .P => "P",
                .M => "M",
                .F => "F",
                .D => "D",
                .T => "T",
                .N => "N",
                .L => "L",
                .G => "G",
                .K => "K",
                .H => "H",
                .J => "J",
                .Q => "Q",
                .X => "X",
                .Zh => "Zh",
                .Ch => "Ch",
                .Sh => "Sh",
                .R => "R",
                .Z => "Z",
                .C => "C",
                .S => "S",
                .Y => "Y",
                .W => "W",
            };
        } else {
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
    }

    pub const FromTextResult = struct { proper: bool, self: Self };
    pub fn fromText(text: []const u8) ?FromTextResult {
        // special case for 'r5'
        if (text.len >= 2 and text[0] == 'r' and std.ascii.isDigit(text[1])) return null;
        inline for (@typeInfo(Self).Enum.fields) |field| {
            const test_str = field.name;
            if (text.len >= test_str.len and std.ascii.eqlIgnoreCase(test_str, text[0..test_str.len])) {
                return FromTextResult{ .proper = std.ascii.isUpper(text[0]), .self = @field(Self, field.name) };
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
    Ue,
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
    Ueng, // uhh do we need this one

    pub fn isAmbiguous(f: PinyinFinal, c: PinyinCharacter) bool {
        if (c.initial) |initial| {
            inline for (.{
                .{ .A, .N },
                .{ .E, .N },
                .{ .E, .R },
                .{ .I, .N },
                .{ .U, .N },
                .{ .V, .N },
                .{ .An, .G },
                .{ .En, .G },
                .{ .Ia, .N },
                .{ .In, .G },
                .{ .Ua, .N },
                .{ .Ian, .G },
                .{ .Uan, .G },
            }) |pair| {
                if (initial == pair[1] and f == pair[0]) return true;
            }
        } else {
            inline for (.{
                .{ .A, .I },
                .{ .A, .O },
                .{ .E, .I },
                .{ .I, .A },
                .{ .I, .E },
                .{ .I, .U },
                .{ .O, .U },
                .{ .U, .A },
                .{ .U, .O },
                .{ .U, .I },
                .{ .U, .E },
                .{ .V, .E },
                .{ .Ia, .O },
                .{ .Ua, .I },
            }) |pair| {
                if (c.final == pair[1] and f == pair[0]) return true;
            }
        }
        return false;
    }
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
        "ue",
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
    pub fn tonePosition(self: Self) u8 {
        return switch (self) {
            .A => 0,
            .O => 0,
            .E => 0,
            .I => 0,
            .U => 0,
            .V => 0,
            .Ai => 0,
            .Ao => 0,
            .An => 0,
            .Ei => 0,
            .En => 0,
            .Er => 0,
            .Ia => 1,
            .Ie => 1,
            .Iu => 1,
            .In => 0,
            .Ou => 0,
            .Ua => 1,
            .Uo => 1,
            .Ui => 1,
            .Un => 0,
            .Ue => 1,
            .Ve => 2, // ü is byte len 2
            .Vn => 0,
            .Ang => 0,
            .Eng => 0,
            .Iao => 1,
            .Ian => 1,
            .Ing => 0,
            .Ong => 0,
            .Uai => 1,
            .Uan => 1,
            .Van => 2,
            .Iang => 1,
            .Iong => 1,
            .Uang => 1,
            .Ueng => 1,
        };
    }
    pub fn isFancy(self: Self) bool { // if we need to modify the tone on the ü
        return switch (self) {
            .V, .Vn => true,
            else => false,
        };
    }
    pub fn writeWithTone(self: Self, tone: u3, proper: bool, writer: anytype) !void {
        // TODO: does this really capitalize the first character properly?

        const ind = self.tonePosition();
        const fancy = self.isFancy();
        const text = self.toString();
        try writer.writeAll(text[0..ind]);
        try writer.writeAll(getTone(
            if (fancy) 'u' else text[ind],
            tone,
            ind == 0 and proper,
            fancy,
        ));
        try writer.writeAll(text[ind + if (fancy) @as(u8, 2) else @as(u8, 1) ..]);
    }
    pub fn sizeWithTone(self: Self, tone: u3, proper: bool) usize {
        const ind = self.tonePosition();
        const fancy = self.isFancy();
        const text = self.toString();
        const tone_len = getTone(
            if (fancy) 'u' else text[ind],
            tone,
            ind == 0 and proper,
            fancy,
        ).len;
        return text.len - (if (fancy) 2 else 1) + tone_len;
    }
    const LowercaseFancyToneTable = [5][]const u8{ "ü", "ǘ", "ǘ", "ǚ", "ǜ" };
    const UppercaseFancyToneTable = [5][]const u8{ "Ü", "Ǖ", "Ǘ", "Ǚ", "Ǜ" };
    const LowercaseToneTable = [5][5][]const u8{
        .{ "a", "ā", "á", "ǎ", "à" },
        .{ "e", "ē", "é", "ě", "è" },
        .{ "i", "ī", "í", "ǐ", "ì" },
        .{ "o", "ō", "ó", "ǒ", "ò" },
        .{ "u", "ū", "ú", "ǔ", "ù" },
    };
    const UppercaseToneTable = [5][5][]const u8{
        .{ "A", "Ā", "Á", "Ǎ", "À" },
        .{ "E", "Ē", "É", "Ě", "È" },
        .{ "I", "Ī", "Í", "Ǐ", "Ì" },
        .{ "O", "Ō", "Ó", "Ǒ", "Ò" },
        .{ "U", "Ū", "Ú", "Ǔ", "Ù" },
    };
    pub fn getTone(c: u8, tone: u3, capital: bool, is_fancy: bool) []const u8 {
        const wrapped_tone = if (tone == 5) 0 else tone;
        if (is_fancy) {
            const table = if (capital) UppercaseFancyToneTable else LowercaseFancyToneTable;
            return table[wrapped_tone];
        } else {
            const table = if (capital) UppercaseToneTable else LowercaseToneTable;
            const c_ind = @as(u8, switch (c) {
                'a', 'A' => 0,
                'e', 'E' => 1,
                'i', 'I' => 2,
                'o', 'O' => 3,
                'u', 'U' => 4,
                else => unreachable,
            });
            return table[c_ind][wrapped_tone];
        }
    }
    pub const FromTextResult = struct { proper: bool, self: Self };
    pub fn fromText(text: []const u8) ?FromTextResult {
        const proper = std.ascii.isUpper(text[0]) or (text.len >= 2 and std.mem.eql(u8, text[0..2], "Ü"));
        // special cases for "u:" and "r"
        inline for (.{ // longer ones go first
            .{ "u:an", Self.Van },
            .{ "u:n", Self.Vn },
            .{ "u:e", Self.Ve },
            .{ "u:", Self.V },
            .{ "r", Self.Er },
        }) |pair| {
            if (text.len >= pair[0].len and
                std.ascii.eqlIgnoreCase(pair[0], text[0..pair[0].len]))
            {
                return FromTextResult{ .proper = proper, .self = pair[1] };
            }
        }
        const fields = @typeInfo(Self).Enum.fields;
        comptime var i = fields.len;
        inline while (i > 0) {
            i -= 1;
            const field = fields[i];
            const test_str = field.name;
            if (text.len >= test_str.len and
                std.ascii.eqlIgnoreCase(test_str, text[0..test_str.len]))
            {
                return FromTextResult{ .proper = proper, .self = @field(Self, field.name) };
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

    pub fn writeToned(self: PinyinCharacter, writer: anytype) !void {
        if (self.initial) |initial| {
            try writer.writeAll(initial.toString(self.proper));
        }
        try self.final.writeWithTone(self.tone, self.initial == null and self.proper, writer);
    }
    pub fn sizeToned(self: PinyinCharacter) usize {
        return (if (self.initial) |initial| initial.toString(self.proper).len else 0) +
            self.final.sizeWithTone(self.tone, self.initial == null and self.proper);
    }
    pub fn write(self: PinyinCharacter, writer: anytype) !void {
        if (self.initial) |initial| {
            try writer.writeAll(initial.toString(self.proper));
        }
        try writer.writeAll(self.final.toString(self.initial == null and self.proper));
        try writer.writeAll(switch (self.tone) {
            0, 5 => "5",
            1 => "1",
            2 => "2",
            3 => "3",
            4 => "4",
            else => unreachable,
        });
    }
    pub fn size(self: PinyinCharacter) usize {
        return (if (self.initial) |initial| initial.toString(self.proper).len else 0) +
            self.final.toString(self.initial == null and self.proper).len + 1;
    }
    pub fn toString(self: PinyinCharacter, alloc: std.mem.Allocator) ![]const u8 {
        var text = try alloc.alloc(u8, self.size());
        errdefer alloc.free(text);
        var stream = std.io.fixedBufferStream(text);
        try self.write(stream.writer());
        return text;
    }

    pub fn fromNumberedPinyin(text: []const u8, i: ?*usize) ?PinyinCharacter {
        const initial_res = PinyinInitial.fromText(text);
        const next_ind = if (initial_res) |initial_res_inner|
            initial_res_inner.self.toString(initial_res_inner.proper).len
        else
            0;
        if (next_ind >= text.len) return null;

        const final_res = PinyinFinal.fromText(text[next_ind..]) orelse return null;
        const proper = if (initial_res) |initial_res_inner|
            initial_res_inner.proper
        else
            final_res.proper;

        // find first digit character index
        var tone_ind: usize = 0;
        while (tone_ind < text.len - 1) : (tone_ind += 1) {
            if (std.ascii.isWhitespace(text[tone_ind + 1])) break;
            if (std.ascii.isDigit(text[tone_ind])) break;
        }
        const tone: u3 = switch (text[tone_ind]) {
            //'0', '5' => @as(u3, 0),
            '1' => @as(u3, 1),
            '2' => @as(u3, 2),
            '3' => @as(u3, 3),
            '4' => @as(u3, 4),
            else => @as(u3, 0),
        };
        if (i) |i_inner| i_inner.* += tone_ind;
        return PinyinCharacter{
            .proper = proper,
            .initial = if (initial_res) |inner| inner.self else null,
            .final = final_res.self,
            .tone = tone,
        };
    }
};

pub const DictionaryPinyin = union(enum) {
    pinyin: PinyinCharacter,
    other: []const u8,
};

pub fn readPinyinCharacters(
    buf: []DictionaryPinyin,
    text: []const u8,
) []const DictionaryPinyin {
    var len: usize = 0;
    var i: usize = 0;
    while (len < buf.len) : (len += 1) {
        while (i < text.len and !std.ascii.isAlphanumeric(text[i])) : (i += 1) {}
        if (i >= text.len) break;

        if (PinyinCharacter.fromNumberedPinyin(text[i..], &i)) |c| {
            buf[len] = .{ .pinyin = c };
            i += 1;
        } else {
            // hope that the next pinyin is separated by a space
            // find next space character
            const begin_i = i;
            while (i < text.len and !std.ascii.isWhitespace(text[i])) : (i += 1) {}
            buf[len] = .{ .other = text[begin_i..i] };
        }
    }
    return buf[0..len];
}

test "pinyin output" {
    //{
    //    const c = PinyinCharacter{
    //        .proper = false,
    //        .initial = .D,
    //        .final = .E,
    //        .tone = 0,
    //    };
    //    var buf = std.ArrayList(u8).init(std.testing.allocator);
    //    defer buf.deinit();
    //    try c.write(buf.writer());
    //    try std.testing.expectEqualStrings("de5", buf.items);
    //}
    {
        const c = PinyinCharacter{
            .proper = false,
            .initial = .L,
            .final = .V,
            .tone = 4,
        };
        var buf = std.ArrayList(u8).init(std.testing.allocator);
        defer buf.deinit();
        try c.writeToned(buf.writer());
        try std.testing.expectEqualStrings("lǜ", buf.items);
    }
}

test "pinyin input" {
    {
        const c = PinyinCharacter.fromNumberedPinyin("yun3", null).?;
        try std.testing.expect(std.meta.eql(PinyinCharacter{
            .proper = false,
            .initial = .Y,
            .final = .Un,
            .tone = 3,
        }, c));
    }
    {
        const c = PinyinCharacter.fromNumberedPinyin("lu:e4", null).?;
        std.debug.print("{any}\n", .{c});
        try std.testing.expect(std.meta.eql(PinyinCharacter{
            .proper = false,
            .initial = .L,
            .final = .Ve,
            .tone = 4,
        }, c));
    }
    {
        const c = PinyinCharacter.fromNumberedPinyin("r5", null).?;
        std.debug.print("{any}\n", .{c});
        try std.testing.expect(std.meta.eql(PinyinCharacter{
            .proper = false,
            .initial = null,
            .final = .Er,
            .tone = 0,
        }, c));
    }
}

test "multiple pinyin characters input" {
    var buf: [20]DictionaryPinyin = undefined;
    const chars = try readPinyinCharacters(&buf, "ni3men dou1 bu4xing2 Z");
    for (chars) |c| {
        std.debug.print("{any}\n", .{c});
    }
    try std.testing.expectEqual(@as(usize, 6), chars.len);
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{
        .proper = false,
        .initial = .N,
        .final = .I,
        .tone = 3,
    } }, chars[0]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{
        .proper = false,
        .initial = .M,
        .final = .En,
        .tone = 0,
    } }, chars[1]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{
        .proper = false,
        .initial = .D,
        .final = .Ou,
        .tone = 1,
    } }, chars[2]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{
        .proper = false,
        .initial = .B,
        .final = .U,
        .tone = 4,
    } }, chars[3]));
    try std.testing.expect(std.meta.eql(DictionaryPinyin{ .pinyin = PinyinCharacter{
        .proper = false,
        .initial = .X,
        .final = .Ing,
        .tone = 2,
    } }, chars[4]));
}

pub const CharacterOrLength = union(enum) {
    character: PinyinCharacter,
    len: u15,
};

pub const PackedCharacterOrLength = ExtraPacked(CharacterOrLength);
