const std = @import("std");
const Limits = @import("limits.zig");
const Logger = @import("log.zig");
const IndexingError = @import("errors.zig").IndexingError;
const ClassHandle = @import("types.zig").ClassHandle;
const Method = @import("types.zig").Method;
const ts_helpers = @import("ts/helpers.zig");
const Queries = @import("Queries.zig");
const Position = @import("types.zig").Position;
const Class = @import("types.zig").Class;
const Primitive = @import("types.zig").Primitive;
const StringTable = @import("StringTable.zig");
const StringHandle = StringTable.StringHandle;
const Namespace = @import("Namespace.zig");
const AstClassInfo = @import("types.zig").AstClassInfo;
const AstMethodInfo = @import("types.zig").AstMethodInfo;
const TypedClassInfo = @import("types.zig").TypedClassInfo;
const Symbols = @import("ts/constants.zig").Symbols;
const Fields = @import("ts/constants.zig").Fields;
const c = ts_helpers.c;

extern "c" fn tree_sitter_java() *c.TSLanguage;

const Index = @This();

namespace: Namespace,
ast_classes: std.ArrayListUnmanaged(AstClassInfo),
classes: std.ArrayListUnmanaged(TypedClassInfo),
arena: std.mem.Allocator,
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn init(arena: std.mem.Allocator) !@This() {
    const index = Index{
        .namespace = Namespace.new(arena),
        .ast_classes = std.ArrayListUnmanaged(AstClassInfo){},
        .classes = std.ArrayListUnmanaged(TypedClassInfo){},
        .arena = arena,
    };

    StringTable.empty_string = try StringTable.put("");
    StringTable.var_string = try StringTable.put("var");
    //inline for (std.meta.tags(Primitive)) |p| {
    //    const primitive_handle = ClassHandle{ .generationId = 0, .index = @intCast(index.classes.items.len) };
    //    const primitive_str = try StringTable.put(@tagName(p));
    //    std.debug.assert(primitive_handle.index == primitive_str.x);
    //    try index.classes.append(Class{ .primitive = p });
    //}
    return index;
}

pub fn indexProject(
    self: *@This(),
    scratch: std.mem.Allocator,
    project: []const u8,
) IndexingError!void {
    try self.parseFiles(scratch, project);
    //std.debug.print("done parsing files\n", .{});
    try self.resolveTypes();
    //std.debug.print("done resolving types\n", .{});

    for (0..self.classes.items.len) |i| {
        try self.resolveReferences(scratch, .{ .generationId = 0, .index = @intCast(i) });
    }
    //std.debug.print("done resolving references\n", .{});
}

fn parseFiles(self: *@This(), scratch: std.mem.Allocator, project: []const u8) !void {
    var it = std.fs.cwd().openDir(project, .{
        .iterate = true,
        .access_sub_paths = true,
        .no_follow = true,
    }) catch |err| {
        return Logger.throw(
            "Could not open project directory {s} due to {!}",
            .{ project, err },
            IndexingError.CouldNotOpenProject,
        );
    };
    defer it.close();

    var walker = try it.walk(scratch);
    // Walk files
    while (walker.next() catch @panic("Error walking")) |entry| {
        if (entry.kind == .file and
            entry.basename.len > 5 and
            std.mem.eql(u8, ".java", entry.basename[entry.basename.len - 5 ..]))
        {
            const source_file = entry.dir.openFile(entry.basename, .{}) catch |err| switch (err) {
                error.FileTooBig => continue, //Todo, show error
                error.AccessDenied => continue, //Todo, show error
                error.SymLinkLoop => continue, //TODO show error
                error.NoSpaceLeft => unreachable, //Indexing takes no disk space
                error.IsDir => unreachable,
                error.Unexpected => unreachable,
                else => unreachable,
            };
            defer source_file.close();
            const buf_or_error = source_file.readToEndAlloc(scratch, Limits.max_file_size);
            if (buf_or_error) |buf| {
                const uri = try std.mem.concat(self.arena, u8, &.{ "file://", project, "/", entry.path }); //TODO, use fs.join function
                self.analyzeFile(uri, buf) catch |err| {
                    Logger.log("ERROR: out of memory to parse file {s} {!}", .{ entry.basename, err });
                    continue;
                };
            } else |err| {
                Logger.log("ERROR: Could not open file {s} {!}", .{ entry.basename, err });
            }
        }
    }
}

