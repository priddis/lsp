const lsp_messages = @import("lsp_messages.zig");
const ResponsePayload = @import("lsp_messages.zig").ResponsePayload;
const std = @import("std");
const logger = @import("../log.zig");

pub fn definition(params: lsp_messages.DefinitionParams) ResponsePayload {
    return ResponsePayload{ .link = location };
}

pub fn typeDefinition(params: lsp_messages.TypeDefinitionParams) ResponsePayload {
    return ResponsePayload{ .none = {} };
}
pub fn references(allocator: std.mem.Allocator, params: lsp_messages.ReferenceParams) ResponsePayload {
    return ResponsePayload{ .references = &.{} };
}
