const std = @import("std");

const Symbols = @import("ts_constants.zig").Symbols;
const Fields = @import("ts_constants.zig").Fields;
const ts_helpers = @import("ts_helpers.zig");
const c = ts_helpers.c;

const AstClassInfo = @import("types.zig").AstClassInfo;
const AstMethodInfo = @import("types.zig").AstMethodInfo;
const Position = @import("types.zig").Position;

extern "c" fn tree_sitter_java() *c.TSLanguage;

pub const TypeCollector = struct {
    alloc: std.mem.Allocator,
    project: []const u8,

    pub fn new(gpa: std.mem.Allocator, project: []const u8) TypeCollector {
        return .{ .alloc = gpa, .project = project };
    }

    pub fn analyzeFile(
        self: TypeCollector,
        file_path: []const u8,
        text: []const u8,
    ) !?AstClassInfo {
        const tree = c.ts_parser_parse_string(
            ts_helpers.parser,
            null,
            text.ptr,
            @intCast(text.len),
        ) orelse @panic("AST not created");
        defer c.ts_tree_delete(tree);

        const package = collectPackage(tree, text) orelse return null;
        const imports = try self.collectImports(tree, text);
        const methods = try self.collectMethods(tree, text);
        var class_opt = try self.collectClasses(tree, package, text);
        if (class_opt) |*class| {
            class.imports = imports;
            class.methods = methods;
            class.uriPosition.uri = std.mem.concat(
                self.alloc,
                u8,
                &.{ "file:/", self.project, "/", file_path },
            ) catch @panic("OOM");
        }
        return class_opt;
    }

    fn collectImports(
        self: TypeCollector,
        tree: *c.TSTree,
        text: []const u8,
    ) ![][]const u8 {
        var imports = std.ArrayList([]const u8).init(self.alloc);
        defer imports.deinit();
        const root = c.ts_tree_root_node(tree);
        var node = c.ts_node_child(root, 0);

        while (!c.ts_node_is_null(node)) {
            defer node = c.ts_node_next_named_sibling(node);

            const symbol = c.ts_node_symbol(node);
            if (symbol == Symbols.import_declaration) {
                const import_decl = c.ts_node_named_child(node, 0);
                const import_text = ts_helpers.nodeToText(import_decl, text);
                try imports.append(import_text);
            }
        }
        return imports.toOwnedSlice();
    }

    //TODO-parse inner classes + multiple classes in the same file
    fn collectClasses(
        self: TypeCollector,
        tree: *c.TSTree,
        package: []const u8,
        text: []const u8,
    ) !?AstClassInfo {
        const root = c.ts_tree_root_node(tree);
        var node = c.ts_node_child(root, 0);

        while (!c.ts_node_is_null(node)) {
            defer node = c.ts_node_next_named_sibling(node);
            const symbol = c.ts_node_symbol(node);
            if (symbol == Symbols.class_declaration) {
                const class_decl = c.ts_node_child_by_field_id(node, Fields.name);
                std.debug.assert(!c.ts_node_is_null(class_decl));
                const node_text = ts_helpers.nodeToText(class_decl, text);
                const full_name = try std.mem.concat(self.alloc, u8, &.{ package, ".", node_text });
                return .{
                    .packageAndName = full_name,
                    .imports = undefined,
                    .methods = undefined,
                    .uriPosition = .{
                        .uri = undefined,
                        .position = ts_helpers.nodeToPoint(class_decl),
                    },
                };
            }
        }
        return null;
    }

    fn collectMethods(self: TypeCollector, tree: *c.TSTree, text: []const u8) ![]AstMethodInfo {
        var methods = std.ArrayList(AstMethodInfo).init(self.alloc);
        defer methods.deinit();

        const root = c.ts_tree_root_node(tree);
        var node = c.ts_node_child(root, 0);

        const class_body: ?c.TSNode = loop: while (!c.ts_node_is_null(node)) {
            defer node = c.ts_node_next_named_sibling(node);
            const symbol = c.ts_node_symbol(node);
            if (symbol == Symbols.class_declaration) {
                const class_body_temp = c.ts_node_child_by_field_id(node, Fields.body);
                std.debug.assert(!c.ts_node_is_null(class_body_temp));
                break :loop class_body_temp;
            }
        } else {
            // No methods founds
            return &.{};
        };

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
                const method_name = ts_helpers.nodeToText(name_node, text);

                //TODO, resolve primitives from node type
                const return_type_node = c.ts_node_child_by_field_id(node, Fields.type);
                std.debug.assert(!c.ts_node_is_null(return_type_node));
                const return_type = ts_helpers.nodeToText(return_type_node, text);

                const point = c.ts_node_start_point(name_node);
                try methods.append(AstMethodInfo{
                    .name = method_name,
                    .returnType = return_type,
                    .position = .{ .line = point.row, .character = point.column },
                });
            }
        }
        return methods.toOwnedSlice();
    }

    fn collectPackage(tree: *c.TSTree, text: []const u8) ?[]const u8 {
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
};

