const std = @import("std");
const assert = std.debug.assert;
const File = std.fs.File;

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
pub extern "c" fn tree_sitter_java() *c.TSLanguage;

const Lookup = struct {
    row: u32 = 0,
    column: u32 = 0
};

pub fn indexProject(project: []const u8) !void {
    var index = std.StringHashMap(Lookup).init(std.heap.page_allocator);
    defer index.deinit();

    var it = try std.fs.openIterableDirAbsolute(project, .{ .access_sub_paths = true, .no_follow = true });
    defer it.close();

    var walker = try it.walk(std.heap.page_allocator);
    while (try walker.next()) |entry| {
        if (entry.basename.len > 5) {
            const filetype: []const u8 = entry.basename[entry.basename.len - 5..];
            if (entry.kind == .file and std.mem.eql(u8, filetype, ".java")) {
                const source_file: File = try entry.dir.openFile(entry.basename, .{});
                //const class = try std.heap.page_allocator.dupe(u8, entry.basename);
                try parseFile(source_file, &index);
                defer source_file.close();
            }
        }
    }
}

pub fn parseFile(file: std.fs.File, index: *std.StringHashMap(Lookup)) !void {
    const gpa = std.heap.page_allocator;
    var buf = [_]u8{0} ** 500000;
    const query = "(method_declaration name: (identifier) @name)";
    const length: u32 = @intCast(try file.readAll(&buf));
    const parser = c.ts_parser_new();
    _ = c.ts_parser_set_language(parser, tree_sitter_java());
    const tree = c.ts_parser_parse_string(parser, null, buf[0..length :0], length);
    defer c.ts_tree_delete(tree);

    var err_offset: u32 = 0;
    var error_type: c.TSQueryError = c.TSQueryErrorNone;

    const root = c.ts_tree_root_node(tree);
    const method_query = c.ts_query_new(tree_sitter_java(), query, query.len, &err_offset, &error_type);

    assert(error_type == c.TSQueryErrorNone);
    const cursor = c.ts_query_cursor_new();
    c.ts_query_cursor_exec(cursor, method_query, root);

    var match: c.TSQueryMatch = undefined;
    var matching = c.ts_query_cursor_next_match(cursor, &match);
    while (matching) {
        const captures: [*]const c.TSQueryCapture = match.captures;
        for (0..match.capture_count) |i| {
            const cur = captures[i];
            const start = c.ts_node_start_byte(cur.node);
            const end = c.ts_node_end_byte(cur.node);
            const point = c.ts_node_start_point(cur.node);
            const method: []u8 = try gpa.dupe(u8, buf[start..end]);
            try index.put(method, Lookup{ .row = point.row, .column = point.column });
        }
        matching = c.ts_query_cursor_next_match(cursor, &match);
    }
}
    
