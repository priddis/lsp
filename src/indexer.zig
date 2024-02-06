//TODO- Revaluate uses of 'unreachable' in this file
const std = @import("std");
const assert = std.debug.assert;
const File = std.fs.File;
const Logger = @import("log.zig");
const IndexingError = @import("errors.zig").IndexingError;
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
const Symbols = @import("ts_constants.zig").Symbols;
const Fields = @import("ts_constants.zig").Fields;

extern "c" fn tree_sitter_java() *c.TSLanguage;

pub const Lookup = struct {
    row: u32 = 0,
    column: u32 = 0,
};

pub const Range = struct {
    start: usize = 0,
    end: usize = 0,
};

pub const ClassTable = std.StringArrayHashMap(struct {
    position: Lookup,
    method_range: Range,
    uri: []const u8,
});

pub const MethodTable = std.StringHashMap(Lookup);

pub const Tables = struct {
    class_lookup: ClassTable,
    method_lookup: MethodTable,

    pub fn init(alloc: std.mem.Allocator) Tables {
        return .{ .class_lookup = ClassTable.init(alloc), .method_lookup = MethodTable.init(alloc) };
    }
};
var parser: *c.TSParser = undefined;

///Sets up parsers and queries
pub fn init() void {
    parser = c.ts_parser_new().?;
    _ = c.ts_parser_set_language(parser, tree_sitter_java());
}

pub fn indexProject(alloc: std.mem.Allocator, project: []const u8) IndexingError!Tables {
    var buf = [_]u8{0} ** 500000;
    var class_lookup = ClassTable.init(alloc);
    var method_lookup = MethodTable.init(alloc);

    var it = std.fs.openDirAbsolute(project, .{ .iterate = true, .access_sub_paths = true, .no_follow = true }) catch |err| switch (err) {
        else => @panic("Could not open directory"),
    };
    defer it.close();

    var walker = it.walk(alloc) catch |err| switch (err) {
        error.OutOfMemory => @panic("OOM"),
    };
    while (walker.next() catch @panic("Cannot navigate dir")) |entry| {
        if (entry.basename.len > 5) {
            const filetype: []const u8 = entry.basename[entry.basename.len - 5 ..];
            if (entry.kind == .file and std.mem.eql(u8, filetype, ".java")) {
                const source_file: File = entry.dir.openFile(entry.basename, .{}) catch |err| switch (err) {
                    error.FileTooBig => continue,
                    error.AccessDenied => continue,
                    error.NoSpaceLeft => unreachable, //Indexing takes no disk space
                    error.SymLinkLoop => unreachable,
                    error.IsDir => unreachable,
                    error.Unexpected => unreachable,
                    else => unreachable,
                };
                defer source_file.close();
                const length: u32 = @intCast(source_file.readAll(&buf) catch unreachable);
                const text = buf[0..length];

                const tree_opt = c.ts_parser_parse_string(parser, null, &buf, length);
                defer c.ts_tree_delete(tree_opt);

                if (tree_opt) |tree| {
                    const package_opt = collectPackage(tree, text);
                    if (package_opt) |package| {
                        const method_start = method_lookup.count();
                        collectMethods(&method_lookup, tree, text);
                        const method_end = method_lookup.count();

                        const path_uri: []u8 = std.mem.concat(alloc, u8, &.{ "file://", project, "/", entry.path }) catch @panic("OOM");
                        collectClasses(alloc, &class_lookup, tree, text, path_uri, package, @truncate( method_start), @truncate(method_end));
                    }
                } else {
                    //TODO: remove if not hit in testing, otherwise handle
                    @panic("AST not created");
                }
            }
        }
    }
    return .{ .class_lookup = class_lookup, .method_lookup = method_lookup };
}

pub fn collectPackage(tree: *c.TSTree, text: []const u8) ?[]const u8 {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.package_declaration) {
            const package_decl = c.ts_node_named_child(node, 0);
            const start = c.ts_node_start_byte(package_decl);
            const end = c.ts_node_end_byte(package_decl);
            return text[start .. end];
        }
    }
    return null;
}


//TODO-parse inner classes + multiple classes in the same file (Single file program feature?)
pub fn collectClasses(alloc: std.mem.Allocator, collect: *ClassTable, tree: *c.TSTree, text: []const u8, uri: []const u8, package: []const u8, method_start: u32, method_end: u32) void {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);

    while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.class_declaration) {
            const class_decl = c.ts_node_child_by_field_id(node, Fields.name);
            const start = c.ts_node_start_byte(class_decl);
            const end = c.ts_node_end_byte(class_decl);
            const point = c.ts_node_start_point(class_decl);
            const package_and_class = std.mem.concat(alloc, u8, &.{package, ".", text[start..end]}) catch @panic("OOM");
            collect.put(package_and_class, .{ .uri = uri, .position = .{ .row = point.row, .column = point.column }, .method_range = .{.start = method_start, .end = method_end}}) catch @panic("OOM");
            return;
        }
    }
}

pub fn collectMethods(collect: *MethodTable, tree: *c.TSTree, text: []const u8) void {
    const root = c.ts_tree_root_node(tree);
    var node = c.ts_node_child(root, 0);
    var class_body: ?c.TSNode = undefined;
    var found = false;

    loop: while (!c.ts_node_is_null(node)) {
        defer node = c.ts_node_next_named_sibling(node);
        const symbol = c.ts_node_symbol(node);
        if (symbol == Symbols.class_declaration) {
            class_body  = c.ts_node_child_by_field_id(node, Fields.body);
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
            const start = c.ts_node_start_byte(node);
            const end = c.ts_node_end_byte(node);
            const point = c.ts_node_start_point(node);
            collect.put(text[start..end], .{ .row = point.row, .column = point.column }) catch @panic("OOM");
        }
    }
}

const expectEqual = std.testing.expectEqual;
test "collectPackage" {
    init();
    const text = @embedFile("testcode/HashMap.java");
    const tree = c.ts_parser_parse_string(parser, null, text, @intCast(text.len));
    const package = collectPackage(tree.?, text);
    try std.testing.expectEqualStrings("java.util", package.?);
}

test "indexProject" {
    init();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);
    const tables = try indexProject(alloc, "/home/micah/code/lsp/src/testcode");

    try expectEqual(@as(usize, 118), tables.method_lookup.count());
}

test "collectClasses" {
    init();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);

    var cl = ClassTable.init(alloc);

    const text = @embedFile("testcode/HashMap.java");
    const tree_opt = c.ts_parser_parse_string(parser, null, text, @intCast(text.len));
    const tree = tree_opt.?;
    defer c.ts_tree_delete(tree_opt);
    collectClasses(alloc, &cl, tree, text, "testcode/HashMap.java", "java.util", 0, 0);
    try std.testing.expectEqual(@as(usize, 1), cl.count());
    try std.testing.expect(cl.contains("java.util.HashMap"));
}

pub fn main() !void {
    init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    //defer std.heap.ArenaAllocator.deinit(arena);
    _ = try indexProject(alloc, "/home/micah/code/lsp/test_projects/elasticsearch");
}

