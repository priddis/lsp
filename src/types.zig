const std = @import("std");
const Location = @import("lsp/lsp_messages.zig").Location;
pub const Position = @import("lsp/lsp_messages.zig").Position;
const Ast = @import("ts/helpers.zig").Ast;
const StringTable = @import("StringTable.zig");
const StringHandle = StringTable.StringHandle;
const Namespace = @import("Namespace.zig");

pub const ClassHandle = packed struct {
    generationId: u8,
    index: u32,
};

pub const Class = union(enum) {
    primitive: Primitive,
    ast_class: AstClassInfo,
    typed_class: TypedClassInfo,
    full_class: CompleteClassInfo,

    pub fn getPackage(self: Class) StringHandle {
        return switch (self) {
            .primitive => StringTable.empty_string,
            inline else => |klass| klass.package,
        };
    }

    pub fn getName(self: Class) StringHandle {
        return switch (self) {
            .primitive => StringHandle{ .x = 100000 }, //TODO
            inline else => |klass| klass.name,
        };
    }

    pub fn getTree(self: Class) ?*Ast {
        return switch (self) {
            .primitive => null,
            .full_class => null,
            inline else => |klass| &klass.tree,
        };
    }

    pub fn getPosition(self: Class) ?Position {
        return switch (self) {
            .primitive => null,
            inline else => |klass| klass.position,
        };
    }
};

pub const Primitive = enum(u4) {
    int,
    byte,
    short,
    long,
    float,
    double,
    boolean,
    char,
    void,
    //Object,

    pub fn fromStringHandle(handle: StringHandle) ?Primitive {
        if (handle.x >= std.enums.values(Primitive).len) return null;
        return @enumFromInt(handle.x);
    }

    pub fn toClassHandle(p: Primitive) ClassHandle {
        return .{ .generationId = 0, .index = @intFromEnum(p) };
    }
};

pub const AstClassInfo = struct {
    package: StringHandle,
    imports: []StringHandle,
    methods: []AstMethodInfo,
    uri: []const u8,
    position: Position,
    tree: *Ast,
    text: []const u8,
};

pub const TypedClassInfo = struct {
    imports: *std.AutoHashMap(StringHandle, Namespace.PackageOrClass),
    methods: []Method,
    //access: JavaAccess
    //static_fields: []Reference
    uri: []const u8,
    position: Position,
    tree: *Ast,
    text: []const u8,
    usages: std.ArrayList(Position),
};

pub const CompleteClassInfo = struct {
    imports: *std.AutoHashMap(StringHandle, ClassHandle),
    methods: []Method,
    //access: JavaAccess
    //static_fields: []Reference
    uri: []const u8,
    position: Position,
    usages: std.ArrayList(Position),
};

pub const AstMethodInfo = struct {
    name: StringHandle,
    //access: JavaAccess
    return_type: StringHandle,
    position: Position,
};

pub const Method = struct {
    name: StringHandle,
    //access: JavaAccess
    return_type: ClassHandle,
    position: Position,
};

pub const UriPosition = struct {
    uri: []const u8,
    position: Position,
};

pub const Range = struct {
    start: usize = 0,
    end: usize = 0,
};

pub const ClassTable = std.StringArrayHashMap(struct {
    position: Position,
    methods: std.StringArrayHashMap(Position),
    uri: []const u8,
});

pub const Tables = struct {
    classes: ClassTable,

    pub fn init(alloc: std.mem.Allocator) Tables {
        return .{ .classes = ClassTable.init(alloc) };
    }
};

test "type sizes" {
    inline for (&.{ AstClassInfo, TypedClassInfo, CompleteClassInfo }) |t| {
        std.debug.print("Type {s}:\n", .{@typeName(t)});
        inline for (std.meta.fields(t)) |f| {
            std.debug.print("\tField {s} size {d} bytes:\n", .{ f.name, @sizeOf(f.type) });
        }
        std.debug.print("\n", .{});
    }
}
