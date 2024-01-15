const std = @import("std");
const logger = @import("log.zig");
const handler = @import("request_handler.zig");

pub fn main() void {
    while (true) { handler.recv() catch |err| {
            std.log.err("top level err {any}\n", .{err});
            return;
        };
    }
}

pub fn panic(msg: []const u8, trace_opt: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    @setCold(true);
    if (trace_opt) |trace| {
        logger.log("\n{s} \n{any}\n", .{ msg, trace });
        const debug_info = std.debug.getSelfDebugInfo() catch {
            logger.log("no debug info\n", .{});
            unreachable;
        };
        const file: std.fs.File = logger.file.?;
        std.debug.writeStackTrace(trace.*, file.writer(), std.heap.page_allocator, debug_info, .no_color) catch {
            logger.log("error writing stack trace\n", .{});
            unreachable;
        };
    } else {
        logger.log("no stack trace {s}\n", .{msg});
        const debug_info = std.debug.getSelfDebugInfo() catch {
            logger.log("no debug info\n", .{});
            unreachable;
        };
        const file: std.fs.File = logger.file.?;
        std.debug.writeCurrentStackTrace(file.writer(), debug_info, .no_color, addr) catch {
            logger.log("error writing current stack trace\n", .{});
            unreachable;
        };
    }
    std.os.abort();
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

