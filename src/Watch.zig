const std = @import("std");
const fanotify = std.os.linux.fanotify;

var fan_group: i32 = undefined;
var pollfd: std.posix.pollfd = undefined;

pub fn init() void {
    fan_group = @intCast(std.os.linux.fanotify_init(.{
        .CLASS = .NOTIF,
        .CLOEXEC = true,
        .NONBLOCK = true,
        .REPORT_NAME = true,
        .REPORT_DIR_FID = true,
        .REPORT_FID = true,
    }, 0));

    pollfd = .{
        .fd = @intCast(fan_group),
        .events = std.posix.POLL.IN,
        .revents = undefined,
    };
}

pub fn mark(dirfd: i32, dir: ?[*:0]const u8) void {
    _ = std.os.linux.fanotify_mark(
        @intCast(fan_group),
        .{ .ADD = true },
        .{
            .MODIFY = true,
            .CREATE = true,
            .DELETE = true,
            .DELETE_SELF = true,
            .EVENT_ON_CHILD = true,
            .MOVED_FROM = true,
            .MOVED_TO = true,
            .MOVE_SELF = true,
            .ONDIR = true,
        },
        dirfd,
        dir,
    );
}

pub fn onEvent() void { //func: anytype, args: anytype) void {
    while (true) {
        var buf: [4096]u8 = undefined;

        buf = std.mem.zeroes([4096]u8);
        std.time.sleep(1_000_000);

        var pollfds = [_]std.posix.pollfd{pollfd};
        const number_of_events = std.posix.poll(&pollfds, -1) catch |e| {
            std.debug.print("Watch Error {!}\n", .{e});
            continue;
        };
        std.debug.assert(number_of_events == 1);

        var len = std.posix.read(pollfd.fd, &buf) catch |e| {
            std.debug.print("Read err {!}\n", .{e});
            continue;
        };
        std.debug.assert(len >= 0);

        var meta: [*]align(1) fanotify.event_metadata = @ptrCast(&buf);
        while (fan_event_ok(&len, meta[0]))  {
            std.debug.assert(meta[0].vers == fanotify.event_metadata.VERSION);
            if (meta[0].mask.Q_OVERFLOW) {
                std.debug.print("file system watch queue overflowed\n", .{});
            }
            const fid: *align(1) fanotify.event_info_fid = @ptrCast(meta + 1);
            const name = switch (fid.hdr.info_type) {
                .DFID_NAME => blk: {
                    const file_handle: *align(1) std.os.linux.file_handle = @ptrCast(&fid.handle);
                    const file_name_z: [*:0]u8 = @ptrCast((&file_handle.f_handle).ptr + file_handle.handle_bytes);
                    const file_name = std.mem.span(file_name_z);
                    //@call(.auto, func, args);
                    std.debug.print("{s}\n", .{file_name});
                    break :blk file_name;
                },
                else => unreachable, //|t| std.debug.panic("unexpected fanotify event '{s}'", .{@tagName(t)}),
            };
            if (meta[0].mask.ONDIR) {
                std.debug.print("mark dir {s}\n", .{name});
                mark();
            } else {
                std.debug.print("modified file {s}\n", .{name});
            }
        }
    }
}

const event_metadata_len = @sizeOf(std.os.linux.fanotify.event_metadata);

fn fan_event_ok(len: u32, meta: fanotify.event_metadata) bool {
    return len >= event_metadata_len and
        meta.event_len >= event_metadata_len and
        meta.event_len <= len;
}

fn fan_event_next(len: *u32, buf: []u8) fanotify.event_metadata {
    const meta: [*]align(1) fanotify.event_metadata = @ptrCast(buf);
    len.* -= meta.event_len;
    const next_meta: [*]align(1) fanotify.event_metadata = @ptrCast(buf[meta[0].event_len..]);
    return next_meta[0];
}
