const std = @import("std");
const index = @import("index.zig");
const lsp_messages = @import("lsp_messages.zig");
const ts_helpers = @import("ts_helpers.zig");
const Logger = @import("log.zig");
const errors = @import("errors.zig");

const Buffer = @import("buffer.zig").Buffer;
const Tables = @import("types.zig").Tables;
const Position = @import("types.zig").Position;
const RecoverableError = @import("errors.zig").RecoverableError;

const Symbols = @import("ts_constants.zig").Symbols;
const Fields = @import("ts_constants.zig").Fields;

pub var buffers: std.ArrayList(Buffer) = undefined;
const c = ts_helpers.c;

pub fn init(alloc: std.mem.Allocator) void {
    buffers = std.ArrayList(Buffer).init(alloc);
}

pub fn indexProject(alloc: std.mem.Allocator, project_path: []const u8) void {
    std.debug.assert(std.fs.path.isAbsolute(project_path));
    _ = alloc;
    //tables = index.indexProject(alloc, project_path) catch @panic("Cannot index project");
}

pub fn dump() void {
    //const a = index.classes.keys();
    //for (a) |k| {
    //    std.debug.print("\nclass {s}", .{k});
    //    for (index.classes.get(k).?.methods.keys()) |p| {
    //        std.debug.print("{s}\n", .{p});
    //    }
    //}
}

pub fn findBuffer(uri: []const u8) ?*Buffer {
    for (buffers.items) |*buf| {
        if (std.mem.eql(u8, buf.uri, uri)) {
            return buf;
        }
    }
    return null;
}

pub fn lookupMethod(method_name: []const u8) ?Position {
    _ = method_name;
    //for (buffers.items) |*buf| {
    //    if (std.mem.eql(u8, class.name, buf.class_name)) {
    //        return buf.methods.get(method_name) orelse return null;
    //    }
    //}

    //std.debug.assert(tables.classes.count() > 0);
    //const cl = tables.classes.get(class.fqdn) orelse return null;
    //return cl.methods.get(method_name) orelse return null;
    return null;
}

pub fn gotoMethodDeclaration(buf: *const Buffer, method_node: c.TSNode) ?Position {
    const parent = c.ts_node_parent(method_node);
    if (c.ts_node_is_null(parent)) {
        return null;
    }
    const method_name = ts_helpers.nodeToText(method_node, buf.text);
    _ = method_name;

    const object_node = c.ts_node_child_by_field_id(parent, Fields.object);

    // Object methods
    if (!c.ts_node_is_null(object_node)) {
        const point = c.ts_node_start_point(object_node);
        const decl_node = findIdentifierDecl(buf, point.row, point.column) orelse return null;
        const type_name = resolveType(decl_node, buf.text) orelse return null;
        _ = type_name;

        //class name to fqdn
        //for (buf.imports.items) |class| {
        //    if (std.mem.eql(u8, class.name, type_name)) {
        //        return lookupMethod(method_name, class);
        //    }
        //}
    }

    // Static/local
    //if (ts_helpers.nodeToText(node, buf.text)) |name| {
    //   Logger.log("lookup {s}\n", .{name});
    //const lookup = index.methods.get(name);
    //if (lookup) |l| {
    //return .{ .row = l.row, .column = l.column };
    //}
    //}
    return null;
}

//Given a declaration node, returns the type
pub fn resolveType(node: c.TSNode, text: []const u8) ?[]const u8 {
    const parent = c.ts_node_parent(node);
    if (c.ts_node_is_null(parent)) {
        return null;
    }
    const parent_symbol = c.ts_node_symbol(parent);
    if (parent_symbol == Symbols.formal_parameter) {
        const type_node = c.ts_node_child_by_field_id(parent, Fields.type);
        return ts_helpers.nodeToText(type_node, text);
    }
    const grandparent = c.ts_node_parent(parent);
    if (c.ts_node_is_null(grandparent)) {
        return null;
    }
    const grandparent_symbol = c.ts_node_symbol(grandparent);
    if (grandparent_symbol == Symbols.local_variable_declaration or grandparent_symbol == Symbols.field_declaration) {
        const type_node = c.ts_node_child_by_field_id(grandparent, Fields.type);
        //TODO: Resolve local variable type inference
        return ts_helpers.nodeToText(type_node, text);
    }
    return null;
}

