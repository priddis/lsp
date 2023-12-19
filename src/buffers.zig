/// Manages open files
const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
pub extern "c" fn tree_sitter_java() *c.TSLanguage;

const Document = struct {
    name: []u8, 
    text: []u8,
    version: u64,
    tree: *c.TSTree,
};


pub fn openDocument(text: []u8) Document {
    const length: u32 = text.len;
    const parser = c.ts_parser_new();
    _ = c.ts_parser_set_language(parser, tree_sitter_java());
    const tree = c.ts_parser_parse_string_encoding(parser, null, text[0..length :0], length, .TSInputEncodingUTF8);
    _ = tree;
    return Document{ 
    };

    //const method_query = c.ts_query_new(tree_sitter_java(), query, query.len, &err_offset, &error_type);

}


test "method_rectrieval" {
    const array_list_code = @embedFile("testcode/ArrayList.java");
    openDocument(array_list_code);



}
