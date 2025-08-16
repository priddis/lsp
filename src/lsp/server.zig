const std = @import("std");
const logger = @import("../log.zig");
const UnrecoverableError = @import("../errors.zig").UnrecoverableError;
const lsp_messages = @import("lsp_messages.zig");
const LspRequest = @import("lsp_messages.zig").LspRequest;
const LspResponse = @import("lsp_messages.zig").LspResponse;
const ResponsePayload = lsp_messages.ResponsePayload;

pub fn receive(arena: std.mem.Allocator) !LspRequest {
    const stdin = std.io.getStdIn();
    const length = try parseLspHeader(arena, stdin.reader());

    const json_buf = try arena.alloc(u8, length);
    try stdin.reader().readNoEof(json_buf);

    const parsed_json = try std.json.parseFromSlice(
        LspRequest,
        arena,
        json_buf[0..length],
        .{
            .allocate = .alloc_always,
        },
    );

    return parsed_json.value;
}

pub fn send(payload: []const u8) !void {
    const stdout = std.io.getStdOut();
    var buffer: [64]u8 = undefined;
    const prefix = std.fmt.bufPrint(
        &buffer,
        "Content-Length: {d}\r\n\r\n",
        .{payload.len},
    ) catch return UnrecoverableError.CouldNotSendResponse;
    _ = try stdout.write(prefix);
    _ = try stdout.write(payload);
}

pub fn handle(arena: std.mem.Allocator, req: LspRequest) !?[]const u8 {
    const lsp_method = std.meta.stringToEnum(LspMethod, req.method) orelse {
        return null;
    };
    logger.log("method = {s}\n", .{req.method});

    const result = switch (lsp_method) {
        .initialize => try initialize(arena, req),
        .initialized => initialized(),
        .exit => exit(),
        .shutdown => shutdown(),

        .@"textDocument/definition" => try definition(arena, req),
        .@"textDocument/typeDefinition" => try typeDefinition(arena, req),
        .@"textDocument/references" => try references(arena, req),
    };

    const res = LspResponse(@TypeOf(result)).build(result, req.id);
    return std.json.stringifyAlloc(arena, res, .{ .emit_null_optional_fields = false }) catch {
        std.log.err("Error stringifying response {?}\n", .{res});
        return null;
    };
}

fn parseLspHeader(alloc: std.mem.Allocator, reader: anytype) UnrecoverableError!usize {
    const content_length_line = reader.readUntilDelimiterAlloc(alloc, '\n', 100) catch |err| switch (err) {
        error.StreamTooLong => return logger.throw("Stream exceeded size for content length\n", .{}, UnrecoverableError.CouldNotParseHeader),
        else => return logger.throw("Unknown error {!} \n", .{err}, UnrecoverableError.CouldNotParseHeader),
    };
    defer alloc.free(content_length_line);

    var colon_opt = std.mem.indexOf(u8, content_length_line, ": ");
    if (colon_opt == null) {
        logger.log("No colon found in content length {s}\n", .{content_length_line});
        return UnrecoverableError.CouldNotParseHeader;
    }
    const content_length_key = content_length_line[0..colon_opt.?];
    const content_length_value = content_length_line[content_length_key.len + 2 .. content_length_line.len - 1];
    if (!std.mem.eql(u8, content_length_key, "Content-Length")) {
        logger.log("Key does not contain string  Content-Length {s}\n", .{content_length_line});
        return UnrecoverableError.CouldNotParseHeader;
    }
    const content_length: usize = std.fmt.parseInt(usize, content_length_value, 10) catch {
        logger.log("Error parsing content length from string {s}\n", .{content_length_value});
        return UnrecoverableError.CouldNotParseHeader;
    };

    const type_line = reader.readUntilDelimiterAlloc(alloc, '\n', 100) catch |err| switch (err) {
        error.StreamTooLong => return logger.throw("Stream exceeded size for content length\n", .{}, UnrecoverableError.CouldNotParseHeader),
        else => return logger.throw("Unknown error\n", .{}, UnrecoverableError.CouldNotParseHeader),
    };

    defer alloc.free(type_line);
    if (type_line.len == 0) return UnrecoverableError.CouldNotParseHeader;
    if (type_line.len == 1) return content_length;

    colon_opt = std.mem.indexOf(u8, type_line, ": ");
    const type_key = type_line[0..colon_opt.?];
    const type_value = type_line[content_length_line.len + 2 .. type_line.len - 1];
    if (std.mem.eql(u8, type_key, "Content-Type")) {
        logger.log("type = {any}\n", .{type_value});
    }

    const terminator = reader.readUntilDelimiterAlloc(alloc, '\n', 2) catch |err| switch (err) {
        error.StreamTooLong => return logger.throw("Stream exceeded size for content length\n", .{}, UnrecoverableError.CouldNotParseHeader),
        else => return logger.throw("Unknown error\n", .{}, UnrecoverableError.CouldNotParseHeader),
    };

    defer alloc.free(terminator);
    std.debug.assert(terminator.len == 1);

    return content_length;
}

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
test "test parseHeader" {
    var fbs = std.io.fixedBufferStream("Content-Length: 5443\r\n\r\n");
    var length: usize = try parseLspHeader(std.testing.allocator, fbs.reader());
    try expectEqual(@as(usize, 5443), length);

    fbs = std.io.fixedBufferStream("Content-Length: 6528\r\nContent-Type: application/json; charset=utf-8\r\n\r\n");
    length = try parseLspHeader(std.testing.allocator, fbs.reader());
    try expectEqual(@as(usize, 6528), length);

    fbs = std.io.fixedBufferStream("Content-Length: \r\nContent-Type: application/json; charset=utf-8\r\n\r\n");
    var parse_error = parseLspHeader(std.testing.allocator, fbs.reader());
    try expectError(UnrecoverableError.CouldNotParseHeader, parse_error);

    fbs = std.io.fixedBufferStream("Content-Length 6528\r\nContent-Type: application/json; charset=utf-8\r\n");
    parse_error = parseLspHeader(std.testing.allocator, fbs.reader());
    try expectError(UnrecoverableError.CouldNotParseHeader, parse_error);

    fbs = std.io.fixedBufferStream("Content-Length: 6443\r\n");
    parse_error = parseLspHeader(std.testing.allocator, fbs.reader());
    try expectError(UnrecoverableError.CouldNotParseHeader, parse_error);

    fbs = std.io.fixedBufferStream("Content-Length: 6443\r\n");
    parse_error = parseLspHeader(std.testing.allocator, fbs.reader());
    try expectError(UnrecoverableError.CouldNotParseHeader, parse_error);
}

