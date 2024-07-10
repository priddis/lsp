const lsp_messages = @import("lsp_messages.zig");
const ResponsePayload = @import("lsp_messages.zig").ResponsePayload;
const std = @import("std");
const logger = @import("../log.zig");
const Buffer = @import("../buffer.zig").Buffer;
const core = @import("../core.zig");

pub fn didOpen(allocator: std.mem.Allocator, params: lsp_messages.DidOpenTextDocumentParams) ResponsePayload {
    const b = Buffer.open(allocator, params.textDocument.uri, params.textDocument.text) catch |err| {
        logger.log("Encountered {any} while opening\n", .{err});
        return ResponsePayload{ .err = .{ .code = -1, .message = "Encountered an error while opening file\n" } };
    };
    core.buffers.append(b) catch @panic("Could not add to buffers");
    return ResponsePayload{ .none = {} };
}

pub fn didChange(allocator: std.mem.Allocator, params: lsp_messages.DidChangeTextDocumentParams) ResponsePayload {
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
                        return ResponsePayload{ .err = .{ .code = -1, .message = "Encountered an error while opening file\n" } };
                    };
                    core.buffers.append(b) catch @panic("Could not add to buffers");
                }
            },
        }
    }
    return ResponsePayload{ .none = {} };
}

pub fn didClose(allocator: std.mem.Allocator, params: lsp_messages.DidCloseTextDocumentParams) ResponsePayload {
    if (core.findBuffer(params.textDocument.uri)) |buffer| {
        buffer.close(allocator);
    }
    return ResponsePayload{ .none = {} };
}

pub fn definition(params: lsp_messages.DefinitionParams) ResponsePayload {
    const location = core.definition(params.textDocument.uri, params.position.line, params.position.character);
    return ResponsePayload{ .link = location };
}

pub fn typeDefinition(params: lsp_messages.TypeDefinitionParams) ResponsePayload {
    if (core.findBuffer(params.textDocument.uri)) |buf| {
        const location = core.gotoTypeDefinition(buf, params.position.line, params.position.character);
        return ResponsePayload{ .link = location };
    }
    return ResponsePayload{ .none = {} };
}

//get node at point
//search text for identifier
//resolve type of each identifier in scope
pub fn references(allocator: std.mem.Allocator, params: lsp_messages.ReferenceParams) ResponsePayload {
    _ = params;
    var buf = [_]u8{0} ** 500000;

    var it = std.fs.openDirAbsolute("TODO, change dir", .{ .iterate = true, .access_sub_paths = true, .no_follow = true }) catch |err| switch (err) {
        else => @panic("Could not open directory"),
    };
    defer it.close();

    var walker = it.walk(allocator) catch |err| switch (err) {
        error.OutOfMemory => @panic("OOM"),
    };
    while (walker.next() catch @panic("Cannot navigate dir")) |entry| {
        if (entry.basename.len > 5) {
            const filetype: []const u8 = entry.basename[entry.basename.len - 5 ..];
            if (entry.kind == .file and std.mem.eql(u8, filetype, ".java")) {
                const source_file: std.fs.File = entry.dir.openFile(entry.basename, .{}) catch |err| switch (err) {
                    error.FileTooBig => continue,
                    error.AccessDenied => continue,
                    error.NoSpaceLeft => unreachable, //Indexing takes no disk space
                    error.SymLinkLoop => unreachable,
                    error.IsDir => unreachable,
                    error.Unexpected => unreachable,
                    else => unreachable,
                };
                defer source_file.close();
                const length: u32 = @intCast(source_file.readAll(&buf) catch @panic("Cannot read file"));
                const text = buf[0..length];
                _ = text;
                //std.mem.lastIndexOf(u8, text, name);
            }
        }
    }
    return ResponsePayload{ .references = &.{} };
}
