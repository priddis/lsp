const std = @import("std");

pub const LspMethod = enum {

    //Lifecycle
    @"initialize",
    @"initialized",
    @"shutdown",
    @"exit",

    //TextDocument
    @"textDocument/didOpen",
    @"textDocument/didChange",
    @"textDocument/didClose",

    @"textDocument/definition",
};
pub const LspRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: u32 = undefined,
    method: []u8 = undefined,
    params: ?std.json.Value = undefined,
};

pub fn LspResponse(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        result: T = undefined,
        id: u32 = undefined,

        const Self = @This();

        pub fn build(_result: T, _id: u32) Self {
            return Self{.result = _result, .id = _id};
        }
    };
}

const URI = []const u8;
/// The URI of a document
pub const DocumentUri = []const u8;
/// A JavaScript regular expression; never used
pub const RegExp = []const u8;

pub const LSPAny = std.json.Value;
pub const LSPArray = []LSPAny;
pub const LSPObject = std.json.ObjectMap;

pub const RequestId = union(enum) {
    integer: i64,
    string: []const u8,
    pub usingnamespace UnionParser(@This());
};

pub const ResponseError = struct {
    /// A number indicating the error type that occurred.
    code: i64,
    /// A string providing a short description of the error.
    message: []const u8,

    /// A primitive or structured value that contains additional
    /// information about the error. Can be omitted.
    data: std.json.Value = .null,
};

/// Indicates in which direction a message is sent in the protocol.
pub const MessageDirection = enum {
    clientToServer,
    serverToClient,
    both,
};

pub const RegistrationMetadata = struct {
    method: ?[]const u8,
    Options: ?type,
};

pub const NotificationMetadata = struct {
    method: []const u8,
    documentation: ?[]const u8,
    direction: MessageDirection,
    Params: ?type,
    registration: RegistrationMetadata,
};

pub const RequestMetadata = struct {
    method: []const u8,
    documentation: ?[]const u8,
    direction: MessageDirection,
    Params: ?type,
    Result: type,
    PartialResult: ?type,
    ErrorData: ?type,
    registration: RegistrationMetadata,
};

pub fn Map(comptime Key: type, comptime Value: type) type {
    if (Key != []const u8) @compileError("TODO support non string Key's");
    return std.json.ArrayHashMap(Value);
}

pub fn UnionParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            const json_value = try std.json.parseFromTokenSourceLeaky(std.json.Value, allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!T {
            inline for (std.meta.fields(T)) |field| {
                if (std.json.parseFromValueLeaky(field.type, allocator, source, options)) |result| {
                    return @unionInit(T, field.name, result);
                } else |_| {}
            }
            return error.UnexpectedToken;
        }

        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}

pub fn EnumCustomStringValues(comptime T: type, comptime contains_empty_enum: bool) type {
    return struct {
        const kvs = build_kvs: {
            const KV = struct { []const u8, T };
            const fields = @typeInfo(T).Union.fields;
            var kvs_array: [fields.len - 1]KV = undefined;
            inline for (fields[0 .. fields.len - 1], 0..) |field, i| {
                kvs_array[i] = .{ field.name, @field(T, field.name) };
            }
            break :build_kvs kvs_array[0..];
        };
        /// NOTE: this maps 'empty' to .empty when T contains an empty enum
        /// this shouldn't happen but this doesn't do any harm
        const map = std.ComptimeStringMap(T, kvs);

        pub fn eql(a: T, b: T) bool {
            const tag_a = std.meta.activeTag(a);
            const tag_b = std.meta.activeTag(b);
            if (tag_a != tag_b) return false;

            if (tag_a == .custom_value) {
                return std.mem.eql(u8, a.custom_value, b.custom_value);
            } else {
                return true;
            }
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            const slice = try std.json.parseFromTokenSourceLeaky([]const u8, allocator, source, options);
            if (contains_empty_enum and slice.len == 0) return .empty;
            return map.get(slice) orelse return .{ .custom_value = slice };
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!T {
            const slice = try std.json.parseFromValueLeaky([]const u8, allocator, source, options);
            if (contains_empty_enum and slice.len == 0) return .empty;
            return map.get(slice) orelse return .{ .custom_value = slice };
        }

        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            if (contains_empty_enum and self == .empty) {
                try stream.write("");
                return;
            }
            switch (self) {
                .custom_value => |str| try stream.write(str),
                else => |val| try stream.write(@tagName(val)),
            }
        }
    };
}

pub fn EnumStringifyAsInt(comptime T: type) type {
    return struct {
        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            try stream.write(@intFromEnum(self));
        }
    };
}

comptime {
    _ = @field(@This(), "notification_metadata");
    _ = @field(@This(), "request_metadata");
}

// Type Aliases

/// The definition of a symbol represented as one or many {@link Location locations}.
/// For most programming languages there is only one location at which a symbol is
/// defined.
///
/// Servers should prefer returning `DefinitionLink` over `Definition` if supported
/// by the client.
pub const Definition = union(enum) {
    Location: Location,
    array_of_Location: []const Location,
    pub usingnamespace UnionParser(@This());
};

/// Information about where a symbol is defined.
///
/// Provides additional metadata over normal {@link Location location} definitions, including the range of
/// the defining symbol
pub const DefinitionLink = LocationLink;

/// The declaration of a symbol representation as one or many {@link Location locations}.
pub const Declaration = union(enum) {
    Location: Location,
    array_of_Location: []const Location,
    pub usingnamespace UnionParser(@This());
};

/// Information about where a symbol is declared.
///
/// Provides additional metadata over normal {@link Location location} declarations, including the range of
/// the declaring symbol.
///
/// Servers should prefer returning `DeclarationLink` over `Declaration` if supported
/// by the client.
pub const DeclarationLink = LocationLink;

/// Inline value information can be provided by different means:
/// - directly as a text value (class InlineValueText).
/// - as a name to use for a variable lookup (class InlineValueVariableLookup)
/// - as an evaluatable expression (class InlineValueEvaluatableExpression)
/// The InlineValue types combines all inline value types into one type.
///
/// @since 3.17.0
pub const InlineValue = union(enum) {
    InlineValueText: InlineValueText,
    InlineValueVariableLookup: InlineValueVariableLookup,
    InlineValueEvaluatableExpression: InlineValueEvaluatableExpression,
    pub usingnamespace UnionParser(@This());
};

/// The result of a document diagnostic pull request. A report can
/// either be a full report containing all diagnostics for the
/// requested document or an unchanged report indicating that nothing
/// has changed in terms of diagnostics in comparison to the last
/// pull request.
///
/// @since 3.17.0
pub const DocumentDiagnosticReport = union(enum) {
    RelatedFullDocumentDiagnosticReport: RelatedFullDocumentDiagnosticReport,
    RelatedUnchangedDocumentDiagnosticReport: RelatedUnchangedDocumentDiagnosticReport,
    pub usingnamespace UnionParser(@This());
};

pub const PrepareRenameResult = union(enum) {
    Range: Range,
    PrepareRenamePlaceholder: PrepareRenamePlaceholder,
    PrepareRenameDefaultBehavior: PrepareRenameDefaultBehavior,
    pub usingnamespace UnionParser(@This());
};

/// A document selector is the combination of one or many document filters.
///
/// @sample `let sel:DocumentSelector = [{ language: 'typescript' }, { language: 'json', pattern: '**∕tsconfig.json' }]`;
///
/// The use of a string as a document filter is deprecated @since 3.16.0.
pub const DocumentSelector = []const DocumentFilter;

pub const ProgressToken = union(enum) {
    integer: i32,
    string: []const u8,
    pub usingnamespace UnionParser(@This());
};

/// An identifier to refer to a change annotation stored with a workspace edit.
pub const ChangeAnnotationIdentifier = []const u8;

/// A workspace diagnostic document report.
///
/// @since 3.17.0
pub const WorkspaceDocumentDiagnosticReport = union(enum) {
    WorkspaceFullDocumentDiagnosticReport: WorkspaceFullDocumentDiagnosticReport,
    WorkspaceUnchangedDocumentDiagnosticReport: WorkspaceUnchangedDocumentDiagnosticReport,
    pub usingnamespace UnionParser(@This());
};

/// An event describing a change to a text document. If only a text is provided
/// it is considered to be the full content of the document.
pub const TextDocumentContentChangeEvent = union(enum) {
    TextDocumentContentChangePartial: TextDocumentContentChangePartial,
    TextDocumentContentChangeWholeDocument: TextDocumentContentChangeWholeDocument,
    pub usingnamespace UnionParser(@This());
};

/// MarkedString can be used to render human readable text. It is either a markdown string
/// or a code-block that provides a language and a code snippet. The language identifier
/// is semantically equal to the optional language identifier in fenced code blocks in GitHub
/// issues. See https://help.github.com/articles/creating-and-highlighting-code-blocks/#syntax-highlighting
///
/// The pair of a language and a value is an equivalent to markdown:
/// ```${language}
/// ${value}
/// ```
///
/// Note that markdown strings will be sanitized - that means html will be escaped.
/// @deprecated use MarkupContent instead.
pub const MarkedString = union(enum) {
    string: []const u8,
    MarkedStringWithLanguage: MarkedStringWithLanguage,
    pub usingnamespace UnionParser(@This());
};

/// A document filter describes a top level text document or
/// a notebook cell document.
///
/// @since 3.17.0 - proposed support for NotebookCellTextDocumentFilter.
pub const DocumentFilter = union(enum) {
    TextDocumentFilter: TextDocumentFilter,
    NotebookCellTextDocumentFilter: NotebookCellTextDocumentFilter,
    pub usingnamespace UnionParser(@This());
};

/// The glob pattern. Either a string pattern or a relative pattern.
///
/// @since 3.17.0
pub const GlobPattern = union(enum) {
    Pattern: Pattern,
    RelativePattern: RelativePattern,
    pub usingnamespace UnionParser(@This());
};

/// A document filter denotes a document by different properties like
/// the {@link TextDocument.languageId language}, the {@link Uri.scheme scheme} of
/// its resource, or a glob-pattern that is applied to the {@link TextDocument.fileName path}.
///
/// Glob patterns can have the following syntax:
/// - `*` to match one or more characters in a path segment
/// - `?` to match on one character in a path segment
/// - `**` to match any number of path segments, including none
/// - `{}` to group sub patterns into an OR expression. (e.g. `**​/*.{ts,js}` matches all TypeScript and JavaScript files)
/// - `[]` to declare a range of characters to match in a path segment (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
/// - `[!...]` to negate a range of characters to match in a path segment (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
///
/// @sample A language filter that applies to typescript files on disk: `{ language: 'typescript', scheme: 'file' }`
/// @sample A language filter that applies to all package.json paths: `{ language: 'json', pattern: '**package.json' }`
///
/// @since 3.17.0
pub const TextDocumentFilter = union(enum) {
    TextDocumentFilterLanguage: TextDocumentFilterLanguage,
    TextDocumentFilterScheme: TextDocumentFilterScheme,
    TextDocumentFilterPattern: TextDocumentFilterPattern,
    pub usingnamespace UnionParser(@This());
};

/// The glob pattern to watch relative to the base path. Glob patterns can have the following syntax:
/// - `*` to match one or more characters in a path segment
/// - `?` to match on one character in a path segment
/// - `**` to match any number of path segments, including none
/// - `{}` to group conditions (e.g. `**​/*.{ts,js}` matches all TypeScript and JavaScript files)
/// - `[]` to declare a range of characters to match in a path segment (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
/// - `[!...]` to negate a range of characters to match in a path segment (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
///
/// @since 3.17.0
pub const Pattern = []const u8;

/// A notebook document filter denotes a notebook document by
/// different properties. The properties will be match
/// against the notebook's URI (same as with documents)
///
/// @since 3.17.0
pub const NotebookDocumentFilter = union(enum) {
    NotebookDocumentFilterNotebookType: NotebookDocumentFilterNotebookType,
    NotebookDocumentFilterScheme: NotebookDocumentFilterScheme,
    NotebookDocumentFilterPattern: NotebookDocumentFilterPattern,
    pub usingnamespace UnionParser(@This());
};

// Enumerations

/// A set of predefined token types. This set is not fixed
/// an clients can specify additional token types via the
/// corresponding client capabilities.
///
/// @since 3.16.0
pub const SemanticTokenTypes = union(enum) {
    namespace,
    /// Represents a generic type. Acts as a fallback for types which can't be mapped to
    /// a specific type like class or enum.
    type,
    class,
    @"enum",
    interface,
    @"struct",
    typeParameter,
    parameter,
    variable,
    property,
    enumMember,
    event,
    function,
    method,
    macro,
    keyword,
    modifier,
    comment,
    string,
    number,
    regexp,
    operator,
    /// @since 3.17.0
    decorator,
    custom_value: []const u8,
    pub usingnamespace EnumCustomStringValues(@This(), false);
};

/// A set of predefined token modifiers. This set is not fixed
/// an clients can specify additional token types via the
/// corresponding client capabilities.
///
/// @since 3.16.0
pub const SemanticTokenModifiers = union(enum) {
    declaration,
    definition,
    readonly,
    static,
    deprecated,
    abstract,
    @"async",
    modification,
    documentation,
    defaultLibrary,
    custom_value: []const u8,
    pub usingnamespace EnumCustomStringValues(@This(), false);
};

/// The document diagnostic report kinds.
///
/// @since 3.17.0
pub const DocumentDiagnosticReportKind = enum {
    /// A diagnostic report with a full
    /// set of problems.
    full,
    /// A report indicating that the last
    /// returned report is still accurate.
    unchanged,
};

/// Predefined error codes.
pub const ErrorCodes = enum(i32) {
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    /// Error code indicating that a server received a notification or
    /// request before the server has received the `initialize` request.
    ServerNotInitialized = -32002,
    UnknownErrorCode = -32001,
    _,
    pub usingnamespace EnumStringifyAsInt(@This());
};

