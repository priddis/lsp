const std = @import("std");
pub fn json() ![]u8 {
    const working_directory = try std.fs.path.relative(std.heap.page_allocator, "/", ".");
    const raw_json = std.mem.concat(std.heap.page_allocator, u8, &.{
        \\{
        \\    "jsonrpc":"2.0",
        \\    "method":"initialize",
        \\    "id":2,
        \\    "params":{
        \\        "processId":20558,
        \\        "workspaceFolders":[
        \\            {
        \\                "uri":"file:\/\/.",
        \\                "name":"
        ,
        working_directory,
        \\"
        \\            }
        \\        ],
        \\        "rootUri":"file:\/\/
        ,
        working_directory,
        \\",
        \\        "rootPath":"
        ,
        working_directory,
        \\",
        \\        "clientInfo":{
        \\            "name":"Neovim",
        \\            "version":"0.9.5"
        \\        },
        \\        "trace":"off",
        \\        "capabilities":{
        \\            "window":{
        \\                "showDocument":{
        \\                    "support":true
        \\                },
        \\                "workDoneProgress":true,
        \\                "showMessage":{
        \\                    "messageActionItem":{
        \\                        "additionalPropertiesSupport":false
        \\                    }
        \\                }
        \\            },
        \\            "textDocument":{
        \\                "callHierarchy":{
        \\                    "dynamicRegistration":false
        \\                },
        \\                "semanticTokens":{
        \\                    "dynamicRegistration":false,
        \\                    "formats":[
        \\                        "relative"
        \\                    ],
        \\                    "tokenModifiers":[
        \\                        "declaration",
        \\                        "definition",
        \\                        "readonly",
        \\                        "static",
        \\                        "deprecated",
        \\                        "abstract",
        \\                        "async",
        \\                        "modification",
        \\                        "documentation",
        \\                        "defaultLibrary"
        \\                    ],
        \\                    "requests":{
        \\                        "full":{
        \\                            "delta":true
        \\                        },
        \\                        "range":false
        \\                    },
        \\                    "serverCancelSupport":false,
        \\                    "augmentsSyntaxTokens":true,
        \\                    "tokenTypes":[
        \\                        "namespace",
        \\                        "type",
        \\                        "class",
        \\                        "enum",
        \\                        "interface",
        \\                        "struct",
        \\                        "typeParameter",
        \\                        "parameter",
        \\                        "variable",
        \\                        "property",
        \\                        "enumMember",
        \\                        "event",
        \\                        "function",
        \\                        "method",
        \\                        "macro",
        \\                        "keyword",
        \\                        "modifier",
        \\                        "comment",
        \\                        "string",
        \\                        "number",
        \\                        "regexp",
        \\                        "operator",
        \\                        "decorator"
        \\                    ],
        \\                    "multilineTokenSupport":false,
        \\                    "overlappingTokenSupport":true
        \\                },
        \\                "declaration":{
        \\                    "linkSupport":true
        \\                },
        \\                "signatureHelp":{
        \\                    "signatureInformation":{
        \\                        "parameterInformation":{
        \\                            "labelOffsetSupport":true
        \\                        },
        \\                        "documentationFormat":[
        \\                            "markdown",
        \\                            "plaintext"
        \\                        ],
        \\                        "activeParameterSupport":true
        \\                    },
        \\                    "dynamicRegistration":false
        \\                },
        \\                "documentHighlight":{
        \\                    "dynamicRegistration":false
        \\                },
        \\                "implementation":{
        \\                    "linkSupport":true
        \\                },
        \\                "rename":{
        \\                    "dynamicRegistration":false,
        \\                    "prepareSupport":true
        \\                },
        \\                "codeAction":{
        \\                    "resolveSupport":{
        \\                        "properties":[
        \\                            "edit"
        \\                        ]
        \\                    },
        \\                    "dynamicRegistration":false,
        \\                    "codeActionLiteralSupport":{
        \\                        "codeActionKind":{
        \\                            "valueSet":[
        \\                                "",
        \\                                "quickfix",
        \\                                "refactor",
        \\                                "refactor.extract",
        \\                                "refactor.inline",
        \\                                "refactor.rewrite",
        \\                                "source",
        \\                                "source.organizeImports"
        \\                            ]
        \\                        }
        \\                    },
        \\                    "dataSupport":true,
        \\                    "isPreferredSupport":true
        \\                },
        \\                "synchronization":{
        \\                    "didSave":true,
        \\                    "willSave":true,
        \\                    "dynamicRegistration":false,
        \\                    "willSaveWaitUntil":true
        \\                },
        \\                "typeDefinition":{
        \\                    "linkSupport":true
        \\                },
        \\                "publishDiagnostics":{
        \\                    "relatedInformation":true,
        \\                    "tagSupport":{
        \\                        "valueSet":[
        \\                            1,
        \\                            2
        \\                        ]
        \\                    }
        \\                },
        \\                "completion":{
        \\                    "completionItemKind":{
        \\                        "valueSet":[
        \\                            1,
        \\                            2,
        \\                            3,
        \\                            4,
        \\                            5,
        \\                            6,
        \\                            7,
        \\                            8,
        \\                            9,
        \\                            10,
        \\                            11,
        \\                            12,
        \\                            13,
        \\                            14,
        \\                            15,
        \\                            16,
        \\                            17,
        \\                            18,
        \\                            19,
        \\                            20,
        \\                            21,
        \\                            22,
        \\                            23,
        \\                            24,
        \\                            25
        \\                        ]
        \\                    },
        \\                    "dynamicRegistration":false,
        \\                    "contextSupport":false,
        \\                    "completionItem":{
        \\                        "deprecatedSupport":false,
        \\                        "preselectSupport":false,
        \\                        "commitCharactersSupport":false,
        \\                        "snippetSupport":false,
        \\                        "documentationFormat":[
        \\                            "markdown",
        \\                            "plaintext"
        \\                        ]
        \\                    }
        \\                },
        \\                "references":{
        \\                    "dynamicRegistration":false
        \\                },
        \\                "hover":{
        \\                    "contentFormat":[
        \\                        "markdown",
        \\                        "plaintext"
        \\                    ],
        \\                    "dynamicRegistration":false
        \\                },
        \\                "documentSymbol":{
        \\                    "hierarchicalDocumentSymbolSupport":true,
        \\                    "dynamicRegistration":false,
        \\                    "symbolKind":{
        \\                        "valueSet":[
        \\                            1,
        \\                            2,
        \\                            3,
        \\                            4,
        \\                            5,
        \\                            6,
        \\                            7,
        \\                            8,
        \\                            9,
        \\                            10,
        \\                            11,
        \\                            12,
        \\                            13,
        \\                            14,
        \\                            15,
        \\                            16,
        \\                            17,
        \\                            18,
        \\                            19,
        \\                            20,
        \\                            21,
        \\                            22,
        \\                            23,
        \\                            24,
        \\                            25,
        \\                            26
        \\                        ]
        \\                    }
        \\                },
        \\                "definition":{
        \\                    "linkSupport":true
        \\                }
        \\            },
        \\            "workspace":{
        \\                "workspaceFolders":true,
        \\                "didChangeWatchedFiles":{
        \\                    "relativePatternSupport":true,
        \\                    "dynamicRegistration":false
        \\                },
        \\                "workspaceEdit":{
        \\                    "resourceOperations":[
        \\                        "rename",
        \\                        "create",
        \\                        "delete"
        \\                    ]
        \\                },
        \\                "semanticTokens":{
        \\                    "refreshSupport":true
        \\                },
        \\                "applyEdit":true,
        \\                "configuration":true,
        \\                "symbol":{
        \\                    "hierarchicalWorkspaceSymbolSupport":true,
        \\                    "dynamicRegistration":false,
        \\                    "symbolKind":{
        \\                        "valueSet":[
        \\                            1,
        \\                            2,
        \\                            3,
        \\                            4,
        \\                            5,
        \\                            6,
        \\                            7,
        \\                            8,
        \\                            9,
        \\                            10,
        \\                            11,
        \\                            12,
        \\                            13,
        \\                            14,
        \\                            15,
        \\                            16,
        \\                            17,
        \\                            18,
        \\                            19,
        \\                            20,
        \\                            21,
        \\                            22,
        \\                            23,
        \\                            24,
        \\                            25,
        \\                            26
        \\                        ]
        \\                    }
        \\                }
        \\            }
        \\        }
        \\    }
        \\
        \\}
    });
    return raw_json;
}