const std = @import("std");
const ts = @import("ts_constants.zig");
const ts_fields = ts.Fields;
const ts_symbols = ts.Symbols;
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
const Buffer = @import("buffer.zig").Buffer;
pub extern "c" fn tree_sitter_java() *c.TSLanguage;

const import_query_text = "(import_declaration (scoped_identifier) @import)";
const identifier_query_text = "(identifier) @_identifier_";

pub var import_query: *c.TSQuery = undefined; 
pub var identifier_query: *c.TSQuery = undefined; 
pub var parser: *c.TSParser = undefined;

pub fn init() void {
    //c.ts_set_allocator(malloc, null, null, free);
    var error_type: c.TSQueryError = c.TSQueryErrorNone;
    var err_offset: u32 = 0;

    import_query = c.ts_query_new(tree_sitter_java(), import_query_text, import_query_text.len, &err_offset, &error_type).?;
    std.debug.assert(error_type == c.TSQueryErrorNone);

    identifier_query = c.ts_query_new(tree_sitter_java(), identifier_query_text, identifier_query_text.len, &err_offset, &error_type).?;
    std.debug.assert(error_type == c.TSQueryErrorNone);

    parser = c.ts_parser_new().?;
    _ = c.ts_parser_set_language(parser, tree_sitter_java());
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

pub const SourceType = enum {
    none,
    method,
    ref,
};

pub fn varOrMethod(node: c.TSNode) SourceType {
    const parent = c.ts_node_parent(node);
    if (c.ts_node_is_null(parent)) {
        return .none;
    }
    const symbol = c.ts_node_symbol(parent);
    if (symbol != ts_symbols.method_invocation) {
        return .ref;
    }
    const object_node = c.ts_node_child_by_field_id(parent, ts_fields.object);
    if (c.ts_node_eq(node, object_node)) {
        return .ref;
    }
    return .method;
}

pub fn nodeToText(node: c.TSNode, text: []const u8) []const u8 {
    std.debug.assert(!c.ts_node_is_null(node));
    const start = c.ts_node_start_byte(node);
    const end = c.ts_node_end_byte(node);
    return text[start..end];
}

const array_list_code = @embedFile("testcode/ArrayListSmall.java");
const array_list_code2 = @embedFile("testcode/ArrayListSmall2.java");

test "pointToName" {
    init();
    const tree_opt = c.ts_parser_parse_string_encoding(parser, null, array_list_code, array_list_code.len, c.TSInputEncodingUTF8);

    const str = pointToName(tree_opt.?, array_list_code, 31, 31);
    try std.testing.expectEqualStrings("elementData", str.?);
}

