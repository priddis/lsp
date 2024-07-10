pub const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const MethodDeclaration = struct {
    const query_text = "(method_declaration) @_method_declaration_";
    var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const LocalVariable = struct {
    const query_text = "(local_variable_declaration) @_local_variable_declaration_";
    var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const MethodInvocation = struct {
    const query_text = "(method_invocation) @_method_invocation_";
    var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const Import = struct {
    const query_text = "(import_declaration (scoped_identifier) @import)";
    var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};

pub const Identifier = struct {
    const query_text = "(identifier) @_identifier_";
    var query: *c.TSQuery = undefined;
    fn Query() *c.TSQuery {
        return query;
    }
};