test "collectImports" {
    const text = @embedFile("testcode/HashMap.java");

    ts_helpers.init();
    const type_collector = TypeCollector.new(std.heap.page_allocator, "");

    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len) orelse @panic("AST not created");
    defer c.ts_tree_delete(tree);
    const imports = try type_collector.collectImports(tree, text);

    try std.testing.expectEqual(@as(usize, 11), imports.len);
    try std.testing.expectEqualStrings("java.io.IOException", imports[0]);
    try std.testing.expectEqualStrings("java.io.InvalidObjectException", imports[1]);
    try std.testing.expectEqualStrings("java.io.ObjectInputStream", imports[2]);
    try std.testing.expectEqualStrings("java.io.Serializable", imports[3]);
    try std.testing.expectEqualStrings("java.lang.reflect.ParameterizedType", imports[4]);
    try std.testing.expectEqualStrings("java.lang.reflect.Type", imports[5]);
    try std.testing.expectEqualStrings("java.util.function.BiConsumer", imports[6]);
    try std.testing.expectEqualStrings("java.util.function.BiFunction", imports[7]);
    try std.testing.expectEqualStrings("java.util.function.Consumer", imports[8]);
    try std.testing.expectEqualStrings("java.util.function.Function", imports[9]);
    try std.testing.expectEqualStrings("jdk.internal.access.SharedSecrets", imports[10]);
}

test "collectPackage" {
    const text = @embedFile("testcode/HashMap.java");

    ts_helpers.init();

    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len).?;
    defer c.ts_tree_delete(tree);

    const package = TypeCollector.collectPackage(tree, text).?;
    try std.testing.expectEqualStrings("java.util", package);
}

test "collectClasses" {
    ts_helpers.init();
    const type_collector = TypeCollector.new(std.heap.page_allocator, "");

    const text = @embedFile("testcode/HashMap.java");
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len).?;
    defer c.ts_tree_delete(tree);

    const ast_class_info_opt = try type_collector.collectClasses(tree, "java.util", text);
    const ast_class_info = ast_class_info_opt.?;
    try std.testing.expectEqualStrings("java.util.HashMap", ast_class_info.packageAndName);
    try std.testing.expectEqual(Position{ .line = 14, .character = 13 }, ast_class_info.uriPosition.position);
}

test "collectMethods" {
    ts_helpers.init();
    const type_collector = TypeCollector.new(std.heap.page_allocator, "");

    const text = @embedFile("testcode/HashMap.java");
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len).?;
    defer c.ts_tree_delete(tree);

    const methods = try type_collector.collectMethods(tree, text);
    try std.testing.expectEqual(@as(usize, 4), methods.len);
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = "size",
            .returnType = "int",
            .position = .{ .line = 19, .character = 15 },
        },
        methods[0],
    );
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = "isEmpty",
            .returnType = "boolean",
            .position = .{ .line = 23, .character = 19 },
        },
        methods[1],
    );
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = "toString",
            .returnType = "String",
            .position = .{ .line = 27, .character = 18 },
        },
        methods[2],
    );
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = "get",
            .returnType = "V",
            .position = .{ .line = 31, .character = 13 },
        },
        methods[3],
    );
}

test "analyzeFile" {
    ts_helpers.init();
    const type_collector = TypeCollector.new(std.heap.page_allocator, "");

    const text = @embedFile("testcode/HashMap.java");
    const class_opt = try type_collector.analyzeFile("/test/project/HashMap.java", text);
    const class = class_opt.?;

    try std.testing.expectEqualStrings("java.util.HashMap", class.packageAndName);
    const imports = class.imports;
    try std.testing.expectEqualStrings("java.io.IOException", imports[0]);
    try std.testing.expectEqualStrings("java.io.InvalidObjectException", imports[1]);
    try std.testing.expectEqualStrings("java.io.ObjectInputStream", imports[2]);
    try std.testing.expectEqualStrings("java.io.Serializable", imports[3]);
    try std.testing.expectEqualStrings("java.lang.reflect.ParameterizedType", imports[4]);
    try std.testing.expectEqualStrings("java.lang.reflect.Type", imports[5]);
    try std.testing.expectEqualStrings("java.util.function.BiConsumer", imports[6]);
    try std.testing.expectEqualStrings("java.util.function.BiFunction", imports[7]);
    try std.testing.expectEqualStrings("java.util.function.Consumer", imports[8]);
    try std.testing.expectEqualStrings("java.util.function.Function", imports[9]);
    try std.testing.expectEqualStrings("jdk.internal.access.SharedSecrets", imports[10]);

    try std.testing.expectEqualStrings("file:///test/project/HashMap.java", class.uriPosition.uri);
    try std.testing.expectEqual(Position{ .line = 14, .character = 13 }, class.uriPosition.position);
}