fn resolveTypes(self: *@This()) !void {
    for (self.ast_classes.items, 0..) |*ast_class, i| {
        //Resolve imports
        var resolved_imports = std.AutoHashMap(StringHandle, Namespace.PackageOrClass).init(self.arena);

        //default imports
        if (self.namespace.resolveImport(StringTable.get("java.lang.*").?)) |java_util| {
            var util_it = java_util.package_or_class.splat.classes.iterator();
            while (util_it.next()) |entry| {
                try resolved_imports.put(entry.key_ptr.*, Namespace.PackageOrClass{ .class = entry.value_ptr.* });
            }
        }
        if (self.namespace.resolveImport(ast_class.package)) |local_package| {
            var util_it = local_package.package_or_class.package.classes.iterator();
            while (util_it.next()) |entry| {
                try resolved_imports.put(entry.key_ptr.*, Namespace.PackageOrClass{ .class = entry.value_ptr.* });
            }
        }
        for (ast_class.imports) |import| {
            if (self.namespace.resolveImport(import)) |import_result| {
                switch (import_result.package_or_class) {
                    .splat => |package| {
                        var it = package.classes.iterator();
                        while (it.next()) |entry| {
                            try resolved_imports.put(entry.key_ptr.*, Namespace.PackageOrClass{ .class = entry.value_ptr.* });
                        }
                    },
                    else => try resolved_imports.put(import_result.name, import_result.package_or_class),
                }
            } else {
                //TODO package not found
            }
        }
        // Resolve return types
        var class_methods = std.ArrayList(Method).init(self.arena);
        for (ast_class.methods) |method| {
            //TODO handle use of subpackaged types
            // For example, Map.Entry
            if (Primitive.fromStringHandle(method.return_type)) |p| {
                try class_methods.append(Method{
                    .name = method.name,
                    .position = method.position,
                    .return_type = Primitive.toClassHandle(p),
                });
            } else if (resolved_imports.get(method.return_type)) |resolved| {
                if (std.meta.activeTag(resolved) == .class) {
                    try class_methods.append(Method{
                        .name = method.name,
                        .position = method.position,
                        .return_type = resolved.class,
                    });
                }
            } else {
                //Logger.log("Missing return type {s}\n", .{StringTable.toSlice(method.return_type)});
            }
        }
        self.classes.items[i] = .{
            .imports = resolved_imports,
            //try self.arena.create(std.AutoHashMap(StringHandle, Namespace.PackageOrClass)),
            .methods = try class_methods.toOwnedSlice(),
            .uri = ast_class.uri,
            .position = ast_class.position,
            .text = ast_class.text,
            .usages = std.ArrayListUnmanaged(Position){},
        };
    }
}

fn resolveReferences(
    self: *@This(),
    scratch: std.mem.Allocator,
    class_handle: ClassHandle,
) !void {
    const typed_class_info = self.classes.items[class_handle.index];
    const tree = c.ts_parser_parse_string(
        ts_helpers.parser,
        null,
        typed_class_info.text.ptr,
        @intCast(typed_class_info.text.len),
    ) orelse @panic("AST not created");
    defer c.ts_tree_delete(tree);

    //const class_name = StringTable.toSlice(typed_class_info.name);
    //std.debug.print("class name - {s}\n", .{class_name});
    var local_var_it = ts_helpers.TSIterator(Queries.LocalVariable).new(tree);
    defer local_var_it.deinit();
    defer scratch.free(typed_class_info.text);

    while (local_var_it.next()) |local| {
        const local_type_str = ts_helpers.localVarType(local, typed_class_info.text);
        const local_type = StringTable.get(local_type_str);
        //std.debug.print("found type {s}\n", .{local_type_str});
        if (StringTable.var_string.equals(local_type)) {
            //TODO-resolve RHS for vars

        } else if (local_type) |known_local_type| {
            if (Primitive.fromStringHandle(known_local_type) != null) {
                continue;
            }
            if (typed_class_info.imports.get(known_local_type)) |resolved_package_or_class| {
                //std.debug.print("resolved {s} to import {d}\n", .{ local_type_str, resolved_package_or_class.class.index });
                const resolved_type_handle = switch (resolved_package_or_class) {
                    .class => |klass| klass,
                    .package => std.debug.panic("type resolved to package", .{}),
                    .splat => std.debug.panic("type resolved to splat", .{}),
                };
                var resolved_type: *TypedClassInfo = &self.classes.items[resolved_type_handle.index];
                try resolved_type.usages.append(self.arena, ts_helpers.nodeToPoint(local));
            } else {
                //std.debug.print("type not imported {s}\n", .{local_type_str});
            }
        } else {
            Logger.log("Unknown local type {s}\n", .{local_type_str});
        }
    }
}

