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
const collectors = @import("collectors.zig");
const ts_helpers = @import("ts_helpers.zig");

extern "c" fn tree_sitter_java() *c.TSLanguage;

pub const Point = struct {
    row: u32 = 0,
    column: u32 = 0,
};

pub const UriPosition = struct {
    uri: []const u8,
    position: Point,
};

pub const Range = struct {
    start: usize = 0,
    end: usize = 0,
};

pub const ClassTable = std.StringArrayHashMap(struct {
    position: Point,
    methods: std.StringArrayHashMap(Point),
    uri: []const u8,
});

pub const Tables = struct {
    classes: ClassTable,

    pub fn init(alloc: std.mem.Allocator) Tables {
        return .{ .classes = ClassTable.init(alloc)  };
    }
};

pub fn indexProject(alloc: std.mem.Allocator, project: []const u8) IndexingError!Tables {
    var buf = [_]u8{0} ** 500000;
    var classes = ClassTable.init(alloc);

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
                const length: u32 = @intCast(source_file.readAll(&buf) catch @panic("Cannot read file"));
                const text = buf[0..length];

                const tree_opt = c.ts_parser_parse_string(ts_helpers.parser, null, &buf, length);
                defer c.ts_tree_delete(tree_opt);

                if (tree_opt) |tree| {
                    const package_opt = collectors.collectPackage(tree, text);
                    if (package_opt) |package| {
                        var methods = std.StringArrayHashMap(Point).init(alloc);
                        methods.ensureTotalCapacity(200) catch @panic("oom"); //TODO, scale capacity
                        collectors.collectMethods(&methods, tree, text);

                        const path_uri: []u8 = std.mem.concat(alloc, u8, &.{ "file://", project, "/", entry.path }) catch @panic("OOM");
                        collectors.collectClasses(alloc, &classes, tree, text, path_uri, package, methods);
                    }
                } else {
                    //TODO: remove if not hit in testing, otherwise handle
                    @panic("AST not created");
                }
            }
        }
    }
    return .{ .classes = classes };
}

test "indexProject" {
    ts_helpers.init();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);
    const tables = try indexProject(alloc, "/home/micah/code/lsp/src/testcode");
    try std.testing.expectEqual(@as(usize, 4), tables.classes.count());
    try std.testing.expect(tables.classes.contains("java.util.ArrayList"));
    const arrayList = tables.classes.get("java.util.ArrayList").?;
    try std.testing.expect(arrayList.methods.contains("sort"));
    try std.testing.expect(arrayList.methods.contains("replaceAllRange"));
}

