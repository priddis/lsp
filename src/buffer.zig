/// Manages open files
const std = @import("std");
const logger = @import("log.zig");
const ts = @import("ts_constants.zig");
const ts_fields = ts.Fields;
const ts_symbols = ts.Symbols;
const ts_helpers = @import("ts_helpers.zig");
const core = @import("core.zig");
const collectors = @import("collectors.zig");
const Point = @import("indexer.zig").Point;
const UriPosition = @import("indexer.zig").UriPosition;

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
pub extern "c" fn tree_sitter_java() *c.TSLanguage;

pub const ClassInfo = struct {
    name: []const u8,
    fqdn: []const u8,
};

pub const Buffer = struct {
    uri: []u8,
    text: [:0]const u8,
    version: u64,
    tree: *c.TSTree,
    methods: std.StringArrayHashMap(Point),
    imports: std.ArrayList(ClassInfo),

    pub fn open(alloc: std.mem.Allocator, filename: []const u8, text: []const u8) !Buffer {
        logger.log("{s}\n", .{text});

        const duplicated_text = try alloc.dupeZ(u8, text);
        const length: u32 = @intCast(duplicated_text.len);
        std.debug.assert(ts_helpers.parser != undefined);
        if (c.ts_parser_parse_string_encoding(ts_helpers.parser, null, duplicated_text, length, c.TSInputEncodingUTF8)) |tree| {
            var b = Buffer{
                .uri = try alloc.dupe(u8, filename),
                .text = duplicated_text,
                .version = 0,
                .tree = tree,
                .methods = std.StringArrayHashMap(Point).init(alloc),
                .imports = std.ArrayList(ClassInfo).init(alloc),
            };
            collectors.collectMethods(&b.methods, tree, duplicated_text);
            collectors.collectImports(&b.imports, tree, duplicated_text) catch @panic("OOM");
            return b;
        } else {
            //TODO; memory leak if tree is null. Panic for now, if encountered later handle
            @panic("Could not parse buffer");
        }
    }

    pub fn close(self: *Buffer, alloc: std.mem.Allocator) void {
        self.methods.deinit();
        self.imports.deinit();
        alloc.free(self.uri);
        alloc.free(self.text);
        c.ts_tree_delete(self.tree);
    }

    pub fn edit(self: *Buffer, alloc: std.mem.Allocator, new_text: []const u8) void {
        //TODO handle edit of imports
        alloc.free(self.text);
        const duplicated_text = alloc.dupeZ(u8, new_text) catch @panic("OOM");
        const length: u32 = @intCast(duplicated_text.len);
        if (c.ts_parser_parse_string_encoding(ts_helpers.parser, null, duplicated_text, length, c.TSInputEncodingUTF8)) |tree| {
            self.text = duplicated_text;
            self.version = self.version + 1;
            self.tree = tree;
        } else {
            @panic("todo handle no tree parsed");
        }
    }

    ///Starting from the reference, search the given scope for the ref definition
    ///If not found in the given scope, move to the parent scope
    pub fn gotoRefDeclaration(self: *const Buffer, row: u32, col: u32) ?c.TSNode {
        logger.log("gotoref declaration {d} {d}\n", .{ row, col });
        const root = c.ts_tree_root_node(self.tree);
        std.debug.assert(!c.ts_node_is_null(root));
        const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = row, .column = col }, .{ .row = row, .column = col });
        const identifier = ts_helpers.nodeToText(node, self.text);

        var scope_node = c.ts_node_parent(node);

        // Outer loop moves up in scope
        while (!c.ts_node_is_null(scope_node)) {
            defer scope_node = c.ts_node_parent(scope_node);
            var cur_node = c.ts_node_named_child(scope_node, 0);

            // Inner loop iterates through scope
            while (!c.ts_node_is_null(cur_node)) {
                defer cur_node = c.ts_node_next_named_sibling(cur_node);
                const symbol = c.ts_node_symbol(cur_node);

                // Local variables/fields
                if (symbol == ts_symbols.local_variable_declaration or symbol == ts_symbols.field_declaration) {
                    const declarator_node = c.ts_node_child_by_field_id(cur_node, ts_fields.declarator);
                    std.debug.assert(!c.ts_node_is_null(declarator_node));

                    const name_node = c.ts_node_child_by_field_id(declarator_node, ts_fields.name);
                    const node_text = ts_helpers.nodeToText(name_node, self.text);
                    if (std.mem.eql(u8, identifier, node_text)) {
                        return name_node;
                    }
                }

                //Parameters
                if (symbol == ts_symbols.formal_parameters) {
                    var param_node = c.ts_node_named_child(cur_node, 0);
                    while (!c.ts_node_is_null(param_node)) {
                        defer param_node = c.ts_node_next_named_sibling(param_node);
                        const param_name_node = c.ts_node_child_by_field_id(param_node, ts_fields.name);
                        const param_text = ts_helpers.nodeToText(param_name_node, self.text);
                        if (std.mem.eql(u8, identifier, param_text)) {
                            return param_name_node;
                        }
                    }
                }
            }
        }
        return null;
    }

    pub fn definition(self: *const Buffer, row: u32, col: u32) ?c.TSPoint {
        const root = c.ts_tree_root_node(self.tree);
        std.debug.assert(!c.ts_node_is_null(root));
        const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = row, .column = col }, .{ .row = row, .column = col });

        const source_type = ts_helpers.varOrMethod(node);
        return switch (source_type) {
            .ref => ref: {
                const maybe_ref_node = self.gotoRefDeclaration(row, col);
                break :ref if (maybe_ref_node) |ref_node| c.ts_node_start_point(ref_node) else null;
            },
            .method => core.gotoMethodDeclaration(self, row, col),
            .none => null,
        };
    }

    pub fn gotoTypeDefinition(self: *const Buffer, row: u32, col: u32) ?UriPosition {
        if (gotoRefDeclaration(self, row, col)) |node| {
            const type_name = core.resolveType(node, self.text) orelse return null;
            for (self.imports.items) |*class| {
                if (std.mem.eql(u8, class.name, type_name)) {
                    const cl = core.index.classes.get(class.fqdn) orelse return null;
                    return .{ .uri = cl.uri, .position = cl.position };
                }
            }
        }
        return null;
    }
};

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

test "goto ref declaration" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const n = doc.gotoRefDeclaration(39, 16);
    const p = c.ts_node_start_point(n.?);
    try std.testing.expectEqual(p.row, 31);
    try std.testing.expectEqual(p.column, 23);
}

test "goto parameter declaration" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const n = doc.gotoRefDeclaration(46, 16);
    const p = c.ts_node_start_point(n.?);
    try std.testing.expectEqual(p.row, 36);
    try std.testing.expectEqual(p.column, 52);
}

test "goto type declaration" {
    ts_helpers.init();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const aalloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);

    core.indexProject(aalloc, "/home/micah/code/lsp/src/testcode");
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const t = doc.gotoTypeDefinition(62, 9);
    try std.testing.expectEqual(@as(usize, 4), core.index.classes.count());
    try std.testing.expect(t != null);
    try std.testing.expectEqualStrings("file:///home/micah/code/lsp/src/testcode/HashMap.java", t.?.uri);
    try std.testing.expectEqual(@as(u32, 138), t.?.position.row);
    try std.testing.expectEqual(@as(u32, 13), t.?.position.column);
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