pub fn analyzeFile(self: *@This(), uri: []const u8, text: []const u8) !void {
    const tree = c.ts_parser_parse_string(
        ts_helpers.parser,
        null,
        text.ptr,
        @intCast(text.len),
    ) orelse @panic("AST not created");
    defer c.ts_tree_delete(tree);

    const package_string = collectPackage(tree, text);
    const imports = try self.collectImportStrings(tree, text);
    const methods = try self.collectMethods(tree, text);
    try self.insertClass(tree, text, package_string, imports, methods, uri);
}

fn collectPackage(tree: *c.TSTree, text: []const u8) []const u8 {
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
    return &.{};
}

fn collectImportStrings(self: *@This(), tree: *c.TSTree, text: []const u8) ![]StringHandle {
    var imports = std.ArrayList(StringHandle).init(self.arena);
    defer imports.deinit();
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);

        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.import_declaration) {
            const import_decl = c.ts_node_named_child(node, 0);
            const import_text = ts_helpers.nodeToText(import_decl, text);
            const import_handle = try StringTable.put(import_text);
            try imports.append(import_handle);
        }
    }
    return imports.toOwnedSlice();
}

fn insertClass(
    self: *@This(),
    tree: *c.TSTree,
    text: []const u8,
    package: []const u8,
    imports: []StringHandle,
    methods: []AstMethodInfo,
    uri: []const u8,
) !void {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.class_declaration) {
            const class_decl = c.ts_node_child_by_field_id(node, Fields.name);
            std.debug.assert(!c.ts_node_is_null(class_decl));
            const class_name = ts_helpers.nodeToText(class_decl, text);
            //std.debug.print("found class {s}\n", .{node_text});
            try self.ast_classes.append(self.arena, .{
                .package = try StringTable.put(package),
                .imports = imports,
                .methods = methods,
                .uri = uri,
                .position = ts_helpers.nodeToPoint(class_decl),
                .text = text,
            });
            try self.classes.append(self.arena, .{
                .imports = undefined,
                .methods = undefined,
                .position = undefined,
                .text = undefined,
                .uri = undefined,
                .usages = undefined,
            });

            const class_handle = ClassHandle{ .index = @intCast(self.classes.items.len - 1), .generationId = 0 };
            try self.namespace.insert(package, class_name, class_handle);
            return;
        }
    }
    return;
}

fn collectMethods(self: *@This(), tree: *c.TSTree, text: []const u8) ![]AstMethodInfo {
    var methods = std.ArrayList(AstMethodInfo).init(self.arena);
    defer methods.deinit();

    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    const class_body: c.TSNode = classbody: while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.class_declaration) {
            const class_body_temp = c.ts_node_child_by_field_id(node, Fields.body);
            std.debug.assert(!c.ts_node_is_null(class_body_temp));
            break :classbody class_body_temp;
        }
    } else {
        // No methods founds
        return &.{};
    };

    std.debug.assert(!c.ts_node_is_null(class_body));
    node = c.ts_node_child(class_body, 0);
    std.debug.assert(!c.ts_node_is_null(node));

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.method_declaration) {
            const name_node = c.ts_node_child_by_field_id(node, Fields.name);
            std.debug.assert(!c.ts_node_is_null(name_node));
            const method_name = try StringTable.put(ts_helpers.nodeToText(name_node, text));

            var return_type_node = c.ts_node_child_by_field_id(node, Fields.type);
            if (c.ts_node_symbol(return_type_node) == Symbols.array_type) {
                return_type_node = c.ts_node_child_by_field_id(return_type_node, Fields.element);
            }
            std.debug.assert(!c.ts_node_is_null(return_type_node));
            const return_type = try StringTable.put(ts_helpers.nodeToText(return_type_node, text));

            const point = c.ts_node_start_point(name_node);
            try methods.append(AstMethodInfo{
                .name = method_name,
                .return_type = return_type,
                .position = .{ .line = point.row, .character = point.column },
            });
        }
    }
    return methods.toOwnedSlice();
}

