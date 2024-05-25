const std = @import("std");
const ts_constants = @import("ts_constants.zig");
const Fields = ts_constants.Fields;
const Symbols = ts_constants.Symbols;
const Position = @import("types.zig").Position;

pub extern "c" fn tree_sitter_java() *c.TSLanguage;

pub const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

const import_query_text = "(import_declaration (scoped_identifier) @import)";
const identifier_query_text = "(identifier) @_identifier_";

pub var import_query: *c.TSQuery = undefined;
pub var identifier_query: *c.TSQuery = undefined;
pub var parser: *c.TSParser = undefined;

pub fn init() void {
    var error_type: c.TSQueryError = c.TSQueryErrorNone;
    var err_offset: u32 = 0;

    import_query = c.ts_query_new(tree_sitter_java(), import_query_text, import_query_text.len, &err_offset, &error_type).?;
    std.debug.assert(error_type == c.TSQueryErrorNone);

    identifier_query = c.ts_query_new(tree_sitter_java(), identifier_query_text, identifier_query_text.len, &err_offset, &error_type).?;
    std.debug.assert(error_type == c.TSQueryErrorNone);

    parser = c.ts_parser_new().?;
    _ = c.ts_parser_set_language(parser, tree_sitter_java());
}

pub fn indexToName(tree: *const c.TSTree, text: []const u8, index: usize) ?[]const u8 {
    const root = c.ts_tree_root_node(tree);

    const node = c.ts_node_named_descendant_for_byte_range(root, index, index);
    if (c.ts_node_is_null(node)) {
        return null;
    }

    const a = c.ts_node_start_byte(node);
    const b = c.ts_node_end_byte(node);

    return text[a..b];
}

pub fn pointToName(tree: *const c.TSTree, text: []const u8, row: u32, col: u32) ?[]const u8 {
    const root = c.ts_tree_root_node(tree);
    const point: c.TSPoint = .{ .row = row, .column = col };

    const node = c.ts_node_named_descendant_for_point_range(root, point, point);
    if (c.ts_node_is_null(node)) {
        return null;
    }

    const a = c.ts_node_start_byte(node);
    const b = c.ts_node_end_byte(node);

    return text[a..b];
}

pub fn nodeToName(node: *const c.TSNode, text: []const u8) []const u8 {
    const a = c.ts_node_start_byte(node);
    const b = c.ts_node_end_byte(node);

    return text[a..b];
}

pub fn nodeToPoint(node: c.TSNode) Position {
    const ts_point = c.ts_node_start_point(node);
    return .{ .line = ts_point.row, .character = ts_point.column };
}

pub const SourceType = enum {
    none,
    method,
    class,
    ref,
};

pub fn varOrMethod(node: c.TSNode) SourceType {
    const parent = c.ts_node_parent(node);
    if (c.ts_node_is_null(parent)) {
        return .none;
    }
    const symbol = c.ts_node_symbol(parent);
    if (symbol != Symbols.method_invocation) {
        return .ref;
    }
    const object_node = c.ts_node_child_by_field_id(parent, Fields.object);
    if (c.ts_node_eq(node, object_node)) {
        return .ref;
    }
    return .method;
}

pub fn pointToNode(tree: *const c.TSTree, row: u32, col: u32) ?c.TSNode {
    const root = c.ts_tree_root_node(tree);
    std.debug.assert(!c.ts_node_is_null(root));
    return c.ts_node_named_descendant_for_point_range(root, .{ .row = row, .column = col }, .{ .row = row, .column = col });
}

pub fn nodeToText(node: c.TSNode, text: []const u8) []const u8 {
    std.debug.assert(!c.ts_node_is_null(node));
    const start = c.ts_node_start_byte(node);
    const end = c.ts_node_end_byte(node);
    return text[start..end];
}

test "pointToName" {
    const array_list_code = @embedFile("testcode/ArrayListSmall.java");
    //const array_list_code2 = @embedFile("testcode/ArrayListSmall2.java");
    init();
    const tree_opt = c.ts_parser_parse_string_encoding(parser, null, array_list_code, array_list_code.len, c.TSInputEncodingUTF8);

    const str = pointToName(tree_opt.?, array_list_code, 31, 31);
    try std.testing.expectEqualStrings("elementData", str.?);
}
