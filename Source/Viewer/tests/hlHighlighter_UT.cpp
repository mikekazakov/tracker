// Copyright (C) 2024 Michael Kazakov. Subject to GNU General Public License version 3.
#include "Tests.h"
#include "Highlighting/Highlighter.h"
#include <lexilla/SciLexer.h>
#include <robin_hood.h>

using namespace nc::viewer::hl;

#define PREFIX "hl::Highlighter "

[[clang::no_destroy]] static const robin_hood::unordered_flat_map<char, Style> m{
    {'D', Style::Default},
    {'C', Style::Comment},
    {'W', Style::Keyword},
    {'P', Style::Preprocessor},
    {'N', Style::Number},
    {'O', Style::Operator},
    {'I', Style::Identifier},
    {'S', Style::String},
};

TEST_CASE(PREFIX "Regular use with C++ lexer")
{
    LexerSettings set;
    set.name = "cpp";
    set.wordlists.push_back("int");
    set.mapping.SetMapping(SCE_C_DEFAULT, Style::Default);
    set.mapping.SetMapping(SCE_C_COMMENT, Style::Comment);
    set.mapping.SetMapping(SCE_C_COMMENTLINE, Style::Comment);
    set.mapping.SetMapping(SCE_C_WORD, Style::Keyword);
    set.mapping.SetMapping(SCE_C_PREPROCESSOR, Style::Preprocessor);
    set.mapping.SetMapping(SCE_C_NUMBER, Style::Number);
    set.mapping.SetMapping(SCE_C_OPERATOR, Style::Operator);
    set.mapping.SetMapping(SCE_C_IDENTIFIER, Style::Identifier);
    set.mapping.SetMapping(SCE_C_STRING, Style::String);

    const std::string src =
        R"(#pragma once
/*Hey!*/
int hello = 10;)";
    const std::string hl_exp = "PPPPPPPPPPPPP"
                               "CCCCCCCCD"
                               "WWWDIIIIIDODNNO";

    REQUIRE(src.length() == hl_exp.length());

    Highlighter highlighter(set);
    std::vector<Style> hl = highlighter.Highlight(src);
    REQUIRE(hl.size() == hl_exp.size());

    for( size_t i = 0; i < hl.size(); ++i ) {
        CHECK(hl[i] == m.at(hl_exp[i]));
    }
}

TEST_CASE(PREFIX "Regular use with YAML lexer")
{
    LexerSettings set;
    set.name = "yaml";
    set.mapping.SetMapping(SCE_YAML_DEFAULT, Style::Default);
    set.mapping.SetMapping(SCE_YAML_COMMENT, Style::Comment);
    set.mapping.SetMapping(SCE_YAML_KEYWORD, Style::Keyword);
    set.mapping.SetMapping(SCE_YAML_NUMBER, Style::Number);
    set.mapping.SetMapping(SCE_YAML_REFERENCE, Style::Identifier);
    set.mapping.SetMapping(SCE_YAML_DOCUMENT, Style::Identifier);
    set.mapping.SetMapping(SCE_YAML_OPERATOR, Style::Operator);
    set.mapping.SetMapping(SCE_YAML_IDENTIFIER, Style::Identifier);
    set.mapping.SetMapping(SCE_YAML_TEXT, Style::String);

    const std::string src =
        R"(name: Build and Test #Hey!
on:
  push:
    paths-ignore:
      - '.github/ISSUE_TEMPLATE/**')";

    const std::string hl_exp = "IIIIODDDDDDDDDDDDDDDDCCCCCC"
                               "IIOD"
                               "IIIIIIOD"
                               "IIIIIIIIIIIIIIIIOD"
                               "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD";

    REQUIRE(src.length() == hl_exp.length());

    Highlighter highlighter(set);
    std::vector<Style> hl = highlighter.Highlight(src);
    REQUIRE(hl.size() == hl_exp.size());

    for( size_t i = 0; i < hl.size(); ++i ) {
        CHECK(hl[i] == m.at(hl_exp[i]));
    }
}
