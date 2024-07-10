const std = @import("std");
const StringTable = @This();
const Primitive = @import("types.zig").Primitive;

strings: std.StringArrayHashMap(void),

pub fn toSlice(self: *@This(), str: StringHandle) []const u8 {
    return self.strings.keys()[str.x];
}

pub fn put(self: *@This(), string: []const u8) !StringHandle {
    const getOrPut = try self.strings.getOrPut(string);
    return StringHandle{ .x = getOrPut.index };
}

pub fn get(self: *const @This(), string: []const u8) ?StringHandle {
    const index = self.strings.getIndex(string) orelse return null;
    return StringHandle{ .x = index };
}

pub fn init(alloc: std.mem.Allocator) !@This() {
    var st = @This(){
        .strings = std.StringArrayHashMap(void).init(alloc),
    };
    errdefer st.strings.deinit();
    empty_string = try st.put("");
    var_string = try st.put("var");
    _ = try st.put("*");
    inline for (std.meta.tags(Primitive)) |p| {
        _ = try st.put(@tagName(p));
    }
    return st;
}

pub const StringHandle = struct {
    x: usize,

    pub fn equals(self: *const StringHandle, other: ?StringHandle) bool {
        return if (other) |o| self.x == o.x else false;
    }
};

pub var empty_string: StringHandle = undefined; //TODO Replace with const
pub var var_string: StringHandle = undefined;

test "String table initialization" {
    var st = try StringTable.init(std.heap.page_allocator);
    try std.testing.expect(st.get("") != null);
    try std.testing.expect(st.get("*") != null);
    try std.testing.expect(st.get("var") != null);
    try std.testing.expect(st.get("int") != null);
    try std.testing.expect(st.get("byte") != null);
    try std.testing.expect(st.get("short") != null);
    try std.testing.expect(st.get("long") != null);
    try std.testing.expect(st.get("float") != null);
    try std.testing.expect(st.get("double") != null);
    try std.testing.expect(st.get("boolean") != null);
    try std.testing.expect(st.get("char") != null);
}

test "String table put" {
    var st = try StringTable.init(std.heap.page_allocator);
    _ = try st.put("String1");
    _ = try st.put("String2");
}