var testgpa_a = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
var testgpa = testgpa_a.allocator();
test "handle - Initialize" {
    const raw_initialize = try @import("../test/initialize.zig").json();

    const parsed_json = std.json.parseFromSlice(lsp_messages.LspRequest, std.testing.allocator, raw_initialize[0..raw_initialize.len], .{ .allocate = .alloc_always }) catch |err| return logger.throw("Could not parse request {!}", .{err}, UnrecoverableError.CouldNotParseRequest);

    defer parsed_json.deinit();
    const req = parsed_json.value;

    const payload = handle(testgpa, req) catch @panic("Could not parse parameters");
    const expected = "{\"jsonrpc\":\"2.0\",\"result\":{\"init_result\":{\"capabilities\":{\"positionEncoding\":\"utf-8\",\"textDocumentSync\":{\"openClose\":true,\"change\":1},\"definitionProvider\":true,\"typeDefinitionProvider\":true,\"referencesProvider\":true},\"serverInfo\":{\"name\":\"jlava\",\"version\":\"0.1\"}}},\"id\":2}";

    try std.testing.expectEqualStrings(expected, payload.?);
}

test "handle - Initialized" {
    const raw_initialized =
        \\{"jsonrpc":"2.0","method":"initialized","id":3}
    ;

    const parsed_json = std.json.parseFromSlice(lsp_messages.LspRequest, std.testing.allocator, raw_initialized[0..raw_initialized.len], .{ .allocate = .alloc_always }) catch |err| return logger.throw("Could not parse request {!}", .{err}, UnrecoverableError.CouldNotParseRequest);

    defer parsed_json.deinit();
    const req = parsed_json.value;

    const payload = handle(testgpa, req) catch @panic("Could not parse parameters");
    try std.testing.expect(payload == null);
}

const capabilities: lsp_messages.ServerCapabilities =
    .{
    .positionEncoding = .@"utf-8",
    .textDocumentSync = .{ .TextDocumentSyncOptions = .{
        .openClose = false,
        .change = lsp_messages.TextDocumentSyncKind.None,
    } },
    .definitionProvider = .{ .bool = true },
    .typeDefinitionProvider = .{ .bool = true },
    .referencesProvider = .{ .bool = true },
};

const LspMethod = enum {
    initialize,
    initialized,
    shutdown,
    exit,

    // Language features
    @"textDocument/definition",
    @"textDocument/typeDefinition",
    @"textDocument/references",
};

// Lifecycle
pub fn initialize(arena: std.mem.Allocator, req: lsp_messages.LspRequest) !ResponsePayload {
    const params = try std.json.innerParseFromValue(
        lsp_messages.InitializeParams,
        arena,
        req.params.?,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
    const init_result: lsp_messages.InitializeResult = .{
        .serverInfo = .{ .name = "jlava", .version = "0.1" },
        .capabilities = capabilities,
    };

    if (params.rootUri) |uri_string| {
        const uri = std.Uri.parse(uri_string) catch return ResponsePayload{ .err = .{ .code = -2, .message = "Could not parse URI\n" } };
        std.debug.assert(uri.path.percent_encoded.len > 1);
        //index.indexProject(allocator, uri.path.percent_encoded);
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

//Text document

pub fn definition(arena: std.mem.Allocator, req: lsp_messages.LspRequest) !ResponsePayload {
    const params = try std.json.innerParseFromValue(
        lsp_messages.DefinitionParams,
        arena,
        req.params.?,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
    _ = params;
    return ResponsePayload{ .link = undefined };
}

pub fn typeDefinition(arena: std.mem.Allocator, req: lsp_messages.LspRequest) !ResponsePayload {
    const params = try std.json.innerParseFromValue(
        lsp_messages.DefinitionParams,
        arena,
        req.params.?,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
    _ = params;
    return ResponsePayload{ .none = {} };
}
pub fn references(arena: std.mem.Allocator, req: lsp_messages.LspRequest) !ResponsePayload {
    const params = try std.json.innerParseFromValue(
        lsp_messages.ReferenceParams,
        arena,
        req.params.?,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
    _ = params;
    return ResponsePayload{ .references = &.{} };
}