pub const LSPErrorCodes = enum(i32) {
    /// A request failed but it was syntactically correct, e.g the
    /// method name was known and the parameters were valid. The error
    /// message should contain human readable information about why
    /// the request failed.
    ///
    /// @since 3.17.0
    RequestFailed = -32803,
    /// The server cancelled the request. This error code should
    /// only be used for requests that explicitly support being
    /// server cancellable.
    ///
    /// @since 3.17.0
    ServerCancelled = -32802,
    /// The server detected that the content of a document got
    /// modified outside normal conditions. A server should
    /// NOT send this error code if it detects a content change
    /// in it unprocessed messages. The result even computed
    /// on an older state might still be useful for the client.
    ///
    /// If a client decides that a result is not of any use anymore
    /// the client should cancel the request.
    ContentModified = -32801,
    /// The client has canceled a request and a server as detected
    /// the cancel.
    RequestCancelled = -32800,
    _,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// A set of predefined range kinds.
pub const FoldingRangeKind = union(enum) {
    /// Folding range for a comment
    comment,
    /// Folding range for an import or include
    imports,
    /// Folding range for a region (e.g. `#region`)
    region,
    custom_value: []const u8,
    pub usingnamespace EnumCustomStringValues(@This(), false);
};

/// A symbol kind.
pub const SymbolKind = enum(u32) {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// Symbol tags are extra annotations that tweak the rendering of a symbol.
///
/// @since 3.16
pub const SymbolTag = enum(u32) {
    /// Render a symbol as obsolete, usually using a strike-out.
    Deprecated = 1,
    placeholder__, // fixes alignment issue
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// Moniker uniqueness level to define scope of the moniker.
///
/// @since 3.16.0
pub const UniquenessLevel = enum {
    /// The moniker is only unique inside a document
    document,
    /// The moniker is unique inside a project for which a dump got created
    project,
    /// The moniker is unique inside the group to which a project belongs
    group,
    /// The moniker is unique inside the moniker scheme.
    scheme,
    /// The moniker is globally unique
    global,
};

/// The moniker kind.
///
/// @since 3.16.0
pub const MonikerKind = enum {
    /// The moniker represent a symbol that is imported into a project
    import,
    /// The moniker represents a symbol that is exported from a project
    @"export",
    /// The moniker represents a symbol that is local to a project (e.g. a local
    /// variable of a function, a class not visible outside the project, ...)
    local,
};

/// Inlay hint kinds.
///
/// @since 3.17.0
pub const InlayHintKind = enum(u32) {
    /// An inlay hint that for a type annotation.
    Type = 1,
    /// An inlay hint that is for a parameter.
    Parameter = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// The message type
pub const MessageType = enum(u32) {
    /// An error message.
    Error = 1,
    /// A warning message.
    Warning = 2,
    /// An information message.
    Info = 3,
    /// A log message.
    Log = 4,
    /// A debug message.
    ///
    /// @since 3.18.0
    Debug = 5,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// Defines how the host (editor) should sync
/// document changes to the language server.
pub const TextDocumentSyncKind = enum(u32) {
    /// Documents should not be synced at all.
    None = 0,
    /// Documents are synced by always sending the full content
    /// of the document.
    Full = 1,
    /// Documents are synced by sending the full content on open.
    /// After that only incremental updates to the document are
    /// send.
    Incremental = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// Represents reasons why a text document is saved.
pub const TextDocumentSaveReason = enum(u32) {
    /// Manually triggered, e.g. by the user pressing save, by starting debugging,
    /// or by an API call.
    Manual = 1,
    /// Automatic after a delay.
    AfterDelay = 2,
    /// When the editor lost focus.
    FocusOut = 3,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// The kind of a completion entry.
pub const CompletionItemKind = enum(u32) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// Completion item tags are extra annotations that tweak the rendering of a completion
/// item.
///
/// @since 3.15.0
pub const CompletionItemTag = enum(u32) {
    /// Render a completion as obsolete, usually using a strike-out.
    Deprecated = 1,
    placeholder__, // fixes alignment issue
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// Defines whether the insert text in a completion item should be interpreted as
/// plain text or a snippet.
pub const InsertTextFormat = enum(u32) {
    /// The primary text to be inserted is treated as a plain string.
    PlainText = 1,
    /// The primary text to be inserted is treated as a snippet.
    ///
    /// A snippet can define tab stops and placeholders with `$1`, `$2`
    /// and `${3:foo}`. `$0` defines the final tab stop, it defaults to
    /// the end of the snippet. Placeholders with equal identifiers are linked,
    /// that is typing in one will update others too.
    ///
    /// See also: https://microsoft.github.io/language-server-protocol/specifications/specification-current/#snippet_syntax
    Snippet = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// How whitespace and indentation is handled during completion
/// item insertion.
///
/// @since 3.16.0
pub const InsertTextMode = enum(u32) {
    /// The insertion or replace strings is taken as it is. If the
    /// value is multi line the lines below the cursor will be
    /// inserted using the indentation defined in the string value.
    /// The client will not apply any kind of adjustments to the
    /// string.
    asIs = 1,
    /// The editor adjusts leading whitespace of new lines so that
    /// they match the indentation up to the cursor of the line for
    /// which the item is accepted.
    ///
    /// Consider a line like this: <2tabs><cursor><3tabs>foo. Accepting a
    /// multi line completion item is indented using 2 tabs and all
    /// following lines inserted will be indented using 2 tabs as well.
    adjustIndentation = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// A document highlight kind.
pub const DocumentHighlightKind = enum(u32) {
    /// A textual occurrence.
    Text = 1,
    /// Read-access of a symbol, like reading a variable.
    Read = 2,
    /// Write-access of a symbol, like writing to a variable.
    Write = 3,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// A set of predefined code action kinds
pub const CodeActionKind = union(enum) {
    /// Empty kind.
    empty,
    /// Base kind for quickfix actions: 'quickfix'
    quickfix,
    /// Base kind for refactoring actions: 'refactor'
    refactor,
    /// Base kind for refactoring extraction actions: 'refactor.extract'
    ///
    /// Example extract actions:
    ///
    /// - Extract method
    /// - Extract function
    /// - Extract variable
    /// - Extract interface from class
    /// - ...
    @"refactor.extract",
    /// Base kind for refactoring inline actions: 'refactor.inline'
    ///
    /// Example inline actions:
    ///
    /// - Inline function
    /// - Inline variable
    /// - Inline constant
    /// - ...
    @"refactor.inline",
    /// Base kind for refactoring rewrite actions: 'refactor.rewrite'
    ///
    /// Example rewrite actions:
    ///
    /// - Convert JavaScript function to class
    /// - Add or remove parameter
    /// - Encapsulate field
    /// - Make method static
    /// - Move method to base class
    /// - ...
    @"refactor.rewrite",
    /// Base kind for source actions: `source`
    ///
    /// Source code actions apply to the entire file.
    source,
    /// Base kind for an organize imports source action: `source.organizeImports`
    @"source.organizeImports",
    /// Base kind for auto-fix source actions: `source.fixAll`.
    ///
    /// Fix all actions automatically fix errors that have a clear fix that do not require user input.
    /// They should not suppress errors or perform unsafe fixes such as generating new types or classes.
    ///
    /// @since 3.15.0
    @"source.fixAll",
    custom_value: []const u8,
    pub usingnamespace EnumCustomStringValues(@This(), true);
};

pub const TraceValues = enum {
    /// Turn tracing off.
    off,
    /// Trace messages only.
    messages,
    /// Verbose message tracing.
    verbose,
};

/// Describes the content type that a client supports in various
/// result literals like `Hover`, `ParameterInfo` or `CompletionItem`.
///
/// Please note that `MarkupKinds` must not start with a `$`. This kinds
/// are reserved for internal usage.
pub const MarkupKind = enum {
    /// Plain text is supported as a content format
    plaintext,
    /// Markdown is supported as a content format
    markdown,
};

/// Describes how an {@link InlineCompletionItemProvider inline completion provider} was triggered.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionTriggerKind = enum(u32) {
    /// Completion was triggered explicitly by a user gesture.
    Invoked = 0,
    /// Completion was triggered automatically while editing.
    Automatic = 1,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// A set of predefined position encoding kinds.
///
/// @since 3.17.0
pub const PositionEncodingKind = union(enum) {
    /// Character offsets count UTF-8 code units (e.g. bytes).
    @"utf-8",
    /// Character offsets count UTF-16 code units.
    ///
    /// This is the default and must always be supported
    /// by servers
    @"utf-16",
    /// Character offsets count UTF-32 code units.
    ///
    /// Implementation note: these are the same as Unicode codepoints,
    /// so this `PositionEncodingKind` may also be used for an
    /// encoding-agnostic representation of character offsets.
    @"utf-32",
    custom_value: []const u8,
    pub usingnamespace EnumCustomStringValues(@This(), false);
};

/// The file event type
pub const FileChangeType = enum(u32) {
    /// The file got created.
    Created = 1,
    /// The file got changed.
    Changed = 2,
    /// The file got deleted.
    Deleted = 3,
    pub usingnamespace EnumStringifyAsInt(@This());
};

pub const WatchKind = enum(u32) {
    /// Interested in create events.
    Create = 1,
    /// Interested in change events
    Change = 2,
    /// Interested in delete events
    Delete = 4,
    _,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// The diagnostic's severity.
pub const DiagnosticSeverity = enum(u32) {
    /// Reports an error.
    Error = 1,
    /// Reports a warning.
    Warning = 2,
    /// Reports an information.
    Information = 3,
    /// Reports a hint.
    Hint = 4,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// The diagnostic tags.
///
/// @since 3.15.0
pub const DiagnosticTag = enum(u32) {
    /// Unused or unnecessary code.
    ///
    /// Clients are allowed to render diagnostics with this tag faded out instead of having
    /// an error squiggle.
    Unnecessary = 1,
    /// Deprecated or obsolete code.
    ///
    /// Clients are allowed to rendered diagnostics with this tag strike through.
    Deprecated = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// How a completion was triggered
pub const CompletionTriggerKind = enum(u32) {
    /// Completion was triggered by typing an identifier (24x7 code
    /// complete), manual invocation (e.g Ctrl+Space) or via API.
    Invoked = 1,
    /// Completion was triggered by a trigger character specified by
    /// the `triggerCharacters` properties of the `CompletionRegistrationOptions`.
    TriggerCharacter = 2,
    /// Completion was re-triggered as current completion list is incomplete
    TriggerForIncompleteCompletions = 3,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// How a signature help was triggered.
///
/// @since 3.15.0
pub const SignatureHelpTriggerKind = enum(u32) {
    /// Signature help was invoked manually by the user or by a command.
    Invoked = 1,
    /// Signature help was triggered by a trigger character.
    TriggerCharacter = 2,
    /// Signature help was triggered by the cursor moving or by the document content changing.
    ContentChange = 3,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// The reason why code actions were requested.
///
/// @since 3.17.0
pub const CodeActionTriggerKind = enum(u32) {
    /// Code actions were explicitly requested by the user or by an extension.
    Invoked = 1,
    /// Code actions were requested automatically.
    ///
    /// This typically happens when current selection in a file changes, but can
    /// also be triggered when file content changes.
    Automatic = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

/// A pattern kind describing if a glob pattern matches a file a folder or
/// both.
///
/// @since 3.16.0
pub const FileOperationPatternKind = enum {
    /// The pattern matches a file only.
    file,
    /// The pattern matches a folder only.
    folder,
};

/// A notebook cell kind.
///
/// @since 3.17.0
pub const NotebookCellKind = enum(u32) {
    /// A markup-cell is formatted source that is used for display.
    Markup = 1,
    /// A code-cell is source code.
    Code = 2,
    pub usingnamespace EnumStringifyAsInt(@This());
};

pub const ResourceOperationKind = enum {
    /// Supports creating new files and folders.
    create,
    /// Supports renaming existing files and folders.
    rename,
    /// Supports deleting existing files and folders.
    delete,
};

pub const FailureHandlingKind = enum {
    /// Applying the workspace change is simply aborted if one of the changes provided
    /// fails. All operations executed before the failing operation stay executed.
    abort,
    /// All operations are executed transactional. That means they either all
    /// succeed or no changes at all are applied to the workspace.
    transactional,
    /// If the workspace edit contains only textual file changes they are executed transactional.
    /// If resource changes (create, rename or delete file) are part of the change the failure
    /// handling strategy is abort.
    textOnlyTransactional,
    /// The client tries to undo the operations already executed. But there is no
    /// guarantee that this is succeeding.
    undo,
};

pub const PrepareSupportDefaultBehavior = enum(u32) {
    /// The client's default behavior is to select the identifier
    /// according the to language's syntax rule.
    Identifier = 1,
    placeholder__, // fixes alignment issue
    pub usingnamespace EnumStringifyAsInt(@This());
};

pub const TokenFormat = enum {
    relative,
    placeholder__, // fixes alignment issue
};

// Structures

pub const ImplementationParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents a location inside a resource, such as a line
/// inside a text file.
pub const Location = struct {
    uri: DocumentUri,
    range: Range,
};

pub const ImplementationRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends ImplementationOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

pub const TypeDefinitionParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

pub const TypeDefinitionRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends TypeDefinitionOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// A workspace folder inside a client.
pub const WorkspaceFolder = struct {
    /// The associated URI for this workspace folder.
    uri: URI,
    /// The name of the workspace folder. Used to refer to this
    /// workspace folder in the user interface.
    name: []const u8,
};

/// The parameters of a `workspace/didChangeWorkspaceFolders` notification.
pub const DidChangeWorkspaceFoldersParams = struct {
    /// The actual workspace folder change event.
    event: WorkspaceFoldersChangeEvent,
};

/// The parameters of a configuration request.
pub const ConfigurationParams = struct {
    items: []const ConfigurationItem,
};

/// Parameters for a {@link DocumentColorRequest}.
pub const DocumentColorParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents a color range from a document.
pub const ColorInformation = struct {
    /// The range in the document where this color appears.
    range: Range,
    /// The actual color value for this color range.
    color: Color,
};

pub const DocumentColorRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentColorOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// Parameters for a {@link ColorPresentationRequest}.
pub const ColorPresentationParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The color to request presentations for.
    color: Color,
    /// The range where the color would be inserted. Serves as a context.
    range: Range,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

pub const ColorPresentation = struct {
    /// The label of this color presentation. It will be shown on the color
    /// picker header. By default this is also the text that is inserted when selecting
    /// this color presentation.
    label: []const u8,
    /// An {@link TextEdit edit} which is applied to a document when selecting
    /// this presentation for the color.  When `falsy` the {@link ColorPresentation.label label}
    /// is used.
    textEdit: ?TextEdit = null,
    /// An optional array of additional {@link TextEdit text edits} that are applied when
    /// selecting this color presentation. Edits must not overlap with the main {@link ColorPresentation.textEdit edit} nor with themselves.
    additionalTextEdits: ?[]const TextEdit = null,
};

pub const WorkDoneProgressOptions = struct {
    workDoneProgress: ?bool = null,
};

/// General text document registration options.
pub const TextDocumentRegistrationOptions = struct {
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,
};

/// Parameters for a {@link FoldingRangeRequest}.
pub const FoldingRangeParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents a folding range. To be valid, start and end line must be bigger than zero and smaller
/// than the number of lines in the document. Clients are free to ignore invalid ranges.
pub const FoldingRange = struct {
    /// The zero-based start line of the range to fold. The folded area starts after the line's last character.
    /// To be valid, the end must be zero or larger and smaller than the number of lines in the document.
    startLine: u32,
    /// The zero-based character offset from where the folded range starts. If not defined, defaults to the length of the start line.
    startCharacter: ?u32 = null,
    /// The zero-based end line of the range to fold. The folded area ends with the line's last character.
    /// To be valid, the end must be zero or larger and smaller than the number of lines in the document.
    endLine: u32,
    /// The zero-based character offset before the folded range ends. If not defined, defaults to the length of the end line.
    endCharacter: ?u32 = null,
    /// Describes the kind of the folding range such as `comment' or 'region'. The kind
    /// is used to categorize folding ranges and used by commands like 'Fold all comments'.
    /// See {@link FoldingRangeKind} for an enumeration of standardized kinds.
    kind: ?FoldingRangeKind = null,
    /// The text that the client should show when the specified range is
    /// collapsed. If not defined or not supported by the client, a default
    /// will be chosen by the client.
    ///
    /// @since 3.17.0
    collapsedText: ?[]const u8 = null,
};

pub const FoldingRangeRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends FoldingRangeOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

pub const DeclarationParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

pub const DeclarationRegistrationOptions = struct {

    // Extends DeclarationOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// A parameter literal used in selection range requests.
pub const SelectionRangeParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The positions inside the text document.
    positions: []const Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A selection range represents a part of a selection hierarchy. A selection range
/// may have a parent selection range that contains it.
pub const SelectionRange = struct {
    /// The {@link Range range} of this selection range.
    range: Range,
    /// The parent selection range containing this range. Therefore `parent.range` must contain `this.range`.
    parent: ?SelectionRange = null,
};

pub const SelectionRangeRegistrationOptions = struct {

    // Extends SelectionRangeOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

pub const WorkDoneProgressCreateParams = struct {
    /// The token to be used to report progress.
    token: ProgressToken,
};

pub const WorkDoneProgressCancelParams = struct {
    /// The token to be used to report progress.
    token: ProgressToken,
};

/// The parameter of a `textDocument/prepareCallHierarchy` request.
///
/// @since 3.16.0
pub const CallHierarchyPrepareParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Represents programming constructs like functions or constructors in the context
/// of call hierarchy.
///
/// @since 3.16.0
pub const CallHierarchyItem = struct {
    /// The name of this item.
    name: []const u8,
    /// The kind of this item.
    kind: SymbolKind,
    /// Tags for this item.
    tags: ?[]const SymbolTag = null,
    /// More detail for this item, e.g. the signature of a function.
    detail: ?[]const u8 = null,
    /// The resource identifier of this item.
    uri: DocumentUri,
    /// The range enclosing this symbol not including leading/trailing whitespace but everything else, e.g. comments and code.
    range: Range,
    /// The range that should be selected and revealed when this symbol is being picked, e.g. the name of a function.
    /// Must be contained by the {@link CallHierarchyItem.range `range`}.
    selectionRange: Range,
    /// A data entry field that is preserved between a call hierarchy prepare and
    /// incoming calls or outgoing calls requests.
    data: ?LSPAny = null,
};

/// Call hierarchy options used during static or dynamic registration.
///
/// @since 3.16.0
pub const CallHierarchyRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends CallHierarchyOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// The parameter of a `callHierarchy/incomingCalls` request.
///
/// @since 3.16.0
pub const CallHierarchyIncomingCallsParams = struct {
    item: CallHierarchyItem,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents an incoming call, e.g. a caller of a method or constructor.
///
/// @since 3.16.0
pub const CallHierarchyIncomingCall = struct {
    /// The item that makes the call.
    from: CallHierarchyItem,
    /// The ranges at which the calls appear. This is relative to the caller
    /// denoted by {@link CallHierarchyIncomingCall.from `this.from`}.
    fromRanges: []const Range,
};

/// The parameter of a `callHierarchy/outgoingCalls` request.
///
/// @since 3.16.0
pub const CallHierarchyOutgoingCallsParams = struct {
    item: CallHierarchyItem,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents an outgoing call, e.g. calling a getter from a method or a method from a constructor etc.
///
/// @since 3.16.0
pub const CallHierarchyOutgoingCall = struct {
    /// The item that is called.
    to: CallHierarchyItem,
    /// The range at which this item is called. This is the range relative to the caller, e.g the item
    /// passed to {@link CallHierarchyItemProvider.provideCallHierarchyOutgoingCalls `provideCallHierarchyOutgoingCalls`}
    /// and not {@link CallHierarchyOutgoingCall.to `this.to`}.
    fromRanges: []const Range,
};

/// @since 3.16.0
pub const SemanticTokensParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// @since 3.16.0
pub const SemanticTokens = struct {
    /// An optional result id. If provided and clients support delta updating
    /// the client will include the result id in the next semantic token request.
    /// A server can then instead of computing all semantic tokens again simply
    /// send a delta.
    resultId: ?[]const u8 = null,
    /// The actual tokens.
    data: []const u32,
};

/// @since 3.16.0
pub const SemanticTokensPartialResult = struct {
    data: []const u32,
};

/// @since 3.16.0
pub const SemanticTokensRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends SemanticTokensOptions
    /// The legend used by the server
    legend: SemanticTokensLegend,
    /// Server supports providing semantic tokens for a specific range
    /// of a document.
    range: ?union(enum) {
        bool: bool,
        literal_1: struct {},
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Server supports providing semantic tokens for a full document.
    full: ?union(enum) {
        bool: bool,
        SemanticTokensFullDelta: SemanticTokensFullDelta,
        pub usingnamespace UnionParser(@This());
    } = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// @since 3.16.0
pub const SemanticTokensDeltaParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The result id of a previous response. The result Id can either point to a full response
    /// or a delta response depending on what was received last.
    previousResultId: []const u8,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// @since 3.16.0
pub const SemanticTokensDelta = struct {
    resultId: ?[]const u8 = null,
    /// The semantic token edits to transform a previous result into a new result.
    edits: []const SemanticTokensEdit,
};

/// @since 3.16.0
pub const SemanticTokensDeltaPartialResult = struct {
    edits: []const SemanticTokensEdit,
};

/// @since 3.16.0
pub const SemanticTokensRangeParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The range the semantic tokens are requested for.
    range: Range,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Params to show a resource in the UI.
///
/// @since 3.16.0
pub const ShowDocumentParams = struct {
    /// The uri to show.
    uri: URI,
    /// Indicates to show the resource in an external program.
    /// To show, for example, `https://code.visualstudio.com/`
    /// in the default WEB browser set `external` to `true`.
    external: ?bool = null,
    /// An optional property to indicate whether the editor
    /// showing the document should take focus or not.
    /// Clients might ignore this property if an external
    /// program is started.
    takeFocus: ?bool = null,
    /// An optional selection range if the document is a text
    /// document. Clients might ignore the property if an
    /// external program is started or the file is not a text
    /// file.
    selection: ?Range = null,
};

/// The result of a showDocument request.
///
/// @since 3.16.0
pub const ShowDocumentResult = struct {
    /// A boolean indicating if the show was successful.
    success: bool,
};

pub const LinkedEditingRangeParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// The result of a linked editing range request.
///
/// @since 3.16.0
pub const LinkedEditingRanges = struct {
    /// A list of ranges that can be edited together. The ranges must have
    /// identical length and contain identical text content. The ranges cannot overlap.
    ranges: []const Range,
    /// An optional word pattern (regular expression) that describes valid contents for
    /// the given ranges. If no pattern is provided, the client configuration's word
    /// pattern will be used.
    wordPattern: ?[]const u8 = null,
};

pub const LinkedEditingRangeRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends LinkedEditingRangeOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// The parameters sent in notifications/requests for user-initiated creation of
/// files.
///
/// @since 3.16.0
pub const CreateFilesParams = struct {
    /// An array of all files/folders created in this operation.
    files: []const FileCreate,
};

/// A workspace edit represents changes to many resources managed in the workspace. The edit
/// should either provide `changes` or `documentChanges`. If documentChanges are present
/// they are preferred over `changes` if the client can handle versioned document edits.
///
/// Since version 3.13.0 a workspace edit can contain resource operations as well. If resource
/// operations are present clients need to execute the operations in the order in which they
/// are provided. So a workspace edit for example can consist of the following two changes:
/// (1) a create file a.txt and (2) a text document edit which insert text into file a.txt.
///
/// An invalid sequence (e.g. (1) delete file a.txt and (2) insert text into file a.txt) will
/// cause failure of the operation. How the client recovers from the failure is described by
/// the client capability: `workspace.workspaceEdit.failureHandling`
pub const WorkspaceEdit = struct {
    /// Holds changes to existing resources.
    changes: ?Map(DocumentUri, []const TextEdit) = null,
    /// Depending on the client capability `workspace.workspaceEdit.resourceOperations` document changes
    /// are either an array of `TextDocumentEdit`s to express changes to n different text documents
    /// where each text document edit addresses a specific version of a text document. Or it can contain
    /// above `TextDocumentEdit`s mixed with create, rename and delete file / folder operations.
    ///
    /// Whether a client supports versioned document edits is expressed via
    /// `workspace.workspaceEdit.documentChanges` client capability.
    ///
    /// If a client neither supports `documentChanges` nor `workspace.workspaceEdit.resourceOperations` then
    /// only plain `TextEdit`s using the `changes` property are supported.
    documentChanges: ?[]const union(enum) {
        TextDocumentEdit: TextDocumentEdit,
        CreateFile: CreateFile,
        RenameFile: RenameFile,
        DeleteFile: DeleteFile,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// A map of change annotations that can be referenced in `AnnotatedTextEdit`s or create, rename and
    /// delete file / folder operations.
    ///
    /// Whether clients honor this property depends on the client capability `workspace.changeAnnotationSupport`.
    ///
    /// @since 3.16.0
    changeAnnotations: ?Map(ChangeAnnotationIdentifier, ChangeAnnotation) = null,
};

/// The options to register for file operations.
///
/// @since 3.16.0
pub const FileOperationRegistrationOptions = struct {
    /// The actual filters.
    filters: []const FileOperationFilter,
};

/// The parameters sent in notifications/requests for user-initiated renames of
/// files.
///
/// @since 3.16.0
pub const RenameFilesParams = struct {
    /// An array of all files/folders renamed in this operation. When a folder is renamed, only
    /// the folder will be included, and not its children.
    files: []const FileRename,
};

/// The parameters sent in notifications/requests for user-initiated deletes of
/// files.
///
/// @since 3.16.0
pub const DeleteFilesParams = struct {
    /// An array of all files/folders deleted in this operation.
    files: []const FileDelete,
};

pub const MonikerParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Moniker definition to match LSIF 0.5 moniker definition.
///
/// @since 3.16.0
pub const Moniker = struct {
    /// The scheme of the moniker. For example tsc or .Net
    scheme: []const u8,
    /// The identifier of the moniker. The value is opaque in LSIF however
    /// schema owners are allowed to define the structure if they want.
    identifier: []const u8,
    /// The scope in which the moniker is unique
    unique: UniquenessLevel,
    /// The moniker kind if known.
    kind: ?MonikerKind = null,
};

pub const MonikerRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends MonikerOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameter of a `textDocument/prepareTypeHierarchy` request.
///
/// @since 3.17.0
pub const TypeHierarchyPrepareParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// @since 3.17.0
pub const TypeHierarchyItem = struct {
    /// The name of this item.
    name: []const u8,
    /// The kind of this item.
    kind: SymbolKind,
    /// Tags for this item.
    tags: ?[]const SymbolTag = null,
    /// More detail for this item, e.g. the signature of a function.
    detail: ?[]const u8 = null,
    /// The resource identifier of this item.
    uri: DocumentUri,
    /// The range enclosing this symbol not including leading/trailing whitespace
    /// but everything else, e.g. comments and code.
    range: Range,
    /// The range that should be selected and revealed when this symbol is being
    /// picked, e.g. the name of a function. Must be contained by the
    /// {@link TypeHierarchyItem.range `range`}.
    selectionRange: Range,
    /// A data entry field that is preserved between a type hierarchy prepare and
    /// supertypes or subtypes requests. It could also be used to identify the
    /// type hierarchy in the server, helping improve the performance on
    /// resolving supertypes and subtypes.
    data: ?LSPAny = null,
};

/// Type hierarchy options used during static or dynamic registration.
///
/// @since 3.17.0
pub const TypeHierarchyRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends TypeHierarchyOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// The parameter of a `typeHierarchy/supertypes` request.
///
/// @since 3.17.0
pub const TypeHierarchySupertypesParams = struct {
    item: TypeHierarchyItem,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// The parameter of a `typeHierarchy/subtypes` request.
///
/// @since 3.17.0
pub const TypeHierarchySubtypesParams = struct {
    item: TypeHierarchyItem,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A parameter literal used in inline value requests.
///
/// @since 3.17.0
pub const InlineValueParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The document range for which inline values should be computed.
    range: Range,
    /// Additional information about the context in which inline values were
    /// requested.
    context: InlineValueContext,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Inline value options used during static or dynamic registration.
///
/// @since 3.17.0
pub const InlineValueRegistrationOptions = struct {

    // Extends InlineValueOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// A parameter literal used in inlay hint requests.
///
/// @since 3.17.0
pub const InlayHintParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The document range for which inlay hints should be computed.
    range: Range,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Inlay hint information.
///
/// @since 3.17.0
pub const InlayHint = struct {
    /// The position of this hint.
    position: Position,
    /// The label of this hint. A human readable string or an array of
    /// InlayHintLabelPart label parts.
    ///
    /// *Note* that neither the string nor the label part can be empty.
    label: union(enum) {
        string: []const u8,
        array_of_InlayHintLabelPart: []const InlayHintLabelPart,
        pub usingnamespace UnionParser(@This());
    },
    /// The kind of this hint. Can be omitted in which case the client
    /// should fall back to a reasonable default.
    kind: ?InlayHintKind = null,
    /// Optional text edits that are performed when accepting this inlay hint.
    ///
    /// *Note* that edits are expected to change the document so that the inlay
    /// hint (or its nearest variant) is now part of the document and the inlay
    /// hint itself is now obsolete.
    textEdits: ?[]const TextEdit = null,
    /// The tooltip text when you hover over this item.
    tooltip: ?union(enum) {
        string: []const u8,
        MarkupContent: MarkupContent,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Render padding before the hint.
    ///
    /// Note: Padding should use the editor's background color, not the
    /// background color of the hint itself. That means padding can be used
    /// to visually align/separate an inlay hint.
    paddingLeft: ?bool = null,
    /// Render padding after the hint.
    ///
    /// Note: Padding should use the editor's background color, not the
    /// background color of the hint itself. That means padding can be used
    /// to visually align/separate an inlay hint.
    paddingRight: ?bool = null,
    /// A data entry field that is preserved on an inlay hint between
    /// a `textDocument/inlayHint` and a `inlayHint/resolve` request.
    data: ?LSPAny = null,
};

/// Inlay hint options used during static or dynamic registration.
///
/// @since 3.17.0
pub const InlayHintRegistrationOptions = struct {

    // Extends InlayHintOptions
    /// The server provides support to resolve additional
    /// information for an inlay hint item.
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// Parameters of the document diagnostic request.
///
/// @since 3.17.0
pub const DocumentDiagnosticParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The additional identifier  provided during registration.
    identifier: ?[]const u8 = null,
    /// The result id of a previous response if provided.
    previousResultId: ?[]const u8 = null,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A partial result for a document diagnostic report.
///
/// @since 3.17.0
pub const DocumentDiagnosticReportPartialResult = struct {
    relatedDocuments: Map(DocumentUri, union(enum) {
        FullDocumentDiagnosticReport: FullDocumentDiagnosticReport,
        UnchangedDocumentDiagnosticReport: UnchangedDocumentDiagnosticReport,
        pub usingnamespace UnionParser(@This());
    }),
};

/// Cancellation data returned from a diagnostic request.
///
/// @since 3.17.0
pub const DiagnosticServerCancellationData = struct {
    retriggerRequest: bool,
};

/// Diagnostic registration options.
///
/// @since 3.17.0
pub const DiagnosticRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DiagnosticOptions
    /// An optional identifier under which the diagnostics are
    /// managed by the client.
    identifier: ?[]const u8 = null,
    /// Whether the language has inter file dependencies meaning that
    /// editing code in one file can result in a different diagnostic
    /// set in another file. Inter file dependencies are common for
    /// most programming languages and typically uncommon for linters.
    interFileDependencies: bool,
    /// The server provides support for workspace diagnostics as well.
    workspaceDiagnostics: bool,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// Parameters of the workspace diagnostic request.
///
/// @since 3.17.0
pub const WorkspaceDiagnosticParams = struct {
    /// The additional identifier provided during registration.
    identifier: ?[]const u8 = null,
    /// The currently known diagnostic reports with their
    /// previous result ids.
    previousResultIds: []const PreviousResultId,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A workspace diagnostic report.
///
/// @since 3.17.0
pub const WorkspaceDiagnosticReport = struct {
    items: []const WorkspaceDocumentDiagnosticReport,
};

/// A partial result for a workspace diagnostic report.
///
/// @since 3.17.0
pub const WorkspaceDiagnosticReportPartialResult = struct {
    items: []const WorkspaceDocumentDiagnosticReport,
};

/// The params sent in an open notebook document notification.
///
/// @since 3.17.0
pub const DidOpenNotebookDocumentParams = struct {
    /// The notebook document that got opened.
    notebookDocument: NotebookDocument,
    /// The text documents that represent the content
    /// of a notebook cell.
    cellTextDocuments: []const TextDocumentItem,
};

/// The params sent in a change notebook document notification.
///
/// @since 3.17.0
pub const DidChangeNotebookDocumentParams = struct {
    /// The notebook document that did change. The version number points
    /// to the version after all provided changes have been applied. If
    /// only the text document content of a cell changes the notebook version
    /// doesn't necessarily have to change.
    notebookDocument: VersionedNotebookDocumentIdentifier,
    /// The actual changes to the notebook document.
    ///
    /// The changes describe single state changes to the notebook document.
    /// So if there are two changes c1 (at array index 0) and c2 (at array
    /// index 1) for a notebook in state S then c1 moves the notebook from
    /// S to S' and c2 from S' to S''. So c1 is computed on the state S and
    /// c2 is computed on the state S'.
    ///
    /// To mirror the content of a notebook using change events use the following approach:
    /// - start with the same initial content
    /// - apply the 'notebookDocument/didChange' notifications in the order you receive them.
    /// - apply the `NotebookChangeEvent`s in a single notification in the order
    ///   you receive them.
    change: NotebookDocumentChangeEvent,
};

/// The params sent in a save notebook document notification.
///
/// @since 3.17.0
pub const DidSaveNotebookDocumentParams = struct {
    /// The notebook document that got saved.
    notebookDocument: NotebookDocumentIdentifier,
};

/// The params sent in a close notebook document notification.
///
/// @since 3.17.0
pub const DidCloseNotebookDocumentParams = struct {
    /// The notebook document that got closed.
    notebookDocument: NotebookDocumentIdentifier,
    /// The text documents that represent the content
    /// of a notebook cell that got closed.
    cellTextDocuments: []const TextDocumentIdentifier,
};

/// A parameter literal used in inline completion requests.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionParams = struct {
    /// Additional information about the context in which inline completions were
    /// requested.
    context: InlineCompletionContext,

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Represents a collection of {@link InlineCompletionItem inline completion items} to be presented in the editor.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionList = struct {
    /// The inline completion items
    items: []const InlineCompletionItem,
};

/// An inline completion item represents a text snippet that is proposed inline to complete text that is being typed.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionItem = struct {
    /// The text to replace the range with. Must be set.
    insertText: union(enum) {
        string: []const u8,
        StringValue: StringValue,
        pub usingnamespace UnionParser(@This());
    },
    /// A text that is used to decide if this inline completion should be shown. When `falsy` the {@link InlineCompletionItem.insertText} is used.
    filterText: ?[]const u8 = null,
    /// The range to replace. Must begin and end on the same line.
    range: ?Range = null,
    /// An optional {@link Command} that is executed *after* inserting this completion.
    command: ?Command = null,
};

/// Inline completion options used during static or dynamic registration.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionRegistrationOptions = struct {

    // Extends InlineCompletionOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

pub const RegistrationParams = struct {
    registrations: []const Registration,
};

pub const UnregistrationParams = struct {
    unregisterations: []const Unregistration,
};

pub const InitializeParams = struct {

    // Extends _InitializeParams
    /// The process Id of the parent process that started
    /// the server.
    ///
    /// Is `null` if the process has not been started by another process.
    /// If the parent process is not alive then the server should exit.
    processId: ?i32 = null,
    /// Information about the client
    ///
    /// @since 3.15.0
    clientInfo: ?ClientInfo = null,
    /// The locale the client is currently showing the user interface
    /// in. This must not necessarily be the locale of the operating
    /// system.
    ///
    /// Uses IETF language tags as the value's syntax
    /// (See https://en.wikipedia.org/wiki/IETF_language_tag)
    ///
    /// @since 3.16.0
    locale: ?[]const u8 = null,
    /// The rootPath of the workspace. Is null
    /// if no folder is open.
    ///
    /// @deprecated in favour of rootUri.
    rootPath: ?[]const u8 = null,
    /// The rootUri of the workspace. Is null if no
    /// folder is open. If both `rootPath` and `rootUri` are set
    /// `rootUri` wins.
    ///
    /// @deprecated in favour of workspaceFolders.
    rootUri: ?DocumentUri = null,
    /// The capabilities provided by the client (editor or tool)
    capabilities: ClientCapabilities,
    /// User provided initialization options.
    initializationOptions: ?LSPAny = null,
    /// The initial trace setting. If omitted trace is disabled ('off').
    trace: ?TraceValues = null,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Extends WorkspaceFoldersInitializeParams
    /// The workspace folders configured in the client when the server starts.
    ///
    /// This property is only available if the client supports workspace folders.
    /// It can be `null` if the client supports workspace folders but none are
    /// configured.
    ///
    /// @since 3.6.0
    workspaceFolders: ?[]const WorkspaceFolder = null,
};

/// The result returned from an initialize request.
pub const InitializeResult = struct {
    /// The capabilities the language server provides.
    capabilities: ServerCapabilities,
    /// Information about the server.
    ///
    /// @since 3.15.0
    serverInfo: ?ServerInfo = null,
};

/// The data type of the ResponseError if the
/// initialize request fails.
pub const InitializeError = struct {
    /// Indicates whether the client execute the following retry logic:
    /// (1) show the message provided by the ResponseError to the user
    /// (2) user selects retry or cancel
    /// (3) if user selected retry the initialize method is sent again.
    retry: bool,
};

pub const InitializedParams = struct {};

/// The parameters of a change configuration notification.
pub const DidChangeConfigurationParams = struct {
    /// The actual changed settings
    settings: LSPAny,
};

pub const DidChangeConfigurationRegistrationOptions = struct {
    section: ?union(enum) {
        string: []const u8,
        array_of_string: []const []const u8,
        pub usingnamespace UnionParser(@This());
    } = null,
};

/// The parameters of a notification message.
pub const ShowMessageParams = struct {
    /// The message type. See {@link MessageType}
    type: MessageType,
    /// The actual message.
    message: []const u8,
};

pub const ShowMessageRequestParams = struct {
    /// The message type. See {@link MessageType}
    type: MessageType,
    /// The actual message.
    message: []const u8,
    /// The message action items to present.
    actions: ?[]const MessageActionItem = null,
};

pub const MessageActionItem = struct {
    /// A short title like 'Retry', 'Open Log' etc.
    title: []const u8,
};

/// The log message parameters.
pub const LogMessageParams = struct {
    /// The message type. See {@link MessageType}
    type: MessageType,
    /// The actual message.
    message: []const u8,
};

/// The parameters sent in an open text document notification
pub const DidOpenTextDocumentParams = struct {
    /// The document that was opened.
    textDocument: TextDocumentItem,
};

/// The change text document notification's parameters.
pub const DidChangeTextDocumentParams = struct {
    /// The document that did change. The version number points
    /// to the version after all provided content changes have
    /// been applied.
    textDocument: VersionedTextDocumentIdentifier,
    /// The actual content changes. The content changes describe single state changes
    /// to the document. So if there are two content changes c1 (at array index 0) and
    /// c2 (at array index 1) for a document in state S then c1 moves the document from
    /// S to S' and c2 from S' to S''. So c1 is computed on the state S and c2 is computed
    /// on the state S'.
    ///
    /// To mirror the content of a document using change events use the following approach:
    /// - start with the same initial content
    /// - apply the 'textDocument/didChange' notifications in the order you receive them.
    /// - apply the `TextDocumentContentChangeEvent`s in a single notification in the order
    ///   you receive them.
    contentChanges: []const TextDocumentContentChangeEvent,
};

/// Describe options to be used when registered for text document change events.
pub const TextDocumentChangeRegistrationOptions = struct {
    /// How documents are synced to the server.
    syncKind: TextDocumentSyncKind,

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,
};

/// The parameters sent in a close text document notification
pub const DidCloseTextDocumentParams = struct {
    /// The document that was closed.
    textDocument: TextDocumentIdentifier,
};

/// The parameters sent in a save text document notification
pub const DidSaveTextDocumentParams = struct {
    /// The document that was saved.
    textDocument: TextDocumentIdentifier,
    /// Optional the content when saved. Depends on the includeText value
    /// when the save notification was requested.
    text: ?[]const u8 = null,
};

/// Save registration options.
pub const TextDocumentSaveRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends SaveOptions
    /// The client is supposed to include the content on save.
    includeText: ?bool = null,
};

/// The parameters sent in a will save text document notification.
pub const WillSaveTextDocumentParams = struct {
    /// The document that will be saved.
    textDocument: TextDocumentIdentifier,
    /// The 'TextDocumentSaveReason'.
    reason: TextDocumentSaveReason,
};

/// A text edit applicable to a text document.
pub const TextEdit = struct {
    /// The range of the text document to be manipulated. To insert
    /// text into a document create a range where start === end.
    range: Range,
    /// The string to be inserted. For delete operations use an
    /// empty string.
    newText: []const u8,
};

/// The watched files change notification's parameters.
pub const DidChangeWatchedFilesParams = struct {
    /// The actual file events.
    changes: []const FileEvent,
};

/// Describe options to be used when registered for text document change events.
pub const DidChangeWatchedFilesRegistrationOptions = struct {
    /// The watchers to register.
    watchers: []const FileSystemWatcher,
};

/// The publish diagnostic notification's parameters.
pub const PublishDiagnosticsParams = struct {
    /// The URI for which diagnostic information is reported.
    uri: DocumentUri,
    /// Optional the version number of the document the diagnostics are published for.
    ///
    /// @since 3.15.0
    version: ?i32 = null,
    /// An array of diagnostic information items.
    diagnostics: []const Diagnostic,
};

/// Completion parameters
pub const CompletionParams = struct {
    /// The completion context. This is only available it the client specifies
    /// to send this using the client capability `textDocument.completion.contextSupport === true`
    context: ?CompletionContext = null,

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A completion item represents a text snippet that is
/// proposed to complete text that is being typed.
pub const CompletionItem = struct {
    /// The label of this completion item.
    ///
    /// The label property is also by default the text that
    /// is inserted when selecting this completion.
    ///
    /// If label details are provided the label itself should
    /// be an unqualified name of the completion item.
    label: []const u8,
    /// Additional details for the label
    ///
    /// @since 3.17.0
    labelDetails: ?CompletionItemLabelDetails = null,
    /// The kind of this completion item. Based of the kind
    /// an icon is chosen by the editor.
    kind: ?CompletionItemKind = null,
    /// Tags for this completion item.
    ///
    /// @since 3.15.0
    tags: ?[]const CompletionItemTag = null,
    /// A human-readable string with additional information
    /// about this item, like type or symbol information.
    detail: ?[]const u8 = null,
    /// A human-readable string that represents a doc-comment.
    documentation: ?union(enum) {
        string: []const u8,
        MarkupContent: MarkupContent,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Indicates if this item is deprecated.
    /// @deprecated Use `tags` instead.
    deprecated: ?bool = null,
    /// Select this item when showing.
    ///
    /// *Note* that only one completion item can be selected and that the
    /// tool / client decides which item that is. The rule is that the *first*
    /// item of those that match best is selected.
    preselect: ?bool = null,
    /// A string that should be used when comparing this item
    /// with other items. When `falsy` the {@link CompletionItem.label label}
    /// is used.
    sortText: ?[]const u8 = null,
    /// A string that should be used when filtering a set of
    /// completion items. When `falsy` the {@link CompletionItem.label label}
    /// is used.
    filterText: ?[]const u8 = null,
    /// A string that should be inserted into a document when selecting
    /// this completion. When `falsy` the {@link CompletionItem.label label}
    /// is used.
    ///
    /// The `insertText` is subject to interpretation by the client side.
    /// Some tools might not take the string literally. For example
    /// VS Code when code complete is requested in this example
    /// `con<cursor position>` and a completion item with an `insertText` of
    /// `console` is provided it will only insert `sole`. Therefore it is
    /// recommended to use `textEdit` instead since it avoids additional client
    /// side interpretation.
    insertText: ?[]const u8 = null,
    /// The format of the insert text. The format applies to both the
    /// `insertText` property and the `newText` property of a provided
    /// `textEdit`. If omitted defaults to `InsertTextFormat.PlainText`.
    ///
    /// Please note that the insertTextFormat doesn't apply to
    /// `additionalTextEdits`.
    insertTextFormat: ?InsertTextFormat = null,
    /// How whitespace and indentation is handled during completion
    /// item insertion. If not provided the clients default value depends on
    /// the `textDocument.completion.insertTextMode` client capability.
    ///
    /// @since 3.16.0
    insertTextMode: ?InsertTextMode = null,
    /// An {@link TextEdit edit} which is applied to a document when selecting
    /// this completion. When an edit is provided the value of
    /// {@link CompletionItem.insertText insertText} is ignored.
    ///
    /// Most editors support two different operations when accepting a completion
    /// item. One is to insert a completion text and the other is to replace an
    /// existing text with a completion text. Since this can usually not be
    /// predetermined by a server it can report both ranges. Clients need to
    /// signal support for `InsertReplaceEdits` via the
    /// `textDocument.completion.insertReplaceSupport` client capability
    /// property.
    ///
    /// *Note 1:* The text edit's range as well as both ranges from an insert
    /// replace edit must be a [single line] and they must contain the position
    /// at which completion has been requested.
    /// *Note 2:* If an `InsertReplaceEdit` is returned the edit's insert range
    /// must be a prefix of the edit's replace range, that means it must be
    /// contained and starting at the same position.
    ///
    /// @since 3.16.0 additional type `InsertReplaceEdit`
    textEdit: ?union(enum) {
        TextEdit: TextEdit,
        InsertReplaceEdit: InsertReplaceEdit,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The edit text used if the completion item is part of a CompletionList and
    /// CompletionList defines an item default for the text edit range.
    ///
    /// Clients will only honor this property if they opt into completion list
    /// item defaults using the capability `completionList.itemDefaults`.
    ///
    /// If not provided and a list's default range is provided the label
    /// property is used as a text.
    ///
    /// @since 3.17.0
    textEditText: ?[]const u8 = null,
    /// An optional array of additional {@link TextEdit text edits} that are applied when
    /// selecting this completion. Edits must not overlap (including the same insert position)
    /// with the main {@link CompletionItem.textEdit edit} nor with themselves.
    ///
    /// Additional text edits should be used to change text unrelated to the current cursor position
    /// (for example adding an import statement at the top of the file if the completion item will
    /// insert an unqualified type).
    additionalTextEdits: ?[]const TextEdit = null,
    /// An optional set of characters that when pressed while this completion is active will accept it first and
    /// then type that character. *Note* that all commit characters should have `length=1` and that superfluous
    /// characters will be ignored.
    commitCharacters: ?[]const []const u8 = null,
    /// An optional {@link Command command} that is executed *after* inserting this completion. *Note* that
    /// additional modifications to the current document should be described with the
    /// {@link CompletionItem.additionalTextEdits additionalTextEdits}-property.
    command: ?Command = null,
    /// A data entry field that is preserved on a completion item between a
    /// {@link CompletionRequest} and a {@link CompletionResolveRequest}.
    data: ?LSPAny = null,
};

/// Represents a collection of {@link CompletionItem completion items} to be presented
/// in the editor.
pub const CompletionList = struct {
    /// This list it not complete. Further typing results in recomputing this list.
    ///
    /// Recomputed lists have all their items replaced (not appended) in the
    /// incomplete completion sessions.
    isIncomplete: bool,
    /// In many cases the items of an actual completion result share the same
    /// value for properties like `commitCharacters` or the range of a text
    /// edit. A completion list can therefore define item defaults which will
    /// be used if a completion item itself doesn't specify the value.
    ///
    /// If a completion list specifies a default value and a completion item
    /// also specifies a corresponding value the one from the item is used.
    ///
    /// Servers are only allowed to return default values if the client
    /// signals support for this via the `completionList.itemDefaults`
    /// capability.
    ///
    /// @since 3.17.0
    itemDefaults: ?CompletionItemDefaults = null,
    /// The completion items.
    items: []const CompletionItem,
};

/// Registration options for a {@link CompletionRequest}.
pub const CompletionRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends CompletionOptions
    /// Most tools trigger completion request automatically without explicitly requesting
    /// it using a keyboard shortcut (e.g. Ctrl+Space). Typically they do so when the user
    /// starts to type an identifier. For example if the user types `c` in a JavaScript file
    /// code complete will automatically pop up present `console` besides others as a
    /// completion item. Characters that make up identifiers don't need to be listed here.
    ///
    /// If code complete should automatically be trigger on characters not being valid inside
    /// an identifier (for example `.` in JavaScript) list them in `triggerCharacters`.
    triggerCharacters: ?[]const []const u8 = null,
    /// The list of all possible characters that commit a completion. This field can be used
    /// if clients don't support individual commit characters per completion item. See
    /// `ClientCapabilities.textDocument.completion.completionItem.commitCharactersSupport`
    ///
    /// If a server provides both `allCommitCharacters` and commit characters on an individual
    /// completion item the ones on the completion item win.
    ///
    /// @since 3.2.0
    allCommitCharacters: ?[]const []const u8 = null,
    /// The server provides support to resolve additional
    /// information for a completion item.
    resolveProvider: ?bool = null,
    /// The server supports the following `CompletionItem` specific
    /// capabilities.
    ///
    /// @since 3.17.0
    completionItem: ?ServerCompletionItemOptions = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Parameters for a {@link HoverRequest}.
pub const HoverParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// The result of a hover request.
pub const Hover = struct {
    /// The hover's content
    contents: union(enum) {
        MarkupContent: MarkupContent,
        MarkedString: MarkedString,
        array_of_MarkedString: []const MarkedString,
        pub usingnamespace UnionParser(@This());
    },
    /// An optional range inside the text document that is used to
    /// visualize the hover, e.g. by changing the background color.
    range: ?Range = null,
};

/// Registration options for a {@link HoverRequest}.
pub const HoverRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends HoverOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Parameters for a {@link SignatureHelpRequest}.
pub const SignatureHelpParams = struct {
    /// The signature help context. This is only available if the client specifies
    /// to send this using the client capability `textDocument.signatureHelp.contextSupport === true`
    ///
    /// @since 3.15.0
    context: ?SignatureHelpContext = null,

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Signature help represents the signature of something
/// callable. There can be multiple signature but only one
/// active and only one active parameter.
pub const SignatureHelp = struct {
    /// One or more signatures.
    signatures: []const SignatureInformation,
    /// The active signature. If omitted or the value lies outside the
    /// range of `signatures` the value defaults to zero or is ignored if
    /// the `SignatureHelp` has no signatures.
    ///
    /// Whenever possible implementors should make an active decision about
    /// the active signature and shouldn't rely on a default value.
    ///
    /// In future version of the protocol this property might become
    /// mandatory to better express this.
    activeSignature: ?u32 = null,
    /// The active parameter of the active signature. If omitted or the value
    /// lies outside the range of `signatures[activeSignature].parameters`
    /// defaults to 0 if the active signature has parameters. If
    /// the active signature has no parameters it is ignored.
    /// In future version of the protocol this property might become
    /// mandatory to better express the active parameter if the
    /// active signature does have any.
    activeParameter: ?u32 = null,
};

/// Registration options for a {@link SignatureHelpRequest}.
pub const SignatureHelpRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends SignatureHelpOptions
    /// List of characters that trigger signature help automatically.
    triggerCharacters: ?[]const []const u8 = null,
    /// List of characters that re-trigger signature help.
    ///
    /// These trigger characters are only active when signature help is already showing. All trigger characters
    /// are also counted as re-trigger characters.
    ///
    /// @since 3.15.0
    retriggerCharacters: ?[]const []const u8 = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Parameters for a {@link DefinitionRequest}.
pub const DefinitionParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Registration options for a {@link DefinitionRequest}.
pub const DefinitionRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DefinitionOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Parameters for a {@link ReferencesRequest}.
pub const ReferenceParams = struct {
    context: ReferenceContext,

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Registration options for a {@link ReferencesRequest}.
pub const ReferenceRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends ReferenceOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Parameters for a {@link DocumentHighlightRequest}.
pub const DocumentHighlightParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A document highlight is a range inside a text document which deserves
/// special attention. Usually a document highlight is visualized by changing
/// the background color of its range.
pub const DocumentHighlight = struct {
    /// The range this highlight applies to.
    range: Range,
    /// The highlight kind, default is {@link DocumentHighlightKind.Text text}.
    kind: ?DocumentHighlightKind = null,
};

/// Registration options for a {@link DocumentHighlightRequest}.
pub const DocumentHighlightRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentHighlightOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Parameters for a {@link DocumentSymbolRequest}.
pub const DocumentSymbolParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents information about programming constructs like variables, classes,
/// interfaces etc.
pub const SymbolInformation = struct {
    /// Indicates if this symbol is deprecated.
    ///
    /// @deprecated Use tags instead
    deprecated: ?bool = null,
    /// The location of this symbol. The location's range is used by a tool
    /// to reveal the location in the editor. If the symbol is selected in the
    /// tool the range's start information is used to position the cursor. So
    /// the range usually spans more than the actual symbol's name and does
    /// normally include things like visibility modifiers.
    ///
    /// The range doesn't have to denote a node range in the sense of an abstract
    /// syntax tree. It can therefore not be used to re-construct a hierarchy of
    /// the symbols.
    location: Location,

    // Extends BaseSymbolInformation
    /// The name of this symbol.
    name: []const u8,
    /// The kind of this symbol.
    kind: SymbolKind,
    /// Tags for this symbol.
    ///
    /// @since 3.16.0
    tags: ?[]const SymbolTag = null,
    /// The name of the symbol containing this symbol. This information is for
    /// user interface purposes (e.g. to render a qualifier in the user interface
    /// if necessary). It can't be used to re-infer a hierarchy for the document
    /// symbols.
    containerName: ?[]const u8 = null,
};

/// Represents programming constructs like variables, classes, interfaces etc.
/// that appear in a document. Document symbols can be hierarchical and they
/// have two ranges: one that encloses its definition and one that points to
/// its most interesting range, e.g. the range of an identifier.
pub const DocumentSymbol = struct {
    /// The name of this symbol. Will be displayed in the user interface and therefore must not be
    /// an empty string or a string only consisting of white spaces.
    name: []const u8,
    /// More detail for this symbol, e.g the signature of a function.
    detail: ?[]const u8 = null,
    /// The kind of this symbol.
    kind: SymbolKind,
    /// Tags for this document symbol.
    ///
    /// @since 3.16.0
    tags: ?[]const SymbolTag = null,
    /// Indicates if this symbol is deprecated.
    ///
    /// @deprecated Use tags instead
    deprecated: ?bool = null,
    /// The range enclosing this symbol not including leading/trailing whitespace but everything else
    /// like comments. This information is typically used to determine if the clients cursor is
    /// inside the symbol to reveal in the symbol in the UI.
    range: Range,
    /// The range that should be selected and revealed when this symbol is being picked, e.g the name of a function.
    /// Must be contained by the `range`.
    selectionRange: Range,
    /// Children of this symbol, e.g. properties of a class.
    children: ?[]const DocumentSymbol = null,
};

/// Registration options for a {@link DocumentSymbolRequest}.
pub const DocumentSymbolRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentSymbolOptions
    /// A human-readable string that is shown when multiple outlines trees
    /// are shown for the same document.
    ///
    /// @since 3.16.0
    label: ?[]const u8 = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link CodeActionRequest}.
pub const CodeActionParams = struct {
    /// The document in which the command was invoked.
    textDocument: TextDocumentIdentifier,
    /// The range for which the command was invoked.
    range: Range,
    /// Context carrying additional information.
    context: CodeActionContext,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents a reference to a command. Provides a title which
/// will be used to represent a command in the UI and, optionally,
/// an array of arguments which will be passed to the command handler
/// function when invoked.
pub const Command = struct {
    /// Title of the command, like `save`.
    title: []const u8,
    /// The identifier of the actual command handler.
    command: []const u8,
    /// Arguments that the command handler should be
    /// invoked with.
    arguments: ?[]const LSPAny = null,
};

/// A code action represents a change that can be performed in code, e.g. to fix a problem or
/// to refactor code.
///
/// A CodeAction must set either `edit` and/or a `command`. If both are supplied, the `edit` is applied first, then the `command` is executed.
pub const CodeAction = struct {
    /// A short, human-readable, title for this code action.
    title: []const u8,
    /// The kind of the code action.
    ///
    /// Used to filter code actions.
    kind: ?CodeActionKind = null,
    /// The diagnostics that this code action resolves.
    diagnostics: ?[]const Diagnostic = null,
    /// Marks this as a preferred action. Preferred actions are used by the `auto fix` command and can be targeted
    /// by keybindings.
    ///
    /// A quick fix should be marked preferred if it properly addresses the underlying error.
    /// A refactoring should be marked preferred if it is the most reasonable choice of actions to take.
    ///
    /// @since 3.15.0
    isPreferred: ?bool = null,
    /// Marks that the code action cannot currently be applied.
    ///
    /// Clients should follow the following guidelines regarding disabled code actions:
    ///
    ///   - Disabled code actions are not shown in automatic [lightbulbs](https://code.visualstudio.com/docs/editor/editingevolved#_code-action)
    ///     code action menus.
    ///
    ///   - Disabled actions are shown as faded out in the code action menu when the user requests a more specific type
    ///     of code action, such as refactorings.
    ///
    ///   - If the user has a [keybinding](https://code.visualstudio.com/docs/editor/refactoring#_keybindings-for-code-actions)
    ///     that auto applies a code action and only disabled code actions are returned, the client should show the user an
    ///     error message with `reason` in the editor.
    ///
    /// @since 3.16.0
    disabled: ?CodeActionDisabled = null,
    /// The workspace edit this code action performs.
    edit: ?WorkspaceEdit = null,
    /// A command this code action executes. If a code action
    /// provides an edit and a command, first the edit is
    /// executed and then the command.
    command: ?Command = null,
    /// A data entry field that is preserved on a code action between
    /// a `textDocument/codeAction` and a `codeAction/resolve` request.
    ///
    /// @since 3.16.0
    data: ?LSPAny = null,
};

/// Registration options for a {@link CodeActionRequest}.
pub const CodeActionRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends CodeActionOptions
    /// CodeActionKinds that this server may return.
    ///
    /// The list of kinds may be generic, such as `CodeActionKind.Refactor`, or the server
    /// may list out every specific kind they provide.
    codeActionKinds: ?[]const CodeActionKind = null,
    /// The server provides support to resolve additional
    /// information for a code action.
    ///
    /// @since 3.16.0
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link WorkspaceSymbolRequest}.
pub const WorkspaceSymbolParams = struct {
    /// A query string to filter symbols by. Clients may send an empty
    /// string here to request all symbols.
    query: []const u8,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A special workspace symbol that supports locations without a range.
///
/// See also SymbolInformation.
///
/// @since 3.17.0
pub const WorkspaceSymbol = struct {
    /// The location of the symbol. Whether a server is allowed to
    /// return a location without a range depends on the client
    /// capability `workspace.symbol.resolveSupport`.
    ///
    /// See SymbolInformation#location for more details.
    location: union(enum) {
        Location: Location,
        LocationUriOnly: LocationUriOnly,
        pub usingnamespace UnionParser(@This());
    },
    /// A data entry field that is preserved on a workspace symbol between a
    /// workspace symbol request and a workspace symbol resolve request.
    data: ?LSPAny = null,

    // Extends BaseSymbolInformation
    /// The name of this symbol.
    name: []const u8,
    /// The kind of this symbol.
    kind: SymbolKind,
    /// Tags for this symbol.
    ///
    /// @since 3.16.0
    tags: ?[]const SymbolTag = null,
    /// The name of the symbol containing this symbol. This information is for
    /// user interface purposes (e.g. to render a qualifier in the user interface
    /// if necessary). It can't be used to re-infer a hierarchy for the document
    /// symbols.
    containerName: ?[]const u8 = null,
};

/// Registration options for a {@link WorkspaceSymbolRequest}.
pub const WorkspaceSymbolRegistrationOptions = struct {

    // Extends WorkspaceSymbolOptions
    /// The server provides support to resolve additional
    /// information for a workspace symbol.
    ///
    /// @since 3.17.0
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link CodeLensRequest}.
pub const CodeLensParams = struct {
    /// The document to request code lens for.
    textDocument: TextDocumentIdentifier,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A code lens represents a {@link Command command} that should be shown along with
/// source text, like the number of references, a way to run tests, etc.
///
/// A code lens is _unresolved_ when no command is associated to it. For performance
/// reasons the creation of a code lens and resolving should be done in two stages.
pub const CodeLens = struct {
    /// The range in which this code lens is valid. Should only span a single line.
    range: Range,
    /// The command this code lens represents.
    command: ?Command = null,
    /// A data entry field that is preserved on a code lens item between
    /// a {@link CodeLensRequest} and a {@link CodeLensResolveRequest}
    data: ?LSPAny = null,
};

/// Registration options for a {@link CodeLensRequest}.
pub const CodeLensRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends CodeLensOptions
    /// Code lens has a resolve provider as well.
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link DocumentLinkRequest}.
pub const DocumentLinkParams = struct {
    /// The document to provide document links for.
    textDocument: TextDocumentIdentifier,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,

    // Uses mixin PartialResultParams
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// A document link is a range in a text document that links to an internal or external resource, like another
/// text document or a web site.
pub const DocumentLink = struct {
    /// The range this link applies to.
    range: Range,
    /// The uri this link points to. If missing a resolve request is sent later.
    target: ?URI = null,
    /// The tooltip text when you hover over this link.
    ///
    /// If a tooltip is provided, is will be displayed in a string that includes instructions on how to
    /// trigger the link, such as `{0} (ctrl + click)`. The specific instructions vary depending on OS,
    /// user settings, and localization.
    ///
    /// @since 3.15.0
    tooltip: ?[]const u8 = null,
    /// A data entry field that is preserved on a document link between a
    /// DocumentLinkRequest and a DocumentLinkResolveRequest.
    data: ?LSPAny = null,
};

/// Registration options for a {@link DocumentLinkRequest}.
pub const DocumentLinkRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentLinkOptions
    /// Document links have a resolve provider as well.
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link DocumentFormattingRequest}.
pub const DocumentFormattingParams = struct {
    /// The document to format.
    textDocument: TextDocumentIdentifier,
    /// The format options.
    options: FormattingOptions,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Registration options for a {@link DocumentFormattingRequest}.
pub const DocumentFormattingRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentFormattingOptions

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link DocumentRangeFormattingRequest}.
pub const DocumentRangeFormattingParams = struct {
    /// The document to format.
    textDocument: TextDocumentIdentifier,
    /// The range to format
    range: Range,
    /// The format options
    options: FormattingOptions,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Registration options for a {@link DocumentRangeFormattingRequest}.
pub const DocumentRangeFormattingRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentRangeFormattingOptions
    /// Whether the server supports formatting multiple ranges at once.
    ///
    /// @since 3.18.0
    /// @proposed
    rangesSupport: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters of a {@link DocumentRangesFormattingRequest}.
///
/// @since 3.18.0
/// @proposed
pub const DocumentRangesFormattingParams = struct {
    /// The document to format.
    textDocument: TextDocumentIdentifier,
    /// The ranges to format
    ranges: []const Range,
    /// The format options
    options: FormattingOptions,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// The parameters of a {@link DocumentOnTypeFormattingRequest}.
pub const DocumentOnTypeFormattingParams = struct {
    /// The document to format.
    textDocument: TextDocumentIdentifier,
    /// The position around which the on type formatting should happen.
    /// This is not necessarily the exact position where the character denoted
    /// by the property `ch` got typed.
    position: Position,
    /// The character that has been typed that triggered the formatting
    /// on type request. That is not necessarily the last character that
    /// got inserted into the document since the client could auto insert
    /// characters as well (e.g. like automatic brace completion).
    ch: []const u8,
    /// The formatting options.
    options: FormattingOptions,
};

/// Registration options for a {@link DocumentOnTypeFormattingRequest}.
pub const DocumentOnTypeFormattingRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends DocumentOnTypeFormattingOptions
    /// A character on which formatting should be triggered, like `{`.
    firstTriggerCharacter: []const u8,
    /// More trigger characters.
    moreTriggerCharacter: ?[]const []const u8 = null,
};

/// The parameters of a {@link RenameRequest}.
pub const RenameParams = struct {
    /// The document to rename.
    textDocument: TextDocumentIdentifier,
    /// The position at which this request was sent.
    position: Position,
    /// The new name of the symbol. If the given name is not valid the
    /// request must return a {@link ResponseError} with an
    /// appropriate message set.
    newName: []const u8,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Registration options for a {@link RenameRequest}.
pub const RenameRegistrationOptions = struct {

    // Extends TextDocumentRegistrationOptions
    /// A document selector to identify the scope of the registration. If set to null
    /// the document selector provided on the client side will be used.
    documentSelector: ?DocumentSelector = null,

    // Extends RenameOptions
    /// Renames should be checked and tested before being executed.
    ///
    /// @since version 3.12.0
    prepareProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

pub const PrepareRenameParams = struct {

    // Extends TextDocumentPositionParams
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// The parameters of a {@link ExecuteCommandRequest}.
pub const ExecuteCommandParams = struct {
    /// The identifier of the actual command handler.
    command: []const u8,
    /// Arguments that the command should be invoked with.
    arguments: ?[]const LSPAny = null,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

/// Registration options for a {@link ExecuteCommandRequest}.
pub const ExecuteCommandRegistrationOptions = struct {

    // Extends ExecuteCommandOptions
    /// The commands to be executed on the server
    commands: []const []const u8,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The parameters passed via an apply workspace edit request.
pub const ApplyWorkspaceEditParams = struct {
    /// An optional label of the workspace edit. This label is
    /// presented in the user interface for example on an undo
    /// stack to undo the workspace edit.
    label: ?[]const u8 = null,
    /// The edits to apply.
    edit: WorkspaceEdit,
};

/// The result returned from the apply workspace edit request.
///
/// @since 3.17 renamed from ApplyWorkspaceEditResponse
pub const ApplyWorkspaceEditResult = struct {
    /// Indicates whether the edit was applied or not.
    applied: bool,
    /// An optional textual description for why the edit was not applied.
    /// This may be used by the server for diagnostic logging or to provide
    /// a suitable error for a request that triggered the edit.
    failureReason: ?[]const u8 = null,
    /// Depending on the client's failure handling strategy `failedChange` might
    /// contain the index of the change that failed. This property is only available
    /// if the client signals a `failureHandlingStrategy` in its client capabilities.
    failedChange: ?u32 = null,
};

pub const WorkDoneProgressBegin = struct {
    kind: []const u8 = "begin",
    /// Mandatory title of the progress operation. Used to briefly inform about
    /// the kind of operation being performed.
    ///
    /// Examples: "Indexing" or "Linking dependencies".
    title: []const u8,
    /// Controls if a cancel button should show to allow the user to cancel the
    /// long running operation. Clients that don't support cancellation are allowed
    /// to ignore the setting.
    cancellable: ?bool = null,
    /// Optional, more detailed associated progress message. Contains
    /// complementary information to the `title`.
    ///
    /// Examples: "3/25 files", "project/src/module2", "node_modules/some_dep".
    /// If unset, the previous progress message (if any) is still valid.
    message: ?[]const u8 = null,
    /// Optional progress percentage to display (value 100 is considered 100%).
    /// If not provided infinite progress is assumed and clients are allowed
    /// to ignore the `percentage` value in subsequent in report notifications.
    ///
    /// The value should be steadily rising. Clients are free to ignore values
    /// that are not following this rule. The value range is [0, 100].
    percentage: ?u32 = null,
};

pub const WorkDoneProgressReport = struct {
    kind: []const u8 = "report",
    /// Controls enablement state of a cancel button.
    ///
    /// Clients that don't support cancellation or don't support controlling the button's
    /// enablement state are allowed to ignore the property.
    cancellable: ?bool = null,
    /// Optional, more detailed associated progress message. Contains
    /// complementary information to the `title`.
    ///
    /// Examples: "3/25 files", "project/src/module2", "node_modules/some_dep".
    /// If unset, the previous progress message (if any) is still valid.
    message: ?[]const u8 = null,
    /// Optional progress percentage to display (value 100 is considered 100%).
    /// If not provided infinite progress is assumed and clients are allowed
    /// to ignore the `percentage` value in subsequent in report notifications.
    ///
    /// The value should be steadily rising. Clients are free to ignore values
    /// that are not following this rule. The value range is [0, 100]
    percentage: ?u32 = null,
};

pub const WorkDoneProgressEnd = struct {
    kind: []const u8 = "end",
    /// Optional, a final message indicating to for example indicate the outcome
    /// of the operation.
    message: ?[]const u8 = null,
};

pub const SetTraceParams = struct {
    value: TraceValues,
};

pub const LogTraceParams = struct {
    message: []const u8,
    verbose: ?[]const u8 = null,
};

pub const CancelParams = struct {
    /// The request id to cancel.
    id: union(enum) {
        integer: i32,
        string: []const u8,
        pub usingnamespace UnionParser(@This());
    },
};

pub const ProgressParams = struct {
    /// The progress token provided by the client or server.
    token: ProgressToken,
    /// The progress data.
    value: LSPAny,
};

/// A parameter literal used in requests to pass a text document and a position inside that
/// document.
pub const TextDocumentPositionParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,
    /// The position inside the text document.
    position: Position,
};

pub const WorkDoneProgressParams = struct {
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

pub const PartialResultParams = struct {
    /// An optional token that a server can use to report partial results (e.g. streaming) to
    /// the client.
    partialResultToken: ?ProgressToken = null,
};

/// Represents the connection of two locations. Provides additional metadata over normal {@link Location locations},
/// including an origin range.
pub const LocationLink = struct {
    /// Span of the origin of this link.
    ///
    /// Used as the underlined span for mouse interaction. Defaults to the word range at
    /// the definition position.
    originSelectionRange: ?Range = null,
    /// The target resource identifier of this link.
    targetUri: DocumentUri,
    /// The full target range of this link. If the target for example is a symbol then target range is the
    /// range enclosing this symbol not including leading/trailing whitespace but everything else
    /// like comments. This information is typically used to highlight the range in the editor.
    targetRange: Range,
    /// The range that should be selected and revealed when this link is being followed, e.g the name of a function.
    /// Must be contained by the `targetRange`. See also `DocumentSymbol#range`
    targetSelectionRange: Range,
};

/// A range in a text document expressed as (zero-based) start and end positions.
///
/// If you want to specify a range that contains a line including the line ending
/// character(s) then use an end position denoting the start of the next line.
/// For example:
/// ```ts
/// {
///     start: { line: 5, character: 23 }
///     end : { line 6, character : 0 }
/// }
/// ```
pub const Range = struct {
    /// The range's start position.
    start: Position,
    /// The range's end position.
    end: Position,
};

pub const ImplementationOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Static registration options to be returned in the initialize
/// request.
pub const StaticRegistrationOptions = struct {
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

pub const TypeDefinitionOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// The workspace folder change event.
pub const WorkspaceFoldersChangeEvent = struct {
    /// The array of added workspace folders
    added: []const WorkspaceFolder,
    /// The array of the removed workspace folders
    removed: []const WorkspaceFolder,
};

pub const ConfigurationItem = struct {
    /// The scope to get the configuration section for.
    scopeUri: ?URI = null,
    /// The configuration section asked for.
    section: ?[]const u8 = null,
};

/// A literal to identify a text document in the client.
pub const TextDocumentIdentifier = struct {
    /// The text document's uri.
    uri: DocumentUri,
};

/// Represents a color in RGBA space.
pub const Color = struct {
    /// The red component of this color in the range [0-1].
    red: f32,
    /// The green component of this color in the range [0-1].
    green: f32,
    /// The blue component of this color in the range [0-1].
    blue: f32,
    /// The alpha component of this color in the range [0-1].
    alpha: f32,
};

pub const DocumentColorOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

pub const FoldingRangeOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

pub const DeclarationOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Position in a text document expressed as zero-based line and character
/// offset. Prior to 3.17 the offsets were always based on a UTF-16 string
/// representation. So a string of the form `a𐐀b` the character offset of the
/// character `a` is 0, the character offset of `𐐀` is 1 and the character
/// offset of b is 3 since `𐐀` is represented using two code units in UTF-16.
/// Since 3.17 clients and servers can agree on a different string encoding
/// representation (e.g. UTF-8). The client announces it's supported encoding
/// via the client capability [`general.positionEncodings`](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#clientCapabilities).
/// The value is an array of position encodings the client supports, with
/// decreasing preference (e.g. the encoding at index `0` is the most preferred
/// one). To stay backwards compatible the only mandatory encoding is UTF-16
/// represented via the string `utf-16`. The server can pick one of the
/// encodings offered by the client and signals that encoding back to the
/// client via the initialize result's property
/// [`capabilities.positionEncoding`](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#serverCapabilities). If the string value
/// `utf-16` is missing from the client's capability `general.positionEncodings`
/// servers can safely assume that the client supports UTF-16. If the server
/// omits the position encoding in its initialize result the encoding defaults
/// to the string value `utf-16`. Implementation considerations: since the
/// conversion from one encoding into another requires the content of the
/// file / line the conversion is best done where the file is read which is
/// usually on the server side.
///
/// Positions are line end character agnostic. So you can not specify a position
/// that denotes `\r|\n` or `\n|` where `|` represents the character offset.
///
/// @since 3.17.0 - support for negotiated position encoding.
pub const Position = struct {
    /// Line position in a document (zero-based).
    ///
    /// If a line number is greater than the number of lines in a document, it defaults back to the number of lines in the document.
    /// If a line number is negative, it defaults to 0.
    line: u32,
    /// Character offset on a line in a document (zero-based).
    ///
    /// The meaning of this offset is determined by the negotiated
    /// `PositionEncodingKind`.
    ///
    /// If the character value is greater than the line length it defaults back to the
    /// line length.
    character: u32,
};

pub const SelectionRangeOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Call hierarchy options used during static registration.
///
/// @since 3.16.0
pub const CallHierarchyOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// @since 3.16.0
pub const SemanticTokensOptions = struct {
    /// The legend used by the server
    legend: SemanticTokensLegend,
    /// Server supports providing semantic tokens for a specific range
    /// of a document.
    range: ?union(enum) {
        bool: bool,
        literal_1: struct {},
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Server supports providing semantic tokens for a full document.
    full: ?union(enum) {
        bool: bool,
        SemanticTokensFullDelta: SemanticTokensFullDelta,
        pub usingnamespace UnionParser(@This());
    } = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// @since 3.16.0
pub const SemanticTokensEdit = struct {
    /// The start offset of the edit.
    start: u32,
    /// The count of elements to remove.
    deleteCount: u32,
    /// The elements to insert.
    data: ?[]const u32 = null,
};

pub const LinkedEditingRangeOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Represents information on a file/folder create.
///
/// @since 3.16.0
pub const FileCreate = struct {
    /// A file:// URI for the location of the file/folder being created.
    uri: []const u8,
};

/// Describes textual changes on a text document. A TextDocumentEdit describes all changes
/// on a document version Si and after they are applied move the document to version Si+1.
/// So the creator of a TextDocumentEdit doesn't need to sort the array of edits or do any
/// kind of ordering. However the edits must be non overlapping.
pub const TextDocumentEdit = struct {
    /// The text document to change.
    textDocument: OptionalVersionedTextDocumentIdentifier,
    /// The edits to be applied.
    ///
    /// @since 3.16.0 - support for AnnotatedTextEdit. This is guarded using a
    /// client capability.
    edits: []const union(enum) {
        TextEdit: TextEdit,
        AnnotatedTextEdit: AnnotatedTextEdit,
        pub usingnamespace UnionParser(@This());
    },
};

/// Create file operation.
pub const CreateFile = struct {
    /// A create
    kind: []const u8 = "create",
    /// The resource to create.
    uri: DocumentUri,
    /// Additional options
    options: ?CreateFileOptions = null,

    // Extends ResourceOperation
    /// An optional annotation identifier describing the operation.
    ///
    /// @since 3.16.0
    annotationId: ?ChangeAnnotationIdentifier = null,
};

/// Rename file operation
pub const RenameFile = struct {
    /// A rename
    kind: []const u8 = "rename",
    /// The old (existing) location.
    oldUri: DocumentUri,
    /// The new location.
    newUri: DocumentUri,
    /// Rename options.
    options: ?RenameFileOptions = null,

    // Extends ResourceOperation
    /// An optional annotation identifier describing the operation.
    ///
    /// @since 3.16.0
    annotationId: ?ChangeAnnotationIdentifier = null,
};

/// Delete file operation
pub const DeleteFile = struct {
    /// A delete
    kind: []const u8 = "delete",
    /// The file to delete.
    uri: DocumentUri,
    /// Delete options.
    options: ?DeleteFileOptions = null,

    // Extends ResourceOperation
    /// An optional annotation identifier describing the operation.
    ///
    /// @since 3.16.0
    annotationId: ?ChangeAnnotationIdentifier = null,
};

/// Additional information that describes document changes.
///
/// @since 3.16.0
pub const ChangeAnnotation = struct {
    /// A human-readable string describing the actual change. The string
    /// is rendered prominent in the user interface.
    label: []const u8,
    /// A flag which indicates that user confirmation is needed
    /// before applying the change.
    needsConfirmation: ?bool = null,
    /// A human-readable string which is rendered less prominent in
    /// the user interface.
    description: ?[]const u8 = null,
};

/// A filter to describe in which file operation requests or notifications
/// the server is interested in receiving.
///
/// @since 3.16.0
pub const FileOperationFilter = struct {
    /// A Uri scheme like `file` or `untitled`.
    scheme: ?[]const u8 = null,
    /// The actual file operation pattern.
    pattern: FileOperationPattern,
};

/// Represents information on a file/folder rename.
///
/// @since 3.16.0
pub const FileRename = struct {
    /// A file:// URI for the original location of the file/folder being renamed.
    oldUri: []const u8,
    /// A file:// URI for the new location of the file/folder being renamed.
    newUri: []const u8,
};

/// Represents information on a file/folder delete.
///
/// @since 3.16.0
pub const FileDelete = struct {
    /// A file:// URI for the location of the file/folder being deleted.
    uri: []const u8,
};

pub const MonikerOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Type hierarchy options used during static registration.
///
/// @since 3.17.0
pub const TypeHierarchyOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// @since 3.17.0
pub const InlineValueContext = struct {
    /// The stack frame (as a DAP Id) where the execution has stopped.
    frameId: i32,
    /// The document range where execution has stopped.
    /// Typically the end position of the range denotes the line where the inline values are shown.
    stoppedLocation: Range,
};

/// Provide inline value as text.
///
/// @since 3.17.0
pub const InlineValueText = struct {
    /// The document range for which the inline value applies.
    range: Range,
    /// The text of the inline value.
    text: []const u8,
};

/// Provide inline value through a variable lookup.
/// If only a range is specified, the variable name will be extracted from the underlying document.
/// An optional variable name can be used to override the extracted name.
///
/// @since 3.17.0
pub const InlineValueVariableLookup = struct {
    /// The document range for which the inline value applies.
    /// The range is used to extract the variable name from the underlying document.
    range: Range,
    /// If specified the name of the variable to look up.
    variableName: ?[]const u8 = null,
    /// How to perform the lookup.
    caseSensitiveLookup: bool,
};

/// Provide an inline value through an expression evaluation.
/// If only a range is specified, the expression will be extracted from the underlying document.
/// An optional expression can be used to override the extracted expression.
///
/// @since 3.17.0
pub const InlineValueEvaluatableExpression = struct {
    /// The document range for which the inline value applies.
    /// The range is used to extract the evaluatable expression from the underlying document.
    range: Range,
    /// If specified the expression overrides the extracted expression.
    expression: ?[]const u8 = null,
};

/// Inline value options used during static registration.
///
/// @since 3.17.0
pub const InlineValueOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// An inlay hint label part allows for interactive and composite labels
/// of inlay hints.
///
/// @since 3.17.0
pub const InlayHintLabelPart = struct {
    /// The value of this label part.
    value: []const u8,
    /// The tooltip text when you hover over this label part. Depending on
    /// the client capability `inlayHint.resolveSupport` clients might resolve
    /// this property late using the resolve request.
    tooltip: ?union(enum) {
        string: []const u8,
        MarkupContent: MarkupContent,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// An optional source code location that represents this
    /// label part.
    ///
    /// The editor will use this location for the hover and for code navigation
    /// features: This part will become a clickable link that resolves to the
    /// definition of the symbol at the given location (not necessarily the
    /// location itself), it shows the hover that shows at the given location,
    /// and it shows a context menu with further code navigation commands.
    ///
    /// Depending on the client capability `inlayHint.resolveSupport` clients
    /// might resolve this property late using the resolve request.
    location: ?Location = null,
    /// An optional command for this label part.
    ///
    /// Depending on the client capability `inlayHint.resolveSupport` clients
    /// might resolve this property late using the resolve request.
    command: ?Command = null,
};

/// A `MarkupContent` literal represents a string value which content is interpreted base on its
/// kind flag. Currently the protocol supports `plaintext` and `markdown` as markup kinds.
///
/// If the kind is `markdown` then the value can contain fenced code blocks like in GitHub issues.
/// See https://help.github.com/articles/creating-and-highlighting-code-blocks/#syntax-highlighting
///
/// Here is an example how such a string can be constructed using JavaScript / TypeScript:
/// ```ts
/// let markdown: MarkdownContent = {
///  kind: MarkupKind.Markdown,
///  value: [
///    '# Header',
///    'Some text',
///    '```typescript',
///    'someCode();',
///    '```'
///  ].join('\n')
/// };
/// ```
///
/// *Please Note* that clients might sanitize the return markdown. A client could decide to
/// remove HTML from the markdown to avoid script execution.
pub const MarkupContent = struct {
    /// The type of the Markup
    kind: MarkupKind,
    /// The content itself
    value: []const u8,
};

/// Inlay hint options used during static registration.
///
/// @since 3.17.0
pub const InlayHintOptions = struct {
    /// The server provides support to resolve additional
    /// information for an inlay hint item.
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// A full diagnostic report with a set of related documents.
///
/// @since 3.17.0
pub const RelatedFullDocumentDiagnosticReport = struct {
    /// Diagnostics of related documents. This information is useful
    /// in programming languages where code in a file A can generate
    /// diagnostics in a file B which A depends on. An example of
    /// such a language is C/C++ where marco definitions in a file
    /// a.cpp and result in errors in a header file b.hpp.
    ///
    /// @since 3.17.0
    relatedDocuments: ?Map(DocumentUri, union(enum) {
        FullDocumentDiagnosticReport: FullDocumentDiagnosticReport,
        UnchangedDocumentDiagnosticReport: UnchangedDocumentDiagnosticReport,
        pub usingnamespace UnionParser(@This());
    }) = null,

    // Extends FullDocumentDiagnosticReport
    /// A full document diagnostic report.
    kind: []const u8 = "full",
    /// An optional result id. If provided it will
    /// be sent on the next diagnostic request for the
    /// same document.
    resultId: ?[]const u8 = null,
    /// The actual items.
    items: []const Diagnostic,
};

/// An unchanged diagnostic report with a set of related documents.
///
/// @since 3.17.0
pub const RelatedUnchangedDocumentDiagnosticReport = struct {
    /// Diagnostics of related documents. This information is useful
    /// in programming languages where code in a file A can generate
    /// diagnostics in a file B which A depends on. An example of
    /// such a language is C/C++ where marco definitions in a file
    /// a.cpp and result in errors in a header file b.hpp.
    ///
    /// @since 3.17.0
    relatedDocuments: ?Map(DocumentUri, union(enum) {
        FullDocumentDiagnosticReport: FullDocumentDiagnosticReport,
        UnchangedDocumentDiagnosticReport: UnchangedDocumentDiagnosticReport,
        pub usingnamespace UnionParser(@This());
    }) = null,

    // Extends UnchangedDocumentDiagnosticReport
    /// A document diagnostic report indicating
    /// no changes to the last result. A server can
    /// only return `unchanged` if result ids are
    /// provided.
    kind: []const u8 = "unchanged",
    /// A result id which will be sent on the next
    /// diagnostic request for the same document.
    resultId: []const u8,
};

/// A diagnostic report with a full set of problems.
///
/// @since 3.17.0
pub const FullDocumentDiagnosticReport = struct {
    /// A full document diagnostic report.
    kind: []const u8 = "full",
    /// An optional result id. If provided it will
    /// be sent on the next diagnostic request for the
    /// same document.
    resultId: ?[]const u8 = null,
    /// The actual items.
    items: []const Diagnostic,
};

/// A diagnostic report indicating that the last returned
/// report is still accurate.
///
/// @since 3.17.0
pub const UnchangedDocumentDiagnosticReport = struct {
    /// A document diagnostic report indicating
    /// no changes to the last result. A server can
    /// only return `unchanged` if result ids are
    /// provided.
    kind: []const u8 = "unchanged",
    /// A result id which will be sent on the next
    /// diagnostic request for the same document.
    resultId: []const u8,
};

/// Diagnostic options.
///
/// @since 3.17.0
pub const DiagnosticOptions = struct {
    /// An optional identifier under which the diagnostics are
    /// managed by the client.
    identifier: ?[]const u8 = null,
    /// Whether the language has inter file dependencies meaning that
    /// editing code in one file can result in a different diagnostic
    /// set in another file. Inter file dependencies are common for
    /// most programming languages and typically uncommon for linters.
    interFileDependencies: bool,
    /// The server provides support for workspace diagnostics as well.
    workspaceDiagnostics: bool,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// A previous result id in a workspace pull request.
///
/// @since 3.17.0
pub const PreviousResultId = struct {
    /// The URI for which the client knowns a
    /// result id.
    uri: DocumentUri,
    /// The value of the previous result id.
    value: []const u8,
};

/// A notebook document.
///
/// @since 3.17.0
pub const NotebookDocument = struct {
    /// The notebook document's uri.
    uri: URI,
    /// The type of the notebook.
    notebookType: []const u8,
    /// The version number of this document (it will increase after each
    /// change, including undo/redo).
    version: i32,
    /// Additional metadata stored with the notebook
    /// document.
    ///
    /// Note: should always be an object literal (e.g. LSPObject)
    metadata: ?LSPObject = null,
    /// The cells of a notebook.
    cells: []const NotebookCell,
};

/// An item to transfer a text document from the client to the
/// server.
pub const TextDocumentItem = struct {
    /// The text document's uri.
    uri: DocumentUri,
    /// The text document's language identifier.
    languageId: []const u8,
    /// The version number of this document (it will increase after each
    /// change, including undo/redo).
    version: i32,
    /// The content of the opened text document.
    text: []const u8,
};

/// A versioned notebook document identifier.
///
/// @since 3.17.0
pub const VersionedNotebookDocumentIdentifier = struct {
    /// The version number of this notebook document.
    version: i32,
    /// The notebook document's uri.
    uri: URI,
};

/// A change event for a notebook document.
///
/// @since 3.17.0
pub const NotebookDocumentChangeEvent = struct {
    /// The changed meta data if any.
    ///
    /// Note: should always be an object literal (e.g. LSPObject)
    metadata: ?LSPObject = null,
    /// Changes to cells
    cells: ?NotebookDocumentCellChanges = null,
};

/// A literal to identify a notebook document in the client.
///
/// @since 3.17.0
pub const NotebookDocumentIdentifier = struct {
    /// The notebook document's uri.
    uri: URI,
};

/// Provides information about the context in which an inline completion was requested.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionContext = struct {
    /// Describes how the inline completion was triggered.
    triggerKind: InlineCompletionTriggerKind,
    /// Provides information about the currently selected item in the autocomplete widget if it is visible.
    selectedCompletionInfo: ?SelectedCompletionInfo = null,
};

/// A string value used as a snippet is a template which allows to insert text
/// and to control the editor cursor when insertion happens.
///
/// A snippet can define tab stops and placeholders with `$1`, `$2`
/// and `${3:foo}`. `$0` defines the final tab stop, it defaults to
/// the end of the snippet. Variables are defined with `$name` and
/// `${name:default value}`.
///
/// @since 3.18.0
/// @proposed
pub const StringValue = struct {
    /// The kind of string value.
    kind: []const u8 = "snippet",
    /// The snippet string.
    value: []const u8,
};

/// Inline completion options used during static registration.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// General parameters to register for a notification or to register a provider.
pub const Registration = struct {
    /// The id used to register the request. The id can be used to deregister
    /// the request again.
    id: []const u8,
    /// The method / capability to register for.
    method: []const u8,
    /// Options necessary for the registration.
    registerOptions: ?LSPAny = null,
};

/// General parameters to unregister a request or notification.
pub const Unregistration = struct {
    /// The id used to unregister the request or notification. Usually an id
    /// provided during the register request.
    id: []const u8,
    /// The method to unregister for.
    method: []const u8,
};

/// The initialize parameters
pub const _InitializeParams = struct {
    /// The process Id of the parent process that started
    /// the server.
    ///
    /// Is `null` if the process has not been started by another process.
    /// If the parent process is not alive then the server should exit.
    processId: ?i32 = null,
    /// Information about the client
    ///
    /// @since 3.15.0
    clientInfo: ?ClientInfo = null,
    /// The locale the client is currently showing the user interface
    /// in. This must not necessarily be the locale of the operating
    /// system.
    ///
    /// Uses IETF language tags as the value's syntax
    /// (See https://en.wikipedia.org/wiki/IETF_language_tag)
    ///
    /// @since 3.16.0
    locale: ?[]const u8 = null,
    /// The rootPath of the workspace. Is null
    /// if no folder is open.
    ///
    /// @deprecated in favour of rootUri.
    rootPath: ?[]const u8 = null,
    /// The rootUri of the workspace. Is null if no
    /// folder is open. If both `rootPath` and `rootUri` are set
    /// `rootUri` wins.
    ///
    /// @deprecated in favour of workspaceFolders.
    rootUri: ?DocumentUri = null,
    /// The capabilities provided by the client (editor or tool)
    capabilities: ClientCapabilities,
    /// User provided initialization options.
    initializationOptions: ?LSPAny = null,
    /// The initial trace setting. If omitted trace is disabled ('off').
    trace: ?TraceValues = null,

    // Uses mixin WorkDoneProgressParams
    /// An optional token that a server can use to report work done progress.
    workDoneToken: ?ProgressToken = null,
};

pub const WorkspaceFoldersInitializeParams = struct {
    /// The workspace folders configured in the client when the server starts.
    ///
    /// This property is only available if the client supports workspace folders.
    /// It can be `null` if the client supports workspace folders but none are
    /// configured.
    ///
    /// @since 3.6.0
    workspaceFolders: ?[]const WorkspaceFolder = null,
};

/// Defines the capabilities provided by a language
/// server.
pub const ServerCapabilities = struct {
    /// The position encoding the server picked from the encodings offered
    /// by the client via the client capability `general.positionEncodings`.
    ///
    /// If the client didn't provide any position encodings the only valid
    /// value that a server can return is 'utf-16'.
    ///
    /// If omitted it defaults to 'utf-16'.
    ///
    /// @since 3.17.0
    positionEncoding: ?PositionEncodingKind = null,
    /// Defines how text documents are synced. Is either a detailed structure
    /// defining each notification or for backwards compatibility the
    /// TextDocumentSyncKind number.
    textDocumentSync: ?union(enum) {
        TextDocumentSyncOptions: TextDocumentSyncOptions,
        TextDocumentSyncKind: TextDocumentSyncKind,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Defines how notebook documents are synced.
    ///
    /// @since 3.17.0
    notebookDocumentSync: ?union(enum) {
        NotebookDocumentSyncOptions: NotebookDocumentSyncOptions,
        NotebookDocumentSyncRegistrationOptions: NotebookDocumentSyncRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides completion support.
    completionProvider: ?CompletionOptions = null,
    /// The server provides hover support.
    hoverProvider: ?union(enum) {
        bool: bool,
        HoverOptions: HoverOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides signature help support.
    signatureHelpProvider: ?SignatureHelpOptions = null,
    /// The server provides Goto Declaration support.
    declarationProvider: ?union(enum) {
        bool: bool,
        DeclarationOptions: DeclarationOptions,
        DeclarationRegistrationOptions: DeclarationRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides goto definition support.
    definitionProvider: ?union(enum) {
        bool: bool,
        DefinitionOptions: DefinitionOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides Goto Type Definition support.
    typeDefinitionProvider: ?union(enum) {
        bool: bool,
        TypeDefinitionOptions: TypeDefinitionOptions,
        TypeDefinitionRegistrationOptions: TypeDefinitionRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides Goto Implementation support.
    implementationProvider: ?union(enum) {
        bool: bool,
        ImplementationOptions: ImplementationOptions,
        ImplementationRegistrationOptions: ImplementationRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides find references support.
    referencesProvider: ?union(enum) {
        bool: bool,
        ReferenceOptions: ReferenceOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides document highlight support.
    documentHighlightProvider: ?union(enum) {
        bool: bool,
        DocumentHighlightOptions: DocumentHighlightOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides document symbol support.
    documentSymbolProvider: ?union(enum) {
        bool: bool,
        DocumentSymbolOptions: DocumentSymbolOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides code actions. CodeActionOptions may only be
    /// specified if the client states that it supports
    /// `codeActionLiteralSupport` in its initial `initialize` request.
    codeActionProvider: ?union(enum) {
        bool: bool,
        CodeActionOptions: CodeActionOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides code lens.
    codeLensProvider: ?CodeLensOptions = null,
    /// The server provides document link support.
    documentLinkProvider: ?DocumentLinkOptions = null,
    /// The server provides color provider support.
    colorProvider: ?union(enum) {
        bool: bool,
        DocumentColorOptions: DocumentColorOptions,
        DocumentColorRegistrationOptions: DocumentColorRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides workspace symbol support.
    workspaceSymbolProvider: ?union(enum) {
        bool: bool,
        WorkspaceSymbolOptions: WorkspaceSymbolOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides document formatting.
    documentFormattingProvider: ?union(enum) {
        bool: bool,
        DocumentFormattingOptions: DocumentFormattingOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides document range formatting.
    documentRangeFormattingProvider: ?union(enum) {
        bool: bool,
        DocumentRangeFormattingOptions: DocumentRangeFormattingOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides document formatting on typing.
    documentOnTypeFormattingProvider: ?DocumentOnTypeFormattingOptions = null,
    /// The server provides rename support. RenameOptions may only be
    /// specified if the client states that it supports
    /// `prepareSupport` in its initial `initialize` request.
    renameProvider: ?union(enum) {
        bool: bool,
        RenameOptions: RenameOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides folding provider support.
    foldingRangeProvider: ?union(enum) {
        bool: bool,
        FoldingRangeOptions: FoldingRangeOptions,
        FoldingRangeRegistrationOptions: FoldingRangeRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides selection range support.
    selectionRangeProvider: ?union(enum) {
        bool: bool,
        SelectionRangeOptions: SelectionRangeOptions,
        SelectionRangeRegistrationOptions: SelectionRangeRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides execute command support.
    executeCommandProvider: ?ExecuteCommandOptions = null,
    /// The server provides call hierarchy support.
    ///
    /// @since 3.16.0
    callHierarchyProvider: ?union(enum) {
        bool: bool,
        CallHierarchyOptions: CallHierarchyOptions,
        CallHierarchyRegistrationOptions: CallHierarchyRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides linked editing range support.
    ///
    /// @since 3.16.0
    linkedEditingRangeProvider: ?union(enum) {
        bool: bool,
        LinkedEditingRangeOptions: LinkedEditingRangeOptions,
        LinkedEditingRangeRegistrationOptions: LinkedEditingRangeRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides semantic tokens support.
    ///
    /// @since 3.16.0
    semanticTokensProvider: ?union(enum) {
        SemanticTokensOptions: SemanticTokensOptions,
        SemanticTokensRegistrationOptions: SemanticTokensRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides moniker support.
    ///
    /// @since 3.16.0
    monikerProvider: ?union(enum) {
        bool: bool,
        MonikerOptions: MonikerOptions,
        MonikerRegistrationOptions: MonikerRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides type hierarchy support.
    ///
    /// @since 3.17.0
    typeHierarchyProvider: ?union(enum) {
        bool: bool,
        TypeHierarchyOptions: TypeHierarchyOptions,
        TypeHierarchyRegistrationOptions: TypeHierarchyRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides inline values.
    ///
    /// @since 3.17.0
    inlineValueProvider: ?union(enum) {
        bool: bool,
        InlineValueOptions: InlineValueOptions,
        InlineValueRegistrationOptions: InlineValueRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server provides inlay hints.
    ///
    /// @since 3.17.0
    inlayHintProvider: ?union(enum) {
        bool: bool,
        InlayHintOptions: InlayHintOptions,
        InlayHintRegistrationOptions: InlayHintRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The server has support for pull model diagnostics.
    ///
    /// @since 3.17.0
    diagnosticProvider: ?union(enum) {
        DiagnosticOptions: DiagnosticOptions,
        DiagnosticRegistrationOptions: DiagnosticRegistrationOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Inline completion options used during static registration.
    ///
    /// @since 3.18.0
    /// @proposed
    inlineCompletionProvider: ?union(enum) {
        bool: bool,
        InlineCompletionOptions: InlineCompletionOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// Workspace specific server capabilities.
    workspace: ?WorkspaceOptions = null,
    /// Experimental server capabilities.
    experimental: ?LSPAny = null,
};

/// Information about the server
///
/// @since 3.15.0
/// @since 3.18.0 ServerInfo type name added.
/// @proposed
pub const ServerInfo = struct {
    /// The name of the server as defined by the server.
    name: []const u8,
    /// The server's version as defined by the server.
    version: ?[]const u8 = null,
};

/// A text document identifier to denote a specific version of a text document.
pub const VersionedTextDocumentIdentifier = struct {
    /// The version number of this document.
    version: i32,

    // Extends TextDocumentIdentifier
    /// The text document's uri.
    uri: DocumentUri,
};

/// Save options.
pub const SaveOptions = struct {
    /// The client is supposed to include the content on save.
    includeText: ?bool = null,
};

/// An event describing a file change.
pub const FileEvent = struct {
    /// The file's uri.
    uri: DocumentUri,
    /// The change type.
    type: FileChangeType,
};

pub const FileSystemWatcher = struct {
    /// The glob pattern to watch. See {@link GlobPattern glob pattern} for more detail.
    ///
    /// @since 3.17.0 support for relative patterns.
    globPattern: GlobPattern,
    /// The kind of events of interest. If omitted it defaults
    /// to WatchKind.Create | WatchKind.Change | WatchKind.Delete
    /// which is 7.
    kind: ?WatchKind = null,
};

/// Represents a diagnostic, such as a compiler error or warning. Diagnostic objects
/// are only valid in the scope of a resource.
pub const Diagnostic = struct {
    /// The range at which the message applies
    range: Range,
    /// The diagnostic's severity. Can be omitted. If omitted it is up to the
    /// client to interpret diagnostics as error, warning, info or hint.
    severity: ?DiagnosticSeverity = null,
    /// The diagnostic's code, which usually appear in the user interface.
    code: ?union(enum) {
        integer: i32,
        string: []const u8,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// An optional property to describe the error code.
    /// Requires the code field (above) to be present/not null.
    ///
    /// @since 3.16.0
    codeDescription: ?CodeDescription = null,
    /// A human-readable string describing the source of this
    /// diagnostic, e.g. 'typescript' or 'super lint'. It usually
    /// appears in the user interface.
    source: ?[]const u8 = null,
    /// The diagnostic's message. It usually appears in the user interface
    message: []const u8,
    /// Additional metadata about the diagnostic.
    ///
    /// @since 3.15.0
    tags: ?[]const DiagnosticTag = null,
    /// An array of related diagnostic information, e.g. when symbol-names within
    /// a scope collide all definitions can be marked via this property.
    relatedInformation: ?[]const DiagnosticRelatedInformation = null,
    /// A data entry field that is preserved between a `textDocument/publishDiagnostics`
    /// notification and `textDocument/codeAction` request.
    ///
    /// @since 3.16.0
    data: ?LSPAny = null,
};

/// Contains additional information about the context in which a completion request is triggered.
pub const CompletionContext = struct {
    /// How the completion was triggered.
    triggerKind: CompletionTriggerKind,
    /// The trigger character (a single character) that has trigger code complete.
    /// Is undefined if `triggerKind !== CompletionTriggerKind.TriggerCharacter`
    triggerCharacter: ?[]const u8 = null,
};

/// Additional details for a completion item label.
///
/// @since 3.17.0
pub const CompletionItemLabelDetails = struct {
    /// An optional string which is rendered less prominently directly after {@link CompletionItem.label label},
    /// without any spacing. Should be used for function signatures and type annotations.
    detail: ?[]const u8 = null,
    /// An optional string which is rendered less prominently after {@link CompletionItem.detail}. Should be used
    /// for fully qualified names and file paths.
    description: ?[]const u8 = null,
};

/// A special text edit to provide an insert and a replace operation.
///
/// @since 3.16.0
pub const InsertReplaceEdit = struct {
    /// The string to be inserted.
    newText: []const u8,
    /// The range if the insert is requested
    insert: Range,
    /// The range if the replace is requested.
    replace: Range,
};

/// In many cases the items of an actual completion result share the same
/// value for properties like `commitCharacters` or the range of a text
/// edit. A completion list can therefore define item defaults which will
/// be used if a completion item itself doesn't specify the value.
///
/// If a completion list specifies a default value and a completion item
/// also specifies a corresponding value the one from the item is used.
///
/// Servers are only allowed to return default values if the client
/// signals support for this via the `completionList.itemDefaults`
/// capability.
///
/// @since 3.17.0
pub const CompletionItemDefaults = struct {
    /// A default commit character set.
    ///
    /// @since 3.17.0
    commitCharacters: ?[]const []const u8 = null,
    /// A default edit range.
    ///
    /// @since 3.17.0
    editRange: ?union(enum) {
        Range: Range,
        EditRangeWithInsertReplace: EditRangeWithInsertReplace,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// A default insert text format.
    ///
    /// @since 3.17.0
    insertTextFormat: ?InsertTextFormat = null,
    /// A default insert text mode.
    ///
    /// @since 3.17.0
    insertTextMode: ?InsertTextMode = null,
    /// A default data value.
    ///
    /// @since 3.17.0
    data: ?LSPAny = null,
};

/// Completion options.
pub const CompletionOptions = struct {
    /// Most tools trigger completion request automatically without explicitly requesting
    /// it using a keyboard shortcut (e.g. Ctrl+Space). Typically they do so when the user
    /// starts to type an identifier. For example if the user types `c` in a JavaScript file
    /// code complete will automatically pop up present `console` besides others as a
    /// completion item. Characters that make up identifiers don't need to be listed here.
    ///
    /// If code complete should automatically be trigger on characters not being valid inside
    /// an identifier (for example `.` in JavaScript) list them in `triggerCharacters`.
    triggerCharacters: ?[]const []const u8 = null,
    /// The list of all possible characters that commit a completion. This field can be used
    /// if clients don't support individual commit characters per completion item. See
    /// `ClientCapabilities.textDocument.completion.completionItem.commitCharactersSupport`
    ///
    /// If a server provides both `allCommitCharacters` and commit characters on an individual
    /// completion item the ones on the completion item win.
    ///
    /// @since 3.2.0
    allCommitCharacters: ?[]const []const u8 = null,
    /// The server provides support to resolve additional
    /// information for a completion item.
    resolveProvider: ?bool = null,
    /// The server supports the following `CompletionItem` specific
    /// capabilities.
    ///
    /// @since 3.17.0
    completionItem: ?ServerCompletionItemOptions = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Hover options.
pub const HoverOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Additional information about the context in which a signature help request was triggered.
///
/// @since 3.15.0
pub const SignatureHelpContext = struct {
    /// Action that caused signature help to be triggered.
    triggerKind: SignatureHelpTriggerKind,
    /// Character that caused signature help to be triggered.
    ///
    /// This is undefined when `triggerKind !== SignatureHelpTriggerKind.TriggerCharacter`
    triggerCharacter: ?[]const u8 = null,
    /// `true` if signature help was already showing when it was triggered.
    ///
    /// Retriggers occurs when the signature help is already active and can be caused by actions such as
    /// typing a trigger character, a cursor move, or document content changes.
    isRetrigger: bool,
    /// The currently active `SignatureHelp`.
    ///
    /// The `activeSignatureHelp` has its `SignatureHelp.activeSignature` field updated based on
    /// the user navigating through available signatures.
    activeSignatureHelp: ?SignatureHelp = null,
};

/// Represents the signature of something callable. A signature
/// can have a label, like a function-name, a doc-comment, and
/// a set of parameters.
pub const SignatureInformation = struct {
    /// The label of this signature. Will be shown in
    /// the UI.
    label: []const u8,
    /// The human-readable doc-comment of this signature. Will be shown
    /// in the UI but can be omitted.
    documentation: ?union(enum) {
        string: []const u8,
        MarkupContent: MarkupContent,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The parameters of this signature.
    parameters: ?[]const ParameterInformation = null,
    /// The index of the active parameter.
    ///
    /// If provided, this is used in place of `SignatureHelp.activeParameter`.
    ///
    /// @since 3.16.0
    activeParameter: ?u32 = null,
};

/// Server Capabilities for a {@link SignatureHelpRequest}.
pub const SignatureHelpOptions = struct {
    /// List of characters that trigger signature help automatically.
    triggerCharacters: ?[]const []const u8 = null,
    /// List of characters that re-trigger signature help.
    ///
    /// These trigger characters are only active when signature help is already showing. All trigger characters
    /// are also counted as re-trigger characters.
    ///
    /// @since 3.15.0
    retriggerCharacters: ?[]const []const u8 = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Server Capabilities for a {@link DefinitionRequest}.
pub const DefinitionOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Value-object that contains additional information when
/// requesting references.
pub const ReferenceContext = struct {
    /// Include the declaration of the current symbol.
    includeDeclaration: bool,
};

/// Reference options.
pub const ReferenceOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Provider options for a {@link DocumentHighlightRequest}.
pub const DocumentHighlightOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// A base for all symbol information.
pub const BaseSymbolInformation = struct {
    /// The name of this symbol.
    name: []const u8,
    /// The kind of this symbol.
    kind: SymbolKind,
    /// Tags for this symbol.
    ///
    /// @since 3.16.0
    tags: ?[]const SymbolTag = null,
    /// The name of the symbol containing this symbol. This information is for
    /// user interface purposes (e.g. to render a qualifier in the user interface
    /// if necessary). It can't be used to re-infer a hierarchy for the document
    /// symbols.
    containerName: ?[]const u8 = null,
};

/// Provider options for a {@link DocumentSymbolRequest}.
pub const DocumentSymbolOptions = struct {
    /// A human-readable string that is shown when multiple outlines trees
    /// are shown for the same document.
    ///
    /// @since 3.16.0
    label: ?[]const u8 = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Contains additional diagnostic information about the context in which
/// a {@link CodeActionProvider.provideCodeActions code action} is run.
pub const CodeActionContext = struct {
    /// An array of diagnostics known on the client side overlapping the range provided to the
    /// `textDocument/codeAction` request. They are provided so that the server knows which
    /// errors are currently presented to the user for the given range. There is no guarantee
    /// that these accurately reflect the error state of the resource. The primary parameter
    /// to compute code actions is the provided range.
    diagnostics: []const Diagnostic,
    /// Requested kind of actions to return.
    ///
    /// Actions not of this kind are filtered out by the client before being shown. So servers
    /// can omit computing them.
    only: ?[]const CodeActionKind = null,
    /// The reason why code actions were requested.
    ///
    /// @since 3.17.0
    triggerKind: ?CodeActionTriggerKind = null,
};

/// Captures why the code action is currently disabled.
///
/// @since 3.18.0
/// @proposed
pub const CodeActionDisabled = struct {
    /// Human readable description of why the code action is currently disabled.
    ///
    /// This is displayed in the code actions UI.
    reason: []const u8,
};

/// Provider options for a {@link CodeActionRequest}.
pub const CodeActionOptions = struct {
    /// CodeActionKinds that this server may return.
    ///
    /// The list of kinds may be generic, such as `CodeActionKind.Refactor`, or the server
    /// may list out every specific kind they provide.
    codeActionKinds: ?[]const CodeActionKind = null,
    /// The server provides support to resolve additional
    /// information for a code action.
    ///
    /// @since 3.16.0
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Location with only uri and does not include range.
///
/// @since 3.18.0
/// @proposed
pub const LocationUriOnly = struct {
    uri: DocumentUri,
};

/// Server capabilities for a {@link WorkspaceSymbolRequest}.
pub const WorkspaceSymbolOptions = struct {
    /// The server provides support to resolve additional
    /// information for a workspace symbol.
    ///
    /// @since 3.17.0
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Code Lens provider options of a {@link CodeLensRequest}.
pub const CodeLensOptions = struct {
    /// Code lens has a resolve provider as well.
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Provider options for a {@link DocumentLinkRequest}.
pub const DocumentLinkOptions = struct {
    /// Document links have a resolve provider as well.
    resolveProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Value-object describing what options formatting should use.
pub const FormattingOptions = struct {
    /// Size of a tab in spaces.
    tabSize: u32,
    /// Prefer spaces over tabs.
    insertSpaces: bool,
    /// Trim trailing whitespace on a line.
    ///
    /// @since 3.15.0
    trimTrailingWhitespace: ?bool = null,
    /// Insert a newline character at the end of the file if one does not exist.
    ///
    /// @since 3.15.0
    insertFinalNewline: ?bool = null,
    /// Trim all newlines after the final newline at the end of the file.
    ///
    /// @since 3.15.0
    trimFinalNewlines: ?bool = null,
};

/// Provider options for a {@link DocumentFormattingRequest}.
pub const DocumentFormattingOptions = struct {

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Provider options for a {@link DocumentRangeFormattingRequest}.
pub const DocumentRangeFormattingOptions = struct {
    /// Whether the server supports formatting multiple ranges at once.
    ///
    /// @since 3.18.0
    /// @proposed
    rangesSupport: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// Provider options for a {@link DocumentOnTypeFormattingRequest}.
pub const DocumentOnTypeFormattingOptions = struct {
    /// A character on which formatting should be triggered, like `{`.
    firstTriggerCharacter: []const u8,
    /// More trigger characters.
    moreTriggerCharacter: ?[]const []const u8 = null,
};

/// Provider options for a {@link RenameRequest}.
pub const RenameOptions = struct {
    /// Renames should be checked and tested before being executed.
    ///
    /// @since version 3.12.0
    prepareProvider: ?bool = null,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const PrepareRenamePlaceholder = struct {
    range: Range,
    placeholder: []const u8,
};

/// @since 3.18.0
/// @proposed
pub const PrepareRenameDefaultBehavior = struct {
    defaultBehavior: bool,
};

/// The server capabilities of a {@link ExecuteCommandRequest}.
pub const ExecuteCommandOptions = struct {
    /// The commands to be executed on the server
    commands: []const []const u8,

    // Uses mixin WorkDoneProgressOptions
    workDoneProgress: ?bool = null,
};

/// @since 3.16.0
pub const SemanticTokensLegend = struct {
    /// The token types a server uses.
    tokenTypes: []const []const u8,
    /// The token modifiers a server uses.
    tokenModifiers: []const []const u8,
};

/// Semantic tokens options to support deltas for full documents
///
/// @since 3.18.0
/// @proposed
pub const SemanticTokensFullDelta = struct {
    /// The server supports deltas for full documents.
    delta: ?bool = null,
};

/// A text document identifier to optionally denote a specific version of a text document.
pub const OptionalVersionedTextDocumentIdentifier = struct {
    /// The version number of this document. If a versioned text document identifier
    /// is sent from the server to the client and the file is not open in the editor
    /// (the server has not received an open notification before) the server can send
    /// `null` to indicate that the version is unknown and the content on disk is the
    /// truth (as specified with document content ownership).
    version: ?i32 = null,

    // Extends TextDocumentIdentifier
    /// The text document's uri.
    uri: DocumentUri,
};

/// A special text edit with an additional change annotation.
///
/// @since 3.16.0.
pub const AnnotatedTextEdit = struct {
    /// The actual identifier of the change annotation
    annotationId: ChangeAnnotationIdentifier,

    // Extends TextEdit
    /// The range of the text document to be manipulated. To insert
    /// text into a document create a range where start === end.
    range: Range,
    /// The string to be inserted. For delete operations use an
    /// empty string.
    newText: []const u8,
};

/// A generic resource operation.
pub const ResourceOperation = struct {
    /// The resource operation kind.
    kind: []const u8,
    /// An optional annotation identifier describing the operation.
    ///
    /// @since 3.16.0
    annotationId: ?ChangeAnnotationIdentifier = null,
};

/// Options to create a file.
pub const CreateFileOptions = struct {
    /// Overwrite existing file. Overwrite wins over `ignoreIfExists`
    overwrite: ?bool = null,
    /// Ignore if exists.
    ignoreIfExists: ?bool = null,
};

/// Rename file options
pub const RenameFileOptions = struct {
    /// Overwrite target if existing. Overwrite wins over `ignoreIfExists`
    overwrite: ?bool = null,
    /// Ignores if target exists.
    ignoreIfExists: ?bool = null,
};

/// Delete file options
pub const DeleteFileOptions = struct {
    /// Delete the content recursively if a folder is denoted.
    recursive: ?bool = null,
    /// Ignore the operation if the file doesn't exist.
    ignoreIfNotExists: ?bool = null,
};

/// A pattern to describe in which file operation requests or notifications
/// the server is interested in receiving.
///
/// @since 3.16.0
pub const FileOperationPattern = struct {
    /// The glob pattern to match. Glob patterns can have the following syntax:
    /// - `*` to match one or more characters in a path segment
    /// - `?` to match on one character in a path segment
    /// - `**` to match any number of path segments, including none
    /// - `{}` to group sub patterns into an OR expression. (e.g. `**​/*.{ts,js}` matches all TypeScript and JavaScript files)
    /// - `[]` to declare a range of characters to match in a path segment (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
    /// - `[!...]` to negate a range of characters to match in a path segment (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but not `example.0`)
    glob: []const u8,
    /// Whether to match files or folders with this pattern.
    ///
    /// Matches both if undefined.
    matches: ?FileOperationPatternKind = null,
    /// Additional options used during matching.
    options: ?FileOperationPatternOptions = null,
};

/// A full document diagnostic report for a workspace diagnostic result.
///
/// @since 3.17.0
pub const WorkspaceFullDocumentDiagnosticReport = struct {
    /// The URI for which diagnostic information is reported.
    uri: DocumentUri,
    /// The version number for which the diagnostics are reported.
    /// If the document is not marked as open `null` can be provided.
    version: ?i32 = null,

    // Extends FullDocumentDiagnosticReport
    /// A full document diagnostic report.
    kind: []const u8 = "full",
    /// An optional result id. If provided it will
    /// be sent on the next diagnostic request for the
    /// same document.
    resultId: ?[]const u8 = null,
    /// The actual items.
    items: []const Diagnostic,
};

/// An unchanged document diagnostic report for a workspace diagnostic result.
///
/// @since 3.17.0
pub const WorkspaceUnchangedDocumentDiagnosticReport = struct {
    /// The URI for which diagnostic information is reported.
    uri: DocumentUri,
    /// The version number for which the diagnostics are reported.
    /// If the document is not marked as open `null` can be provided.
    version: ?i32 = null,

    // Extends UnchangedDocumentDiagnosticReport
    /// A document diagnostic report indicating
    /// no changes to the last result. A server can
    /// only return `unchanged` if result ids are
    /// provided.
    kind: []const u8 = "unchanged",
    /// A result id which will be sent on the next
    /// diagnostic request for the same document.
    resultId: []const u8,
};

/// A notebook cell.
///
/// A cell's document URI must be unique across ALL notebook
/// cells and can therefore be used to uniquely identify a
/// notebook cell or the cell's text document.
///
/// @since 3.17.0
pub const NotebookCell = struct {
    /// The cell's kind
    kind: NotebookCellKind,
    /// The URI of the cell's text document
    /// content.
    document: DocumentUri,
    /// Additional metadata stored with the cell.
    ///
    /// Note: should always be an object literal (e.g. LSPObject)
    metadata: ?LSPObject = null,
    /// Additional execution summary information
    /// if supported by the client.
    executionSummary: ?ExecutionSummary = null,
};

/// Cell changes to a notebook document.
///
/// @since 3.18.0
/// @proposed
pub const NotebookDocumentCellChanges = struct {
    /// Changes to the cell structure to add or
    /// remove cells.
    structure: ?NotebookDocumentCellChangeStructure = null,
    /// Changes to notebook cells properties like its
    /// kind, execution summary or metadata.
    data: ?[]const NotebookCell = null,
    /// Changes to the text content of notebook cells.
    textContent: ?[]const NotebookDocumentCellContentChanges = null,
};

/// Describes the currently selected completion item.
///
/// @since 3.18.0
/// @proposed
pub const SelectedCompletionInfo = struct {
    /// The range that will be replaced if this completion item is accepted.
    range: Range,
    /// The text the range will be replaced with if this completion is accepted.
    text: []const u8,
};

/// Information about the client
///
/// @since 3.15.0
/// @since 3.18.0 ClientInfo type name added.
/// @proposed
pub const ClientInfo = struct {
    /// The name of the client as defined by the client.
    name: []const u8,
    /// The client's version as defined by the client.
    version: ?[]const u8 = null,
};

/// Defines the capabilities provided by the client.
pub const ClientCapabilities = struct {
    /// Workspace specific client capabilities.
    workspace: ?WorkspaceClientCapabilities = null,
    /// Text document specific client capabilities.
    textDocument: ?TextDocumentClientCapabilities = null,
    /// Capabilities specific to the notebook document support.
    ///
    /// @since 3.17.0
    notebookDocument: ?NotebookDocumentClientCapabilities = null,
    /// Window specific client capabilities.
    window: ?WindowClientCapabilities = null,
    /// General client capabilities.
    ///
    /// @since 3.16.0
    general: ?GeneralClientCapabilities = null,
    /// Experimental client capabilities.
    experimental: ?LSPAny = null,
};

pub const TextDocumentSyncOptions = struct {
    /// Open and close notifications are sent to the server. If omitted open close notification should not
    /// be sent.
    openClose: ?bool = null,
    /// Change notifications are sent to the server. See TextDocumentSyncKind.None, TextDocumentSyncKind.Full
    /// and TextDocumentSyncKind.Incremental. If omitted it defaults to TextDocumentSyncKind.None.
    change: ?TextDocumentSyncKind = null,
    /// If present will save notifications are sent to the server. If omitted the notification should not be
    /// sent.
    willSave: ?bool = null,
    /// If present will save wait until requests are sent to the server. If omitted the request should not be
    /// sent.
    willSaveWaitUntil: ?bool = null,
    /// If present save notifications are sent to the server. If omitted the notification should not be
    /// sent.
    save: ?union(enum) {
        bool: bool,
        SaveOptions: SaveOptions,
        pub usingnamespace UnionParser(@This());
    } = null,
};

/// Options specific to a notebook plus its cells
/// to be synced to the server.
///
/// If a selector provides a notebook document
/// filter but no cell selector all cells of a
/// matching notebook document will be synced.
///
/// If a selector provides no notebook document
/// filter but only a cell selector all notebook
/// document that contain at least one matching
/// cell will be synced.
///
/// @since 3.17.0
pub const NotebookDocumentSyncOptions = struct {
    /// The notebooks to be synced
    notebookSelector: []const union(enum) {
        NotebookDocumentFilterWithNotebook: NotebookDocumentFilterWithNotebook,
        NotebookDocumentFilterWithCells: NotebookDocumentFilterWithCells,
        pub usingnamespace UnionParser(@This());
    },
    /// Whether save notification should be forwarded to
    /// the server. Will only be honored if mode === `notebook`.
    save: ?bool = null,
};

/// Registration options specific to a notebook.
///
/// @since 3.17.0
pub const NotebookDocumentSyncRegistrationOptions = struct {

    // Extends NotebookDocumentSyncOptions
    /// The notebooks to be synced
    notebookSelector: []const union(enum) {
        NotebookDocumentFilterWithNotebook: NotebookDocumentFilterWithNotebook,
        NotebookDocumentFilterWithCells: NotebookDocumentFilterWithCells,
        pub usingnamespace UnionParser(@This());
    },
    /// Whether save notification should be forwarded to
    /// the server. Will only be honored if mode === `notebook`.
    save: ?bool = null,

    // Uses mixin StaticRegistrationOptions
    /// The id used to register the request. The id can be used to deregister
    /// the request again. See also Registration#id.
    id: ?[]const u8 = null,
};

/// Defines workspace specific capabilities of the server.
///
/// @since 3.18.0
/// @proposed
pub const WorkspaceOptions = struct {
    /// The server supports workspace folder.
    ///
    /// @since 3.6.0
    workspaceFolders: ?WorkspaceFoldersServerCapabilities = null,
    /// The server is interested in notifications/requests for operations on files.
    ///
    /// @since 3.16.0
    fileOperations: ?FileOperationOptions = null,
};

/// @since 3.18.0
/// @proposed
pub const TextDocumentContentChangePartial = struct {
    /// The range of the document that changed.
    range: Range,
    /// The optional length of the range that got replaced.
    ///
    /// @deprecated use range instead.
    rangeLength: ?u32 = null,
    /// The new text for the provided range.
    text: []const u8,
};

/// @since 3.18.0
/// @proposed
pub const TextDocumentContentChangeWholeDocument = struct {
    /// The new text of the whole document.
    text: []const u8,
};

/// Structure to capture a description for an error code.
///
/// @since 3.16.0
pub const CodeDescription = struct {
    /// An URI to open with more information about the diagnostic error.
    href: URI,
};

/// Represents a related message and source code location for a diagnostic. This should be
/// used to point to code locations that cause or related to a diagnostics, e.g when duplicating
/// a symbol in a scope.
pub const DiagnosticRelatedInformation = struct {
    /// The location of this related diagnostic information.
    location: Location,
    /// The message of this related diagnostic information.
    message: []const u8,
};

/// Edit range variant that includes ranges for insert and replace operations.
///
/// @since 3.18.0
/// @proposed
pub const EditRangeWithInsertReplace = struct {
    insert: Range,
    replace: Range,
};

/// @since 3.18.0
/// @proposed
pub const ServerCompletionItemOptions = struct {
    /// The server has support for completion item label
    /// details (see also `CompletionItemLabelDetails`) when
    /// receiving a completion item in a resolve call.
    ///
    /// @since 3.17.0
    labelDetailsSupport: ?bool = null,
};

/// @since 3.18.0
/// @proposed
/// @deprecated use MarkupContent instead.
pub const MarkedStringWithLanguage = struct {
    language: []const u8,
    value: []const u8,
};

/// Represents a parameter of a callable-signature. A parameter can
/// have a label and a doc-comment.
pub const ParameterInformation = struct {
    /// The label of this parameter information.
    ///
    /// Either a string or an inclusive start and exclusive end offsets within its containing
    /// signature label. (see SignatureInformation.label). The offsets are based on a UTF-16
    /// string representation as `Position` and `Range` does.
    ///
    /// *Note*: a label of type string should be a substring of its containing signature label.
    /// Its intended use case is to highlight the parameter label part in the `SignatureInformation.label`.
    label: union(enum) {
        string: []const u8,
        tuple_1: struct { u32, u32 },
        pub usingnamespace UnionParser(@This());
    },
    /// The human-readable doc-comment of this parameter. Will be shown
    /// in the UI but can be omitted.
    documentation: ?union(enum) {
        string: []const u8,
        MarkupContent: MarkupContent,
        pub usingnamespace UnionParser(@This());
    } = null,
};

/// A notebook cell text document filter denotes a cell text
/// document by different properties.
///
/// @since 3.17.0
pub const NotebookCellTextDocumentFilter = struct {
    /// A filter that matches against the notebook
    /// containing the notebook cell. If a string
    /// value is provided it matches against the
    /// notebook type. '*' matches every notebook.
    notebook: union(enum) {
        string: []const u8,
        NotebookDocumentFilter: NotebookDocumentFilter,
        pub usingnamespace UnionParser(@This());
    },
    /// A language id like `python`.
    ///
    /// Will be matched against the language id of the
    /// notebook cell document. '*' matches every language.
    language: ?[]const u8 = null,
};

/// Matching options for the file operation pattern.
///
/// @since 3.16.0
pub const FileOperationPatternOptions = struct {
    /// The pattern should be matched ignoring casing.
    ignoreCase: ?bool = null,
};

pub const ExecutionSummary = struct {
    /// A strict monotonically increasing value
    /// indicating the execution order of a cell
    /// inside a notebook.
    executionOrder: u32,
    /// Whether the execution was successful or
    /// not if known by the client.
    success: ?bool = null,
};

/// Structural changes to cells in a notebook document.
///
/// @since 3.18.0
/// @proposed
pub const NotebookDocumentCellChangeStructure = struct {
    /// The change to the cell array.
    array: NotebookCellArrayChange,
    /// Additional opened cell text documents.
    didOpen: ?[]const TextDocumentItem = null,
    /// Additional closed cell text documents.
    didClose: ?[]const TextDocumentIdentifier = null,
};

/// Content changes to a cell in a notebook document.
///
/// @since 3.18.0
/// @proposed
pub const NotebookDocumentCellContentChanges = struct {
    document: VersionedTextDocumentIdentifier,
    changes: []const TextDocumentContentChangeEvent,
};

/// Workspace specific client capabilities.
pub const WorkspaceClientCapabilities = struct {
    /// The client supports applying batch edits
    /// to the workspace by supporting the request
    /// 'workspace/applyEdit'
    applyEdit: ?bool = null,
    /// Capabilities specific to `WorkspaceEdit`s.
    workspaceEdit: ?WorkspaceEditClientCapabilities = null,
    /// Capabilities specific to the `workspace/didChangeConfiguration` notification.
    didChangeConfiguration: ?DidChangeConfigurationClientCapabilities = null,
    /// Capabilities specific to the `workspace/didChangeWatchedFiles` notification.
    didChangeWatchedFiles: ?DidChangeWatchedFilesClientCapabilities = null,
    /// Capabilities specific to the `workspace/symbol` request.
    symbol: ?WorkspaceSymbolClientCapabilities = null,
    /// Capabilities specific to the `workspace/executeCommand` request.
    executeCommand: ?ExecuteCommandClientCapabilities = null,
    /// The client has support for workspace folders.
    ///
    /// @since 3.6.0
    workspaceFolders: ?bool = null,
    /// The client supports `workspace/configuration` requests.
    ///
    /// @since 3.6.0
    configuration: ?bool = null,
    /// Capabilities specific to the semantic token requests scoped to the
    /// workspace.
    ///
    /// @since 3.16.0.
    semanticTokens: ?SemanticTokensWorkspaceClientCapabilities = null,
    /// Capabilities specific to the code lens requests scoped to the
    /// workspace.
    ///
    /// @since 3.16.0.
    codeLens: ?CodeLensWorkspaceClientCapabilities = null,
    /// The client has support for file notifications/requests for user operations on files.
    ///
    /// Since 3.16.0
    fileOperations: ?FileOperationClientCapabilities = null,
    /// Capabilities specific to the inline values requests scoped to the
    /// workspace.
    ///
    /// @since 3.17.0.
    inlineValue: ?InlineValueWorkspaceClientCapabilities = null,
    /// Capabilities specific to the inlay hint requests scoped to the
    /// workspace.
    ///
    /// @since 3.17.0.
    inlayHint: ?InlayHintWorkspaceClientCapabilities = null,
    /// Capabilities specific to the diagnostic requests scoped to the
    /// workspace.
    ///
    /// @since 3.17.0.
    diagnostics: ?DiagnosticWorkspaceClientCapabilities = null,
    /// Capabilities specific to the folding range requests scoped to the workspace.
    ///
    /// @since 3.18.0
    /// @proposed
    foldingRange: ?FoldingRangeWorkspaceClientCapabilities = null,
};

/// Text document specific client capabilities.
pub const TextDocumentClientCapabilities = struct {
    /// Defines which synchronization capabilities the client supports.
    synchronization: ?TextDocumentSyncClientCapabilities = null,
    /// Capabilities specific to the `textDocument/completion` request.
    completion: ?CompletionClientCapabilities = null,
    /// Capabilities specific to the `textDocument/hover` request.
    hover: ?HoverClientCapabilities = null,
    /// Capabilities specific to the `textDocument/signatureHelp` request.
    signatureHelp: ?SignatureHelpClientCapabilities = null,
    /// Capabilities specific to the `textDocument/declaration` request.
    ///
    /// @since 3.14.0
    declaration: ?DeclarationClientCapabilities = null,
    /// Capabilities specific to the `textDocument/definition` request.
    definition: ?DefinitionClientCapabilities = null,
    /// Capabilities specific to the `textDocument/typeDefinition` request.
    ///
    /// @since 3.6.0
    typeDefinition: ?TypeDefinitionClientCapabilities = null,
    /// Capabilities specific to the `textDocument/implementation` request.
    ///
    /// @since 3.6.0
    implementation: ?ImplementationClientCapabilities = null,
    /// Capabilities specific to the `textDocument/references` request.
    references: ?ReferenceClientCapabilities = null,
    /// Capabilities specific to the `textDocument/documentHighlight` request.
    documentHighlight: ?DocumentHighlightClientCapabilities = null,
    /// Capabilities specific to the `textDocument/documentSymbol` request.
    documentSymbol: ?DocumentSymbolClientCapabilities = null,
    /// Capabilities specific to the `textDocument/codeAction` request.
    codeAction: ?CodeActionClientCapabilities = null,
    /// Capabilities specific to the `textDocument/codeLens` request.
    codeLens: ?CodeLensClientCapabilities = null,
    /// Capabilities specific to the `textDocument/documentLink` request.
    documentLink: ?DocumentLinkClientCapabilities = null,
    /// Capabilities specific to the `textDocument/documentColor` and the
    /// `textDocument/colorPresentation` request.
    ///
    /// @since 3.6.0
    colorProvider: ?DocumentColorClientCapabilities = null,
    /// Capabilities specific to the `textDocument/formatting` request.
    formatting: ?DocumentFormattingClientCapabilities = null,
    /// Capabilities specific to the `textDocument/rangeFormatting` request.
    rangeFormatting: ?DocumentRangeFormattingClientCapabilities = null,
    /// Capabilities specific to the `textDocument/onTypeFormatting` request.
    onTypeFormatting: ?DocumentOnTypeFormattingClientCapabilities = null,
    /// Capabilities specific to the `textDocument/rename` request.
    rename: ?RenameClientCapabilities = null,
    /// Capabilities specific to the `textDocument/foldingRange` request.
    ///
    /// @since 3.10.0
    foldingRange: ?FoldingRangeClientCapabilities = null,
    /// Capabilities specific to the `textDocument/selectionRange` request.
    ///
    /// @since 3.15.0
    selectionRange: ?SelectionRangeClientCapabilities = null,
    /// Capabilities specific to the `textDocument/publishDiagnostics` notification.
    publishDiagnostics: ?PublishDiagnosticsClientCapabilities = null,
    /// Capabilities specific to the various call hierarchy requests.
    ///
    /// @since 3.16.0
    callHierarchy: ?CallHierarchyClientCapabilities = null,
    /// Capabilities specific to the various semantic token request.
    ///
    /// @since 3.16.0
    semanticTokens: ?SemanticTokensClientCapabilities = null,
    /// Capabilities specific to the `textDocument/linkedEditingRange` request.
    ///
    /// @since 3.16.0
    linkedEditingRange: ?LinkedEditingRangeClientCapabilities = null,
    /// Client capabilities specific to the `textDocument/moniker` request.
    ///
    /// @since 3.16.0
    moniker: ?MonikerClientCapabilities = null,
    /// Capabilities specific to the various type hierarchy requests.
    ///
    /// @since 3.17.0
    typeHierarchy: ?TypeHierarchyClientCapabilities = null,
    /// Capabilities specific to the `textDocument/inlineValue` request.
    ///
    /// @since 3.17.0
    inlineValue: ?InlineValueClientCapabilities = null,
    /// Capabilities specific to the `textDocument/inlayHint` request.
    ///
    /// @since 3.17.0
    inlayHint: ?InlayHintClientCapabilities = null,
    /// Capabilities specific to the diagnostic pull model.
    ///
    /// @since 3.17.0
    diagnostic: ?DiagnosticClientCapabilities = null,
    /// Client capabilities specific to inline completions.
    ///
    /// @since 3.18.0
    /// @proposed
    inlineCompletion: ?InlineCompletionClientCapabilities = null,
};

/// Capabilities specific to the notebook document support.
///
/// @since 3.17.0
pub const NotebookDocumentClientCapabilities = struct {
    /// Capabilities specific to notebook document synchronization
    ///
    /// @since 3.17.0
    synchronization: NotebookDocumentSyncClientCapabilities,
};

pub const WindowClientCapabilities = struct {
    /// It indicates whether the client supports server initiated
    /// progress using the `window/workDoneProgress/create` request.
    ///
    /// The capability also controls Whether client supports handling
    /// of progress notifications. If set servers are allowed to report a
    /// `workDoneProgress` property in the request specific server
    /// capabilities.
    ///
    /// @since 3.15.0
    workDoneProgress: ?bool = null,
    /// Capabilities specific to the showMessage request.
    ///
    /// @since 3.16.0
    showMessage: ?ShowMessageRequestClientCapabilities = null,
    /// Capabilities specific to the showDocument request.
    ///
    /// @since 3.16.0
    showDocument: ?ShowDocumentClientCapabilities = null,
};

/// General client capabilities.
///
/// @since 3.16.0
pub const GeneralClientCapabilities = struct {
    /// Client capability that signals how the client
    /// handles stale requests (e.g. a request
    /// for which the client will not process the response
    /// anymore since the information is outdated).
    ///
    /// @since 3.17.0
    staleRequestSupport: ?StaleRequestSupportOptions = null,
    /// Client capabilities specific to regular expressions.
    ///
    /// @since 3.16.0
    regularExpressions: ?RegularExpressionsClientCapabilities = null,
    /// Client capabilities specific to the client's markdown parser.
    ///
    /// @since 3.16.0
    markdown: ?MarkdownClientCapabilities = null,
    /// The position encodings supported by the client. Client and server
    /// have to agree on the same position encoding to ensure that offsets
    /// (e.g. character position in a line) are interpreted the same on both
    /// sides.
    ///
    /// To keep the protocol backwards compatible the following applies: if
    /// the value 'utf-16' is missing from the array of position encodings
    /// servers can assume that the client supports UTF-16. UTF-16 is
    /// therefore a mandatory encoding.
    ///
    /// If omitted it defaults to ['utf-16'].
    ///
    /// Implementation considerations: since the conversion from one encoding
    /// into another requires the content of the file / line the conversion
    /// is best done where the file is read which is usually on the server
    /// side.
    ///
    /// @since 3.17.0
    positionEncodings: ?[]const PositionEncodingKind = null,
};

/// @since 3.18.0
/// @proposed
pub const NotebookDocumentFilterWithNotebook = struct {
    /// The notebook to be synced If a string
    /// value is provided it matches against the
    /// notebook type. '*' matches every notebook.
    notebook: union(enum) {
        string: []const u8,
        NotebookDocumentFilter: NotebookDocumentFilter,
        pub usingnamespace UnionParser(@This());
    },
    /// The cells of the matching notebook to be synced.
    cells: ?[]const NotebookCellLanguage = null,
};

/// @since 3.18.0
/// @proposed
pub const NotebookDocumentFilterWithCells = struct {
    /// The notebook to be synced If a string
    /// value is provided it matches against the
    /// notebook type. '*' matches every notebook.
    notebook: ?union(enum) {
        string: []const u8,
        NotebookDocumentFilter: NotebookDocumentFilter,
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The cells of the matching notebook to be synced.
    cells: []const NotebookCellLanguage,
};

pub const WorkspaceFoldersServerCapabilities = struct {
    /// The server has support for workspace folders
    supported: ?bool = null,
    /// Whether the server wants to receive workspace folder
    /// change notifications.
    ///
    /// If a string is provided the string is treated as an ID
    /// under which the notification is registered on the client
    /// side. The ID can be used to unregister for these events
    /// using the `client/unregisterCapability` request.
    changeNotifications: ?union(enum) {
        string: []const u8,
        bool: bool,
        pub usingnamespace UnionParser(@This());
    } = null,
};

/// Options for notifications/requests for user operations on files.
///
/// @since 3.16.0
pub const FileOperationOptions = struct {
    /// The server is interested in receiving didCreateFiles notifications.
    didCreate: ?FileOperationRegistrationOptions = null,
    /// The server is interested in receiving willCreateFiles requests.
    willCreate: ?FileOperationRegistrationOptions = null,
    /// The server is interested in receiving didRenameFiles notifications.
    didRename: ?FileOperationRegistrationOptions = null,
    /// The server is interested in receiving willRenameFiles requests.
    willRename: ?FileOperationRegistrationOptions = null,
    /// The server is interested in receiving didDeleteFiles file notifications.
    didDelete: ?FileOperationRegistrationOptions = null,
    /// The server is interested in receiving willDeleteFiles file requests.
    willDelete: ?FileOperationRegistrationOptions = null,
};

/// A relative pattern is a helper to construct glob patterns that are matched
/// relatively to a base URI. The common value for a `baseUri` is a workspace
/// folder root, but it can be another absolute URI as well.
///
/// @since 3.17.0
pub const RelativePattern = struct {
    /// A workspace folder or a base URI to which this pattern will be matched
    /// against relatively.
    baseUri: union(enum) {
        WorkspaceFolder: WorkspaceFolder,
        uri: URI,
        pub usingnamespace UnionParser(@This());
    },
    /// The actual glob pattern;
    pattern: Pattern,
};

/// A document filter where `language` is required field.
///
/// @since 3.18.0
/// @proposed
pub const TextDocumentFilterLanguage = struct {
    /// A language id, like `typescript`.
    language: []const u8,
    /// A Uri {@link Uri.scheme scheme}, like `file` or `untitled`.
    scheme: ?[]const u8 = null,
    /// A glob pattern, like **​/*.{ts,js}. See TextDocumentFilter for examples.
    pattern: ?[]const u8 = null,
};

/// A document filter where `scheme` is required field.
///
/// @since 3.18.0
/// @proposed
pub const TextDocumentFilterScheme = struct {
    /// A language id, like `typescript`.
    language: ?[]const u8 = null,
    /// A Uri {@link Uri.scheme scheme}, like `file` or `untitled`.
    scheme: []const u8,
    /// A glob pattern, like **​/*.{ts,js}. See TextDocumentFilter for examples.
    pattern: ?[]const u8 = null,
};

/// A document filter where `pattern` is required field.
///
/// @since 3.18.0
/// @proposed
pub const TextDocumentFilterPattern = struct {
    /// A language id, like `typescript`.
    language: ?[]const u8 = null,
    /// A Uri {@link Uri.scheme scheme}, like `file` or `untitled`.
    scheme: ?[]const u8 = null,
    /// A glob pattern, like **​/*.{ts,js}. See TextDocumentFilter for examples.
    pattern: []const u8,
};

/// A change describing how to move a `NotebookCell`
/// array from state S to S'.
///
/// @since 3.17.0
pub const NotebookCellArrayChange = struct {
    /// The start oftest of the cell that changed.
    start: u32,
    /// The deleted cells
    deleteCount: u32,
    /// The new cells, if any
    cells: ?[]const NotebookCell = null,
};

pub const WorkspaceEditClientCapabilities = struct {
    /// The client supports versioned document changes in `WorkspaceEdit`s
    documentChanges: ?bool = null,
    /// The resource operations the client supports. Clients should at least
    /// support 'create', 'rename' and 'delete' files and folders.
    ///
    /// @since 3.13.0
    resourceOperations: ?[]const ResourceOperationKind = null,
    /// The failure handling strategy of a client if applying the workspace edit
    /// fails.
    ///
    /// @since 3.13.0
    failureHandling: ?FailureHandlingKind = null,
    /// Whether the client normalizes line endings to the client specific
    /// setting.
    /// If set to `true` the client will normalize line ending characters
    /// in a workspace edit to the client-specified new line
    /// character.
    ///
    /// @since 3.16.0
    normalizesLineEndings: ?bool = null,
    /// Whether the client in general supports change annotations on text edits,
    /// create file, rename file and delete file changes.
    ///
    /// @since 3.16.0
    changeAnnotationSupport: ?ChangeAnnotationsSupportOptions = null,
};

pub const DidChangeConfigurationClientCapabilities = struct {
    /// Did change configuration notification supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

pub const DidChangeWatchedFilesClientCapabilities = struct {
    /// Did change watched files notification supports dynamic registration. Please note
    /// that the current protocol doesn't support static configuration for file changes
    /// from the server side.
    dynamicRegistration: ?bool = null,
    /// Whether the client has support for {@link  RelativePattern relative pattern}
    /// or not.
    ///
    /// @since 3.17.0
    relativePatternSupport: ?bool = null,
};

/// Client capabilities for a {@link WorkspaceSymbolRequest}.
pub const WorkspaceSymbolClientCapabilities = struct {
    /// Symbol request supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Specific capabilities for the `SymbolKind` in the `workspace/symbol` request.
    symbolKind: ?ClientSymbolKindOptions = null,
    /// The client supports tags on `SymbolInformation`.
    /// Clients supporting tags have to handle unknown tags gracefully.
    ///
    /// @since 3.16.0
    tagSupport: ?ClientSymbolTagOptions = null,
    /// The client support partial workspace symbols. The client will send the
    /// request `workspaceSymbol/resolve` to the server to resolve additional
    /// properties.
    ///
    /// @since 3.17.0
    resolveSupport: ?ClientSymbolResolveOptions = null,
};

/// The client capabilities of a {@link ExecuteCommandRequest}.
pub const ExecuteCommandClientCapabilities = struct {
    /// Execute command supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

/// @since 3.16.0
pub const SemanticTokensWorkspaceClientCapabilities = struct {
    /// Whether the client implementation supports a refresh request sent from
    /// the server to the client.
    ///
    /// Note that this event is global and will force the client to refresh all
    /// semantic tokens currently shown. It should be used with absolute care
    /// and is useful for situation where a server for example detects a project
    /// wide change that requires such a calculation.
    refreshSupport: ?bool = null,
};

/// @since 3.16.0
pub const CodeLensWorkspaceClientCapabilities = struct {
    /// Whether the client implementation supports a refresh request sent from the
    /// server to the client.
    ///
    /// Note that this event is global and will force the client to refresh all
    /// code lenses currently shown. It should be used with absolute care and is
    /// useful for situation where a server for example detect a project wide
    /// change that requires such a calculation.
    refreshSupport: ?bool = null,
};

/// Capabilities relating to events from file operations by the user in the client.
///
/// These events do not come from the file system, they come from user operations
/// like renaming a file in the UI.
///
/// @since 3.16.0
pub const FileOperationClientCapabilities = struct {
    /// Whether the client supports dynamic registration for file requests/notifications.
    dynamicRegistration: ?bool = null,
    /// The client has support for sending didCreateFiles notifications.
    didCreate: ?bool = null,
    /// The client has support for sending willCreateFiles requests.
    willCreate: ?bool = null,
    /// The client has support for sending didRenameFiles notifications.
    didRename: ?bool = null,
    /// The client has support for sending willRenameFiles requests.
    willRename: ?bool = null,
    /// The client has support for sending didDeleteFiles notifications.
    didDelete: ?bool = null,
    /// The client has support for sending willDeleteFiles requests.
    willDelete: ?bool = null,
};

/// Client workspace capabilities specific to inline values.
///
/// @since 3.17.0
pub const InlineValueWorkspaceClientCapabilities = struct {
    /// Whether the client implementation supports a refresh request sent from the
    /// server to the client.
    ///
    /// Note that this event is global and will force the client to refresh all
    /// inline values currently shown. It should be used with absolute care and is
    /// useful for situation where a server for example detects a project wide
    /// change that requires such a calculation.
    refreshSupport: ?bool = null,
};

/// Client workspace capabilities specific to inlay hints.
///
/// @since 3.17.0
pub const InlayHintWorkspaceClientCapabilities = struct {
    /// Whether the client implementation supports a refresh request sent from
    /// the server to the client.
    ///
    /// Note that this event is global and will force the client to refresh all
    /// inlay hints currently shown. It should be used with absolute care and
    /// is useful for situation where a server for example detects a project wide
    /// change that requires such a calculation.
    refreshSupport: ?bool = null,
};

/// Workspace client capabilities specific to diagnostic pull requests.
///
/// @since 3.17.0
pub const DiagnosticWorkspaceClientCapabilities = struct {
    /// Whether the client implementation supports a refresh request sent from
    /// the server to the client.
    ///
    /// Note that this event is global and will force the client to refresh all
    /// pulled diagnostics currently shown. It should be used with absolute care and
    /// is useful for situation where a server for example detects a project wide
    /// change that requires such a calculation.
    refreshSupport: ?bool = null,
};

/// Client workspace capabilities specific to folding ranges
///
/// @since 3.18.0
/// @proposed
pub const FoldingRangeWorkspaceClientCapabilities = struct {
    /// Whether the client implementation supports a refresh request sent from the
    /// server to the client.
    ///
    /// Note that this event is global and will force the client to refresh all
    /// folding ranges currently shown. It should be used with absolute care and is
    /// useful for situation where a server for example detects a project wide
    /// change that requires such a calculation.
    ///
    /// @since 3.18.0
    /// @proposed
    refreshSupport: ?bool = null,
};

pub const TextDocumentSyncClientCapabilities = struct {
    /// Whether text document synchronization supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// The client supports sending will save notifications.
    willSave: ?bool = null,
    /// The client supports sending a will save request and
    /// waits for a response providing text edits which will
    /// be applied to the document before it is saved.
    willSaveWaitUntil: ?bool = null,
    /// The client supports did save notifications.
    didSave: ?bool = null,
};

/// Completion client capabilities
pub const CompletionClientCapabilities = struct {
    /// Whether completion supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// The client supports the following `CompletionItem` specific
    /// capabilities.
    completionItem: ?ClientCompletionItemOptions = null,
    completionItemKind: ?ClientCompletionItemOptionsKind = null,
    /// Defines how the client handles whitespace and indentation
    /// when accepting a completion item that uses multi line
    /// text in either `insertText` or `textEdit`.
    ///
    /// @since 3.17.0
    insertTextMode: ?InsertTextMode = null,
    /// The client supports to send additional context information for a
    /// `textDocument/completion` request.
    contextSupport: ?bool = null,
    /// The client supports the following `CompletionList` specific
    /// capabilities.
    ///
    /// @since 3.17.0
    completionList: ?CompletionListCapabilities = null,
};

pub const HoverClientCapabilities = struct {
    /// Whether hover supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Client supports the following content formats for the content
    /// property. The order describes the preferred format of the client.
    contentFormat: ?[]const MarkupKind = null,
};

/// Client Capabilities for a {@link SignatureHelpRequest}.
pub const SignatureHelpClientCapabilities = struct {
    /// Whether signature help supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// The client supports the following `SignatureInformation`
    /// specific properties.
    signatureInformation: ?ClientSignatureInformationOptions = null,
    /// The client supports to send additional context information for a
    /// `textDocument/signatureHelp` request. A client that opts into
    /// contextSupport will also support the `retriggerCharacters` on
    /// `SignatureHelpOptions`.
    ///
    /// @since 3.15.0
    contextSupport: ?bool = null,
};

/// @since 3.14.0
pub const DeclarationClientCapabilities = struct {
    /// Whether declaration supports dynamic registration. If this is set to `true`
    /// the client supports the new `DeclarationRegistrationOptions` return value
    /// for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
    /// The client supports additional metadata in the form of declaration links.
    linkSupport: ?bool = null,
};

/// Client Capabilities for a {@link DefinitionRequest}.
pub const DefinitionClientCapabilities = struct {
    /// Whether definition supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// The client supports additional metadata in the form of definition links.
    ///
    /// @since 3.14.0
    linkSupport: ?bool = null,
};

/// Since 3.6.0
pub const TypeDefinitionClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `TypeDefinitionRegistrationOptions` return value
    /// for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
    /// The client supports additional metadata in the form of definition links.
    ///
    /// Since 3.14.0
    linkSupport: ?bool = null,
};

/// @since 3.6.0
pub const ImplementationClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `ImplementationRegistrationOptions` return value
    /// for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
    /// The client supports additional metadata in the form of definition links.
    ///
    /// @since 3.14.0
    linkSupport: ?bool = null,
};

/// Client Capabilities for a {@link ReferencesRequest}.
pub const ReferenceClientCapabilities = struct {
    /// Whether references supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

/// Client Capabilities for a {@link DocumentHighlightRequest}.
pub const DocumentHighlightClientCapabilities = struct {
    /// Whether document highlight supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

/// Client Capabilities for a {@link DocumentSymbolRequest}.
pub const DocumentSymbolClientCapabilities = struct {
    /// Whether document symbol supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Specific capabilities for the `SymbolKind` in the
    /// `textDocument/documentSymbol` request.
    symbolKind: ?ClientSymbolKindOptions = null,
    /// The client supports hierarchical document symbols.
    hierarchicalDocumentSymbolSupport: ?bool = null,
    /// The client supports tags on `SymbolInformation`. Tags are supported on
    /// `DocumentSymbol` if `hierarchicalDocumentSymbolSupport` is set to true.
    /// Clients supporting tags have to handle unknown tags gracefully.
    ///
    /// @since 3.16.0
    tagSupport: ?ClientSymbolTagOptions = null,
    /// The client supports an additional label presented in the UI when
    /// registering a document symbol provider.
    ///
    /// @since 3.16.0
    labelSupport: ?bool = null,
};

/// The Client Capabilities of a {@link CodeActionRequest}.
pub const CodeActionClientCapabilities = struct {
    /// Whether code action supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// The client support code action literals of type `CodeAction` as a valid
    /// response of the `textDocument/codeAction` request. If the property is not
    /// set the request can only return `Command` literals.
    ///
    /// @since 3.8.0
    codeActionLiteralSupport: ?ClientCodeActionLiteralOptions = null,
    /// Whether code action supports the `isPreferred` property.
    ///
    /// @since 3.15.0
    isPreferredSupport: ?bool = null,
    /// Whether code action supports the `disabled` property.
    ///
    /// @since 3.16.0
    disabledSupport: ?bool = null,
    /// Whether code action supports the `data` property which is
    /// preserved between a `textDocument/codeAction` and a
    /// `codeAction/resolve` request.
    ///
    /// @since 3.16.0
    dataSupport: ?bool = null,
    /// Whether the client supports resolving additional code action
    /// properties via a separate `codeAction/resolve` request.
    ///
    /// @since 3.16.0
    resolveSupport: ?ClientCodeActionResolveOptions = null,
    /// Whether the client honors the change annotations in
    /// text edits and resource operations returned via the
    /// `CodeAction#edit` property by for example presenting
    /// the workspace edit in the user interface and asking
    /// for confirmation.
    ///
    /// @since 3.16.0
    honorsChangeAnnotations: ?bool = null,
};

/// The client capabilities  of a {@link CodeLensRequest}.
pub const CodeLensClientCapabilities = struct {
    /// Whether code lens supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

/// The client capabilities of a {@link DocumentLinkRequest}.
pub const DocumentLinkClientCapabilities = struct {
    /// Whether document link supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Whether the client supports the `tooltip` property on `DocumentLink`.
    ///
    /// @since 3.15.0
    tooltipSupport: ?bool = null,
};

pub const DocumentColorClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `DocumentColorRegistrationOptions` return value
    /// for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
};

/// Client capabilities of a {@link DocumentFormattingRequest}.
pub const DocumentFormattingClientCapabilities = struct {
    /// Whether formatting supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

/// Client capabilities of a {@link DocumentRangeFormattingRequest}.
pub const DocumentRangeFormattingClientCapabilities = struct {
    /// Whether range formatting supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Whether the client supports formatting multiple ranges at once.
    ///
    /// @since 3.18.0
    /// @proposed
    rangesSupport: ?bool = null,
};

/// Client capabilities of a {@link DocumentOnTypeFormattingRequest}.
pub const DocumentOnTypeFormattingClientCapabilities = struct {
    /// Whether on type formatting supports dynamic registration.
    dynamicRegistration: ?bool = null,
};

pub const RenameClientCapabilities = struct {
    /// Whether rename supports dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Client supports testing for validity of rename operations
    /// before execution.
    ///
    /// @since 3.12.0
    prepareSupport: ?bool = null,
    /// Client supports the default behavior result.
    ///
    /// The value indicates the default behavior used by the
    /// client.
    ///
    /// @since 3.16.0
    prepareSupportDefaultBehavior: ?PrepareSupportDefaultBehavior = null,
    /// Whether the client honors the change annotations in
    /// text edits and resource operations returned via the
    /// rename request's workspace edit by for example presenting
    /// the workspace edit in the user interface and asking
    /// for confirmation.
    ///
    /// @since 3.16.0
    honorsChangeAnnotations: ?bool = null,
};

pub const FoldingRangeClientCapabilities = struct {
    /// Whether implementation supports dynamic registration for folding range
    /// providers. If this is set to `true` the client supports the new
    /// `FoldingRangeRegistrationOptions` return value for the corresponding
    /// server capability as well.
    dynamicRegistration: ?bool = null,
    /// The maximum number of folding ranges that the client prefers to receive
    /// per document. The value serves as a hint, servers are free to follow the
    /// limit.
    rangeLimit: ?u32 = null,
    /// If set, the client signals that it only supports folding complete lines.
    /// If set, client will ignore specified `startCharacter` and `endCharacter`
    /// properties in a FoldingRange.
    lineFoldingOnly: ?bool = null,
    /// Specific options for the folding range kind.
    ///
    /// @since 3.17.0
    foldingRangeKind: ?ClientFoldingRangeKindOptions = null,
    /// Specific options for the folding range.
    ///
    /// @since 3.17.0
    foldingRange: ?ClientFoldingRangeOptions = null,
};

pub const SelectionRangeClientCapabilities = struct {
    /// Whether implementation supports dynamic registration for selection range providers. If this is set to `true`
    /// the client supports the new `SelectionRangeRegistrationOptions` return value for the corresponding server
    /// capability as well.
    dynamicRegistration: ?bool = null,
};

/// The publish diagnostic client capabilities.
pub const PublishDiagnosticsClientCapabilities = struct {
    /// Whether the clients accepts diagnostics with related information.
    relatedInformation: ?bool = null,
    /// Client supports the tag property to provide meta data about a diagnostic.
    /// Clients supporting tags have to handle unknown tags gracefully.
    ///
    /// @since 3.15.0
    tagSupport: ?ClientDiagnosticsTagOptions = null,
    /// Whether the client interprets the version property of the
    /// `textDocument/publishDiagnostics` notification's parameter.
    ///
    /// @since 3.15.0
    versionSupport: ?bool = null,
    /// Client supports a codeDescription property
    ///
    /// @since 3.16.0
    codeDescriptionSupport: ?bool = null,
    /// Whether code action supports the `data` property which is
    /// preserved between a `textDocument/publishDiagnostics` and
    /// `textDocument/codeAction` request.
    ///
    /// @since 3.16.0
    dataSupport: ?bool = null,
};

/// @since 3.16.0
pub const CallHierarchyClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
};

/// @since 3.16.0
pub const SemanticTokensClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
    /// Which requests the client supports and might send to the server
    /// depending on the server's capability. Please note that clients might not
    /// show semantic tokens or degrade some of the user experience if a range
    /// or full request is advertised by the client but not provided by the
    /// server. If for example the client capability `requests.full` and
    /// `request.range` are both set to true but the server only provides a
    /// range provider the client might not render a minimap correctly or might
    /// even decide to not show any semantic tokens at all.
    requests: ClientSemanticTokensRequestOptions,
    /// The token types that the client supports.
    tokenTypes: []const []const u8,
    /// The token modifiers that the client supports.
    tokenModifiers: []const []const u8,
    /// The token formats the clients supports.
    formats: []const TokenFormat,
    /// Whether the client supports tokens that can overlap each other.
    overlappingTokenSupport: ?bool = null,
    /// Whether the client supports tokens that can span multiple lines.
    multilineTokenSupport: ?bool = null,
    /// Whether the client allows the server to actively cancel a
    /// semantic token request, e.g. supports returning
    /// LSPErrorCodes.ServerCancelled. If a server does the client
    /// needs to retrigger the request.
    ///
    /// @since 3.17.0
    serverCancelSupport: ?bool = null,
    /// Whether the client uses semantic tokens to augment existing
    /// syntax tokens. If set to `true` client side created syntax
    /// tokens and semantic tokens are both used for colorization. If
    /// set to `false` the client only uses the returned semantic tokens
    /// for colorization.
    ///
    /// If the value is `undefined` then the client behavior is not
    /// specified.
    ///
    /// @since 3.17.0
    augmentsSyntaxTokens: ?bool = null,
};

/// Client capabilities for the linked editing range request.
///
/// @since 3.16.0
pub const LinkedEditingRangeClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
};

/// Client capabilities specific to the moniker request.
///
/// @since 3.16.0
pub const MonikerClientCapabilities = struct {
    /// Whether moniker supports dynamic registration. If this is set to `true`
    /// the client supports the new `MonikerRegistrationOptions` return value
    /// for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
};

/// @since 3.17.0
pub const TypeHierarchyClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
};

/// Client capabilities specific to inline values.
///
/// @since 3.17.0
pub const InlineValueClientCapabilities = struct {
    /// Whether implementation supports dynamic registration for inline value providers.
    dynamicRegistration: ?bool = null,
};

/// Inlay hint client capabilities.
///
/// @since 3.17.0
pub const InlayHintClientCapabilities = struct {
    /// Whether inlay hints support dynamic registration.
    dynamicRegistration: ?bool = null,
    /// Indicates which properties a client can resolve lazily on an inlay
    /// hint.
    resolveSupport: ?ClientInlayHintResolveOptions = null,
};

/// Client capabilities specific to diagnostic pull requests.
///
/// @since 3.17.0
pub const DiagnosticClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is set to `true`
    /// the client supports the new `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
    /// Whether the clients supports related documents for document diagnostic pulls.
    relatedDocumentSupport: ?bool = null,
};

/// Client capabilities specific to inline completions.
///
/// @since 3.18.0
/// @proposed
pub const InlineCompletionClientCapabilities = struct {
    /// Whether implementation supports dynamic registration for inline completion providers.
    dynamicRegistration: ?bool = null,
};

/// Notebook specific client capabilities.
///
/// @since 3.17.0
pub const NotebookDocumentSyncClientCapabilities = struct {
    /// Whether implementation supports dynamic registration. If this is
    /// set to `true` the client supports the new
    /// `(TextDocumentRegistrationOptions & StaticRegistrationOptions)`
    /// return value for the corresponding server capability as well.
    dynamicRegistration: ?bool = null,
    /// The client supports sending execution summary data per cell.
    executionSummarySupport: ?bool = null,
};

/// Show message request client capabilities
pub const ShowMessageRequestClientCapabilities = struct {
    /// Capabilities specific to the `MessageActionItem` type.
    messageActionItem: ?ClientShowMessageActionItemOptions = null,
};

/// Client capabilities for the showDocument request.
///
/// @since 3.16.0
pub const ShowDocumentClientCapabilities = struct {
    /// The client has support for the showDocument
    /// request.
    support: bool,
};

/// @since 3.18.0
/// @proposed
pub const StaleRequestSupportOptions = struct {
    /// The client will actively cancel the request.
    cancel: bool,
    /// The list of requests for which the client
    /// will retry the request if it receives a
    /// response with error code `ContentModified`
    retryOnContentModified: []const []const u8,
};

/// Client capabilities specific to regular expressions.
///
/// @since 3.16.0
pub const RegularExpressionsClientCapabilities = struct {
    /// The engine's name.
    engine: []const u8,
    /// The engine's version.
    version: ?[]const u8 = null,
};

/// Client capabilities specific to the used markdown parser.
///
/// @since 3.16.0
pub const MarkdownClientCapabilities = struct {
    /// The name of the parser.
    parser: []const u8,
    /// The version of the parser.
    version: ?[]const u8 = null,
    /// A list of HTML tags that the client allows / supports in
    /// Markdown.
    ///
    /// @since 3.17.0
    allowedTags: ?[]const []const u8 = null,
};

/// @since 3.18.0
/// @proposed
pub const NotebookCellLanguage = struct {
    language: []const u8,
};

/// A notebook document filter where `notebookType` is required field.
///
/// @since 3.18.0
/// @proposed
pub const NotebookDocumentFilterNotebookType = struct {
    /// The type of the enclosing notebook.
    notebookType: []const u8,
    /// A Uri {@link Uri.scheme scheme}, like `file` or `untitled`.
    scheme: ?[]const u8 = null,
    /// A glob pattern.
    pattern: ?[]const u8 = null,
};

/// A notebook document filter where `scheme` is required field.
///
/// @since 3.18.0
/// @proposed
pub const NotebookDocumentFilterScheme = struct {
    /// The type of the enclosing notebook.
    notebookType: ?[]const u8 = null,
    /// A Uri {@link Uri.scheme scheme}, like `file` or `untitled`.
    scheme: []const u8,
    /// A glob pattern.
    pattern: ?[]const u8 = null,
};

/// A notebook document filter where `pattern` is required field.
///
/// @since 3.18.0
/// @proposed
pub const NotebookDocumentFilterPattern = struct {
    /// The type of the enclosing notebook.
    notebookType: ?[]const u8 = null,
    /// A Uri {@link Uri.scheme scheme}, like `file` or `untitled`.
    scheme: ?[]const u8 = null,
    /// A glob pattern.
    pattern: []const u8,
};

/// @since 3.18.0
/// @proposed
pub const ChangeAnnotationsSupportOptions = struct {
    /// Whether the client groups edits with equal labels into tree nodes,
    /// for instance all edits labelled with "Changes in Strings" would
    /// be a tree node.
    groupsOnLabel: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientSymbolKindOptions = struct {
    /// The symbol kind values the client supports. When this
    /// property exists the client also guarantees that it will
    /// handle values outside its set gracefully and falls back
    /// to a default value when unknown.
    ///
    /// If this property is not present the client only supports
    /// the symbol kinds from `File` to `Array` as defined in
    /// the initial version of the protocol.
    valueSet: ?[]const SymbolKind = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientSymbolTagOptions = struct {
    /// The tags supported by the client.
    valueSet: []const SymbolTag,
};

/// @since 3.18.0
/// @proposed
pub const ClientSymbolResolveOptions = struct {
    /// The properties that a client can resolve lazily. Usually
    /// `location.range`
    properties: []const []const u8,
};

/// @since 3.18.0
/// @proposed
pub const ClientCompletionItemOptions = struct {
    /// Client supports snippets as insert text.
    ///
    /// A snippet can define tab stops and placeholders with `$1`, `$2`
    /// and `${3:foo}`. `$0` defines the final tab stop, it defaults to
    /// the end of the snippet. Placeholders with equal identifiers are linked,
    /// that is typing in one will update others too.
    snippetSupport: ?bool = null,
    /// Client supports commit characters on a completion item.
    commitCharactersSupport: ?bool = null,
    /// Client supports the following content formats for the documentation
    /// property. The order describes the preferred format of the client.
    documentationFormat: ?[]const MarkupKind = null,
    /// Client supports the deprecated property on a completion item.
    deprecatedSupport: ?bool = null,
    /// Client supports the preselect property on a completion item.
    preselectSupport: ?bool = null,
    /// Client supports the tag property on a completion item. Clients supporting
    /// tags have to handle unknown tags gracefully. Clients especially need to
    /// preserve unknown tags when sending a completion item back to the server in
    /// a resolve call.
    ///
    /// @since 3.15.0
    tagSupport: ?CompletionItemTagOptions = null,
    /// Client support insert replace edit to control different behavior if a
    /// completion item is inserted in the text or should replace text.
    ///
    /// @since 3.16.0
    insertReplaceSupport: ?bool = null,
    /// Indicates which properties a client can resolve lazily on a completion
    /// item. Before version 3.16.0 only the predefined properties `documentation`
    /// and `details` could be resolved lazily.
    ///
    /// @since 3.16.0
    resolveSupport: ?ClientCompletionItemResolveOptions = null,
    /// The client supports the `insertTextMode` property on
    /// a completion item to override the whitespace handling mode
    /// as defined by the client (see `insertTextMode`).
    ///
    /// @since 3.16.0
    insertTextModeSupport: ?ClientCompletionItemInsertTextModeOptions = null,
    /// The client has support for completion item label
    /// details (see also `CompletionItemLabelDetails`).
    ///
    /// @since 3.17.0
    labelDetailsSupport: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientCompletionItemOptionsKind = struct {
    /// The completion item kind values the client supports. When this
    /// property exists the client also guarantees that it will
    /// handle values outside its set gracefully and falls back
    /// to a default value when unknown.
    ///
    /// If this property is not present the client only supports
    /// the completion items kinds from `Text` to `Reference` as defined in
    /// the initial version of the protocol.
    valueSet: ?[]const CompletionItemKind = null,
};

/// The client supports the following `CompletionList` specific
/// capabilities.
///
/// @since 3.17.0
pub const CompletionListCapabilities = struct {
    /// The client supports the following itemDefaults on
    /// a completion list.
    ///
    /// The value lists the supported property names of the
    /// `CompletionList.itemDefaults` object. If omitted
    /// no properties are supported.
    ///
    /// @since 3.17.0
    itemDefaults: ?[]const []const u8 = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientSignatureInformationOptions = struct {
    /// Client supports the following content formats for the documentation
    /// property. The order describes the preferred format of the client.
    documentationFormat: ?[]const MarkupKind = null,
    /// Client capabilities specific to parameter information.
    parameterInformation: ?ClientSignatureParameterInformationOptions = null,
    /// The client supports the `activeParameter` property on `SignatureInformation`
    /// literal.
    ///
    /// @since 3.16.0
    activeParameterSupport: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientCodeActionLiteralOptions = struct {
    /// The code action kind is support with the following value
    /// set.
    codeActionKind: ClientCodeActionKindOptions,
};

/// @since 3.18.0
/// @proposed
pub const ClientCodeActionResolveOptions = struct {
    /// The properties that a client can resolve lazily.
    properties: []const []const u8,
};

/// @since 3.18.0
/// @proposed
pub const ClientFoldingRangeKindOptions = struct {
    /// The folding range kind values the client supports. When this
    /// property exists the client also guarantees that it will
    /// handle values outside its set gracefully and falls back
    /// to a default value when unknown.
    valueSet: ?[]const FoldingRangeKind = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientFoldingRangeOptions = struct {
    /// If set, the client signals that it supports setting collapsedText on
    /// folding ranges to display custom labels instead of the default text.
    ///
    /// @since 3.17.0
    collapsedText: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientDiagnosticsTagOptions = struct {
    /// The tags supported by the client.
    valueSet: []const DiagnosticTag,
};

/// @since 3.18.0
/// @proposed
pub const ClientSemanticTokensRequestOptions = struct {
    /// The client will send the `textDocument/semanticTokens/range` request if
    /// the server provides a corresponding handler.
    range: ?union(enum) {
        bool: bool,
        literal_1: struct {},
        pub usingnamespace UnionParser(@This());
    } = null,
    /// The client will send the `textDocument/semanticTokens/full` request if
    /// the server provides a corresponding handler.
    full: ?union(enum) {
        bool: bool,
        ClientSemanticTokensRequestFullDelta: ClientSemanticTokensRequestFullDelta,
        pub usingnamespace UnionParser(@This());
    } = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientInlayHintResolveOptions = struct {
    /// The properties that a client can resolve lazily.
    properties: []const []const u8,
};

/// @since 3.18.0
/// @proposed
pub const ClientShowMessageActionItemOptions = struct {
    /// Whether the client supports additional attributes which
    /// are preserved and send back to the server in the
    /// request's response.
    additionalPropertiesSupport: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const CompletionItemTagOptions = struct {
    /// The tags supported by the client.
    valueSet: []const CompletionItemTag,
};

/// @since 3.18.0
/// @proposed
pub const ClientCompletionItemResolveOptions = struct {
    /// The properties that a client can resolve lazily.
    properties: []const []const u8,
};

/// @since 3.18.0
/// @proposed
pub const ClientCompletionItemInsertTextModeOptions = struct {
    valueSet: []const InsertTextMode,
};

/// @since 3.18.0
/// @proposed
pub const ClientSignatureParameterInformationOptions = struct {
    /// The client supports processing label offsets instead of a
    /// simple label string.
    ///
    /// @since 3.14.0
    labelOffsetSupport: ?bool = null,
};

/// @since 3.18.0
/// @proposed
pub const ClientCodeActionKindOptions = struct {
    /// The code action kind values the client supports. When this
    /// property exists the client also guarantees that it will
    /// handle values outside its set gracefully and falls back
    /// to a default value when unknown.
    valueSet: []const CodeActionKind,
};

/// @since 3.18.0
/// @proposed
pub const ClientSemanticTokensRequestFullDelta = struct {
    /// The client will send the `textDocument/semanticTokens/full/delta` request if
    /// the server provides a corresponding handler.
    delta: ?bool = null,
};

pub const notification_metadata = [_]NotificationMetadata{
    // The `workspace/didChangeWorkspaceFolders` notification is sent from the client to the server when the workspace
    // folder configuration changes.
    .{
        .method = "workspace/didChangeWorkspaceFolders",
        .documentation = "The `workspace/didChangeWorkspaceFolders` notification is sent from the client to the server when the workspace\nfolder configuration changes.",
        .direction = .clientToServer,
        .Params = DidChangeWorkspaceFoldersParams,
        .registration = .{ .method = null, .Options = null },
    },
    // The `window/workDoneProgress/cancel` notification is sent from  the client to the server to cancel a progress
    // initiated on the server side.
    .{
        .method = "window/workDoneProgress/cancel",
        .documentation = "The `window/workDoneProgress/cancel` notification is sent from  the client to the server to cancel a progress\ninitiated on the server side.",
        .direction = .clientToServer,
        .Params = WorkDoneProgressCancelParams,
        .registration = .{ .method = null, .Options = null },
    },
    // The did create files notification is sent from the client to the server when
    // files were created from within the client.
    //
    // @since 3.16.0
    .{
        .method = "workspace/didCreateFiles",
        .documentation = "The did create files notification is sent from the client to the server when\nfiles were created from within the client.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = CreateFilesParams,
        .registration = .{ .method = null, .Options = FileOperationRegistrationOptions },
    },
    // The did rename files notification is sent from the client to the server when
    // files were renamed from within the client.
    //
    // @since 3.16.0
    .{
        .method = "workspace/didRenameFiles",
        .documentation = "The did rename files notification is sent from the client to the server when\nfiles were renamed from within the client.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = RenameFilesParams,
        .registration = .{ .method = null, .Options = FileOperationRegistrationOptions },
    },
    // The will delete files request is sent from the client to the server before files are actually
    // deleted as long as the deletion is triggered from within the client.
    //
    // @since 3.16.0
    .{
        .method = "workspace/didDeleteFiles",
        .documentation = "The will delete files request is sent from the client to the server before files are actually\ndeleted as long as the deletion is triggered from within the client.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = DeleteFilesParams,
        .registration = .{ .method = null, .Options = FileOperationRegistrationOptions },
    },
    // A notification sent when a notebook opens.
    //
    // @since 3.17.0
    .{
        .method = "notebookDocument/didOpen",
        .documentation = "A notification sent when a notebook opens.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = DidOpenNotebookDocumentParams,
        .registration = .{ .method = "notebookDocument/sync", .Options = null },
    },
    .{
        .method = "notebookDocument/didChange",
        .documentation = null,
        .direction = .clientToServer,
        .Params = DidChangeNotebookDocumentParams,
        .registration = .{ .method = "notebookDocument/sync", .Options = null },
    },
    // A notification sent when a notebook document is saved.
    //
    // @since 3.17.0
    .{
        .method = "notebookDocument/didSave",
        .documentation = "A notification sent when a notebook document is saved.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = DidSaveNotebookDocumentParams,
        .registration = .{ .method = "notebookDocument/sync", .Options = null },
    },
    // A notification sent when a notebook closes.
    //
    // @since 3.17.0
    .{
        .method = "notebookDocument/didClose",
        .documentation = "A notification sent when a notebook closes.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = DidCloseNotebookDocumentParams,
        .registration = .{ .method = "notebookDocument/sync", .Options = null },
    },
    // The initialized notification is sent from the client to the
    // server after the client is fully initialized and the server
    // is allowed to send requests from the server to the client.
    .{
        .method = "initialized",
        .documentation = "The initialized notification is sent from the client to the\nserver after the client is fully initialized and the server\nis allowed to send requests from the server to the client.",
        .direction = .clientToServer,
        .Params = InitializedParams,
        .registration = .{ .method = null, .Options = null },
    },
    // The exit event is sent from the client to the server to
    // ask the server to exit its process.
    .{
        .method = "exit",
        .documentation = "The exit event is sent from the client to the server to\nask the server to exit its process.",
        .direction = .clientToServer,
        .Params = null,
        .registration = .{ .method = null, .Options = null },
    },
    // The configuration change notification is sent from the client to the server
    // when the client's configuration has changed. The notification contains
    // the changed configuration as defined by the language client.
    .{
        .method = "workspace/didChangeConfiguration",
        .documentation = "The configuration change notification is sent from the client to the server\nwhen the client's configuration has changed. The notification contains\nthe changed configuration as defined by the language client.",
        .direction = .clientToServer,
        .Params = DidChangeConfigurationParams,
        .registration = .{ .method = null, .Options = DidChangeConfigurationRegistrationOptions },
    },
    // The show message notification is sent from a server to a client to ask
    // the client to display a particular message in the user interface.
    .{
        .method = "window/showMessage",
        .documentation = "The show message notification is sent from a server to a client to ask\nthe client to display a particular message in the user interface.",
        .direction = .serverToClient,
        .Params = ShowMessageParams,
        .registration = .{ .method = null, .Options = null },
    },
    // The log message notification is sent from the server to the client to ask
    // the client to log a particular message.
    .{
        .method = "window/logMessage",
        .documentation = "The log message notification is sent from the server to the client to ask\nthe client to log a particular message.",
        .direction = .serverToClient,
        .Params = LogMessageParams,
        .registration = .{ .method = null, .Options = null },
    },
    // The telemetry event notification is sent from the server to the client to ask
    // the client to log telemetry data.
    .{
        .method = "telemetry/event",
        .documentation = "The telemetry event notification is sent from the server to the client to ask\nthe client to log telemetry data.",
        .direction = .serverToClient,
        .Params = LSPAny,
        .registration = .{ .method = null, .Options = null },
    },
    // The document open notification is sent from the client to the server to signal
    // newly opened text documents. The document's truth is now managed by the client
    // and the server must not try to read the document's truth using the document's
    // uri. Open in this sense means it is managed by the client. It doesn't necessarily
    // mean that its content is presented in an editor. An open notification must not
    // be sent more than once without a corresponding close notification send before.
    // This means open and close notification must be balanced and the max open count
    // is one.
    .{
        .method = "textDocument/didOpen",
        .documentation = "The document open notification is sent from the client to the server to signal\nnewly opened text documents. The document's truth is now managed by the client\nand the server must not try to read the document's truth using the document's\nuri. Open in this sense means it is managed by the client. It doesn't necessarily\nmean that its content is presented in an editor. An open notification must not\nbe sent more than once without a corresponding close notification send before.\nThis means open and close notification must be balanced and the max open count\nis one.",
        .direction = .clientToServer,
        .Params = DidOpenTextDocumentParams,
        .registration = .{ .method = null, .Options = TextDocumentRegistrationOptions },
    },
    // The document change notification is sent from the client to the server to signal
    // changes to a text document.
    .{
        .method = "textDocument/didChange",
        .documentation = "The document change notification is sent from the client to the server to signal\nchanges to a text document.",
        .direction = .clientToServer,
        .Params = DidChangeTextDocumentParams,
        .registration = .{ .method = null, .Options = TextDocumentChangeRegistrationOptions },
    },
    // The document close notification is sent from the client to the server when
    // the document got closed in the client. The document's truth now exists where
    // the document's uri points to (e.g. if the document's uri is a file uri the
    // truth now exists on disk). As with the open notification the close notification
    // is about managing the document's content. Receiving a close notification
    // doesn't mean that the document was open in an editor before. A close
    // notification requires a previous open notification to be sent.
    .{
        .method = "textDocument/didClose",
        .documentation = "The document close notification is sent from the client to the server when\nthe document got closed in the client. The document's truth now exists where\nthe document's uri points to (e.g. if the document's uri is a file uri the\ntruth now exists on disk). As with the open notification the close notification\nis about managing the document's content. Receiving a close notification\ndoesn't mean that the document was open in an editor before. A close\nnotification requires a previous open notification to be sent.",
        .direction = .clientToServer,
        .Params = DidCloseTextDocumentParams,
        .registration = .{ .method = null, .Options = TextDocumentRegistrationOptions },
    },
    // The document save notification is sent from the client to the server when
    // the document got saved in the client.
    .{
        .method = "textDocument/didSave",
        .documentation = "The document save notification is sent from the client to the server when\nthe document got saved in the client.",
        .direction = .clientToServer,
        .Params = DidSaveTextDocumentParams,
        .registration = .{ .method = null, .Options = TextDocumentSaveRegistrationOptions },
    },
    // A document will save notification is sent from the client to the server before
    // the document is actually saved.
    .{
        .method = "textDocument/willSave",
        .documentation = "A document will save notification is sent from the client to the server before\nthe document is actually saved.",
        .direction = .clientToServer,
        .Params = WillSaveTextDocumentParams,
        .registration = .{ .method = null, .Options = TextDocumentRegistrationOptions },
    },
    // The watched files notification is sent from the client to the server when
    // the client detects changes to file watched by the language client.
    .{
        .method = "workspace/didChangeWatchedFiles",
        .documentation = "The watched files notification is sent from the client to the server when\nthe client detects changes to file watched by the language client.",
        .direction = .clientToServer,
        .Params = DidChangeWatchedFilesParams,
        .registration = .{ .method = null, .Options = DidChangeWatchedFilesRegistrationOptions },
    },
    // Diagnostics notification are sent from the server to the client to signal
    // results of validation runs.
    .{
        .method = "textDocument/publishDiagnostics",
        .documentation = "Diagnostics notification are sent from the server to the client to signal\nresults of validation runs.",
        .direction = .serverToClient,
        .Params = PublishDiagnosticsParams,
        .registration = .{ .method = null, .Options = null },
    },
    .{
        .method = "$/setTrace",
        .documentation = null,
        .direction = .clientToServer,
        .Params = SetTraceParams,
        .registration = .{ .method = null, .Options = null },
    },
    .{
        .method = "$/logTrace",
        .documentation = null,
        .direction = .serverToClient,
        .Params = LogTraceParams,
        .registration = .{ .method = null, .Options = null },
    },
    .{
        .method = "$/cancelRequest",
        .documentation = null,
        .direction = .both,
        .Params = CancelParams,
        .registration = .{ .method = null, .Options = null },
    },
    .{
        .method = "$/progress",
        .documentation = null,
        .direction = .both,
        .Params = ProgressParams,
        .registration = .{ .method = null, .Options = null },
    },
};
pub const request_metadata = [_]RequestMetadata{
    // A request to resolve the implementation locations of a symbol at a given text
    // document position. The request's parameter is of type {@link TextDocumentPositionParams}
    // the response is of type {@link Definition} or a Thenable that resolves to such.
    .{
        .method = "textDocument/implementation",
        .documentation = "A request to resolve the implementation locations of a symbol at a given text\ndocument position. The request's parameter is of type {@link TextDocumentPositionParams}\nthe response is of type {@link Definition} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = ImplementationParams,
        .Result = ?union(enum) {
            Definition: Definition,
            array_of_DefinitionLink: []const DefinitionLink,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            array_of_Location: []const Location,
            array_of_DefinitionLink: []const DefinitionLink,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = ImplementationRegistrationOptions },
    },
    // A request to resolve the type definition locations of a symbol at a given text
    // document position. The request's parameter is of type {@link TextDocumentPositionParams}
    // the response is of type {@link Definition} or a Thenable that resolves to such.
    .{
        .method = "textDocument/typeDefinition",
        .documentation = "A request to resolve the type definition locations of a symbol at a given text\ndocument position. The request's parameter is of type {@link TextDocumentPositionParams}\nthe response is of type {@link Definition} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = TypeDefinitionParams,
        .Result = ?union(enum) {
            Definition: Definition,
            array_of_DefinitionLink: []const DefinitionLink,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            array_of_Location: []const Location,
            array_of_DefinitionLink: []const DefinitionLink,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = TypeDefinitionRegistrationOptions },
    },
    // The `workspace/workspaceFolders` is sent from the server to the client to fetch the open workspace folders.
    .{
        .method = "workspace/workspaceFolders",
        .documentation = "The `workspace/workspaceFolders` is sent from the server to the client to fetch the open workspace folders.",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?[]const WorkspaceFolder,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // The 'workspace/configuration' request is sent from the server to the client to fetch a certain
    // configuration setting.
    //
    // This pull model replaces the old push model were the client signaled configuration change via an
    // event. If the server still needs to react to configuration changes (since the server caches the
    // result of `workspace/configuration` requests) the server should register for an empty configuration
    // change event and empty the cache if such an event is received.
    .{
        .method = "workspace/configuration",
        .documentation = "The 'workspace/configuration' request is sent from the server to the client to fetch a certain\nconfiguration setting.\n\nThis pull model replaces the old push model were the client signaled configuration change via an\nevent. If the server still needs to react to configuration changes (since the server caches the\nresult of `workspace/configuration` requests) the server should register for an empty configuration\nchange event and empty the cache if such an event is received.",
        .direction = .serverToClient,
        .Params = ConfigurationParams,
        .Result = []const LSPAny,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to list all color symbols found in a given text document. The request's
    // parameter is of type {@link DocumentColorParams} the
    // response is of type {@link ColorInformation ColorInformation[]} or a Thenable
    // that resolves to such.
    .{
        .method = "textDocument/documentColor",
        .documentation = "A request to list all color symbols found in a given text document. The request's\nparameter is of type {@link DocumentColorParams} the\nresponse is of type {@link ColorInformation ColorInformation[]} or a Thenable\nthat resolves to such.",
        .direction = .clientToServer,
        .Params = DocumentColorParams,
        .Result = []const ColorInformation,
        .PartialResult = []const ColorInformation,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentColorRegistrationOptions },
    },
    // A request to list all presentation for a color. The request's
    // parameter is of type {@link ColorPresentationParams} the
    // response is of type {@link ColorInformation ColorInformation[]} or a Thenable
    // that resolves to such.
    .{
        .method = "textDocument/colorPresentation",
        .documentation = "A request to list all presentation for a color. The request's\nparameter is of type {@link ColorPresentationParams} the\nresponse is of type {@link ColorInformation ColorInformation[]} or a Thenable\nthat resolves to such.",
        .direction = .clientToServer,
        .Params = ColorPresentationParams,
        .Result = []const ColorPresentation,
        .PartialResult = []const ColorPresentation,
        .ErrorData = null,
        .registration = .{
            .method = null,
            .Options = struct {
                // And WorkDoneProgressOptions
                workDoneProgress: ?bool = null,
                // And TextDocumentRegistrationOptions
                /// A document selector to identify the scope of the registration. If set to null
                /// the document selector provided on the client side will be used.
                documentSelector: ?DocumentSelector = null,
            },
        },
    },
    // A request to provide folding ranges in a document. The request's
    // parameter is of type {@link FoldingRangeParams}, the
    // response is of type {@link FoldingRangeList} or a Thenable
    // that resolves to such.
    .{
        .method = "textDocument/foldingRange",
        .documentation = "A request to provide folding ranges in a document. The request's\nparameter is of type {@link FoldingRangeParams}, the\nresponse is of type {@link FoldingRangeList} or a Thenable\nthat resolves to such.",
        .direction = .clientToServer,
        .Params = FoldingRangeParams,
        .Result = ?[]const FoldingRange,
        .PartialResult = []const FoldingRange,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = FoldingRangeRegistrationOptions },
    },
    // @since 3.18.0
    // @proposed
    .{
        .method = "workspace/foldingRange/refresh",
        .documentation = "@since 3.18.0\n@proposed",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to resolve the type definition locations of a symbol at a given text
    // document position. The request's parameter is of type {@link TextDocumentPositionParams}
    // the response is of type {@link Declaration} or a typed array of {@link DeclarationLink}
    // or a Thenable that resolves to such.
    .{
        .method = "textDocument/declaration",
        .documentation = "A request to resolve the type definition locations of a symbol at a given text\ndocument position. The request's parameter is of type {@link TextDocumentPositionParams}\nthe response is of type {@link Declaration} or a typed array of {@link DeclarationLink}\nor a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = DeclarationParams,
        .Result = ?union(enum) {
            Declaration: Declaration,
            array_of_DeclarationLink: []const DeclarationLink,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            array_of_Location: []const Location,
            array_of_DeclarationLink: []const DeclarationLink,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DeclarationRegistrationOptions },
    },
    // A request to provide selection ranges in a document. The request's
    // parameter is of type {@link SelectionRangeParams}, the
    // response is of type {@link SelectionRange SelectionRange[]} or a Thenable
    // that resolves to such.
    .{
        .method = "textDocument/selectionRange",
        .documentation = "A request to provide selection ranges in a document. The request's\nparameter is of type {@link SelectionRangeParams}, the\nresponse is of type {@link SelectionRange SelectionRange[]} or a Thenable\nthat resolves to such.",
        .direction = .clientToServer,
        .Params = SelectionRangeParams,
        .Result = ?[]const SelectionRange,
        .PartialResult = []const SelectionRange,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = SelectionRangeRegistrationOptions },
    },
    // The `window/workDoneProgress/create` request is sent from the server to the client to initiate progress
    // reporting from the server.
    .{
        .method = "window/workDoneProgress/create",
        .documentation = "The `window/workDoneProgress/create` request is sent from the server to the client to initiate progress\nreporting from the server.",
        .direction = .serverToClient,
        .Params = WorkDoneProgressCreateParams,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to result a `CallHierarchyItem` in a document at a given position.
    // Can be used as an input to an incoming or outgoing call hierarchy.
    //
    // @since 3.16.0
    .{
        .method = "textDocument/prepareCallHierarchy",
        .documentation = "A request to result a `CallHierarchyItem` in a document at a given position.\nCan be used as an input to an incoming or outgoing call hierarchy.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = CallHierarchyPrepareParams,
        .Result = ?[]const CallHierarchyItem,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = CallHierarchyRegistrationOptions },
    },
    // A request to resolve the incoming calls for a given `CallHierarchyItem`.
    //
    // @since 3.16.0
    .{
        .method = "callHierarchy/incomingCalls",
        .documentation = "A request to resolve the incoming calls for a given `CallHierarchyItem`.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = CallHierarchyIncomingCallsParams,
        .Result = ?[]const CallHierarchyIncomingCall,
        .PartialResult = []const CallHierarchyIncomingCall,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to resolve the outgoing calls for a given `CallHierarchyItem`.
    //
    // @since 3.16.0
    .{
        .method = "callHierarchy/outgoingCalls",
        .documentation = "A request to resolve the outgoing calls for a given `CallHierarchyItem`.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = CallHierarchyOutgoingCallsParams,
        .Result = ?[]const CallHierarchyOutgoingCall,
        .PartialResult = []const CallHierarchyOutgoingCall,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // @since 3.16.0
    .{
        .method = "textDocument/semanticTokens/full",
        .documentation = "@since 3.16.0",
        .direction = .clientToServer,
        .Params = SemanticTokensParams,
        .Result = ?SemanticTokens,
        .PartialResult = SemanticTokensPartialResult,
        .ErrorData = null,
        .registration = .{ .method = "textDocument/semanticTokens", .Options = SemanticTokensRegistrationOptions },
    },
    // @since 3.16.0
    .{
        .method = "textDocument/semanticTokens/full/delta",
        .documentation = "@since 3.16.0",
        .direction = .clientToServer,
        .Params = SemanticTokensDeltaParams,
        .Result = ?union(enum) {
            SemanticTokens: SemanticTokens,
            SemanticTokensDelta: SemanticTokensDelta,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            SemanticTokensPartialResult: SemanticTokensPartialResult,
            SemanticTokensDeltaPartialResult: SemanticTokensDeltaPartialResult,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = "textDocument/semanticTokens", .Options = SemanticTokensRegistrationOptions },
    },
    // @since 3.16.0
    .{
        .method = "textDocument/semanticTokens/range",
        .documentation = "@since 3.16.0",
        .direction = .clientToServer,
        .Params = SemanticTokensRangeParams,
        .Result = ?SemanticTokens,
        .PartialResult = SemanticTokensPartialResult,
        .ErrorData = null,
        .registration = .{ .method = "textDocument/semanticTokens", .Options = null },
    },
    // @since 3.16.0
    .{
        .method = "workspace/semanticTokens/refresh",
        .documentation = "@since 3.16.0",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to show a document. This request might open an
    // external program depending on the value of the URI to open.
    // For example a request to open `https://code.visualstudio.com/`
    // will very likely open the URI in a WEB browser.
    //
    // @since 3.16.0
    .{
        .method = "window/showDocument",
        .documentation = "A request to show a document. This request might open an\nexternal program depending on the value of the URI to open.\nFor example a request to open `https://code.visualstudio.com/`\nwill very likely open the URI in a WEB browser.\n\n@since 3.16.0",
        .direction = .serverToClient,
        .Params = ShowDocumentParams,
        .Result = ShowDocumentResult,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to provide ranges that can be edited together.
    //
    // @since 3.16.0
    .{
        .method = "textDocument/linkedEditingRange",
        .documentation = "A request to provide ranges that can be edited together.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = LinkedEditingRangeParams,
        .Result = ?LinkedEditingRanges,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = LinkedEditingRangeRegistrationOptions },
    },
    // The will create files request is sent from the client to the server before files are actually
    // created as long as the creation is triggered from within the client.
    //
    // The request can return a `WorkspaceEdit` which will be applied to workspace before the
    // files are created. Hence the `WorkspaceEdit` can not manipulate the content of the file
    // to be created.
    //
    // @since 3.16.0
    .{
        .method = "workspace/willCreateFiles",
        .documentation = "The will create files request is sent from the client to the server before files are actually\ncreated as long as the creation is triggered from within the client.\n\nThe request can return a `WorkspaceEdit` which will be applied to workspace before the\nfiles are created. Hence the `WorkspaceEdit` can not manipulate the content of the file\nto be created.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = CreateFilesParams,
        .Result = ?WorkspaceEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = FileOperationRegistrationOptions },
    },
    // The will rename files request is sent from the client to the server before files are actually
    // renamed as long as the rename is triggered from within the client.
    //
    // @since 3.16.0
    .{
        .method = "workspace/willRenameFiles",
        .documentation = "The will rename files request is sent from the client to the server before files are actually\nrenamed as long as the rename is triggered from within the client.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = RenameFilesParams,
        .Result = ?WorkspaceEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = FileOperationRegistrationOptions },
    },
    // The did delete files notification is sent from the client to the server when
    // files were deleted from within the client.
    //
    // @since 3.16.0
    .{
        .method = "workspace/willDeleteFiles",
        .documentation = "The did delete files notification is sent from the client to the server when\nfiles were deleted from within the client.\n\n@since 3.16.0",
        .direction = .clientToServer,
        .Params = DeleteFilesParams,
        .Result = ?WorkspaceEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = FileOperationRegistrationOptions },
    },
    // A request to get the moniker of a symbol at a given text document position.
    // The request parameter is of type {@link TextDocumentPositionParams}.
    // The response is of type {@link Moniker Moniker[]} or `null`.
    .{
        .method = "textDocument/moniker",
        .documentation = "A request to get the moniker of a symbol at a given text document position.\nThe request parameter is of type {@link TextDocumentPositionParams}.\nThe response is of type {@link Moniker Moniker[]} or `null`.",
        .direction = .clientToServer,
        .Params = MonikerParams,
        .Result = ?[]const Moniker,
        .PartialResult = []const Moniker,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = MonikerRegistrationOptions },
    },
    // A request to result a `TypeHierarchyItem` in a document at a given position.
    // Can be used as an input to a subtypes or supertypes type hierarchy.
    //
    // @since 3.17.0
    .{
        .method = "textDocument/prepareTypeHierarchy",
        .documentation = "A request to result a `TypeHierarchyItem` in a document at a given position.\nCan be used as an input to a subtypes or supertypes type hierarchy.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = TypeHierarchyPrepareParams,
        .Result = ?[]const TypeHierarchyItem,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = TypeHierarchyRegistrationOptions },
    },
    // A request to resolve the supertypes for a given `TypeHierarchyItem`.
    //
    // @since 3.17.0
    .{
        .method = "typeHierarchy/supertypes",
        .documentation = "A request to resolve the supertypes for a given `TypeHierarchyItem`.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = TypeHierarchySupertypesParams,
        .Result = ?[]const TypeHierarchyItem,
        .PartialResult = []const TypeHierarchyItem,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to resolve the subtypes for a given `TypeHierarchyItem`.
    //
    // @since 3.17.0
    .{
        .method = "typeHierarchy/subtypes",
        .documentation = "A request to resolve the subtypes for a given `TypeHierarchyItem`.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = TypeHierarchySubtypesParams,
        .Result = ?[]const TypeHierarchyItem,
        .PartialResult = []const TypeHierarchyItem,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to provide inline values in a document. The request's parameter is of
    // type {@link InlineValueParams}, the response is of type
    // {@link InlineValue InlineValue[]} or a Thenable that resolves to such.
    //
    // @since 3.17.0
    .{
        .method = "textDocument/inlineValue",
        .documentation = "A request to provide inline values in a document. The request's parameter is of\ntype {@link InlineValueParams}, the response is of type\n{@link InlineValue InlineValue[]} or a Thenable that resolves to such.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = InlineValueParams,
        .Result = ?[]const InlineValue,
        .PartialResult = []const InlineValue,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = InlineValueRegistrationOptions },
    },
    // @since 3.17.0
    .{
        .method = "workspace/inlineValue/refresh",
        .documentation = "@since 3.17.0",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to provide inlay hints in a document. The request's parameter is of
    // type {@link InlayHintsParams}, the response is of type
    // {@link InlayHint InlayHint[]} or a Thenable that resolves to such.
    //
    // @since 3.17.0
    .{
        .method = "textDocument/inlayHint",
        .documentation = "A request to provide inlay hints in a document. The request's parameter is of\ntype {@link InlayHintsParams}, the response is of type\n{@link InlayHint InlayHint[]} or a Thenable that resolves to such.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = InlayHintParams,
        .Result = ?[]const InlayHint,
        .PartialResult = []const InlayHint,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = InlayHintRegistrationOptions },
    },
    // A request to resolve additional properties for an inlay hint.
    // The request's parameter is of type {@link InlayHint}, the response is
    // of type {@link InlayHint} or a Thenable that resolves to such.
    //
    // @since 3.17.0
    .{
        .method = "inlayHint/resolve",
        .documentation = "A request to resolve additional properties for an inlay hint.\nThe request's parameter is of type {@link InlayHint}, the response is\nof type {@link InlayHint} or a Thenable that resolves to such.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = InlayHint,
        .Result = InlayHint,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // @since 3.17.0
    .{
        .method = "workspace/inlayHint/refresh",
        .documentation = "@since 3.17.0",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // The document diagnostic request definition.
    //
    // @since 3.17.0
    .{
        .method = "textDocument/diagnostic",
        .documentation = "The document diagnostic request definition.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = DocumentDiagnosticParams,
        .Result = DocumentDiagnosticReport,
        .PartialResult = DocumentDiagnosticReportPartialResult,
        .ErrorData = DiagnosticServerCancellationData,
        .registration = .{ .method = null, .Options = DiagnosticRegistrationOptions },
    },
    // The workspace diagnostic request definition.
    //
    // @since 3.17.0
    .{
        .method = "workspace/diagnostic",
        .documentation = "The workspace diagnostic request definition.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = WorkspaceDiagnosticParams,
        .Result = WorkspaceDiagnosticReport,
        .PartialResult = WorkspaceDiagnosticReportPartialResult,
        .ErrorData = DiagnosticServerCancellationData,
        .registration = .{ .method = null, .Options = null },
    },
    // The diagnostic refresh request definition.
    //
    // @since 3.17.0
    .{
        .method = "workspace/diagnostic/refresh",
        .documentation = "The diagnostic refresh request definition.\n\n@since 3.17.0",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to provide inline completions in a document. The request's parameter is of
    // type {@link InlineCompletionParams}, the response is of type
    // {@link InlineCompletion InlineCompletion[]} or a Thenable that resolves to such.
    //
    // @since 3.18.0
    // @proposed
    .{
        .method = "textDocument/inlineCompletion",
        .documentation = "A request to provide inline completions in a document. The request's parameter is of\ntype {@link InlineCompletionParams}, the response is of type\n{@link InlineCompletion InlineCompletion[]} or a Thenable that resolves to such.\n\n@since 3.18.0\n@proposed",
        .direction = .clientToServer,
        .Params = InlineCompletionParams,
        .Result = ?union(enum) {
            InlineCompletionList: InlineCompletionList,
            array_of_InlineCompletionItem: []const InlineCompletionItem,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = []const InlineCompletionItem,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = InlineCompletionRegistrationOptions },
    },
    // The `client/registerCapability` request is sent from the server to the client to register a new capability
    // handler on the client side.
    .{
        .method = "client/registerCapability",
        .documentation = "The `client/registerCapability` request is sent from the server to the client to register a new capability\nhandler on the client side.",
        .direction = .serverToClient,
        .Params = RegistrationParams,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // The `client/unregisterCapability` request is sent from the server to the client to unregister a previously registered capability
    // handler on the client side.
    .{
        .method = "client/unregisterCapability",
        .documentation = "The `client/unregisterCapability` request is sent from the server to the client to unregister a previously registered capability\nhandler on the client side.",
        .direction = .serverToClient,
        .Params = UnregistrationParams,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // The initialize request is sent from the client to the server.
    // It is sent once as the request after starting up the server.
    // The requests parameter is of type {@link InitializeParams}
    // the response if of type {@link InitializeResult} of a Thenable that
    // resolves to such.
    .{
        .method = "initialize",
        .documentation = "The initialize request is sent from the client to the server.\nIt is sent once as the request after starting up the server.\nThe requests parameter is of type {@link InitializeParams}\nthe response if of type {@link InitializeResult} of a Thenable that\nresolves to such.",
        .direction = .clientToServer,
        .Params = InitializeParams,
        .Result = InitializeResult,
        .PartialResult = null,
        .ErrorData = InitializeError,
        .registration = .{ .method = null, .Options = null },
    },
    // A shutdown request is sent from the client to the server.
    // It is sent once when the client decides to shutdown the
    // server. The only notification that is sent after a shutdown request
    // is the exit event.
    .{
        .method = "shutdown",
        .documentation = "A shutdown request is sent from the client to the server.\nIt is sent once when the client decides to shutdown the\nserver. The only notification that is sent after a shutdown request\nis the exit event.",
        .direction = .clientToServer,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // The show message request is sent from the server to the client to show a message
    // and a set of options actions to the user.
    .{
        .method = "window/showMessageRequest",
        .documentation = "The show message request is sent from the server to the client to show a message\nand a set of options actions to the user.",
        .direction = .serverToClient,
        .Params = ShowMessageRequestParams,
        .Result = ?MessageActionItem,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A document will save request is sent from the client to the server before
    // the document is actually saved. The request can return an array of TextEdits
    // which will be applied to the text document before it is saved. Please note that
    // clients might drop results if computing the text edits took too long or if a
    // server constantly fails on this request. This is done to keep the save fast and
    // reliable.
    .{
        .method = "textDocument/willSaveWaitUntil",
        .documentation = "A document will save request is sent from the client to the server before\nthe document is actually saved. The request can return an array of TextEdits\nwhich will be applied to the text document before it is saved. Please note that\nclients might drop results if computing the text edits took too long or if a\nserver constantly fails on this request. This is done to keep the save fast and\nreliable.",
        .direction = .clientToServer,
        .Params = WillSaveTextDocumentParams,
        .Result = ?[]const TextEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = TextDocumentRegistrationOptions },
    },
    // Request to request completion at a given text document position. The request's
    // parameter is of type {@link TextDocumentPosition} the response
    // is of type {@link CompletionItem CompletionItem[]} or {@link CompletionList}
    // or a Thenable that resolves to such.
    //
    // The request can delay the computation of the {@link CompletionItem.detail `detail`}
    // and {@link CompletionItem.documentation `documentation`} properties to the `completionItem/resolve`
    // request. However, properties that are needed for the initial sorting and filtering, like `sortText`,
    // `filterText`, `insertText`, and `textEdit`, must not be changed during resolve.
    .{
        .method = "textDocument/completion",
        .documentation = "Request to request completion at a given text document position. The request's\nparameter is of type {@link TextDocumentPosition} the response\nis of type {@link CompletionItem CompletionItem[]} or {@link CompletionList}\nor a Thenable that resolves to such.\n\nThe request can delay the computation of the {@link CompletionItem.detail `detail`}\nand {@link CompletionItem.documentation `documentation`} properties to the `completionItem/resolve`\nrequest. However, properties that are needed for the initial sorting and filtering, like `sortText`,\n`filterText`, `insertText`, and `textEdit`, must not be changed during resolve.",
        .direction = .clientToServer,
        .Params = CompletionParams,
        .Result = ?union(enum) {
            array_of_CompletionItem: []const CompletionItem,
            CompletionList: CompletionList,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = []const CompletionItem,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = CompletionRegistrationOptions },
    },
    // Request to resolve additional information for a given completion item.The request's
    // parameter is of type {@link CompletionItem} the response
    // is of type {@link CompletionItem} or a Thenable that resolves to such.
    .{
        .method = "completionItem/resolve",
        .documentation = "Request to resolve additional information for a given completion item.The request's\nparameter is of type {@link CompletionItem} the response\nis of type {@link CompletionItem} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = CompletionItem,
        .Result = CompletionItem,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // Request to request hover information at a given text document position. The request's
    // parameter is of type {@link TextDocumentPosition} the response is of
    // type {@link Hover} or a Thenable that resolves to such.
    .{
        .method = "textDocument/hover",
        .documentation = "Request to request hover information at a given text document position. The request's\nparameter is of type {@link TextDocumentPosition} the response is of\ntype {@link Hover} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = HoverParams,
        .Result = ?Hover,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = HoverRegistrationOptions },
    },
    .{
        .method = "textDocument/signatureHelp",
        .documentation = null,
        .direction = .clientToServer,
        .Params = SignatureHelpParams,
        .Result = ?SignatureHelp,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = SignatureHelpRegistrationOptions },
    },
    // A request to resolve the definition location of a symbol at a given text
    // document position. The request's parameter is of type {@link TextDocumentPosition}
    // the response is of either type {@link Definition} or a typed array of
    // {@link DefinitionLink} or a Thenable that resolves to such.
    .{
        .method = "textDocument/definition",
        .documentation = "A request to resolve the definition location of a symbol at a given text\ndocument position. The request's parameter is of type {@link TextDocumentPosition}\nthe response is of either type {@link Definition} or a typed array of\n{@link DefinitionLink} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = DefinitionParams,
        .Result = ?union(enum) {
            Definition: Definition,
            array_of_DefinitionLink: []const DefinitionLink,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            array_of_Location: []const Location,
            array_of_DefinitionLink: []const DefinitionLink,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DefinitionRegistrationOptions },
    },
    // A request to resolve project-wide references for the symbol denoted
    // by the given text document position. The request's parameter is of
    // type {@link ReferenceParams} the response is of type
    // {@link Location Location[]} or a Thenable that resolves to such.
    .{
        .method = "textDocument/references",
        .documentation = "A request to resolve project-wide references for the symbol denoted\nby the given text document position. The request's parameter is of\ntype {@link ReferenceParams} the response is of type\n{@link Location Location[]} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = ReferenceParams,
        .Result = ?[]const Location,
        .PartialResult = []const Location,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = ReferenceRegistrationOptions },
    },
    // Request to resolve a {@link DocumentHighlight} for a given
    // text document position. The request's parameter is of type {@link TextDocumentPosition}
    // the request response is an array of type {@link DocumentHighlight}
    // or a Thenable that resolves to such.
    .{
        .method = "textDocument/documentHighlight",
        .documentation = "Request to resolve a {@link DocumentHighlight} for a given\ntext document position. The request's parameter is of type {@link TextDocumentPosition}\nthe request response is an array of type {@link DocumentHighlight}\nor a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = DocumentHighlightParams,
        .Result = ?[]const DocumentHighlight,
        .PartialResult = []const DocumentHighlight,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentHighlightRegistrationOptions },
    },
    // A request to list all symbols found in a given text document. The request's
    // parameter is of type {@link TextDocumentIdentifier} the
    // response is of type {@link SymbolInformation SymbolInformation[]} or a Thenable
    // that resolves to such.
    .{
        .method = "textDocument/documentSymbol",
        .documentation = "A request to list all symbols found in a given text document. The request's\nparameter is of type {@link TextDocumentIdentifier} the\nresponse is of type {@link SymbolInformation SymbolInformation[]} or a Thenable\nthat resolves to such.",
        .direction = .clientToServer,
        .Params = DocumentSymbolParams,
        .Result = ?union(enum) {
            array_of_SymbolInformation: []const SymbolInformation,
            array_of_DocumentSymbol: []const DocumentSymbol,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            array_of_SymbolInformation: []const SymbolInformation,
            array_of_DocumentSymbol: []const DocumentSymbol,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentSymbolRegistrationOptions },
    },
    // A request to provide commands for the given text document and range.
    .{
        .method = "textDocument/codeAction",
        .documentation = "A request to provide commands for the given text document and range.",
        .direction = .clientToServer,
        .Params = CodeActionParams,
        .Result = ?[]const union(enum) {
            Command: Command,
            CodeAction: CodeAction,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = []const union(enum) {
            Command: Command,
            CodeAction: CodeAction,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = CodeActionRegistrationOptions },
    },
    // Request to resolve additional information for a given code action.The request's
    // parameter is of type {@link CodeAction} the response
    // is of type {@link CodeAction} or a Thenable that resolves to such.
    .{
        .method = "codeAction/resolve",
        .documentation = "Request to resolve additional information for a given code action.The request's\nparameter is of type {@link CodeAction} the response\nis of type {@link CodeAction} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = CodeAction,
        .Result = CodeAction,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to list project-wide symbols matching the query string given
    // by the {@link WorkspaceSymbolParams}. The response is
    // of type {@link SymbolInformation SymbolInformation[]} or a Thenable that
    // resolves to such.
    //
    // @since 3.17.0 - support for WorkspaceSymbol in the returned data. Clients
    //  need to advertise support for WorkspaceSymbols via the client capability
    //  `workspace.symbol.resolveSupport`.
    //
    .{
        .method = "workspace/symbol",
        .documentation = "A request to list project-wide symbols matching the query string given\nby the {@link WorkspaceSymbolParams}. The response is\nof type {@link SymbolInformation SymbolInformation[]} or a Thenable that\nresolves to such.\n\n@since 3.17.0 - support for WorkspaceSymbol in the returned data. Clients\n need to advertise support for WorkspaceSymbols via the client capability\n `workspace.symbol.resolveSupport`.\n",
        .direction = .clientToServer,
        .Params = WorkspaceSymbolParams,
        .Result = ?union(enum) {
            array_of_SymbolInformation: []const SymbolInformation,
            array_of_WorkspaceSymbol: []const WorkspaceSymbol,
            pub usingnamespace UnionParser(@This());
        },
        .PartialResult = union(enum) {
            array_of_SymbolInformation: []const SymbolInformation,
            array_of_WorkspaceSymbol: []const WorkspaceSymbol,
            pub usingnamespace UnionParser(@This());
        },
        .ErrorData = null,
        .registration = .{ .method = null, .Options = WorkspaceSymbolRegistrationOptions },
    },
    // A request to resolve the range inside the workspace
    // symbol's location.
    //
    // @since 3.17.0
    .{
        .method = "workspaceSymbol/resolve",
        .documentation = "A request to resolve the range inside the workspace\nsymbol's location.\n\n@since 3.17.0",
        .direction = .clientToServer,
        .Params = WorkspaceSymbol,
        .Result = WorkspaceSymbol,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to provide code lens for the given text document.
    .{
        .method = "textDocument/codeLens",
        .documentation = "A request to provide code lens for the given text document.",
        .direction = .clientToServer,
        .Params = CodeLensParams,
        .Result = ?[]const CodeLens,
        .PartialResult = []const CodeLens,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = CodeLensRegistrationOptions },
    },
    // A request to resolve a command for a given code lens.
    .{
        .method = "codeLens/resolve",
        .documentation = "A request to resolve a command for a given code lens.",
        .direction = .clientToServer,
        .Params = CodeLens,
        .Result = CodeLens,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to refresh all code actions
    //
    // @since 3.16.0
    .{
        .method = "workspace/codeLens/refresh",
        .documentation = "A request to refresh all code actions\n\n@since 3.16.0",
        .direction = .serverToClient,
        .Params = null,
        .Result = ?void,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to provide document links
    .{
        .method = "textDocument/documentLink",
        .documentation = "A request to provide document links",
        .direction = .clientToServer,
        .Params = DocumentLinkParams,
        .Result = ?[]const DocumentLink,
        .PartialResult = []const DocumentLink,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentLinkRegistrationOptions },
    },
    // Request to resolve additional information for a given document link. The request's
    // parameter is of type {@link DocumentLink} the response
    // is of type {@link DocumentLink} or a Thenable that resolves to such.
    .{
        .method = "documentLink/resolve",
        .documentation = "Request to resolve additional information for a given document link. The request's\nparameter is of type {@link DocumentLink} the response\nis of type {@link DocumentLink} or a Thenable that resolves to such.",
        .direction = .clientToServer,
        .Params = DocumentLink,
        .Result = DocumentLink,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request to format a whole document.
    .{
        .method = "textDocument/formatting",
        .documentation = "A request to format a whole document.",
        .direction = .clientToServer,
        .Params = DocumentFormattingParams,
        .Result = ?[]const TextEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentFormattingRegistrationOptions },
    },
    // A request to format a range in a document.
    .{
        .method = "textDocument/rangeFormatting",
        .documentation = "A request to format a range in a document.",
        .direction = .clientToServer,
        .Params = DocumentRangeFormattingParams,
        .Result = ?[]const TextEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentRangeFormattingRegistrationOptions },
    },
    // A request to format ranges in a document.
    //
    // @since 3.18.0
    // @proposed
    .{
        .method = "textDocument/rangesFormatting",
        .documentation = "A request to format ranges in a document.\n\n@since 3.18.0\n@proposed",
        .direction = .clientToServer,
        .Params = DocumentRangesFormattingParams,
        .Result = ?[]const TextEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentRangeFormattingRegistrationOptions },
    },
    // A request to format a document on type.
    .{
        .method = "textDocument/onTypeFormatting",
        .documentation = "A request to format a document on type.",
        .direction = .clientToServer,
        .Params = DocumentOnTypeFormattingParams,
        .Result = ?[]const TextEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = DocumentOnTypeFormattingRegistrationOptions },
    },
    // A request to rename a symbol.
    .{
        .method = "textDocument/rename",
        .documentation = "A request to rename a symbol.",
        .direction = .clientToServer,
        .Params = RenameParams,
        .Result = ?WorkspaceEdit,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = RenameRegistrationOptions },
    },
    // A request to test and perform the setup necessary for a rename.
    //
    // @since 3.16 - support for default behavior
    .{
        .method = "textDocument/prepareRename",
        .documentation = "A request to test and perform the setup necessary for a rename.\n\n@since 3.16 - support for default behavior",
        .direction = .clientToServer,
        .Params = PrepareRenameParams,
        .Result = ?PrepareRenameResult,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
    // A request send from the client to the server to execute a command. The request might return
    // a workspace edit which the client will apply to the workspace.
    .{
        .method = "workspace/executeCommand",
        .documentation = "A request send from the client to the server to execute a command. The request might return\na workspace edit which the client will apply to the workspace.",
        .direction = .clientToServer,
        .Params = ExecuteCommandParams,
        .Result = ?LSPAny,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = ExecuteCommandRegistrationOptions },
    },
    // A request sent from the server to the client to modified certain resources.
    .{
        .method = "workspace/applyEdit",
        .documentation = "A request sent from the server to the client to modified certain resources.",
        .direction = .serverToClient,
        .Params = ApplyWorkspaceEditParams,
        .Result = ApplyWorkspaceEditResult,
        .PartialResult = null,
        .ErrorData = null,
        .registration = .{ .method = null, .Options = null },
    },
};
