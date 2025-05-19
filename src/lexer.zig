const lexer = @import("lexer");

pub const Diagnostics = lexer.Diagnostics;
pub const Lexer = lexer.Lexer(.{
    .comment = .{ .pattern = "//([^\n])*" },

    // punctuation
    .equal = .{ .pattern = "=" },
    .left_paren = .{ .pattern = "\\(" },
    .right_paren = .{ .pattern = "\\)" },
    .left_brace = .{ .pattern = "{" },
    .right_brace = .{ .pattern = "}" },
    .semicolon = .{ .pattern = ";" },

    // literal values
    .string = .{ .pattern = "\"([^\"]|\\\\\")*\"" },

    // misc
    .newline = .{ .pattern = "(\n|\r\n)", .skip = true },
    .space = .{ .pattern = " ", .skip = true },

    // special values
    .ident = .{ .pattern = "\\w\\W*" },
    .number = .{ .pattern = "-?\\0+" },
});

pub const Token = Lexer.Token;
pub const TokenType = Lexer.TokenType;
