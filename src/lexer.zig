const lexer = @import("lexer");

pub const Diagnostics = lexer.Diagnostics;
pub const Lexer = lexer.Lexer(.{
    .comment = .{ .pattern = "//([^\n])*" },

    // operators
    .division = .{ .pattern = "/" },
    .plus = .{ .pattern = "\\+" },

    // punctuation
    .equal = .{ .pattern = "=" },
    .left_paren = .{ .pattern = "\\(" },
    .right_paren = .{ .pattern = "\\)" },
    .colon = .{ .pattern = ":" },
    .comma = .{ .pattern = "," },
    .period = .{ .pattern = "." },
    .left_brace = .{ .pattern = "{" },
    .right_brace = .{ .pattern = "}" },
    .left_bracket = .{ .pattern = "\\[" },
    .right_bracket = .{ .pattern = "\\]" },
    .semicolon = .{ .pattern = ";" },

    // keywords
    .service = .{ .pattern = "service" },
    .true = .{ .pattern = "true" },
    .false = .{ .pattern = "false" },

    // literal values
    .string = .{ .pattern = "\"([^\"]|\\\\\")*\"" },

    // misc
    .newline = .{ .pattern = "(\n|\r\n)", .skip = true },
    .space = .{ .pattern = " ", .skip = true },

    // special values
    .ident = .{ .pattern = "\\w\\W*" },
});

pub const Token = Lexer.Token;
pub const TokenType = Lexer.TokenType;
