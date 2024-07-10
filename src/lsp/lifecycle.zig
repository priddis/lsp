const std = @import("std");
const lsp_messages = @import("lsp_messages.zig");
const ResponsePayload = lsp_messages.ResponsePayload;
const server_capabilities = @import("server_capabilities.zig");
const logger = @import("../log.zig");
const core = @import("../core.zig");

const state = .{
    .ready1 = false,
    .ready2 = false,
    .shutdown = false,
    .exit = false,
};

const parse_options = .{ .allocate = .alloc_always, .ignore_unknown_fields = true };

pub fn initialize(allocator: std.mem.Allocator, params: lsp_messages.InitializeParams) ResponsePayload {
    logger.log("initialize params {any}\n", .{params});
    const init_result: lsp_messages.InitializeResult = .{ .serverInfo = .{ .name = "jlava", .version = "0.1" }, .capabilities = server_capabilities.capabilities };

    if (params.rootUri) |uri_string| {
        const uri = std.Uri.parse(uri_string) catch return ResponsePayload{ .err = .{ .code = -2, .message = "Could not parse URI\n" } };
        std.debug.assert(uri.path.percent_encoded.len > 1);
        core.indexProject(allocator, uri.path.percent_encoded);
    }

    return ResponsePayload{ .init_result = init_result };
}

pub fn initialized() ResponsePayload {
    return ResponsePayload{ .none = {} };
}

pub fn shutdown() ResponsePayload {
    return ResponsePayload{ .none = {} };
}

pub fn exit() ResponsePayload {
    logger.log("exit server\n", .{});
    std.process.exit(0);
    return ResponsePayload{ .none = {} };
}
