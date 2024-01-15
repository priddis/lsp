const std = @import("std");
const logger = @import("log.zig");
const UnrecoverableError = @import("errors.zig").UnrecoverableError;
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

    const parsed_json = std.json.parseFromSlice(lsp_messages.LspRequest, allocator, json_buf[0..length], .{ .allocate = .alloc_always }) catch |err| return logger.throw("Could not parse request {!}", .{err}, UnrecoverableError.CouldNotParseRequest);
    defer parsed_json.deinit();
    const req = parsed_json.value;
    logger.log("request - : {s}\n", .{json_buf[0..length]});
    const res_option: ?[]const u8 = handle(req);

    const stdout = std.io.getStdOut();
    if (res_option) |res| {
        var buffer: [64]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buffer, "Content-Length: {d}\r\n\r\n", .{res.len}) catch return UnrecoverableError.CouldNotSendResponse;
        logger.log("response - : {s}\n", .{res});
        _ = stdout.write(prefix) catch |err| return logger.throw("Could not send response header {!}", .{err}, UnrecoverableError.CouldNotSendResponse);
        _ = stdout.write(res) catch |err| return logger.throw("Could not send response {!}", .{err}, UnrecoverableError.CouldNotSendResponse);
        allocator.free(res);
    }
}

fn handle(req: lsp_messages.LspRequest) ?[]const u8 {
    const lsp_method = std.meta.stringToEnum(lsp_messages.LspMethod, req.method) orelse {
        logger.log("unrecognized method {s}\n", .{req.method});
        return null;
    };
    logger.log("method = {s}\n", .{req.method});
    return switch (lsp_method) {
        //lifecycle
        .initialize => lifecycle.initialize(allocator, req),
        .initialized => lifecycle.initialized(allocator, req),
        .shutdown => lifecycle.shutdown(allocator, req),
        .exit => lifecycle.exit(allocator, req),

        //textdocument
        .@"textDocument/didOpen" => textdocument.didOpen(allocator, req),
        .@"textDocument/didChange" => textdocument.didChange(allocator, req),
        .@"textDocument/didClose" => textdocument.didClose(allocator, req),

        .@"textDocument/definition" => textdocument.definition(allocator, req),
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
