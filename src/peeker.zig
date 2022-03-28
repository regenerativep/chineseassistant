const std = @import("std");
const unicode = std.unicode;
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

pub fn CodepointArrayPeeker(comptime max_bytes: usize, comptime max_codepoints: usize) type {
    return struct {
        view: unicode.Utf8View,
        iter: unicode.Utf8Iterator,
        byte_buf: std.BoundedArray(u8, max_bytes),
        codepoint_ends: std.BoundedArray(usize, max_codepoints),

        const Self = @This();
        pub fn init(slice: []const u8) !Self {
            var peeker: Self = .{
                .view = undefined,
                .iter = undefined,
                .byte_buf = .{},
                .codepoint_ends = .{},
            };
            peeker.view = try unicode.Utf8View.init(slice);
            peeker.iter = peeker.view.iterator();
            return peeker;
        }

        pub fn fill(self: *Self) void {
            while (true) {
                var prev_i = self.iter.i;
                if (self.iter.nextCodepointSlice()) |slice| {
                    const codepoint_doesnt_fit = self.byte_buf.buffer.len - self.byte_buf.len < slice.len;
                    const codepoint_ends_no_space = self.codepoint_ends.buffer.len - self.codepoint_ends.len == 0;
                    if (codepoint_doesnt_fit or codepoint_ends_no_space) {
                        self.iter.i = prev_i; // rewind, cannot fit next codepoint
                        break;
                    } else {
                        self.codepoint_ends.appendAssumeCapacity(self.byte_buf.len + slice.len);
                        self.byte_buf.appendSliceAssumeCapacity(slice);
                    }
                } else {
                    break;
                }
            }
        }

        // assumes there exists a codepoint, and that codepoint is valid
        pub fn firstCodepointInBuffer(self: *Self) []const u8 {
            const len = unicode.utf8ByteSequenceLength(self.byte_buf.buffer[0]) catch unreachable;
            return self.byte_buf.buffer[0..len];
        }

        pub fn removeFirstNCodepoints(self: *Self, n: usize) void {
            const bytes_up_to = self.codepoint_ends.buffer[n - 1];
            const new_bytes_len = self.byte_buf.len - bytes_up_to;
            mem.copy(u8, self.byte_buf.buffer[0..new_bytes_len], self.byte_buf.buffer[bytes_up_to..self.byte_buf.len]);
            self.byte_buf.len = new_bytes_len;
            const new_codepoints_len = self.codepoint_ends.len - n;
            mem.copy(usize, self.codepoint_ends.buffer[0..new_codepoints_len], self.codepoint_ends.buffer[n..self.codepoint_ends.len]);
            self.codepoint_ends.len = new_codepoints_len;
            for (self.codepoint_ends.slice()) |*val| {
                val.* -= bytes_up_to;
            }
        }

        pub const VariationIterator = struct {
            peeker: *Self,
            i: usize,

            pub fn next(self: *VariationIterator) ?[]const u8 {
                if (self.i > 0) {
                    self.i -= 1;
                } else {
                    return null;
                }
                return self.peeker.byte_buf.buffer[0..self.peeker.codepoint_ends.get(self.i)];
            }
        };
        pub fn variationIterator(self: *Self) VariationIterator {
            return .{
                .peeker = self,
                .i = self.codepoint_ends.len,
            };
        }
    };
}

test "codepoint peeker" {
    var peeker = try CodepointArrayPeeker(20, 20).init("你们都!不行asd啊");
    while (true) {
        peeker.fill();
        if (peeker.byte_buf.len == 0) {
            break;
        }
        std.debug.print("bytes: {any}\npoints: {any}\n", .{ peeker.byte_buf.slice(), peeker.codepoint_ends.slice() });
        var iter = peeker.variationIterator();
        while (iter.next()) |slice| {
            std.debug.print("{s}\n", .{slice});
        }
        peeker.removeFirstNCodepoints(2);
    }
}
