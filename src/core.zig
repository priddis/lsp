const std = @import("std");
const indexer = @import("indexer.zig");
const lsp_messages = @import("lsp_messages.zig");
const ts_helpers = @import("ts_helpers.zig");
const core = @import("core.zig");
const Tables = indexer.Tables;
const Buffer = @import("buffer.zig").Buffer;
const Logger = @import("log.zig");
const Symbols = @import("ts_constants.zig").Symbols;
const Fields = @import("ts_constants.zig").Fields;

pub var index: Tables = undefined;
pub var buffers: std.ArrayList(Buffer) = undefined; 
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub fn init(alloc: std.mem.Allocator) void {
    buffers = std.ArrayList(Buffer).init(alloc);
}

pub fn indexProject(alloc: std.mem.Allocator, project_path: []const u8) void {
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
        Logger.log("lookup {s}\n", .{name});
        //const lookup = index.methods.get(name);
        //if (lookup) |l| {
            //return .{ .row = l.row, .column = l.column };
        //}
    }
    return null;
}

///Given a declaration node, returns the type 
pub fn resolveType(node: c.TSNode, text: []const u8) ?[]const u8 {
    const parent = c.ts_node_parent(node);
    if (c.ts_node_is_null(parent)) {
        return null;
    }
    const parent_symbol = c.ts_node_symbol(parent);
    if (parent_symbol == Symbols.formal_parameter) {
        const type_node = c.ts_node_child_by_field_id(parent, Fields.@"type");
        return ts_helpers.nodeToText(type_node, text);
    }
    const grandparent = c.ts_node_parent(parent);
    if (c.ts_node_is_null(grandparent)) {
        return null;
    }
    const grandparent_symbol = c.ts_node_symbol(grandparent);
    if (grandparent_symbol == Symbols.local_variable_declaration or grandparent_symbol == Symbols.field_declaration) {
        const type_node = c.ts_node_child_by_field_id(grandparent, Fields.@"type");
        //TODO: Resolve local variable type inference
        return ts_helpers.nodeToText(type_node, text);
    }
    return null;
}

const array_list_code = @embedFile("testcode/ArrayListSmall.java");

test "resolve type - parameter" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 36, .column = 52  }, .{.row = 36, .column = 52} );

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("int", type_str.?);
}

test "resolve type - field declaration" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 12, .column = 31 }, .{.row = 12, .column = 31 } );

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("long", type_str.?);
}


test "resolve type - local variable declaration" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 37, .column = 17 }, .{.row = 37, .column = 17 } );

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("Object[]", type_str.?);
}


test "resolve type - local variable hashmap" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 61, .column = 23 }, .{.row = 61, .column = 23 } );

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("HashMap", type_str.?);
}
