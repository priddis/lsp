/// Manages open files
const std = @import("std");
const logger = @import("log.zig");
const ts = @import("ts/constants.zig");
const ts_fields = ts.Fields;
const ts_symbols = ts.Symbols;
const ts_helpers = @import("ts/helpers.zig");
const UriPosition = @import("types.zig").UriPosition;
const Position = @import("types.zig").Position;

const c = ts_helpers.c;

pub const Buffer = struct {
    uri: []const u8,
    text: [:0]const u8,
    version: u64,
    tree: *c.TSTree,
    class_name: []const u8,

    pub fn open(alloc: std.mem.Allocator, filename: []const u8, text: []const u8) !Buffer {
        logger.log("{s}\n", .{text});

        const duplicated_text = try alloc.dupeZ(u8, text);
        const length: u32 = @intCast(duplicated_text.len);
        std.debug.assert(ts_helpers.parser != undefined);
        if (c.ts_parser_parse_string_encoding(ts_helpers.parser, null, duplicated_text, length, c.TSInputEncodingUTF8)) |tree| {
            const name = ""; //collectors.collectClassName(tree, duplicated_text) orelse @panic("No class name in buffer\n");
            const b = Buffer{
                .uri = try alloc.dupe(u8, filename),
                .text = duplicated_text,
                .version = 0,
                .tree = tree,
                .class_name = name,
            };
            return b;
        } else {
            //TODO; memory leak if tree is null. Panic for now, if encountered later handle
            @panic("Could not parse buffer");
        }
    }

    pub fn close(self: *Buffer, alloc: std.mem.Allocator) void {
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
};

// Tests
//
const array_list_code = @embedFile("../testcode/ArrayListSmall.java");
const array_list_code2 = @embedFile("../testcode/ArrayListSmall2.java");

test "openclose" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayListSmall.java", array_list_code);
    defer doc.close(std.testing.allocator);

    try std.testing.expectEqualStrings("ArrayListSmall", doc.class_name);
}

test "edit" {
    ts_helpers.init();
    var doc = try Buffer.open(std.testing.allocator, "ArrayList.java", array_list_code);
    defer doc.close(std.testing.allocator);

    const str = ts_helpers.pointToName(doc.tree, doc.text, 31, 31);
    try std.testing.expectEqualStrings("elementData", str.?);

    doc.edit(std.testing.allocator, array_list_code2);
    const str2 = ts_helpers.pointToName(doc.tree, doc.text, 25, 24);
    try std.testing.expectEqualStrings("elementData", str2.?);
}
