const std = @import("std");
const Location = @import("lsp_messages.zig").Location;
pub const Position = @import("lsp_messages.zig").Position;

pub const ClassHandle = packed struct {
    generationId: u8,
    index: u32,
};

pub const AstClassInfo = struct { packageAndName: []const u8, imports: [][]const u8, methods: []AstMethodInfo, uriPosition: UriPosition, };
pub const Class = struct {
    packageAndName: []const u8,
    imports: []ClassHandle,
    methods: []Method,
    //access: JavaAccess
    //static_fields: []Reference
    uri: []const u8,
    position: Position,
};

pub const AstMethodInfo = struct {
    name: []const u8,
    //access: JavaAccess
    returnType: []const u8,
    position: Position,
};

pub const Method = struct {
    name: []const u8,
    //access: JavaAccess
    returnType: ClassHandle,
    position: Location,
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