///Testing only
fn getClass(self: @This(), full_class_name: []const u8) TypedClassInfo {
    const package_or_class = self.namespace.resolveImportString(full_class_name).?;
    const class_handle = package_or_class.package_or_class.class;
    return self.classes.items[class_handle.index];
}

///Testing only
fn getClassFromHandle(self: @This(), class_handle: ClassHandle) TypedClassInfo {
    return self.classes.items[class_handle.index];
}

var testgpa = std.heap.GeneralPurposeAllocator(.{}){};
var testarena = std.heap.ArenaAllocator().init(testgpa.allocator());

test "init" {
    //try StringTable.init();
    //ts_helpers.init();
    //var index = try init(testgpa.allocator());

    //const int = index.getClass("int"); //std.mem.sliceTo("int", 0));
    //try std.testing.expect(int.primitive == Primitive.int);
}

test "goto Class" {
    try StringTable.init();
    ts_helpers.init();
    var index = try init(testgpa.allocator());

    try index.indexProject(testgpa.allocator(), "src/test/BasicReference/");
    const klassA = index.getClass("mypackage.ClassA");

    try std.testing.expectEqual(@as(u32, 3), klassA.position.line);
    try std.testing.expectEqual(@as(u32, 13), klassA.position.character);

    const doThing = klassA.methods[0];
    try std.testing.expectEqual(@as(u32, 9), doThing.position.line);
    try std.testing.expectEqual(@as(u32, 15), doThing.position.character);

    const doAnotherThing = klassA.methods[1];
    try std.testing.expectEqual(@as(u32, 15), doAnotherThing.position.line);
    try std.testing.expectEqual(@as(u32, 15), doAnotherThing.position.character);

    const klassB = index.getClass("mypackage.ClassB");
    try std.testing.expectEqual(2, klassB.usages.items.len);
}

test "collectImports" {
    const text = @embedFile("test/HashMap.java");

    ts_helpers.init();
    try StringTable.init();
    var index = try Index.init(testgpa.allocator());

    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len) orelse @panic("AST not created");
    defer c.ts_tree_delete(tree);
    const imports = try index.collectImportStrings(tree, text);

    try std.testing.expectEqual(@as(usize, 11), imports.len);
    try std.testing.expectEqualStrings("java.io.IOException", StringTable.toSlice(imports[0]));
    try std.testing.expectEqualStrings("java.io.InvalidObjectException", StringTable.toSlice(imports[1]));
    try std.testing.expectEqualStrings("java.io.ObjectInputStream", StringTable.toSlice(imports[2]));
    try std.testing.expectEqualStrings("java.io.Serializable", StringTable.toSlice(imports[3]));
    try std.testing.expectEqualStrings("java.lang.reflect.ParameterizedType", StringTable.toSlice(imports[4]));
    try std.testing.expectEqualStrings("java.lang.reflect.Type", StringTable.toSlice(imports[5]));
    try std.testing.expectEqualStrings("java.util.function.BiConsumer", StringTable.toSlice(imports[6]));
    try std.testing.expectEqualStrings("java.util.function.BiFunction", StringTable.toSlice(imports[7]));
    try std.testing.expectEqualStrings("java.util.function.Consumer", StringTable.toSlice(imports[8]));
    try std.testing.expectEqualStrings("java.util.function.Function", StringTable.toSlice(imports[9]));
    try std.testing.expectEqualStrings("jdk.internal.access.SharedSecrets", StringTable.toSlice(imports[10]));
}

test "collectPackage" {
    const text = @embedFile("test/HashMap.java");
    try StringTable.init();
    ts_helpers.init();

    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len).?;
    defer c.ts_tree_delete(tree);

    const package = Index.collectPackage(tree, text);
    try std.testing.expectEqualStrings("java.util", package);
}

