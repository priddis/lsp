const std = @import("std");
const logger = @import("../log.zig");
const UnrecoverableError = @import("../errors.zig").UnrecoverableError;
const lsp_messages = @import("lsp_messages.zig");
const lifecycle = @import("lifecycle.zig");
const textdocument = @import("textdocument.zig");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

pub fn recv() UnrecoverableError!void {
    const stdin = std.io.getStdIn();
    const length = try parseLspHeader(allocator, stdin.reader());

    const json_buf = try allocator.alloc(u8, length);
    try stdin.reader().readNoEof(json_buf);

    const parsed_json = std.json.parseFromSlice(lsp_messages.LspRequest, allocator, json_buf[0..length], .{ .allocate = .alloc_always }) catch |err| return logger.throw(
        "Could not parse request {!}",
        .{err},
        UnrecoverableError.CouldNotParseRequest,
    );

    defer parsed_json.deinit();
    const req = parsed_json.value;
    logger.log("request - : {s}\n", .{json_buf[0..length]});

    const stdout = std.io.getStdOut();
    const payload = handle(req) catch @panic("Could not parse parameters");

    if (payload) |res| {
        var buffer: [64]u8 = undefined;
        const prefix = std.fmt.bufPrint(
            &buffer,
            "Content-Length: {d}\r\n\r\n",
            .{res.len},
        ) catch return UnrecoverableError.CouldNotSendResponse;
        logger.log("response - : {s}\n", .{res});
        _ = stdout.write(prefix) catch |err| return logger.throw(
            "Could not send response header {!}",
            .{err},
            UnrecoverableError.CouldNotSendResponse,
        );
        _ = stdout.write(res) catch |err| return logger.throw(
            "Could not send response {!}",
            .{err},
            UnrecoverableError.CouldNotSendResponse,
        );
        allocator.free(res);
    }
}

fn handle(req: lsp_messages.LspRequest) !?[]const u8 {
    const lsp_method = std.meta.stringToEnum(lsp_messages.LspMethod, req.method) orelse {
        logger.log("unrecognized method {s}\n", .{req.method});
        return null;
    };
    logger.log("method = {s}\n", .{req.method});
    const inner_result = switch (lsp_method) {
        //lifecycle
        .initialize => res: {
            const parameters = try parseParameters(lsp_messages.InitializeParams, allocator, req);
            break :res lifecycle.initialize(allocator, parameters);
        },
        .initialized => lifecycle.initialized(),
        .shutdown => lifecycle.shutdown(),
        .exit => lifecycle.exit(),
        //textdocument
        .@"textDocument/didOpen" => res: {
            const parameters = try parseParameters(lsp_messages.DidOpenTextDocumentParams, allocator, req);
            break :res textdocument.didOpen(allocator, parameters);
        },
        .@"textDocument/didChange" => res: {
            const parameters = try parseParameters(lsp_messages.DidChangeTextDocumentParams, allocator, req);
            break :res textdocument.didChange(allocator, parameters);
        },
        .@"textDocument/didClose" => res: {
            const parameters = try parseParameters(lsp_messages.DidCloseTextDocumentParams, allocator, req);
            break :res textdocument.didClose(allocator, parameters);
        },

        .@"textDocument/definition" => res: {
            const parameters = try parseParameters(lsp_messages.DefinitionParams, allocator, req);
            break :res textdocument.definition(parameters);
        },
        .@"textDocument/typeDefinition" => res: {
            const parameters = try parseParameters(lsp_messages.TypeDefinitionParams, allocator, req);
            break :res textdocument.typeDefinition(parameters);
        },
        .@"textDocument/references" => res: {
            const parameters = try parseParameters(lsp_messages.ReferenceParams, allocator, req);
            break :res textdocument.references(allocator, parameters);
        },
    };
    if (inner_result == .none) {
        return null;
    }
    const res = lsp_messages.LspResponse(@TypeOf(inner_result)).build(inner_result, req.id);
    return std.json.stringifyAlloc(allocator, res, .{ .emit_null_optional_fields = false }) catch {
        std.log.err("Error stringifying response {?}\n", .{res});
        return null;
    };
}

const parse_options = .{ .allocate = .alloc_always, .ignore_unknown_fields = true };
fn parseParameters(comptime ParameterType: type, alloc: std.mem.Allocator, req: lsp_messages.LspRequest) !ParameterType {
    return try std.json.innerParseFromValue(ParameterType, alloc, req.params.?, parse_options);
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

test "handle - Initialize" {
    const raw_initialize = try @import("../../testdata/initialize.zig").json();

    const parsed_json = std.json.parseFromSlice(lsp_messages.LspRequest, std.testing.allocator, raw_initialize[0..raw_initialize.len], .{ .allocate = .alloc_always }) catch |err| return logger.throw("Could not parse request {!}", .{err}, UnrecoverableError.CouldNotParseRequest);

    defer parsed_json.deinit();
    const req = parsed_json.value;

    const payload = handle(req) catch @panic("Could not parse parameters");
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

    const payload = handle(req) catch @panic("Could not parse parameters");
    try std.testing.expect(payload == null);
}
