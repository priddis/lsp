const lsp_messages = @import("lsp_messages.zig");
const std = @import("std");
const logger = @import("log.zig");
const Buffer = @import("buffer.zig").Buffer;
const indexer = @import("indexer.zig");
const core = @import("core.zig");

const parse_options = .{ .allocate = .alloc_always, .ignore_unknown_fields = true};

//Handlers
pub fn didOpen(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.parseFromValue(lsp_messages.DidOpenTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error parsing didOpen params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    const b = Buffer.open(allocator, params.value.textDocument.uri, params.value.textDocument.text) catch |err| {
        logger.log("Encountered {any} while opening\n", .{err});
        return null;
    };
    core.buffers.append(b) catch @panic("Could not add to buffers");
    return null;
}

pub fn didChange(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DidChangeTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error parsing didChange params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    for (params.contentChanges) |contentChanges| {
        switch (contentChanges) {
            .TextDocumentContentChangePartial => @panic("TODO:handle partial change"),
            .TextDocumentContentChangeWholeDocument => |change| {
                if (core.findBuffer(params.textDocument.uri)) |buffer| {
                    buffer.edit(allocator, change.text);
                } else {
                    logger.log("Edit for non-open document. Opening...", .{});
                    const b = Buffer.open(allocator, params.textDocument.uri, change.text) catch |err| {
                        logger.log("Encountered {any} while opening\n", .{err});
                        return null;
                    };
                    core.buffers.append(b) catch @panic("Could not add to buffers");
                }
            }
        }
    }
    return null;
}

pub fn didClose(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DidCloseTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error didClose parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    if (core.findBuffer(params.textDocument.uri)) |buffer| {
        buffer.close(allocator);
    }
    return null;
}

pub fn definition(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DefinitionParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error definition parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };

    const location_opt = core.definition(params.textDocument.uri, params.position.line, params.position.character);
    if (location_opt) |location| {
        const res = lsp_messages.LspResponse(@TypeOf(location)).build(location, req.id);
        return std.json.stringifyAlloc(allocator, res, .{ .emit_null_optional_fields = false }) catch { 
            std.log.err("Error stringifying response {?}\n", .{res});
            return null; 
        };
    } else {
        //TODO: return method not found
        return null;
    }
}

pub fn typeDefinition(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.TypeDefinitionParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error definition parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };

    const location_opt = core.definition(params.textDocument.uri, params.position.line, params.position.character);
    if (location_opt) |location| {
        const res = lsp_messages.LspResponse(@TypeOf(location)).build(location, req.id);
        return std.json.stringifyAlloc(allocator, res, .{ .emit_null_optional_fields = false }) catch { 
            std.log.err("Error stringifying response {?}\n", .{res});
            return null; 
        };
    } else {
        //TODO: return method not found
        return null;
    }
}
