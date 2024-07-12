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

    pub fn resolveName(self: Package, import_string: []const u8) ?ImportResult {
        var it = std.mem.splitScalar(u8, import_string, '.');
        var p: Namespace.Package = self;
        var name = StringTable.empty_string;
        while (it.next()) |package_string| {
            if (std.mem.eql(u8, package_string, "*")) {
                return ImportResult{ .name = name, .package_or_class = .{ .splat = p } };
            }
            name = StringTable.get(package_string) orelse return null;
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

    pub fn getClass(package: Package, class: []const u8) ?ClassHandle {
        const str = StringTable.get(class) orelse return null;
        return package.classes.get(str);
    }
};

root: Package,
allocator: std.mem.Allocator,

pub fn new(allocator: std.mem.Allocator) Namespace {
    return .{
        .root = .{
            .classes = std.AutoHashMap(StringHandle, ClassHandle).init(allocator),
            .packages = std.AutoHashMap(StringHandle, Package).init(allocator),
        },
        .allocator = allocator,
    };
}

pub fn insert(self: *Namespace, package: []const u8, name: []const u8, class: ClassHandle) !void {
    var it = std.mem.splitScalar(u8, package, '.');
    var p = &self.root;
    while (it.next()) |package_string| {
        const str_handle = try StringTable.put(package_string);
        const res = try p.packages.getOrPut(str_handle);
        if (!res.found_existing) {
            res.value_ptr.* = .{
                .classes = std.AutoHashMap(StringHandle, ClassHandle).init(self.allocator),
                .packages = std.AutoHashMap(StringHandle, Package).init(self.allocator),
            };
        }
        p = res.value_ptr;
    }
    const str_handle = try StringTable.put(name);
    try p.classes.put(str_handle, class);
}

pub fn resolveImport(self: @This(), name: StringHandle) ?ImportResult {
    const str = StringTable.toSlice(name);
    return self.root.resolveName(str);
}

pub fn resolveImportString(self: @This(), str: []const u8) ?ImportResult {
    return self.root.resolveName(str);
}

pub fn getPackage(self: Namespace, package: []const u8) ?Package {
    var it = std.mem.splitScalar(u8, package, '.');
    var p = self.root;
    while (it.next()) |package_string| {
        const handle = StringTable.get(package_string) orelse return null;
        p = p.packages.get(handle) orelse return null;
    }
    return p;
}
var tgpa = std.heap.GeneralPurposeAllocator(.{}){};
var testgpa = tgpa.allocator();
test "Package" {
    try StringTable.init();

    var namespace: Namespace = new(testgpa);
    try namespace.insert(&.{}, &.{}, ClassHandle{ .generationId = 0, .index = 0 });
    try namespace.insert("java.util", "ArrayList", ClassHandle{ .generationId = 0, .index = 1 });
    try namespace.insert("java.util", "HashMap", ClassHandle{ .generationId = 0, .index = 2 });
    try namespace.insert("java.collections.api", "HashMap", ClassHandle{ .generationId = 0, .index = 3 });
    try namespace.insert("com.src.packages.zig", "Exception", ClassHandle{ .generationId = 0, .index = 4 });
    try namespace.insert("org.src.packages.zig", "Exception", ClassHandle{ .generationId = 0, .index = 5 });

    var package = namespace.getPackage("java.util").?;
    var class = package.classes.get(StringTable.get("ArrayList").?).?;
    try std.testing.expect(class.index == 1);

    package = namespace.getPackage("java.util").?;
    class = package.classes.get(StringTable.get("HashMap").?).?;
    try std.testing.expect(class.index == 2);

    package = namespace.getPackage("java.collections.api").?;
    class = package.classes.get(StringTable.get("HashMap").?).?;
    try std.testing.expect(class.index == 3);

    package = namespace.getPackage("com.src.packages.zig").?;
    class = package.classes.get(StringTable.get("Exception").?).?;
    try std.testing.expect(class.index == 4);

    package = namespace.getPackage("org.src.packages.zig").?;
    class = package.classes.get(StringTable.get("Exception").?).?;
    try std.testing.expect(class.index == 5);
}

test "resolveImport" {
    try StringTable.init();

    var namespace: Namespace = new(testgpa);
    try namespace.insert(&.{}, &.{}, ClassHandle{ .generationId = 0, .index = 0 });
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
    try std.testing.expect(util.resolveName("ArrayList").?.package_or_class.class.index == 1);

    const util_splat = namespace.resolveImportString("java.util.*").?.package_or_class.splat;
    try std.testing.expect(util_splat.resolveName("ArrayList").?.package_or_class.class.index == 1);

    const java = namespace.resolveImportString("java").?.package_or_class.package;
    try std.testing.expect(java.resolveName("util.ArrayList").?.package_or_class.class.index == 1);
    try std.testing.expect(java.resolveName("util.HashMap").?.package_or_class.class.index == 2);
    try std.testing.expect(java.resolveName("Exception").?.package_or_class.class.index == 3);
}