///Starting from the reference, search the given scope for the ref definition
///If not found in the given scope, move to the parent scope
pub fn findIdentifierDecl(self: *const Buffer, row: u32, col: u32) ?c.TSNode {
    const node = ts_helpers.pointToNode(self.tree, row, col) orelse return null;
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
            if (symbol == Symbols.local_variable_declaration or symbol == Symbols.field_declaration) {
                const declarator_node = c.ts_node_child_by_field_id(cur_node, Fields.declarator);
                std.debug.assert(!c.ts_node_is_null(declarator_node));

                const name_node = c.ts_node_child_by_field_id(declarator_node, Fields.name);
                const node_text = ts_helpers.nodeToText(name_node, self.text);
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

//get node at point
//search text for identifier
//resolve type of each identifier in scope
pub fn references(allocator: std.mem.Allocator, uri: []u8, position: lsp_messages.Position) []lsp_messages.Location {
    if (findBuffer(uri)) |buf| {
        const root = c.ts_tree_root_node(buf.tree);
        std.debug.assert(!c.ts_node_is_null(root));
        const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = position.line, .column = position.character }, .{ .row = position.line, .column = position.character });

        const identifier = ts_helpers.nodeToName(node);
        const source_type = ts_helpers.varOrMethod(node);

        switch (source_type) {
            .ref => findReferenceUsages(allocator, buf, identifier, node),
            .method => findMethodUsages(allocator, buf, identifier, node),
            else => @panic("TODO"),
        }
    }
}

pub fn findReferenceUsages(text: []const u8, identifier: []const u8, node: *const c.TSNode) void {
    _ = text;
    _ = identifier;
    _ = node;
}

pub fn findMethodUsages(allocator: std.mem.Allocator, project: []const u8, identifier: []const u8) ![]lsp_messages.Location {
    var it = std.fs.openDirAbsolute(project, .{ .iterate = true, .access_sub_paths = true, .no_follow = true }) catch |err| switch (err) {
        else => @panic("Could not open directory"),
    };
    defer it.close();
    var buf = [_]u8{0} ** 500000; //TODO

    var walker = it.walk(allocator) catch @panic("Out of Memory");
    while (walker.next() catch @panic("Cannot navigate dir")) |entry| {
        if (entry.basename.len > 5 and entry.kind == .file and std.mem.eql(u8, entry.basename[entry.basename.len - 5 ..], ".java")) {
            const source_file: std.fs.File = entry.dir.openFile(entry.basename, .{}) catch |err| switch (err) {
                error.FileTooBig => continue,
                error.AccessDenied => continue,
                error.NoSpaceLeft => unreachable, //Indexing takes no disk space
                error.SymLinkLoop => unreachable,
                error.IsDir => unreachable,
                error.Unexpected => unreachable,
                else => unreachable,
            };
            defer source_file.close();
            const length: u32 = @intCast(source_file.readAll(&buf) catch @panic("Cannot read file"));
            const text = buf[0..length];
            while (std.mem.indexOf(u8, text, identifier)) |id_index| {
                _ = id_index;
                //classes.addOne();

            }
        }
    }
    return .{};
}

pub fn definition(uri: []const u8, line: u32, character: u32) ?lsp_messages.Location {
    if (findBuffer(uri)) |buf| {
        const root = c.ts_tree_root_node(buf.tree);
        std.debug.assert(!c.ts_node_is_null(root));
        const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = line, .column = character }, .{ .row = line, .column = character });

        const source_type = ts_helpers.varOrMethod(node);
        const point = switch (source_type) {
            .ref => ref: {
                const maybe_ref_node = findIdentifierDecl(buf, line, character);
                break :ref if (maybe_ref_node) |ref_node| ts_helpers.nodeToPoint(ref_node) else null;
            },
            .method => gotoMethodDeclaration(buf, node),
            .class => null,
            .none => null,
        };
        if (point) |p| {
            return .{ .uri = buf.uri, .range = .{ .start = p, .end = p } };
        } else {
            return null;
        }
    }
    return null;
}

pub fn gotoTypeDefinition(self: *const Buffer, row: u32, col: u32) ?lsp_messages.Location {
    const node = findIdentifierDecl(self, row, col) orelse return null;
    const type_name = resolveType(node, self.text) orelse return null;
    _ = type_name;
    //for (self.imports.items) |*class| {
    //    if (std.mem.eql(u8, class.name, type_name)) {
    //        if (tables.classes.get(class.fqdn)) |cl| {
    //            return .{
    //                .uri = cl.uri,
    //                .range = .{
    //                    .start = .{ .line = cl.position.line, .character = cl.position.character },
    //                    .end = .{ .line = cl.position.line, .character = cl.position.character },
    //                },
    //            };
    //        }
    //    }
    //}
    return null;
}

