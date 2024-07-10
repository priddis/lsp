pub const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const List = .{ MethodDeclarationQuery, LocalVariable, MethodInvocationQuery, ImportQuery, IdentifierQuery };

pub const MethodDeclarationQuery = struct {
    pub const query_text = "(method_declaration) @_method_declaration_";
    pub var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const LocalVariable = struct {
    pub const query_text = "(local_variable_declaration) @_local_variable_declaration_";
    pub var query: *c.TSQuery = undefined;
    pub fn Query() *c.TSQuery {
        return query;
    }
};

pub const MethodInvocationQuery = struct {
    pub const query_text = "(method_invocation) @_method_invocation_";
    pub var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const ImportQuery = struct {
    pub const query_text = "(import_declaration (scoped_identifier) @import)";
    pub var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const IdentifierQuery = struct {
    pub const query_text = "(identifier) @_identifier_";
    pub var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};
