const std = @import("std");
const logger = @import("log.zig");
//const request_handler = @import("lsp/request_handler.zig");
const StringTable = @import("StringTable.zig");
const ts_helpers = @import("ts/helpers.zig");
const Index = @import("Index.zig");
const Class = @import("types.zig").Class;

pub fn main() !void {

    //core.init(std.heap.page_allocator);
    ts_helpers.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    gpa.setRequestedMemoryLimit(1 * 1_000_000_000);
    var argIt = try std.process.argsWithAllocator(gpa.allocator());

    std.debug.assert(argIt.skip());
    if (argIt.next()) |project_dir| {
        var arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer arena.deinit();

        try StringTable.init();
        var clindx = try Index.init(arena.allocator());
        try clindx.indexProject(gpa.allocator(), project_dir);
        //        std.debug.print("Number of classes {d}\n", .{clindx.classes.items.len});
        //        std.debug.print("Capacity of class array {d}\n", .{clindx.classes.capacity});
        //        std.debug.print("Size of each class {d}\n", .{@sizeOf(Class)});
        //        std.debug.print("bytes for class array {d}\n", .{clindx.classes.capacity * @sizeOf(Class)});
        //        std.debug.print("Allocated bytes from arena {d}mb\n", .{arena.queryCapacity() / 1_000_000});
        //        std.debug.print("gpa allocated bytes {d}mb\n", .{gpa.total_requested_bytes / 1_000_000});
        //        std.debug.print("String table size {d}\n", .{StringTable.gpa.total_requested_bytes / 1_000_000});
        //std.debug.print("Allocated bytes from gpa {d}mb\n", .{gpa.total_requested_bytes / 1000000});
        return;
    }

    //while (true) {
    //    request_handler.recv() catch |err| {
    //        std.log.err("top level err {any}\n", .{err});
    //        return;
    //    };
    //}
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
    std.process.exit(1);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
