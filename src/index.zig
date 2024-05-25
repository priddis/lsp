//TODO- Revaluate uses of 'unreachable' in this file
const std = @import("std");
const Limits = @import("limits.zig");
const File = std.fs.File;
const Logger = @import("log.zig");
const IndexingError = @import("errors.zig").IndexingError;
const collectors = @import("collectors.zig");
const Class = @import("types.zig").Class;
const AstClassInfo = @import("types.zig").AstClassInfo;

const ClassIndex = union(enum) {
    astClassInfo: AstClassInfo,
    class: Class,
    class_removed: void,
};

pub fn indexProject(alloc: std.mem.Allocator, project: []const u8) IndexingError!void {
    const type_collector = collectors.TypeCollector.new(alloc, project);
    var classes: std.StringArrayHashMapUnmanaged(ClassIndex) = undefined;
    classes = std.StringArrayHashMapUnmanaged(ClassIndex).init(alloc, &[0][]u8{}, &[0]Class{}) catch @panic("OOM");
    var it = std.fs.cwd().openDir(project, .{ .iterate = true, .access_sub_paths = true, .no_follow = true },) catch |err| {
        return Logger.throw("Could not open project directory {s} due to {!}", .{ project, err }, IndexingError.CouldNotOpenProject,);
    };
    defer it.close();

    var walker = it.walk(alloc) catch |err| switch (err) {
        error.OutOfMemory => @panic("OOM"),
    };
    while (walker.next() catch @panic("Error walking")) |entry| {
        if (entry.kind == .file and
            entry.basename.len > 5 and
            std.mem.eql(u8, ".java", entry.basename[entry.basename.len - 5 ..]))
        {
            const source_file: File = entry.dir.openFile(entry.basename, .{}) catch |err| switch (err) {
                error.FileTooBig => continue, //Todo, show error
                error.AccessDenied => continue, //Todo, show error
                error.NoSpaceLeft => unreachable, //Indexing takes no disk space
                error.SymLinkLoop => unreachable,
                error.IsDir => unreachable,
                error.Unexpected => unreachable,
                else => unreachable,
            };
            defer source_file.close();
            const buf_or_error = source_file.readToEndAlloc(alloc, Limits.max_file_size);
            if (buf_or_error) |buf| {
                const ast_class_info = type_collector.analyzeFile(entry.path, buf) catch |err| {
                    Logger.log("ERROR: out of memory to parse file {s} {!}", .{ entry.basename, err });
                    continue;
                } orelse continue;

                classes.put(alloc, ast_class_info.packageAndName, .{
                    .packageAndName = ast_class_info.packageAndName,
                    .imports = &.{},
                    .methods = &.{},
                    .uri = ast_class_info.uriPosition.uri,
                    .position = ast_class_info.uriPosition.position,
                });
            } else |err| {
                Logger.log("ERROR: Could not open file {s} {!}", .{ entry.basename, err });
            }
        }
    }
    return .{ .classes = .{} };
}

test "indexProject" {
    const ts_helpers = @import("ts_helpers.zig");
    ts_helpers.init();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer std.heap.ArenaAllocator.deinit(arena);
    const tables = try indexProject(alloc, "src/testcode");
    try std.testing.expectEqual(@as(usize, 3), tables.classes.count());
    try std.testing.expect(tables.classes.contains("java.util.ArrayList"));
    const arrayList = tables.classes.get("java.util.ArrayList").?;
    try std.testing.expect(arrayList.methods.contains("sort"));
    try std.testing.expect(arrayList.methods.contains("replaceAllRange"));
}
