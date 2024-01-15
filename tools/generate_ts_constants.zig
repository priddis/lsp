pub extern "c" fn tree_sitter_java() *c.TSLanguage;
const std = @import("std");

const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

const TSFields = [_][:0]const u8 {
    "name",
    "declarator",
    "object",
    "parameters",
    "body",
};

const TSSymbols = [_][:0]const u8 {
    "field_declaration",
    "local_variable_declaration",
    "method_invocation",
    "formal_parameter",
    //"class_declaration",
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 2) @panic("wrong number of arguments");

    const output_file_path = args[1];
    const output_file = try std.fs.cwd().createFile(output_file_path, .{ .truncate = true });
    defer output_file.close();
    const writer = output_file.writer();

    try writer.writeAll("pub const Fields = struct {\n");
    for (TSFields) |field| {
        const id = c.ts_language_field_id_for_name(tree_sitter_java(), field, @truncate(field.len));
        std.debug.assert(id != 0);
        try std.fmt.format(writer, "\tpub const {s}: u16 = {d};\n", .{field, id});
    }
    try writer.writeAll("};\n");

    try writer.writeAll("pub const Symbols = struct {\n");
    for (TSSymbols) |symbol| {
        const id = c.ts_language_symbol_for_name(tree_sitter_java(), symbol, @truncate(symbol.len), true);
        std.debug.assert(id != 0);
        try std.fmt.format(writer, "\tpub const {s}: u16 = {d};\n", .{symbol, id});
    }
    try writer.writeAll("};\n");
}
