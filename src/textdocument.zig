const lsp_messages = @import("lsp_messages.zig");
const std = @import("std");
const logger = @import("log.zig");

const parse_options = .{ .allocate = .alloc_always, .ignore_unknown_fields = true};

pub fn didOpen(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.parseFromValue(lsp_messages.DidOpenTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.err("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    const uri = std.Uri.parse(params.value.textDocument.uri) catch unreachable;
    logger.err("didOpen: {s}\n", .{uri.path});
    return null;
}

pub fn didChange(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DidChangeTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.err("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    _ = params;
    return null;
}

pub fn didClose(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DidCloseTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.err("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    _ = params;
    return null;
}

pub fn definition(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DefinitionParams, allocator, req.params.?, parse_options) catch {
        logger.err("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    _ = params;
    return null;
}
