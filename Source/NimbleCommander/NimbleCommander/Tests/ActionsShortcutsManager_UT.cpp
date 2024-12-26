// Copyright (C) 2024 Michael Kazakov. Subject to GNU General Public License version 3.
#include "Tests.h"
#include <NimbleCommander/Core/ActionsShortcutsManager.h>
#include <Config/ConfigImpl.h>
#include <Config/NonPersistentOverwritesStorage.h>

using Catch::Matchers::UnorderedEquals;
using ASM = nc::core::ActionsShortcutsManager;
using AS = ASM::ShortCut;
using ASs = ASM::ShortCuts;

#define PREFIX "nc::core::ActionsShortcutsManager "

static const auto g_EmptyConfigJSON = R"({
    "hotkeyOverrides_v1": {}
})";

TEST_CASE(PREFIX "TagFromAction")
{
    CHECK(ASM::TagFromAction("menu.edit.copy") == 12'000);          // Valid query
    CHECK(ASM::TagFromAction("menu.i.dont.exist") == std::nullopt); // Invalid query
}

TEST_CASE(PREFIX "ActionFromTag")
{
    CHECK(ASM::ActionFromTag(12'000) == "menu.edit.copy"); // Valid query
    CHECK(ASM::ActionFromTag(346'242) == std::nullopt);    // Invalid query
}

TEST_CASE(PREFIX "ShortCutFromAction")
{
    nc::config::ConfigImpl config{g_EmptyConfigJSON, std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    ASM manager{config};

    SECTION("Non-existent")
    {
        REQUIRE(manager.ShortCutFromAction("menu.i.dont.exist") == std::nullopt);
    }
    SECTION("Default value")
    {
        REQUIRE(manager.ShortCutFromAction("menu.edit.copy") == ASs{AS("⌘c")});
    }
    SECTION("Override with a single shortcut")
    {
        REQUIRE(manager.SetShortCutOverride("menu.edit.copy", AS("⌘j")));
        REQUIRE(manager.ShortCutFromAction("menu.edit.copy") == ASs{AS("⌘j")});
    }
    SECTION("Override with an empty shortcut")
    {
        REQUIRE(manager.SetShortCutOverride("menu.edit.copy", AS()));
        REQUIRE(manager.ShortCutFromAction("menu.edit.copy") == ASs{});
    }
    SECTION("Override with two shortcuts")
    {
        REQUIRE(manager.SetShortCutsOverride("menu.edit.copy", std::array{AS("⌘j"), AS("⌘k")}));
        REQUIRE(manager.ShortCutFromAction("menu.edit.copy") == ASs{AS("⌘j"), AS("⌘k")});
    }
    SECTION("Override with two shortcuts and some empty bogus ones")
    {
        REQUIRE(manager.SetShortCutsOverride("menu.edit.copy", std::array{AS(), AS("⌘j"), AS(), AS("⌘k"), AS()}));
        REQUIRE(manager.ShortCutFromAction("menu.edit.copy") == ASs{AS("⌘j"), AS("⌘k")});
    }
}

TEST_CASE(PREFIX "ShortCutFromTag")
{
    nc::config::ConfigImpl config{g_EmptyConfigJSON, std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    ASM manager{config};

    REQUIRE(manager.ShortCutFromTag(346'242) == std::nullopt);
    REQUIRE(manager.ShortCutFromTag(12'000) == ASs{AS("⌘c")});
    REQUIRE(manager.SetShortCutOverride("menu.edit.copy", AS("⌘j")));
    REQUIRE(manager.ShortCutFromTag(12'000) == ASs{AS("⌘j")});
}

TEST_CASE(PREFIX "DefaultShortCutFromTag")
{
    nc::config::ConfigImpl config{g_EmptyConfigJSON, std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    ASM manager{config};

    REQUIRE(manager.DefaultShortCutFromTag(346'242) == std::nullopt);
    REQUIRE(manager.DefaultShortCutFromTag(12'000) == ASs{AS("⌘c")});
    REQUIRE(manager.SetShortCutOverride("menu.edit.copy", AS("⌘j")));
    REQUIRE(manager.DefaultShortCutFromTag(12'000) == ASs{AS("⌘c")});
}

TEST_CASE(PREFIX "RevertToDefaults")
{
    nc::config::ConfigImpl config{g_EmptyConfigJSON, std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    ASM manager{config};

    REQUIRE(manager.SetShortCutOverride("menu.edit.copy", AS("⌘j")));
    manager.RevertToDefaults();
    REQUIRE(manager.ShortCutFromAction("menu.edit.copy") == ASs{AS("⌘c")});
}

TEST_CASE(PREFIX "ActionTagsFromShortCut")
{
    nc::config::ConfigImpl config{g_EmptyConfigJSON, std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    ASM manager{config};

    SECTION("Non-existent shortcut")
    {
        REQUIRE(manager.ActionTagsFromShortCut(AS("⇧^⌘⌥j")) == std::nullopt);
    }
    SECTION("Non-existent shortcut when a domain is specified")
    {
        REQUIRE(manager.ActionTagsFromShortCut(AS("⇧^⌘⌥j"), "this.domain.doesnt.exist.") == std::nullopt);
    }
    SECTION("Existent shortcut, but a domain doesn't match")
    {
        REQUIRE(manager.ActionTagsFromShortCut(AS("⌘1"), "this.domain.doesnt.exist.") == std::nullopt);
    }
    SECTION("Shortcut used by two actions in different domains")
    {
        auto tags = manager.ActionTagsFromShortCut(AS("⌘1"));
        REQUIRE(tags);
        REQUIRE(std::set<int>(tags->begin(), tags->end()) ==
                std::set<int>{ASM::TagFromAction("menu.go.quick_lists.parent_folders").value(),
                              ASM::TagFromAction("viewer.toggle_text").value()});
    }
    SECTION("Shortcut used by two actions in different domains, specify first")
    {
        REQUIRE(manager.ActionTagsFromShortCut(AS("⌘1"), "menu.") ==
                ASM::ActionTags{ASM::TagFromAction("menu.go.quick_lists.parent_folders").value()});
    }
    SECTION("Shortcut used by two actions in different domains, specify second")
    {
        REQUIRE(manager.ActionTagsFromShortCut(AS("⌘1"), "viewer.") ==
                ASM::ActionTags{ASM::TagFromAction("viewer.toggle_text").value()});
    }
    SECTION("Shortcut is used by by two actions by default and one via override")
    {
        REQUIRE(manager.SetShortCutOverride("menu.window.zoom", AS("⌘1")));
        auto tags = manager.ActionTagsFromShortCut(AS("⌘1"));
        REQUIRE(tags);
        REQUIRE(std::set<int>(tags->begin(), tags->end()) ==
                std::set<int>{
                    ASM::TagFromAction("menu.go.quick_lists.parent_folders").value(),
                    ASM::TagFromAction("viewer.toggle_text").value(),
                    ASM::TagFromAction("menu.window.zoom").value(),
                });
    }
    SECTION("Shortcut is used by by two actions by default and one via override (multiple shortcuts)")
    {
        REQUIRE(manager.SetShortCutsOverride("menu.window.zoom", std::array{AS("⇧^⌘⌥j"), AS("⌘1")}));
        auto tags = manager.ActionTagsFromShortCut(AS("⌘1"));
        REQUIRE(tags);
        REQUIRE(std::set<int>(tags->begin(), tags->end()) ==
                std::set<int>{
                    ASM::TagFromAction("menu.go.quick_lists.parent_folders").value(),
                    ASM::TagFromAction("viewer.toggle_text").value(),
                    ASM::TagFromAction("menu.window.zoom").value(),
                });
    }
    SECTION("After setting and removing the override its not reported as being used")
    {
        REQUIRE(manager.SetShortCutsOverride("menu.window.zoom", std::array{AS("⇧^⌘⌥k"), AS("⇧^⌘⌥j")}));
        REQUIRE(manager.SetShortCutsOverride("menu.window.zoom", {}));
        REQUIRE(manager.ActionTagsFromShortCut(AS("⇧^⌘⌥k")) == std::nullopt);
        REQUIRE(manager.ActionTagsFromShortCut(AS("⇧^⌘⌥j")) == std::nullopt);
    }
}

TEST_CASE(PREFIX "FirstOfActionTagsFromShortCut")
{
    nc::config::ConfigImpl config{g_EmptyConfigJSON, std::make_shared<nc::config::NonPersistentOverwritesStorage>("")};
    ASM manager{config};
    REQUIRE(manager.FirstOfActionTagsFromShortCut({}, AS("⌘1")) == std::nullopt);
    REQUIRE(manager.FirstOfActionTagsFromShortCut(std::initializer_list<int>{346'242}, AS("⌘1")) == std::nullopt);
    REQUIRE(manager.FirstOfActionTagsFromShortCut(
                std::initializer_list<int>{ASM::TagFromAction("menu.go.quick_lists.parent_folders").value()},
                AS("⌘1")) == ASM::TagFromAction("menu.go.quick_lists.parent_folders").value());
    REQUIRE(manager.FirstOfActionTagsFromShortCut(
                std::initializer_list<int>{ASM::TagFromAction("menu.go.quick_lists.parent_folders").value()},
                AS("⌘1"),
                "menu.") == ASM::TagFromAction("menu.go.quick_lists.parent_folders").value());

    REQUIRE(manager.FirstOfActionTagsFromShortCut(
                std::initializer_list<int>{ASM::TagFromAction("menu.go.quick_lists.parent_folders").value()},
                AS("⌘1"),
                "viewer.") == std::nullopt);

    REQUIRE(manager.FirstOfActionTagsFromShortCut(
                std::initializer_list<int>{ASM::TagFromAction("viewer.toggle_text").value()}, AS("⌘1")) ==
            ASM::TagFromAction("viewer.toggle_text").value());

    REQUIRE(manager.FirstOfActionTagsFromShortCut(
                std::initializer_list<int>{ASM::TagFromAction("viewer.toggle_text").value()}, AS("⌘1"), "menu.") ==
            std::nullopt);
    REQUIRE(manager.FirstOfActionTagsFromShortCut(
                std::initializer_list<int>{ASM::TagFromAction("viewer.toggle_text").value()}, AS("⌘1"), "viewer.") ==
            ASM::TagFromAction("viewer.toggle_text").value());
}

// TODO: unit tests for overrides persistence. include both variants of overrides.
