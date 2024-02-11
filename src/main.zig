const std = @import("std");
const logger = @import("log.zig");
const request_handler = @import("request_handler.zig");
const ts_helpers = @import("ts_helpers.zig");
const core = @import("core.zig");
const indexer = @import("indexer.zig");

pub fn main() void {
    core.init(std.heap.page_allocator);
    ts_helpers.init();
    while (true) { request_handler.recv() catch |err| {
            std.log.err("top level err {any}\n", .{err});
            return;
        };
    }
}

// Logic for logging errors on panic
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