const array_list_code = @embedFile("testcode/ArrayListSmall.java");
const array_list_code_edit = @embedFile("testcode/ArrayListSmall2.java");

test "resolve type - parameter" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 36, .column = 52 }, .{ .row = 36, .column = 52 });

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("int", type_str.?);
}

test "resolve type - field declaration" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 12, .column = 31 }, .{ .row = 12, .column = 31 });

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("long", type_str.?);
}

test "resolve type - local variable declaration" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 37, .column = 17 }, .{ .row = 37, .column = 17 });

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("Object[]", type_str.?);
}

test "resolve type - local variable hashmap" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 61, .column = 23 }, .{ .row = 61, .column = 23 });

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("HashMap", type_str.?);
}

test "go to method declaration - object.method" {
    ts_helpers.init();
    const tree = c.ts_parser_parse_string(ts_helpers.parser, null, array_list_code, @intCast(array_list_code.len));
    const root = c.ts_tree_root_node(tree);
    //gotoMethodDeclaration
    const node = c.ts_node_named_descendant_for_point_range(root, .{ .row = 61, .column = 23 }, .{ .row = 61, .column = 23 });

    const type_str = resolveType(node, array_list_code);
    try std.testing.expectEqualStrings("HashMap", type_str.?);
}

test "goto ref declaration" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const n = findIdentifierDecl(&doc, 39, 16);
    const p = c.ts_node_start_point(n.?);
    try std.testing.expectEqual(p.row, 31);
    try std.testing.expectEqual(p.column, 23);
}

test "goto parameter declaration" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);
    const n = findIdentifierDecl(&doc, 46, 16);
    const p = c.ts_node_start_point(n.?);
    try std.testing.expectEqual(p.row, 36);
    try std.testing.expectEqual(p.column, 52);
}

test "goto type declaration" {
    ts_helpers.init();
    const tables: Tables = undefined;
    const arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer std.heap.ArenaAllocator.deinit(arena);

    const expected_path = try std.fs.cwd().realpathAlloc(std.heap.page_allocator, "src/testcode");
    _ = expected_path;
    //indexProject(arena.allocator(), expected_path);
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);

    const t = gotoTypeDefinition(&doc, 62, 9);

    try std.testing.expectEqual(@as(usize, 3), tables.classes.count());
    try std.testing.expect(t != null);
    var buf = [_]u8{0} ** 5000;
    const filepath = try std.fs.cwd().realpath("src/testcode/HashMap.java", &buf);
    const expected_file = try std.mem.concat(std.heap.page_allocator, u8, &.{ "file://", filepath });
    try std.testing.expectEqualStrings(expected_file, t.?.uri);
    try std.testing.expectEqual(@as(u32, 138), t.?.range.start.line);
    try std.testing.expectEqual(@as(u32, 13), t.?.range.start.character);
}

test "lookupMethod - new method in buffer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer std.heap.ArenaAllocator.deinit(arena);

    ts_helpers.init();
    init(std.testing.allocator);
    defer buffers.deinit();

    const project_path = try std.fs.cwd().realpathAlloc(std.heap.page_allocator, "src/testcode");
    indexProject(arena.allocator(), project_path);
    var doc = try Buffer.open(std.testing.allocator, "ArrayListSmall.java", array_list_code_edit);
    defer doc.close(std.testing.allocator);
    try buffers.append(doc);
    const res = lookupMethod("newTestMethod");
    try std.testing.expect(res != null);
    try std.testing.expectEqual(@as(u32, 52), res.?.line);
    try std.testing.expectEqual(@as(u32, 16), res.?.character);
}

test "lookupMethod - indexedLookup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const aalloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);

    ts_helpers.init();
    init(std.testing.allocator);
    defer buffers.deinit();

    const project_path = try std.fs.cwd().realpathAlloc(std.heap.page_allocator, "src/testcode");
    indexProject(aalloc, project_path);
    //dump();
    const res = lookupMethod("trimToSize");
    //const res = core.lookupMethod("clone", .{ .name = "HashMap", .fqdn = "java.util.HashMap" });
    try std.testing.expect(res != null);
    try std.testing.expectEqual(@as(u32, 200), res.?.line);
    try std.testing.expectEqual(@as(u32, 16), res.?.character);
}
