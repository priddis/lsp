const std = @import("std");
const UnrecoverableError = @import("errors.zig").UnrecoverableError;
const IndexingError = @import("errors.zig").IndexingError;

pub var file: ?std.fs.File = null;

pub fn log(comptime msg: []const u8, args: anytype) void {
    if (file == null) {
        file = std.fs.createFileAbsolute("/home/micah/code/lsp/err.log", .{ .truncate = true }) catch |er| blk: {
            std.log.err("unable to open file {!}", .{er});
            break :blk null;
        };
    }
    if (file) |f| {
        std.fmt.format(f.writer(), msg, args) catch |er| {
            std.log.err("unable to write to file {!}\n", .{er});
        };
    }
}

pub fn throw(comptime msg: []const u8, args: anytype, comptime e: anytype) @TypeOf(e) {
    log(msg, args);
    return e;
}
