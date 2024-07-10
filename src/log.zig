const std = @import("std");

pub var file: ?std.fs.File = null;

const scope_level = enum { default };

pub fn log(comptime msg: []const u8, args: anytype) void {
    if (file == null) {
        //TODO, replace path
        file = std.fs.createFileAbsolute("/var/home/mp/code/lsp/err.log", .{ .truncate = true }) catch |er| blk: {
            std.log.err("unable to open log file {!}", .{er});
            break :blk null;
        };
    }
    if (file) |f| {
        std.fmt.format(f.writer(), msg, args) catch |er| {
            std.log.err("unable to write to file err.log {!}\n", .{er});
        };
    }
    std.debug.print(msg, args);
    //std.log.defaultLog(.info, scope_level.default, msg, args);
}

pub fn throw(comptime msg: []const u8, args: anytype, comptime e: anytype) @TypeOf(e) {
    log(msg, args);
    return e;
}
