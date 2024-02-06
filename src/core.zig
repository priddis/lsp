const std = @import("std");
const indexer = @import("indexer.zig");
const lsp_messages = @import("lsp_messages.zig");
const ts_helpers = @import("ts_helpers.zig");
const Tables = indexer.Tables;
const Buffer = @import("buffer.zig").Buffer;

pub var index: Tables = undefined;
pub var buffers: std.ArrayList(Buffer) = undefined; 
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub fn init(alloc: std.mem.Allocator, project_path: []const u8) void {
    buffers = std.ArrayList(Buffer).init(alloc);
    indexer.init();
    index = indexer.indexProject(alloc, project_path) catch @panic("Cannot index project");
}

pub fn definition(uri: []const u8, line: u32, character: u32) ?lsp_messages.Location {
    if (findBuffer(uri)) |buf| {
        if (buf.definition(line, character)) |point| {
            return .{ .uri = buf.uri, .range = .{ .start = .{ .line = point.row, .character = point.column}, .end = .{ .line = point.row, .character = point.column} } };
        }
    }
    return null;
}

pub fn findBuffer(uri: []const u8) ?*Buffer {
    for (buffers.items) |*buf| {
        if (std.mem.eql(u8, buf.uri, uri)) {
            return buf;
        }
    }
    return null;
}

pub fn gotoMethodDeclaration(buf: *const Buffer, row: u32, col: u32) ?c.TSPoint {
    if (ts_helpers.pointToName(buf.tree, buf.text, row, col)) |name| {
        const lookup = index.method_lookup.get(name);
        if (lookup) |l| {
            return .{ .row = l.row, .column = l.column };
        }
    }
    return null;
}

const array_list_code = @embedFile("testcode/ArrayListSmall.java");
const array_list_code2 = @embedFile("testcode/ArrayListSmall2.java");
