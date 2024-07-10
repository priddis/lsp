const std = @import("std");
const StringTable = @import("StringTable.zig");
const StringHandle = @import("StringTable.zig").StringHandle;
const ClassHandle = @import("types.zig").ClassHandle;

const Namespace = @This();

pub const ImportResult = struct {
    name: StringHandle,
    package_or_class: PackageOrClass,
};

pub const PackageOrClass = union(enum) {
    package: Package,
    splat: Package,
    class: ClassHandle,
};

pub const Package = struct {
    classes: std.AutoHashMap(StringHandle, ClassHandle),
    packages: std.AutoHashMap(StringHandle, Package),

    pub fn resolveName(self: Package, string_table: *const StringTable, import_string: []const u8) ?ImportResult {
        var it = std.mem.splitScalar(u8, import_string, '.');
        var p: Namespace.Package = self;
        var name = StringTable.empty_string;
        while (it.next()) |package_string| {
            if (std.mem.eql(u8, package_string, "*")) {
                return ImportResult{ .name = name, .package_or_class = .{ .splat = p } };
            }
            name = string_table.get(package_string) orelse return null;
            const maybe_package = p.packages.get(name);
            if (maybe_package) |next_package| {
                p = next_package;
            } else {
                const klass = p.classes.get(name) orelse return null;
                return ImportResult{ .name = name, .package_or_class = .{ .class = klass } };
            }
        }
        return ImportResult{ .name = name, .package_or_class = .{ .package = p } };
    }
};

root: Package,
string_table: *StringTable,
allocator: std.mem.Allocator,

pub fn new(allocator: std.mem.Allocator, string_table: *StringTable) Namespace {
    return .{
        .root = .{
            .classes = std.AutoHashMap(StringHandle, ClassHandle).init(allocator),
            .packages = std.AutoHashMap(StringHandle, Package).init(allocator),
        },
        .string_table = string_table,
        .allocator = allocator,
    };
}

pub fn insert(self: *Namespace, package: []const u8, name: []const u8, class: ClassHandle) !void {
    var it = std.mem.splitScalar(u8, package, '.');
    var p = &self.root;
    while (it.next()) |package_string| {
        const str_handle = try self.string_table.put(package_string);
        const res = try p.packages.getOrPut(str_handle);
        if (!res.found_existing) {
            res.value_ptr.* = .{
                .classes = std.AutoHashMap(StringHandle, ClassHandle).init(self.allocator),
                .packages = std.AutoHashMap(StringHandle, Package).init(self.allocator),
            };
        }
        p = res.value_ptr;
    }
    const str_handle = try self.string_table.put(name);
    try p.classes.putNoClobber(str_handle, class);
}

pub fn resolveImport(self: @This(), name: StringHandle) ?ImportResult {
    const str = self.string_table.toSlice(name);
    return self.root.resolveName(self.string_table, str);
}

pub fn resolveImportString(self: @This(), str: []const u8) ?ImportResult {
    return self.root.resolveName(self.string_table, str);
}

pub fn getPackage(self: Namespace, package: []const u8) ?Package {
    var it = std.mem.splitScalar(u8, package, '.');
    var p = self.root;
    while (it.next()) |package_string| {
        const handle = self.string_table.get(package_string) orelse return null;
        p = p.packages.get(handle) orelse return null;
    }
    return p;
}

pub fn getClass(self: Namespace, package: Package, class: []const u8) ?ClassHandle {
    const str = self.string_table.get(class) orelse return null;
    return package.classes.get(str);
}

test "Package" {
    var st = try StringTable.init(std.heap.page_allocator);

    var namespace: Namespace = new(std.heap.page_allocator, &st);
    try namespace.insert("java.util", "ArrayList", ClassHandle{ .generationId = 0, .index = 1 });
    try namespace.insert("java.util", "HashMap", ClassHandle{ .generationId = 0, .index = 2 });
    try namespace.insert("java.collections.api", "HashMap", ClassHandle{ .generationId = 0, .index = 3 });
    try namespace.insert("com.src.packages.zig", "Exception", ClassHandle{ .generationId = 0, .index = 4 });
    try namespace.insert("org.src.packages.zig", "Exception", ClassHandle{ .generationId = 0, .index = 5 });

    var package = namespace.getPackage("java.util").?;
    var class = package.classes.get(st.get("ArrayList").?).?;
    try std.testing.expect(class.index == 1);

    package = namespace.getPackage("java.util").?;
    class = package.classes.get(st.get("HashMap").?).?;
    try std.testing.expect(class.index == 2);

    package = namespace.getPackage("java.collections.api").?;
    class = package.classes.get(st.get("HashMap").?).?;
    try std.testing.expect(class.index == 3);

    package = namespace.getPackage("com.src.packages.zig").?;
    class = package.classes.get(st.get("Exception").?).?;
    try std.testing.expect(class.index == 4);

    package = namespace.getPackage("org.src.packages.zig").?;
    class = package.classes.get(st.get("Exception").?).?;
    try std.testing.expect(class.index == 5);
}

test "resolveImport" {
    var st = try StringTable.init(std.heap.page_allocator);

    var namespace: Namespace = new(std.heap.page_allocator, &st);
    try namespace.insert("java.util", "ArrayList", ClassHandle{ .generationId = 0, .index = 1 });
    try namespace.insert("java.util", "HashMap", ClassHandle{ .generationId = 0, .index = 2 });
    try namespace.insert("java", "Exception", ClassHandle{ .generationId = 0, .index = 3 });

    const array_list = namespace.resolveImportString("java.util.ArrayList").?.package_or_class.class;
    try std.testing.expect(1 == array_list.index);

    const hash_map = namespace.resolveImportString("java.util.HashMap").?.package_or_class.class;
    try std.testing.expect(2 == hash_map.index);

    const exception = namespace.resolveImportString("java.Exception").?.package_or_class.class;
    try std.testing.expect(3 == exception.index);

    const notfound = namespace.resolveImportString("java.notfound");
    try std.testing.expect(notfound == null);

    const util = namespace.resolveImportString("java.util").?.package_or_class.package;
    try std.testing.expect(util.resolveName(&st, "ArrayList").?.package_or_class.class.index == 1);

    const util_splat = namespace.resolveImportString("java.util.*").?.package_or_class.splat;
    try std.testing.expect(util_splat.resolveName(&st, "ArrayList").?.package_or_class.class.index == 1);

    const java = namespace.resolveImportString("java").?.package_or_class.package;
    try std.testing.expect(java.resolveName(&st, "util.ArrayList").?.package_or_class.class.index == 1);
    try std.testing.expect(java.resolveName(&st, "util.HashMap").?.package_or_class.class.index == 2);
    try std.testing.expect(java.resolveName(&st, "Exception").?.package_or_class.class.index == 3);
}