test "insertClass" {
    //try StringTable.init();
    //ts_helpers.init();
    //var index = try Index.init(testgpa.allocator());

    //const text = @embedFile("test/HashMap.java");
    //const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len).?;
    //defer c.ts_tree_delete(tree);

    //try index.insertClass(tree, text, "java.util", &.{}, &.{}, &.{});
    //const class_info = index.getClass("java.util.HashMap");
    //try std.testing.expectEqual(Position{ .line = 14, .character = 13 }, class_info.getPosition());
    //const package = index.namespace.getPackage("java.util").?;
    //try std.testing.expect(package.getClass("HashMap") != null);
}

test "collectMethods" {
    try StringTable.init();
    ts_helpers.init();
    var index = try Index.init(testgpa.allocator());

    const text = @embedFile("test/HashMap.java");
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, text, text.len).?;
    defer c.ts_tree_delete(tree);

    const methods = try index.collectMethods(tree, text);
    try std.testing.expectEqual(@as(usize, 4), methods.len);
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = try StringTable.put("size"),
            .return_type = try StringTable.put("int"),
            .position = .{ .line = 19, .character = 15 },
        },
        methods[0],
    );
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = try StringTable.put("isEmpty"),
            .return_type = try StringTable.put("boolean"),
            .position = .{ .line = 23, .character = 19 },
        },
        methods[1],
    );
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = try StringTable.put("toString"),
            .return_type = try StringTable.put("String"),
            .position = .{ .line = 27, .character = 18 },
        },
        methods[2],
    );
    try std.testing.expectEqualDeep(
        AstMethodInfo{
            .name = try StringTable.put("get"),
            .return_type = try StringTable.put("V"),
            .position = .{ .line = 31, .character = 13 },
        },
        methods[3],
    );
}

test "analyzeFile" {
    try StringTable.init();
    ts_helpers.init();
    var index = try Index.init(testgpa.allocator());

    const text = @embedFile("test/HashMap.java");
    try index.analyzeFile("file:///test/project/HashMap.java", text);
    const ast_class = index.ast_classes.items[0];

    const imports = ast_class.imports;
    try std.testing.expectEqualStrings("java.io.IOException", StringTable.toSlice(imports[0]));
    try std.testing.expectEqualStrings("java.io.InvalidObjectException", StringTable.toSlice(imports[1]));
    try std.testing.expectEqualStrings("java.io.ObjectInputStream", StringTable.toSlice(imports[2]));
    try std.testing.expectEqualStrings("java.io.Serializable", StringTable.toSlice(imports[3]));
    try std.testing.expectEqualStrings("java.lang.reflect.ParameterizedType", StringTable.toSlice(imports[4]));
    try std.testing.expectEqualStrings("java.lang.reflect.Type", StringTable.toSlice(imports[5]));
    try std.testing.expectEqualStrings("java.util.function.BiConsumer", StringTable.toSlice(imports[6]));
    try std.testing.expectEqualStrings("java.util.function.BiFunction", StringTable.toSlice(imports[7]));
    try std.testing.expectEqualStrings("java.util.function.Consumer", StringTable.toSlice(imports[8]));
    try std.testing.expectEqualStrings("java.util.function.Function", StringTable.toSlice(imports[9]));
    try std.testing.expectEqualStrings("jdk.internal.access.SharedSecrets", StringTable.toSlice(imports[10]));

    try std.testing.expectEqualStrings("file:///test/project/HashMap.java", ast_class.uri);
    try std.testing.expectEqual(Position{ .line = 14, .character = 13 }, ast_class.position);
}

test "array type" {
    try StringTable.init();
    ts_helpers.init();
    var index = try Index.init(testgpa.allocator());
    try index.indexProject(testgpa.allocator(), "src/test/Arrays/");
    const klass = index.getClass("mypackage.ClassA");
    const first = klass.methods[0];
    try std.testing.expectEqual(Primitive.toClassHandle(.int), first.return_type);

    const second = klass.methods[1];
    try std.testing.expectEqual(index.getClass("mypackage.ClassB"), index.getClassFromHandle(second.return_type));

    const klassB = index.getClass("mypackage.ClassB");
    const usages = klassB.usages.items;
    try std.testing.expectEqual(2, usages.len);
    try std.testing.expectEqual(18, usages[0].line);
    try std.testing.expectEqual(8, usages[0].character);
}
