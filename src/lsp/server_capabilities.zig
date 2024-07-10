const lsp_messages = @import("lsp_messages.zig");

pub const capabilities: lsp_messages.ServerCapabilities =
    .{
    .positionEncoding = .@"utf-8",
    .textDocumentSync = .{ .TextDocumentSyncOptions = .{
        .openClose = true,
        .change = lsp_messages.TextDocumentSyncKind.Full,
    } },
    .definitionProvider = .{ .bool = true },
    .typeDefinitionProvider = .{ .bool = true },
    .referencesProvider = .{ .bool = true },
};
