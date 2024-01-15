const lsp_messages = @import("lsp_messages.zig");
const std = @import("std");
const logger = @import("log.zig");
const Buffer = @import("buffer.zig").Buffer;
const Indexer = @import("indexer.zig");

const parse_options = .{ .allocate = .alloc_always, .ignore_unknown_fields = true};

var buffers: [5]?Buffer = .{null} ** 5;

pub fn didOpen(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.parseFromValue(lsp_messages.DidOpenTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    //const uri = std.Uri.parse(params.value.textDocument.uri) catch unreachable;
    buffers[0] = Buffer.open(allocator, params.value.textDocument.uri, params.value.textDocument.text) catch |err| {

        logger.log("Encountered {any} while opening\n", .{err});
        return null;
    };
    return null;
}

pub fn didChange(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DidChangeTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    _ = params;
    return null;
}

pub fn didClose(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DidCloseTextDocumentParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    _ = params;
    return null;
}

pub fn definition(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.DefinitionParams, allocator, req.params.?, parse_options) catch {
        logger.log("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    if (buffers[0]) |buf| {
        if (buf.scopedSearch(params.position.line, params.position.character)) |point| {
            const location: lsp_messages.Location = .{ .uri = buf.uri, .range = .{ .start = .{ .line = point.row, .character = point.column}, .end = .{ .line = point.row, .character = point.column} } };
            const res = lsp_messages.LspResponse(@TypeOf(location)).build(location, req.id);
            return std.json.stringifyAlloc(allocator, res, .{ .emit_null_optional_fields = false }) catch { 
                std.log.err("Error stringifying response {?}\n", .{res});
                return null; 
            };
        }
        //if (buf.findName(params.position.line, params.position.character)) |s| {
            //logger.log("found name = {s}\n", .{s});

            //const lookup = null;//Indexer.index_table.method_lookup.get(s);
            //if (lookup) |l| {
                //const location: lsp_messages.Location = .{ .uri = l.uri, .range = .{ .start = .{ .line = l.row, .character = l.column}, .end = .{ .line = l.row, .character = l.column} } };
                //const res = lsp_messages.LspResponse(@TypeOf(location)).build(location, req.id);
                //return std.json.stringifyAlloc(allocator, res, .{ .emit_null_optional_fields = false }) catch { 
                    //std.log.err("Error stringifying response {?}\n", .{res});
                    //return null; 
                //};
            //}

        //}
    }
    return null;
}
