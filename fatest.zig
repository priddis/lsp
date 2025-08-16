const std = @import("std");

pub fn main() !void {
    const fan_group = std.os.linux.fanotify_init(.{
        .CLASS = .NOTIF,
        .CLOEXEC = true,
        .NONBLOCK = true,
        .REPORT_NAME = true,
        .REPORT_DIR_FID = true,
        .REPORT_FID = true,
    }, 0);

    const pollfd: std.posix.pollfd = .{
        .fd = @intCast(fan_group),
        .events = std.posix.POLL.IN,
        .revents = undefined,
    };

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
        std.os.linux.AT.FDCWD,
        "/home/micah/testc",
    );
    var buf: [4096]u8 = undefined;
    while (true) {
        buf = std.mem.zeroes([4096]u8);
        std.time.sleep(1_000_000);

        var pollfds = [_]std.posix.pollfd{pollfd};
        const number_of_events = try std.posix.poll(&pollfds, -1);
        std.debug.assert(number_of_events == 1);

        var len = try std.posix.read(pollfd.fd, &buf);
        std.debug.assert(len >= 0);

        const fanotify = std.os.linux.fanotify;

        var meta: [*]align(1) fanotify.event_metadata = @ptrCast(&buf);
        while (len >= @sizeOf(fanotify.event_metadata) and meta[0].event_len >= @sizeOf(fanotify.event_metadata) and meta[0].event_len <= len) : ({
            len -= meta[0].event_len;
            meta = @ptrCast(@as([*]u8, @ptrCast(meta)) + meta[0].event_len);
        }) {
            std.debug.assert(meta[0].vers == fanotify.event_metadata.VERSION);
            if (meta[0].mask.Q_OVERFLOW) {
                std.debug.print("file system watch queue overflowed\n", .{});
                std.debug.panic("queue overflowed", {});
                //TODO, reindex
            }
            const fid: *align(1) fanotify.event_info_fid = @ptrCast(meta + 1);
            switch (fid.hdr.info_type) {
                .DFID_NAME => {
                    const file_handle: *align(1) std.os.linux.file_handle = @ptrCast(&fid.handle);
                    const file_name_z: [*:0]u8 = @ptrCast((&file_handle.f_handle).ptr + file_handle.handle_bytes);
                    const file_name = std.mem.span(file_name_z);
                    std.debug.print("dir {s}\n", .{file_name});
                },
                .FID_NAME => {
                    const file_handle: *align(1) std.os.linux.file_handle = @ptrCast(&fid.handle);
                    const file_name_z: [*:0]u8 = @ptrCast((&file_handle.f_handle).ptr + file_handle.handle_bytes);
                    const file_name = std.mem.span(file_name_z);
                    std.debug.print("{s}\n", .{file_name});
                },
                else => |t| std.debug.print("unexpected fanotify event '{s}'", .{@tagName(t)}),
            }
        }
    }
}
