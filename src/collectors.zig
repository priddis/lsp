const std = @import("std");
const File = std.fs.File;
const Point = @import("indexer.zig").Point;
const Logger = @import("log.zig");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
const Symbols = @import("ts_constants.zig").Symbols;
const Fields = @import("ts_constants.zig").Fields;
const ts_helpers = @import("ts_helpers.zig");
const ClassTable = @import("indexer.zig").ClassTable;
const ClassInfo = @import("buffer.zig").ClassInfo;


extern "c" fn tree_sitter_java() *c.TSLanguage;

pub fn collectImports(collect: *std.ArrayList(ClassInfo), tree: *c.TSTree, text: []const u8) !void {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.import_declaration) {
            const import_decl = c.ts_node_named_child(node, 0);
            const node_text = ts_helpers.nodeToText(import_decl, text);
            if (std.mem.lastIndexOfScalar(u8, node_text, '.')) |i| {
                const class = node_text[i + 1..];
                try collect.append(.{ .name = class, .fqdn = node_text });
            }
        }
    }
}

//TODO-parse inner classes + multiple classes in the same file (Single file program feature?)
pub fn collectClasses(alloc: std.mem.Allocator, collect: *ClassTable, tree: *c.TSTree, text: []const u8, uri: []const u8, package: []const u8, methods: std.StringArrayHashMap(Point)) void {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.class_declaration) {
            const class_decl = c.ts_node_child_by_field_id(node, Fields.name);
            const node_text = ts_helpers.nodeToText(class_decl, text);
            const point = c.ts_node_start_point(class_decl);
            const package_and_class = std.mem.concat(alloc, u8, &.{ package, ".", node_text }) catch @panic("OOM");
            collect.put(package_and_class, .{ .uri = uri, .position = .{ .row = point.row, .column = point.column }, .methods = methods }) catch @panic("OOM");
            return;
        }
    }
}

pub fn collectMethods(collect: *std.StringArrayHashMap(Point), tree: *c.TSTree, text: []const u8) void {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);
    var class_body: ?c.TSNode = undefined;
    var found = false;

    loop: while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.class_declaration) {
            class_body = c.ts_node_child_by_field_id(node, Fields.body);
            std.debug.assert(class_body != null);
            std.debug.assert(!c.ts_node_is_null(class_body.?));
            found = true;
            break :loop;
        }
    }
    if (!found) {
        return;
    }
    std.debug.assert(class_body != null);
    std.debug.assert(!c.ts_node_is_null(class_body.?));
    node = c.ts_node_child(class_body.?, 0);
    std.debug.assert(!c.ts_node_is_null(node));

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.method_declaration) {
            const name_node = c.ts_node_child_by_field_id(node, Fields.name);
            std.debug.assert(!c.ts_node_is_null(name_node));
            const node_text = ts_helpers.nodeToText(name_node, text);
            const point = c.ts_node_start_point(name_node);
            collect.put(node_text, .{ .row = point.row, .column = point.column }) catch @panic("OOM");
        }
    }
}

pub fn collectPackage(tree: *c.TSTree, text: []const u8) ?[]const u8 {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.package_declaration) {
            const package_decl = c.ts_node_named_child(node, 0);
            return ts_helpers.nodeToText(package_decl, text);
        }
    }
    return null;
}

fn findByFqdn(list: []const ClassInfo, str: []const u8) bool {
    for (list) |ci| {
        if (std.mem.eql(u8, ci.fqdn, str)) {
            return true;
        }
    }
    return false;
}

fn findByName(list: []const ClassInfo, str: []const u8) bool {
    for (list) |ci| {
        if (std.mem.eql(u8, ci.name, str)) {
            return true;
        }
    }
    return false;
}

test "collectImports" {

    ts_helpers.init();

    var imports = std.ArrayList(ClassInfo).init(std.testing.allocator);
    defer imports.deinit();
    const text = @embedFile("testcode/HashMap.java");
    const tree_opt = c.ts_parser_parse_string(ts_helpers.parser, null, text, @intCast(text.len));
    defer c.ts_tree_delete(tree_opt);
    const tree = tree_opt.?;
    try collectImports(&imports, tree, text);
    try std.testing.expectEqual(@as(usize, 11), imports.items.len);
    try std.testing.expect(findByFqdn(imports.items, "java.io.IOException"));
    try std.testing.expect(findByFqdn(imports.items, "java.io.InvalidObjectException"));
    try std.testing.expect(findByFqdn(imports.items, "java.io.ObjectInputStream"));
    try std.testing.expect(findByFqdn(imports.items, "java.io.Serializable"));
    try std.testing.expect(findByFqdn(imports.items, "java.lang.reflect.ParameterizedType"));
    try std.testing.expect(findByFqdn(imports.items, "java.lang.reflect.Type"));
    try std.testing.expect(findByFqdn(imports.items, "java.util.function.BiConsumer"));
    try std.testing.expect(findByFqdn(imports.items, "java.util.function.BiFunction"));
    try std.testing.expect(findByFqdn(imports.items, "java.util.function.Consumer"));
    try std.testing.expect(findByFqdn(imports.items, "java.util.function.Function"));
    try std.testing.expect(findByFqdn(imports.items, "jdk.internal.access.SharedSecrets"));
}

test "collectClasses" {
    ts_helpers.init();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);
    const methods = std.StringArrayHashMap(Point).init(alloc);

    var cl = ClassTable.init(alloc);

    const text = @embedFile("testcode/HashMap.java");
    const tree_opt = c.ts_parser_parse_string(ts_helpers.parser, null, text, @intCast(text.len));
    const tree = tree_opt.?;
    defer c.ts_tree_delete(tree_opt);
    collectClasses(alloc, &cl, tree, text, "testcode/HashMap.java", "java.util", methods);
    try std.testing.expectEqual(@as(usize, 1), cl.count());
    try std.testing.expect(cl.contains("java.util.HashMap"));
}

test "collectPackage" {
    ts_helpers.init();
    const text = @embedFile("testcode/HashMap.java");
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, @intCast(text.len));
    const package = collectPackage(tree.?, text);
    try std.testing.expectEqualStrings("java.util", package.?);
}
