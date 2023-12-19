const std = @import("std");
const handler = @import("request_handler.zig");

pub fn main() void {
    while (true) {
        handler.recv() catch |err| {
            std.log.err("top level err {any}\n", .{err});
            return;
        };
    }
}

