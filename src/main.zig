const std = @import("std");
const logger = @import("log.zig");
const server = @import("lsp/server.zig");
const receive = server.receive;
const send = server.send;
const handle = server.handle;

const StringTable = @import("StringTable.zig");
const ts_helpers = @import("ts/helpers.zig");
const Index = @import("Index.zig");
const Class = @import("types.zig").Class;
const Watch = @import("Watch.zig");

pub var index: Index = undefined;
pub var mutex: std.Thread.Mutex = .{};

pub fn main() !void {
    ts_helpers.init();
    Watch.init();
    try StringTable.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    gpa.setRequestedMemoryLimit(1 * 1_000_000_000);
    var argIt = try std.process.argsWithAllocator(gpa.allocator());

    std.debug.assert(argIt.skip());
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    index = Index.init(arena.allocator());

    // Cmdline mode
    if (argIt.next()) |project_dir| {
        try index.indexProject(arena.allocator(), project_dir);
        std.debug.print("Number of classes {d}\n", .{index.classes.items.len});
        std.debug.print("Capacity of class array {d}\n", .{index.classes.capacity});
        std.debug.print("Size of each class {d}\n", .{@sizeOf(Class)});
        std.debug.print("bytes for class array {d}\n", .{index.classes.capacity * @sizeOf(Class)});
        std.debug.print("Allocated bytes from arena {d}mb\n", .{arena.queryCapacity() / 1_000_000});
        std.debug.print("gpa allocated bytes {d}mb\n", .{gpa.total_requested_bytes / 1_000_000});
        std.debug.print("String table size {d}\n", .{StringTable.gpa.total_requested_bytes / 1_000_000});
        std.debug.print("Allocated bytes from gpa {d}mb\n", .{gpa.total_requested_bytes / 1000000});
    }

    const watch_thread = try std.Thread.spawn(.{ .allocator = gpa.allocator() }, Watch.onEvent, .{});
    watch_thread.detach();

    //server mode
    while (true) {
        defer _ = arena.reset(.retain_capacity);
        const req = try receive(arena.allocator());
        //TODO This is dumb, lock should be made more granular
        mutex.lock();
        defer mutex.unlock();
        const res = try handle(arena.allocator(), req);
        if (res) |response| {
            try send(response);
        }
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
    std.process.exit(1);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
