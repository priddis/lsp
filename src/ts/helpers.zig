const std = @import("std");
const ts_constants = @import("constants.zig");
const Fields = ts_constants.Fields;
const Symbols = ts_constants.Symbols;
const Position = @import("../types.zig").Position;
const Queries = @import("../Queries.zig");

pub extern "c" fn tree_sitter_java() *c.TSLanguage;

pub const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const Ast = c.TSTree;

const identifier_query_text = "(identifier) @_identifier_";

var parameter_query: *c.TSQuery = undefined;
var local_variable_declaration_query = undefined;
var method_invocation_query: *c.TSQuery = undefined;
pub var parser: *c.TSParser = undefined;

pub fn parse(text: []const u8) Ast {
    return c.ts_parser_parse_string(
        parser,
        null,
        text.ptr,
        @intCast(text.len),
    ) orelse @panic("AST not created");
}

pub fn init() void {
    var error_type: c.TSQueryError = c.TSQueryErrorNone;
    var err_offset: u32 = 0;

    inline for (Queries.List) |query_type| {
        query_type.query = c.ts_query_new(
            tree_sitter_java(),
            query_type.query_text,
            query_type.query_text.len,
            &err_offset,
            &error_type,
        ).?;
        std.debug.assert(error_type == c.TSQueryErrorNone);
    }

    parser = c.ts_parser_new().?;
    _ = c.ts_parser_set_language(parser, tree_sitter_java());
}

pub fn TSIterator(QueryType: anytype) type {
    return struct {
        cursor: *c.TSQueryCursor,

        pub fn new(
            ast: *const Ast,
        ) @This() {
            const root = c.ts_tree_root_node(ast);
            //TODO remove page allocator use
            //var cursor = std.heap.page_allocator.create(c.TSQuery) catch @panic("TODO remove");
            const cursor = c.ts_query_cursor_new();
            c.ts_query_cursor_exec(cursor.?, QueryType.Query(), root);
            return .{ .cursor = cursor.? };
        }

        pub fn next(self: *const @This()) ?c.TSNode {
            var match: c.TSQueryMatch = undefined;
            if (c.ts_query_cursor_next_match(self.cursor, &match)) {
                std.debug.assert(match.capture_count == 1);
                const capture = match.captures[0];
                return capture.node;
            }
            return null;
        }

        pub fn deinit(self: *const @This()) void {
            c.ts_query_cursor_delete(self.cursor);
            //std.heap.page_allocator.destroy(self.cursor);
        }
    };
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

pub fn nodeToName(node: c.TSNode, text: []const u8) []const u8 {
    const a = c.ts_node_start_byte(node);
    const b = c.ts_node_end_byte(node);

    return text[a..b];
}

pub fn nodeToPoint(node: c.TSNode) Position {
    const ts_point = c.ts_node_start_point(node);
    return .{ .line = ts_point.row, .character = ts_point.column };
}

pub fn localVarType(local: c.TSNode, text: []const u8) []const u8 {
    const type_node = c.ts_node_child_by_field_id(local, Fields.type);
    return nodeToName(type_node, text);
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

pub fn findIdentifierDecl(ref: c.TSNode, text: []const u8) ?c.TSNode {
    // We are looking for the variable, field, or parameter decl that matches this identifier
    const identifier = nodeToText(ref, text);

    var scope_node = c.ts_node_parent(ref);

    // Outer loop moves up in scope
    while (!c.ts_node_is_null(scope_node)) {
        defer scope_node = c.ts_node_parent(scope_node);
        var cur_node = c.ts_node_named_child(scope_node, 0);

        // Inner loop iterates through scope
        while (!c.ts_node_is_null(cur_node)) {
            defer cur_node = c.ts_node_next_named_sibling(cur_node);
            const symbol = c.ts_node_symbol(cur_node);

            // Local variables/fields
            if (symbol == Symbols.local_variable_declaration or symbol == Symbols.field_declaration) {
                const declarator_node = c.ts_node_child_by_field_id(cur_node, Fields.declarator);
                std.debug.assert(!c.ts_node_is_null(declarator_node));

                const name_node = c.ts_node_child_by_field_id(declarator_node, Fields.name);
                const node_text = nodeToText(name_node, text);
                if (std.mem.eql(u8, identifier, node_text)) {
                    return name_node;
                }
            }

            //Parameters
            if (symbol == Symbols.formal_parameters) {
                var param_node = c.ts_node_named_child(cur_node, 0);
                while (!c.ts_node_is_null(param_node)) {
                    defer param_node = c.ts_node_next_named_sibling(param_node);

                    const param_name_node = c.ts_node_child_by_field_id(param_node, Fields.name);
                    std.debug.assert(!c.ts_node_is_null(param_name_node));
                    const param_text = nodeToText(param_name_node, text);
                    if (std.mem.eql(u8, identifier, param_text)) {
                        return param_name_node;
                    }
                }
            }
        }
    }
    return null;
}

test "pointToName" {
    const array_list_code = @embedFile("../test/ArrayListSmall.java");
    //const array_list_code2 = @embedFile("testcode/ArrayListSmall2.java");
    init();
    const tree_opt = c.ts_parser_parse_string_encoding(parser, null, array_list_code, array_list_code.len, c.TSInputEncodingUTF8);

    const str = pointToName(tree_opt.?, array_list_code, 31, 31);
    try std.testing.expectEqualStrings("elementData", str.?);
}

test "referenceIterator" {
    //const testcode = @embedFile("test_projects/BasicReference/ClassA.java");
    //init();
    //const tree_opt = c.ts_parser_parse_string_encoding(parser, null, testcode, testcode.len, c.TSInputEncodingUTF8);
    //const it = ReferenceIterator.new(tree_opt.?);

}
