/// Manages open files
const std = @import("std");
const logger = @import("log.zig");
const indexer = @import("indexer.zig");
const ts = @import("ts_constants.zig");
const ts_fields = ts.Fields;
const ts_symbols = ts.Symbols;
const ts_helpers = @import("ts_helpers.zig");
const core = @import("core.zig");
const MethodTable = indexer.MethodTable;

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
pub extern "c" fn tree_sitter_java() *c.TSLanguage;


pub const Buffer = struct {
    uri: []u8,
    text: [:0]const u8,
    version: u64,
    tree: *c.TSTree,
    methods: MethodTable,

    pub fn open(alloc: std.mem.Allocator, filename: []const u8, text: []const u8) !Buffer {
        logger.log("{s}\n", .{text});

        const duplicated_text = try alloc.dupeZ(u8, text);
        const length: u32 = @intCast(duplicated_text.len);
        const tree_opt = c.ts_parser_parse_string_encoding(ts_helpers.parser, null, duplicated_text, length, c.TSInputEncodingUTF8);
        if (tree_opt) |tree| {
            var b = Buffer{
                .uri = try alloc.dupe(u8, filename),
                .text = duplicated_text,
                .version = 0,
                .tree = tree,
                .methods = MethodTable.init(alloc),
            };
            indexer.collectMethods(&b.methods, tree, duplicated_text);

            return b;
        } else {
            //TODO; memory leak if tree_opt is null. Panic for now, if encountered later handle
            @panic("Could not parse buffer");
        }
    }

    pub fn close(self: *Buffer, alloc: std.mem.Allocator) void {
        self.methods.deinit();
        alloc.free(self.uri);
        alloc.free(self.text);
        c.ts_tree_delete(self.tree);
    }


    pub fn edit(self: *Buffer, alloc: std.mem.Allocator, new_text: []const u8) void {
        alloc.free(self.text);
        const duplicated_text = alloc.dupeZ(u8, new_text) catch @panic("OOM");
        const length: u32 = @intCast(duplicated_text.len);
        const tree_opt = c.ts_parser_parse_string_encoding(ts_helpers.parser, null, duplicated_text, length, c.TSInputEncodingUTF8);
        if (tree_opt) |tree| {
            self.text = duplicated_text;
            self.version = self.version + 1;
            self.tree = tree;
        } else {
            @panic("todo handle no tree parsed");
        }
    }

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
                        if (std.mem.eql(u8, identifier, self.text[name_start.. name_end])) {
                            return c.ts_node_start_point(param_name_node);
                        }

                    }
                }
                if (name_node_opt) |name_node| {
                    const name_start = c.ts_node_start_byte(name_node);
                    const name_end = c.ts_node_end_byte(name_node);
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

        const source_type = ts_helpers.varOrMethod(node);
        return switch (source_type) {
            .ref => self.gotoRefDeclaration(row, col),
            .method => core.gotoMethodDeclaration(self, row, col),
            .none => null,
        };
    }
};

fn collectImports(alloc: std.mem.Allocator, text: []const u8, tree: *c.TSTree) !void {
    _ = alloc;
    _ = text;
    _ = tree;
}



// Tests
//
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;
const array_list_code = @embedFile("testcode/ArrayListSmall.java");
const array_list_code2 = @embedFile("testcode/ArrayListSmall2.java");

test "openclose" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
}

test "scoped_search" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const p = doc.gotoRefDeclaration(39, 16);
    try std.testing.expect(p != null);
    try std.testing.expectEqual(p.?.row, 31);
    try std.testing.expectEqual(p.?.column, 23);
}

test "goto parameter declaration" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const p = doc.gotoRefDeclaration(46, 16);
    try std.testing.expect(p != null);
    try std.testing.expectEqual(p.?.row, 36);
    try std.testing.expectEqual(p.?.column, 52);
}

test "edit" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);

    const str = ts_helpers.pointToName(doc.tree, doc.text, 31, 31);
    try expectEqualStrings("elementData", str.?);

    doc.edit(std.testing.allocator, array_list_code2);
    const str2 = ts_helpers.pointToName(doc.tree, doc.text, 25, 24);
    try expectEqualStrings("elementData", str2.?);
}
