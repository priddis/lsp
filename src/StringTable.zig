const std = @import("std");
const StringTable = @This();
const Primitive = @import("types.zig").Primitive;

pub var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};

pub var strings: std.StringArrayHashMap(void) = std.StringArrayHashMap(void).init(gpa.allocator());

pub fn toSlice(str: StringHandle) []const u8 {
    return strings.keys()[str.x];
}

pub fn put(string: []const u8) !StringHandle {
    const getOrPut = try strings.getOrPutAdapted(string, strings.ctx);
    if (!getOrPut.found_existing) {
        getOrPut.key_ptr.* = try gpa.allocator().dupe(u8, string);
    }

    return StringHandle{ .x = getOrPut.index };
}

pub fn get(string: []const u8) ?StringHandle {
    const index = strings.getIndex(string) orelse return null;
    return StringHandle{ .x = index };
}

pub fn init() !void {
    gpa.setRequestedMemoryLimit(6 * 1_000_000_000);
    errdefer strings.deinit();
    inline for (std.meta.tags(Primitive)) |p| {
        _ = try put(@tagName(p));
    }
    empty_string = try put("");
    var_string = try put("var");
    _ = try put("*");
    _ = try put("java.lang.*");
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
    try StringTable.init();
    try std.testing.expect(get("") != null);
    try std.testing.expect(get("*") != null);
    try std.testing.expect(get("var") != null);
    try std.testing.expect(get("int").?.x == @intFromEnum(Primitive.int));
    try std.testing.expect(get("byte").?.x == @intFromEnum(Primitive.byte));
    try std.testing.expect(get("short").?.x == @intFromEnum(Primitive.short));
    try std.testing.expect(get("long").?.x == @intFromEnum(Primitive.long));
    try std.testing.expect(get("float").?.x == @intFromEnum(Primitive.float));
    try std.testing.expect(get("double").?.x == @intFromEnum(Primitive.double));
    try std.testing.expect(get("boolean").?.x == @intFromEnum(Primitive.boolean));
    try std.testing.expect(get("char").?.x == @intFromEnum(Primitive.char));
}

test "String table put" {
    const allocated_string = try std.testing.allocator.alloc(u8, 5);
    @memcpy(allocated_string, "hello");
    try StringTable.init();
    _ = try put("String1");
    _ = try put("String2");
    _ = try put(allocated_string);
    std.testing.allocator.free(allocated_string);

    //Asserts that after the allocated string is deallocated, the string should still exist in the table
    _ = get("hello").?;
}
