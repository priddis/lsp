/// Manages open files
const std = @import("std");
const logger = @import("log.zig");
const indexer = @import("indexer.zig");
const ts = @import("ts_constants.zig");
const ts_fields = ts.Fields;
const ts_symbols = ts.Symbols;

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
pub extern "c" fn tree_sitter_java() *c.TSLanguage;
const import_query_text = "(import_declaration (scoped_identifier) @import)";
const identifier_query_text = "(identifier) @_identifier_";

var import_query: *c.TSQuery = undefined; 
var identifier_query: *c.TSQuery = undefined; 
var parser: *c.TSParser = undefined;

fn testing_malloc(length: usize) callconv(.C) *anyopaque {
    const bytes = std.testing.allocator.alloc(u8, length) catch unreachable;
    return bytes.ptr;
}

fn init() void {
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
pub const Buffer = struct {
    uri: []u8,
    text: [:0]const u8,
    version: u64,
    tree: *c.TSTree,

    pub fn findName(self: *const Buffer, row: u32, col: u32) ?[]const u8 {
        const root = c.ts_tree_root_node(self.tree);
        const point: c.TSPoint = .{ .row = row, .column = col };

        const node = c.ts_node_named_descendant_for_point_range(root, point, point);
        if (c.ts_node_is_null(node)) {
            return null;
        }

        const a = c.ts_node_start_byte(node);
        const b = c.ts_node_end_byte(node);

        return self.text[a..b];
    }

    pub fn open(alloc: std.mem.Allocator, filename: []const u8, text: []const u8) !Buffer {
        init();
        logger.log("{s}\n", .{text});
        const duplicated_text = try alloc.dupeZ(u8, text);
        const length: u32 = @intCast(duplicated_text.len);
        const tree_opt = c.ts_parser_parse_string_encoding(parser, null, duplicated_text, length, c.TSInputEncodingUTF8);
        if (tree_opt) |tree| {
            return Buffer{
                .uri = try alloc.dupe(u8, filename),
                .text = duplicated_text,
                .version = 0,
                .tree = tree,
            };
        } else {
            unreachable;
        }
    }

    pub fn close(self: *const Buffer, alloc: std.mem.Allocator) void {
        alloc.free(self.text);
        alloc.free(self.uri);
    }

    // Given a 
    pub fn gotoRefDeclaration(self: *const Buffer, row: u32, col: u32) ?c.TSPoint {
        logger.log("gotoref declaration {d} {d}\n", .{row, col});
        const root = c.ts_tree_root_node(self.tree);
        std.debug.assert(!c.ts_node_is_null(root));
        const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = row, .column = col}, .{ .row = row, .column = col});
        const start = c.ts_node_start_byte(node);
        const end = c.ts_node_end_byte(node);
        const identifier = self.text[start..end];

        var level_node = c.ts_node_parent(node);

        while (!c.ts_node_is_null(level_node)) {
            defer level_node = c.ts_node_parent(level_node);
            var cur_node = c.ts_node_named_child(level_node, 0);

            while (!c.ts_node_is_null(cur_node)) {
                defer cur_node = c.ts_node_next_named_sibling(cur_node);
                const symbol = c.ts_node_symbol(cur_node);
                var name_node_opt: ?c.TSNode = null;
                if (symbol == ts_symbols.local_variable_declaration 
                    or symbol == ts_symbols.field_declaration) {

                    const declarator_node = c.ts_node_child_by_field_id(cur_node, ts_fields.declarator);
                    std.debug.assert(!c.ts_node_is_null(declarator_node));

                    name_node_opt = c.ts_node_child_by_field_id(declarator_node, ts_fields.name);
                    std.debug.assert(!c.ts_node_is_null(name_node_opt.?));
                }
                if (symbol == ts_symbols.formal_parameters) {
                    var param_node = c.ts_node_named_child(cur_node, 0);
                    while (!c.ts_node_is_null(param_node)) {
                        defer param_node = c.ts_node_next_named_sibling(param_node);
                        const param_name_node = c.ts_node_child_by_field_id(param_node, ts_fields.name);
                        std.debug.assert(!c.ts_node_is_null(param_name_node));
                        const name_start = c.ts_node_start_byte(param_name_node);
                        const name_end = c.ts_node_end_byte(param_name_node);
                        //std.debug.print("found formal parameter {s} = {s}\n", .{identifier, self.text[name_start.. name_end]});
                        if (std.mem.eql(u8, identifier, self.text[name_start.. name_end])) {
                            return c.ts_node_start_point(param_name_node);
                        }

                    }
                }
                if (name_node_opt) |name_node| {
                    const name_start = c.ts_node_start_byte(name_node);
                    const name_end = c.ts_node_end_byte(name_node);
                    //logger.log("checking if {s} = {s}\n", .{identifier, self.text[name_start.. name_end]});
                    if (std.mem.eql(u8, identifier, self.text[name_start.. name_end])) {
                        return c.ts_node_start_point(name_node);
                    }
                }
            }
        }
        return null;
    }

    pub fn definition(self: *const Buffer, row: u32, col: u32) ?c.TSPoint {
        const root = c.ts_tree_root_node(self.tree);
        std.debug.assert(!c.ts_node_is_null(root));
        const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = row, .column = col}, .{ .row = row, .column = col});

        const source_type = varOrMethod(node);
        return switch (source_type) {
            .ref => self.gotoRefDeclaration(row, col),
            .method => self.gotoMethodDeclaration(row, col),
            .none => null,
        };

    }

    pub fn gotoMethodDeclaration(self: *const Buffer, row: u32, col: u32) ?c.TSPoint {
        logger.log("goto method\n", .{});
        if (self.findName(row, col)) |s| {
            logger.log("found name = {s}\n", .{s});

            const lookup = indexer.index.method_lookup.get(s);
            if (lookup) |l| {
                return .{ .row = l.row, .column = l.column };
            }
        }
        return null;
    }
};

fn collectImports(alloc: std.mem.Allocator, text: []const u8, tree: *c.TSTree) !void {
    const root = c.ts_tree_root_node(tree);

    const cursor = c.ts_query_cursor_new();
    c.ts_query_cursor_exec(cursor, import_query, root);

    var match: c.TSQueryMatch = undefined;
    while (c.ts_query_cursor_next_match(cursor, &match)) {
        const captures: [*]const c.TSQueryCapture = match.captures;
        for (captures[0..match.capture_count]) |capture| {
            const start = c.ts_node_start_byte(capture.node);
            const end = c.ts_node_end_byte(capture.node);
            const match_str: []u8 = try alloc.dupe(u8, text[start..end]);
            alloc.free(match_str);
        }
    }
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


// Tests
//
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;
const array_list_code = @embedFile("testcode/ArrayListSmall.java");
test "method_retrieval" {
    init();
    const doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const str = doc.findName(31, 31);

    try expectEqualStrings("elementData", str.?);
}

test "imports" {
    init();
    const doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    try collectImports(std.testing.allocator, array_list_code, doc.tree);
}

test "scoped_search" {
    init();
    const doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const p = doc.gotoRefDeclaration(39, 16);
    try std.testing.expect(p != null);
    try std.testing.expectEqual(p.?.row, 31);
    try std.testing.expectEqual(p.?.column, 23);
}

test "goto parameter declaration" {
    init();
    const doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const p = doc.gotoRefDeclaration(46, 16);
    try std.testing.expect(p != null);
    try std.testing.expectEqual(p.?.row, 36);
    try std.testing.expectEqual(p.?.column, 52);
}
