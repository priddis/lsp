const std = @import("std");
const lsp_messages = @import("lsp_messages.zig");
const server_capabilities = @import("server_capabilities.zig");
const logger = @import("log.zig");
const indexer = @import("indexer.zig");

const state = .{
    .ready1 = false,
    .ready2 = false,
    .shutdown = false,
    .exit = false,
};

const parse_options = .{ .allocate = .alloc_always, .ignore_unknown_fields = true };

pub fn initialize(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    const params = std.json.innerParseFromValue(lsp_messages.InitializeParams, allocator, req.params.?, parse_options) catch {
        std.log.err("Error parsing params {any}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    logger.log("initialize params {any}\n", .{params});
    const init_result: lsp_messages.InitializeResult = .{ .serverInfo = .{ .name = "jlava", .version = "0.1" }, .capabilities = server_capabilities.capabilities };
    const res = lsp_messages.LspResponse(@TypeOf(init_result)).build(init_result, req.id);

    if (params.rootUri) |uri_string| {
        logger.log("opening path {s}\n", .{uri_string});
        const uri = std.Uri.parse(uri_string) catch unreachable;
        indexer.init();
        const table = indexer.indexProject(allocator, uri.path) catch unreachable;
        _ = table;
    }

    return std.json.stringifyAlloc(allocator, res, .{ .emit_null_optional_fields = false }) catch {
        std.log.err("Error stringifying response {?}\n", .{res});
        return null;
    };
}
pub fn initialized(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    _ = allocator;
    _ = req;
    return null;
}
pub fn shutdown(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    std.log.err("shutdown server\n", .{});
    const params = std.json.innerParseFromValue(lsp_messages.InitializedParams, allocator, req.params.?, parse_options) catch {
        std.log.err("Error parsing params {?}\n", .{req.params});
        return null; //TODO, does the server need to respond to a parsing error?
    };
    _ = params;
    return null;
}
pub fn exit(allocator: std.mem.Allocator, req: lsp_messages.LspRequest) ?[]const u8 {
    std.log.err("exit server\n", .{});
    _ = allocator;
    _ = req;
    std.process.exit(0);
    return null;
}

const test_alloc = std.testing.allocator;
test "initialize" {
    const req =
        \\{ "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "processId": 3877617, "rootPath": "/home/malintha/Documents/wso2/experimental/projects/ballerina/error-constructor", "rootUri": "file:///home/malintha/Documents/wso2/experimental/projects/ballerina/error-constructor", "initializationOptions": { "enableSemanticHighlighting": true }, "capabilities": { "workspace": { "applyEdit": true, "workspaceEdit": { "documentChanges": true, "resourceOperations": [ "create", "rename", "delete" ], "failureHandling": "textOnlyTransactional" }, "didChangeConfiguration": { "dynamicRegistration": true }, "didChangeWatchedFiles": { "dynamicRegistration": true }, "symbol": { "symbolKind": { "valueSet": [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 ] }, "dynamicRegistration": true }, "executeCommand": { "dynamicRegistration": true }, "workspaceFolders": true, "configuration": true }, "textDocument": { "synchronization": { "willSave": true, "willSaveWaitUntil": true, "didSave": true, "dynamicRegistration": true }, "completion": { "completionItem": { "snippetSupport": true, "commitCharactersSupport": true, "documentationFormat": [ "markdown", "plaintext" ], "deprecatedSupport": true, "preselectSupport": true, "tagSupport": { "valueSet": [ 1 ] } }, "completionItemKind": { "valueSet": [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 ] }, "contextSupport": true, "dynamicRegistration": true }, "hover": { "contentFormat": [ "markdown", "plaintext" ], "dynamicRegistration": true }, "signatureHelp": { "signatureInformation": { "documentationFormat": [ "markdown", "plaintext" ], "parameterInformation": { "labelOffsetSupport": true } }, "contextSupport": true, "dynamicRegistration": true }, "references": { "dynamicRegistration": true }, "documentHighlight": { "dynamicRegistration": true }, "documentSymbol": { "symbolKind": { "valueSet": [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 ] }, "hierarchicalDocumentSymbolSupport": true, "dynamicRegistration": true }, "formatting": { "dynamicRegistration": true }, "rangeFormatting": { "dynamicRegistration": true }, "onTypeFormatting": { "dynamicRegistration": true }, "declaration": { "linkSupport": true, "dynamicRegistration": true }, "definition": { "linkSupport": true, "dynamicRegistration": true }, "typeDefinition": { "linkSupport": true, "dynamicRegistration": true }, "implementation": { "linkSupport": true, "dynamicRegistration": true }, "codeAction": { "codeActionLiteralSupport": { "codeActionKind": { "valueSet": [ "", "quickfix", "refactor", "refactor.extract", "refactor.inline", "refactor.rewrite", "source", "source.organizeImports" ] } }, "isPreferredSupport": true, "dynamicRegistration": true }, "codeLens": { "dynamicRegistration": true }, "documentLink": { "tooltipSupport": true, "dynamicRegistration": true }, "colorProvider": { "dynamicRegistration": true }, "rename": { "prepareSupport": true, "dynamicRegistration": true }, "publishDiagnostics": { "relatedInformation": true, "tagSupport": { "valueSet": [ 1, 2 ] }, "versionSupport": false }, "foldingRange": { "rangeLimit": 5000, "lineFoldingOnly": true, "dynamicRegistration": true }, "selectionRange": { "dynamicRegistration": true } }, "window": { "workDoneProgress": true } }, "clientInfo": { "name": "vscode", "version": "1.61.0" }, "trace": "verbose", "workspaceFolders": [ { "uri": "file:///home/malintha/Documents/wso2/experimental/projects/ballerina/error-constructor", "name": "error-constructor" } ] } }
    ;
    _ = req;

    //const res_op = initialize(test_alloc,

}
