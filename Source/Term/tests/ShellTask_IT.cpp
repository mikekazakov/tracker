// Copyright (C) 2014-2024 Michael Kazakov. Subject to GNU General Public License version 3.

#include "Tests.h"
#include "AtomicHolder.h"

#include <Base/CommonPaths.h>
#include <Base/dispatch_cpp.h>
#include <Base/mach_time.h>
#include <InterpreterImpl.h>
#include <ParserImpl.h>
#include <Screen.h>
#include <ShellTask.h>
#include <Utility/SystemInformation.h>
#include <algorithm>
#include <fmt/format.h>
#include <fmt/std.h>
#include <fstream>
#include <libproc.h>
#include <magic_enum.hpp>
#include <numeric>
#include <sys/param.h>
#include <sys/proc_info.h>
#include <unordered_map>

#pragma clang diagnostic ignored "-Wframe-larger-than="

using namespace nc;
using namespace nc::term;
using nc::base::CommonPaths;
using TaskState = ShellTask::TaskState;
using namespace std::chrono_literals;
#define PREFIX "nc::term::ShellTask "

[[maybe_unused]] static std::string RightPad(std::string _input, size_t _to, char _with = ' ')
{
    if( _input.size() < _to )
        _input.append(_to - _input.size(), _with);
    return _input;
}

static bool WaitChildrenListToBecome(const ShellTask &_shell,
                                     const std::vector<std::string> &_expected,
                                     std::chrono::nanoseconds _deadline,
                                     std::chrono::nanoseconds _poll_period)
{
    const auto deadline = nc::base::machtime() + _deadline;
    while( true ) {
        const auto list = _shell.ChildrenList();
        if( list == _expected )
            return true;
        if( nc::base::machtime() >= deadline )
            return false;
        std::this_thread::sleep_for(_poll_period);
    }
}

static bool WaitUntilProcessDies(int _pid, std::chrono::nanoseconds _deadline, std::chrono::nanoseconds _poll_period)
{
    const auto deadline = nc::base::machtime() + _deadline;
    while( true ) {
        const bool dead = kill(_pid, 0) < 0;
        if( dead && errno == ESRCH )
            return true;
        if( nc::base::machtime() >= deadline )
            return false;
        std::this_thread::sleep_for(_poll_period);
    }
}

// get all fs files, pipes and sockets
static std::vector<int> GetAllFileDescriptors()
{
    // TODO: move this to nc::base and cover with tests
    const int pid = getpid();
    const int buffer_size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nullptr, 0);
    if( buffer_size == -1 ) {
        abort();
    }

    std::vector<proc_fdinfo> fdinfos(buffer_size / sizeof(proc_fdinfo));

    const int rc =
        proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fdinfos.data(), static_cast<int>(fdinfos.size() * sizeof(proc_fdinfo)));
    if( rc < 0 )
        abort();

    std::vector<int> res;
    for( auto &info : fdinfos )
        if( info.proc_fdtype == PROX_FDTYPE_VNODE || info.proc_fdtype == PROX_FDTYPE_PIPE ||
            info.proc_fdtype == PROX_FDTYPE_SOCKET )
            res.emplace_back(info.proc_fd);

    std::ranges::sort(res);

    return res;
}

TEST_CASE(PREFIX "Inactive -> Shell -> Terminate - Inactive")
{
    ShellTask shell;
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    QueuedAtomicHolder<ShellTask::TaskState> shell_state(shell.State());
    REQUIRE(shell.State() == TaskState::Inactive);

    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });

    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    const int pid = shell.ShellPID();
    REQUIRE(pid >= 0);

    shell.Terminate();
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Inactive));
    REQUIRE(WaitUntilProcessDies(pid, 5s, 1ms));
}

TEST_CASE(PREFIX "Inactive -> Shell -> ProgramInternal (exit) -> Dead -> Inactive")
{
    QueuedAtomicHolder<ShellTask::TaskState> shell_state(ShellTask::TaskState::Inactive);
    ShellTask shell;
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
    REQUIRE(shell.State() == TaskState::Inactive);
    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    shell.WriteChildInput("exit\r");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramInternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Dead));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Inactive));
}

TEST_CASE(PREFIX "Inactive -> Shell -> ProgramInternal (vi) -> Shell -> Terminate -> Inactive")
{
    ShellTask shell;
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    QueuedAtomicHolder<ShellTask::TaskState> shell_state(shell.State());
    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
    REQUIRE(shell.State() == TaskState::Inactive);
    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    shell.WriteChildInput("vi\r");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramInternal));
    shell.WriteChildInput(":q\r");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    shell.Terminate();
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Inactive));
}

TEST_CASE(PREFIX "Inactive -> Shell -> ProgramExternal (vi) -> Shell -> Terminate -> Inactive")
{
    ShellTask shell;
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    QueuedAtomicHolder<ShellTask::TaskState> shell_state(shell.State());
    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
    REQUIRE(shell.State() == TaskState::Inactive);
    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    shell.ExecuteWithFullPath("/usr/bin/vi", nullptr);
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    shell.WriteChildInput(":q\r");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    shell.Terminate();
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Inactive));
}

TEST_CASE(PREFIX "Launch=>Exit via output (Bash)")
{
    AtomicHolder<std::string> buffer_dump;
    Screen screen(20, 3);
    ParserImpl parser;
    InterpreterImpl interpreter(screen);

    ShellTask shell;
    shell.ResizeWindow(20, 3);
    SECTION("bash")
    {
        shell.SetShellPath("/bin/bash");
        shell.SetEnvVar("PS1", "Hello=>");
        shell.AddCustomShellArgument("bash");
    }
    SECTION("zsh")
    {
        shell.SetShellPath("/bin/zsh");
        shell.SetEnvVar("PS1", "Hello=>");
        shell.AddCustomShellArgument("zsh");
        shell.AddCustomShellArgument("-f");
    }
    SECTION("csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    SECTION("tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    const auto type = shell.GetShellType();
    shell.SetOnChildOutput([&](const void *_d, int _sz) {
        if( auto cmds = parser.Parse({reinterpret_cast<const std::byte *>(_d), static_cast<size_t>(_sz)});
            !cmds.empty() ) {
            if( auto lock = screen.AcquireLock() ) {
                interpreter.Interpret(cmds);
                buffer_dump.store(screen.Buffer().DumpScreenAsANSI());
            }
        }
    });
    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));

    if( type == ShellTask::ShellType::TCSH ) {
        shell.WriteChildInput("set prompt='Hello=>'\rclear\r");
    }

    const std::string expected = "Hello=>             "
                                 "                    "
                                 "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected));

    shell.WriteChildInput("exit\r");
    std::unordered_map<ShellTask::ShellType, std::string> expected2;
    expected2[ShellTask::ShellType::Bash] = "Hello=>exit         "
                                            "exit                "
                                            "                    ";
    expected2[ShellTask::ShellType::TCSH] = expected2[ShellTask::ShellType::Bash];
    expected2[ShellTask::ShellType::ZSH] = "Hello=>exit         "
                                           "                    "
                                           "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected2[type]));
}

TEST_CASE(PREFIX "ChDir(), verify via output and cwd prompt (Bash)")
{
    const TempTestDir dir;
    const auto dir2 = dir.directory / "Therion" / "";
    const auto dir3 = dir.directory / "Blackmore's Night" / "";
    const auto dir4 = dir.directory / U"Сектор Газа" / "";
    const auto dir5 = dir.directory / U"😀🍻" / "";
    for( const auto &d : {dir2, dir3, dir4, dir5} )
        std::filesystem::create_directory(d);

    AtomicHolder<std::string> buffer_dump;
    AtomicHolder<std::filesystem::path> cwd;
    Screen screen(20, 5);
    ParserImpl parser;
    InterpreterImpl interpreter(screen);

    ShellTask shell;
    shell.ResizeWindow(20, 5);
    SECTION("bash")
    {
        shell.SetShellPath("/bin/bash");
        shell.SetEnvVar("PS1", ">");
        shell.AddCustomShellArgument("bash");
    }
    SECTION("zsh")
    {
        shell.SetShellPath("/bin/zsh");
        shell.SetEnvVar("PS1", ">");
        shell.AddCustomShellArgument("zsh");
        shell.AddCustomShellArgument("-f");
    }
    SECTION("csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    SECTION("tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    const auto type = shell.GetShellType();
    shell.SetOnChildOutput([&](const void *_d, int _sz) {
        if( auto cmds = parser.Parse({reinterpret_cast<const std::byte *>(_d), static_cast<size_t>(_sz)});
            !cmds.empty() ) {
            if( auto lock = screen.AcquireLock() ) {
                interpreter.Interpret(cmds);
                buffer_dump.store(screen.Buffer().DumpScreenAsANSI());
            }
        }
    });
    shell.SetOnPwdPrompt([&](const char *_cwd, bool) { cwd.store(_cwd); });
    REQUIRE(shell.Launch(dir.directory));

    if( type == ShellTask::ShellType::TCSH ) {
        shell.WriteChildInput("set prompt='>'\rclear\r");
    }

    const std::string expected1 = ">                   "
                                  "                    "
                                  "                    "
                                  "                    "
                                  "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected1));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));

    shell.ChDir(dir2);
    const std::string expected2 = ">                   "
                                  ">                   "
                                  "                    "
                                  "                    "
                                  "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected2));
    REQUIRE(cwd.wait_to_become(5s, dir2));

    shell.ChDir(dir3);
    const std::string expected3 = ">                   "
                                  ">                   "
                                  ">                   "
                                  "                    "
                                  "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected3));
    REQUIRE(cwd.wait_to_become(5s, dir3));

    shell.ChDir(dir4);
    const std::string expected4 = ">                   "
                                  ">                   "
                                  ">                   "
                                  ">                   "
                                  "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected4));
    REQUIRE(cwd.wait_to_become(5s, dir4));

    shell.ChDir(dir5);
    const std::string expected5 = ">                   "
                                  ">                   "
                                  ">                   "
                                  ">                   "
                                  ">                   ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected5));
    REQUIRE(cwd.wait_to_become(5s, dir5));
}

TEST_CASE(PREFIX "Launch an invalid shell")
{
    SECTION("Looks like Bash")
    {
        ShellTask shell;
        shell.SetShellPath("/bin/blah/bash");
        CHECK(shell.Launch(CommonPaths::AppTemporaryDirectory()) == false);
        CHECK(shell.State() == ShellTask::TaskState::Inactive);
    }
    SECTION("Just nonsense")
    {
        ShellTask shell;
        shell.SetShellPath("/blah/blah/blah");
        CHECK(shell.Launch(CommonPaths::AppTemporaryDirectory()) == false);
        CHECK(shell.State() == ShellTask::TaskState::Inactive);
    }
}

TEST_CASE(PREFIX "CWD prompt response")
{
    const TempTestDir dir;
    AtomicHolder<ShellTask::TaskState> shell_state;
    ShellTask shell;
    shell_state.value = shell.State();
    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
    AtomicHolder<std::filesystem::path> cwd;
    shell.SetOnPwdPrompt([&](const char *_cwd, bool) { cwd.store(_cwd); });
    REQUIRE(shell.State() == TaskState::Inactive);
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    REQUIRE(shell.Launch(dir.directory));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));

    const char *new_dir1 = "foo";
    shell.ExecuteWithFullPath("/bin/mkdir", new_dir1);
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));
    shell.ExecuteWithFullPath("cd", new_dir1);
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory / new_dir1 / ""));
    shell.ExecuteWithFullPath("cd", "..");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));

    const char *new_dir2 = reinterpret_cast<const char *>(u8"привет");
    shell.ExecuteWithFullPath("/bin/mkdir", Task::EscapeShellFeed(new_dir2).c_str());
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));
    shell.ExecuteWithFullPath("cd", Task::EscapeShellFeed(new_dir2).c_str());
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory / new_dir2 / ""));
    shell.ExecuteWithFullPath("cd", "..");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));

    const char *new_dir3 = reinterpret_cast<const char *>(u8"привет, мир!");
    shell.ExecuteWithFullPath("/bin/mkdir", ("'" + std::string(new_dir3) + "'").c_str());
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));
    shell.ExecuteWithFullPath("cd", Task::EscapeShellFeed(new_dir3).c_str());
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory / new_dir3 / ""));
    shell.ExecuteWithFullPath("cd", "..");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(cwd.wait_to_become(5s, dir.directory));

    // skipping emoji test for now, as CSH/TCSH requires escaping emojis as e.g. '\U+1F37B', i.e.
    // EscapeShellFeed should ideally become shell-type-aware AND to properly parse its input
    // unicode-wise. that really sucks.
}

TEST_CASE(PREFIX "CWD prompt response - changed/same")
{
    const TempTestDir dir;
    ShellTask shell;
    QueuedAtomicHolder<std::pair<std::filesystem::path, bool>> cwd;
    shell.SetOnPwdPrompt([&](const char *_cwd, bool _changed) { cwd.store({_cwd, _changed}); });
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    REQUIRE(shell.Launch(dir.directory));
    REQUIRE(cwd.wait_to_become(5s, {dir.directory, false}));

    shell.ExecuteWithFullPath("cd", ".");
    REQUIRE(cwd.wait_to_become(5s, {dir.directory, false}));

    shell.ExecuteWithFullPath("cd", "/");
    REQUIRE(cwd.wait_to_become(5s, {"/", true}));

    shell.ExecuteWithFullPath("cd", "/");
    REQUIRE(cwd.wait_to_become(5s, {"/", false}));
}

TEST_CASE(PREFIX "Test basics (legacy stuff)")
{
    const TempTestDir dir;
    const auto dir2 = dir.directory / "Test" / "";
    std::filesystem::create_directory(dir2);

    QueuedAtomicHolder<ShellTask::TaskState> shell_state;
    AtomicHolder<std::filesystem::path> cwd;
    ShellTask shell;
    shell_state.store(shell.State());
    shell_state.strict(false);
    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
    shell.SetOnPwdPrompt([&](const char *_cwd, bool) { cwd.store(_cwd); });
    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    shell.ResizeWindow(100, 100);
    REQUIRE(shell.Launch(dir.directory));

    // check cwd
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(shell.CWD() == dir.directory.generic_string());

    // the only task is running is shell itself, and is not returned by ChildrenList
    // though __in the process of bash initialization__ it can temporary spawn subprocesses
    REQUIRE(WaitChildrenListToBecome(shell, {}, 5s, 1ms));

    // test executing binaries within a shell
    shell.ExecuteWithFullPath("/usr/bin/top", nullptr);
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(WaitChildrenListToBecome(shell, {"top"}, 5s, 1ms));

    // simulates user press Q to quit top
    shell.WriteChildInput("q");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    REQUIRE(WaitChildrenListToBecome(shell, {}, 5s, 1ms));

    // check chdir
    shell.ChDir(dir2);
    REQUIRE(cwd.wait_to_become(5s, dir2));
    REQUIRE(shell.CWD() == dir2.generic_string());

    // test chdir in the middle of some typing
    shell.WriteChildInput("ls ");
    shell.ChDir(dir.directory);
    REQUIRE(cwd.wait_to_become(5s, dir.directory));
    REQUIRE(shell.CWD() == dir.directory.generic_string());

    // check internal program state
    shell.WriteChildInput("top\r");
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramInternal));
    REQUIRE(WaitChildrenListToBecome(shell, {"top"}, 5s, 1ms));

    // check termination
    shell.Terminate();
    REQUIRE(shell.ChildrenList().empty());
    REQUIRE(shell.State() == ShellTask::TaskState::Inactive);

    // check execution with short path in different directory
    REQUIRE(shell.Launch(dir.directory));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
    shell.Execute("top", "/usr/bin/", nullptr);
    REQUIRE(shell_state.wait_to_become(5s, TaskState::ProgramExternal));
    REQUIRE(WaitChildrenListToBecome(shell, {"top"}, 5s, 1ms));

    shell.Terminate();
    REQUIRE(shell.ChildrenList().empty());
}

TEST_CASE(PREFIX "Test vim interaction via output")
{
    const TempTestDir dir;
    std::filesystem::remove(dir.directory / ".vim_test.swp");

    AtomicHolder<std::string> buffer_dump;
    Screen screen(40, 10);
    ParserImpl parser;
    InterpreterImpl interpreter(screen);

    ShellTask shell;
    shell.ResizeWindow(40, 10);
    SECTION("bash")
    {
        shell.SetShellPath("/bin/bash");
        shell.SetEnvVar("PS1", ">");
        shell.AddCustomShellArgument("bash");
    }
    SECTION("zsh")
    {
        shell.SetShellPath("/bin/zsh");
        shell.SetEnvVar("PS1", ">");
        shell.AddCustomShellArgument("zsh");
        shell.AddCustomShellArgument("-f");
    }
    SECTION("csh")
    {
        shell.SetShellPath("/bin/csh");
    }
    SECTION("tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    shell.SetOnChildOutput([&](const void *_d, int _sz) {
        if( auto cmds = parser.Parse({reinterpret_cast<const std::byte *>(_d), static_cast<size_t>(_sz)});
            !cmds.empty() ) {
            if( auto lock = screen.AcquireLock() ) {
                interpreter.Interpret(cmds);
                buffer_dump.store(screen.Buffer().DumpScreenAsANSI());
            }
        }
    });
    REQUIRE(shell.Launch(dir.directory));

    if( shell.GetShellType() == ShellTask::ShellType::TCSH ) {
        shell.WriteChildInput("set prompt='>'\rclear\r");
    }

    shell.WriteChildInput("vim vim_test\r"); // vim vim_test Return
    const auto expected1 = "                                        "
                           "~                                       "
                           "~                                       "
                           "~                                       "
                           "~                                       "
                           "~                                       "
                           "~                                       "
                           "~                                       "
                           "~                                       "
                           "\"vim_test\" [New]                        ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected1));

    shell.WriteChildInput("i1\r2\r3\r4\r5\r\eOA\eOA\r"); // i 1 Return 2 Return 3 Return 4 Return 5
                                                         // Return Up Up Return
    const auto expected2 = "1                                       "
                           "2                                       "
                           "3                                       "
                           "                                        "
                           "4                                       "
                           "5                                       "
                           "                                        "
                           "~                                       "
                           "~                                       "
                           "-- INSERT --                            ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected2));

    shell.WriteChildInput("\x1b:q!\r"); // Esc : q ! Return
    const auto expected3 = ">vim vim_test                           "
                           ">                                       "
                           "                                        "
                           "                                        "
                           "                                        "
                           "                                        "
                           "                                        "
                           "                                        "
                           "                                        "
                           "                                        ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected3));
}

// this is a torture test to verify assumptions about synchronization under load.
// unfortunately, this test case works fine on my laptop, but fails on GitHub Actions.
// after already spending several evenings on this, I'm giving up for now...
TEST_CASE(PREFIX "Test multiple shells in parallel via output", "[!mayfail]")
{
    const TempTestDir dir;
    constexpr size_t number = 10; // just casually spawn 10 shells, not a big deal...

    struct Context {
        AtomicHolder<std::string> buffer_dump;
        AtomicHolder<ShellTask::TaskState> shell_state;
        Screen screen{20, 5};
        ParserImpl parser;
        InterpreterImpl interpreter{screen};
        ShellTask shell;
    };
    std::array<Context, number> shells;

    SECTION("bash")
    {
        for( auto &ctx : shells ) {
            ctx.shell.SetShellPath("/bin/bash");
            ctx.shell.SetEnvVar("PS1", ">");
            ctx.shell.AddCustomShellArgument("bash");
        }
    }
    SECTION("zsh")
    {
        for( auto &ctx : shells ) {
            ctx.shell.SetShellPath("/bin/zsh");
            ctx.shell.SetEnvVar("PS1", ">");
            ctx.shell.AddCustomShellArgument("zsh");
            ctx.shell.AddCustomShellArgument("-f");
        }
    }
    SECTION("csh")
    {
        for( auto &ctx : shells ) {
            ctx.shell.SetShellPath("/bin/csh");
        }
    }
    SECTION("tcsh")
    {
        for( auto &ctx : shells ) {
            ctx.shell.SetShellPath("/bin/tcsh");
        }
    }
    for( auto &ctx : shells ) {
        ctx.shell.ResizeWindow(20, 5);
        ctx.shell.SetOnChildOutput([&](const void *_d, int _sz) {
            if( auto cmds = ctx.parser.Parse({reinterpret_cast<const std::byte *>(_d), static_cast<size_t>(_sz)});
                !cmds.empty() ) {
                if( auto lock = ctx.screen.AcquireLock() ) {
                    ctx.interpreter.Interpret(cmds);
                    ctx.buffer_dump.store(ctx.screen.Buffer().DumpScreenAsANSI());
                }
            }
        });
        ctx.shell.SetOnStateChange([&](ShellTask::TaskState _new_state) { ctx.shell_state.store(_new_state); });
        REQUIRE(ctx.shell.Launch(dir.directory));

        if( ctx.shell.GetShellType() == ShellTask::ShellType::TCSH )
            ctx.shell.WriteChildInput("set prompt='>'\rclear\r");
    }

    // wait until each shell wakes up
    for( size_t i = 0; i != number; ++i ) {
        const std::string expected = ">                   "
                                     "                    "
                                     "                    "
                                     "                    "
                                     "                    ";
        REQUIRE(shells[i].buffer_dump.wait_to_become(5s, expected));
    }

    // write the shell number to each shell
    for( size_t i = 0; i != number; ++i ) {
        const std::string msg = "Hi," + std::to_string(i);
        shells[i].shell.WriteChildInput(msg);
    }

    // wait until each shell dispays it
    for( size_t i = 0; i != number; ++i ) {
        const std::string msg = "Hi," + std::to_string(i);
        std::string line = ">                   ";
        line.replace(1, msg.size(), msg);
        const std::string expected = line + "                    "
                                            "                    "
                                            "                    "
                                            "                    ";
        REQUIRE(shells[i].buffer_dump.wait_to_become(5s, expected));
    }

    // now tell all the shell to bugger off
    for( auto &ctx : shells )
        ctx.shell.Terminate();

    // and wait until there were none
    for( auto &ctx : shells )
        REQUIRE(ctx.shell_state.wait_to_become(5s, TaskState::Inactive));
}

TEST_CASE(PREFIX "doesn't keep external cwd change commands in history")
{
    AtomicHolder<std::string> buffer_dump;
    Screen screen(20, 6);
    ParserImpl parser;
    InterpreterImpl interpreter(screen);

    ShellTask shell;
    shell.ResizeWindow(20, 6);
    SECTION("bash")
    {
        shell.SetShellPath("/bin/bash");
        shell.SetEnvVar("PS1", ">");
        shell.AddCustomShellArgument("bash");
    }
    SECTION("zsh")
    {
        shell.SetShellPath("/bin/zsh");
        shell.SetEnvVar("PS1", ">");
        shell.AddCustomShellArgument("zsh");
        shell.AddCustomShellArgument("-f");
    }
    // [t]csh is out of equation - no such option exists (?)
    shell.SetOnChildOutput([&](const void *_d, int _sz) {
        if( auto cmds = parser.Parse({reinterpret_cast<const std::byte *>(_d), static_cast<size_t>(_sz)});
            !cmds.empty() ) {
            if( auto lock = screen.AcquireLock() ) {
                interpreter.Interpret(cmds);
                buffer_dump.store(screen.Buffer().DumpScreenAsANSI());
            }
        }
    });
    REQUIRE(shell.Launch("/bin"));

    shell.WriteChildInput("echo 123\r");
    const std::string expected1 = ">echo 123           "
                                  "123                 "
                                  ">                   "
                                  "                    "
                                  "                    "
                                  "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected1));

    shell.ChDir("/");
    const std::string expected2 = ">echo 123           "
                                  "123                 "
                                  ">                   "
                                  ">                   "
                                  "                    "
                                  "                    ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected2));

    shell.WriteChildInput("echo 456\r");
    const std::string expected3 = ">echo 123           "
                                  "123                 "
                                  ">                   "
                                  ">echo 456           "
                                  "456                 "
                                  ">                   ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected3));

    shell.WriteChildInput("\e[A");
    const std::string expected4 = ">echo 123           "
                                  "123                 "
                                  ">                   "
                                  ">echo 456           "
                                  "456                 "
                                  ">echo 456           ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected4));

    shell.WriteChildInput("\e[A");
    const std::string expected5 = ">echo 123           "
                                  "123                 "
                                  ">                   "
                                  ">echo 456           "
                                  "456                 "
                                  ">echo 123           ";
    REQUIRE(buffer_dump.wait_to_become_with_runloop(5s, 1ms, expected5));
}

TEST_CASE(PREFIX "Launches when shell is a symlink to a real binary")
{
    const TempTestDir dir;
    const auto basedir = dir.directory;
    ShellTask shell;

    std::filesystem::path rel_path;
    size_t depth = std::count(basedir.native().begin(), basedir.native().end(), '/');
    while( depth-- > 0 )
        rel_path /= "../";

    std::filesystem::path shell_path;
    SECTION("/bin/bash")
    {
        SECTION("Symlink has an absolute path")
        {
            std::filesystem::create_symlink("/bin/bash", shell_path = basedir / "bash");
        }
        SECTION("Symlink has a relative path")
        {
            std::filesystem::create_symlink(rel_path / "bin/bash", shell_path = basedir / "bash");
        }
    }
    SECTION("/bin/zsh")
    {
        SECTION("Symlink has an absolute path")
        {
            std::filesystem::create_symlink("/bin/zsh", shell_path = basedir / "zsh");
        }
        SECTION("Symlink has a relative path")
        {
            std::filesystem::create_symlink(rel_path / "bin/zsh", shell_path = basedir / "zsh");
        }
    }
    SECTION("/bin/tcsh")
    {
        SECTION("Symlink has an absolute path")
        {
            std::filesystem::create_symlink("/bin/tcsh", shell_path = basedir / "tcsh");
        }
        SECTION("Symlink has a relative path")
        {
            std::filesystem::create_symlink(rel_path / "bin/tcsh", shell_path = basedir / "tcsh");
        }
    }
    SECTION("/bin/csh")
    {
        SECTION("Symlink has an absolute path")
        {
            std::filesystem::create_symlink("/bin/csh", shell_path = basedir / "csh");
        }
        SECTION("Symlink has a relative path")
        {
            std::filesystem::create_symlink(rel_path / "bin/csh", shell_path = basedir / "csh");
        }
    }
    shell.SetShellPath(shell_path);
    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()) == true);
    REQUIRE(shell.State() == ShellTask::TaskState::Shell);
}

TEST_CASE(PREFIX "ChildrenList()")
{
    SECTION("Check the support for nested children")
    {
        QueuedAtomicHolder<ShellTask::TaskState> shell_state;
        ShellTask shell;
        shell_state.store(shell.State());
        shell_state.strict(false);
        shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
        shell.SetShellPath("/bin/bash");
        REQUIRE(shell.Launch("/"));
        REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
        REQUIRE(WaitChildrenListToBecome(shell, {}, 5s, 1ms));
        shell.WriteChildInput("/bin/zsh\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh"}, 5s, 1ms));
        shell.WriteChildInput("/bin/bash\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh", "bash"}, 5s, 1ms));
        shell.WriteChildInput("/bin/zsh\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh", "bash", "zsh"}, 5s, 1ms));
        shell.WriteChildInput("exit\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh", "bash"}, 5s, 1ms));
        shell.WriteChildInput("exit\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh"}, 5s, 1ms));
        shell.WriteChildInput("exit\r");
        REQUIRE(WaitChildrenListToBecome(shell, {}, 5s, 1ms));
    }
    SECTION("Supports getting children names longer than MAXCOMLEN=16 characters")
    {
        // This test creates an executable that sleeps for 10 seconds and runs it as a terminal's subprocess.
        // The reason for this moronic idea is that I wasn't able to figure out a way of getting a binary image with a
        // long name. Copying and renaming a default stuff like /bin/sleep no longer works on macOS :-(
        const TempTestDir dir;
        const auto basedir = dir.directory;
        std::ofstream(basedir / "a.c") << "#include <unistd.h> \n int main() { sleep(10); }";
        REQUIRE(system(fmt::format("cd {} && clang a.c -o an_executable_with_a_very_long_name", basedir).c_str()) == 0);

        QueuedAtomicHolder<ShellTask::TaskState> shell_state;
        ShellTask shell;
        shell_state.store(shell.State());
        shell_state.strict(false);
        shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });
        shell.SetShellPath("/bin/bash");
        REQUIRE(shell.Launch(basedir));
        REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));
        REQUIRE(WaitChildrenListToBecome(shell, {}, 5s, 1ms));
        shell.WriteChildInput("/bin/zsh\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh"}, 5s, 1ms));
        shell.WriteChildInput("./an_executable_with_a_very_long_name\r");
        REQUIRE(WaitChildrenListToBecome(shell, {"zsh", "an_executable_with_a_very_long_name"}, 5s, 1ms));
    }
}

TEST_CASE(PREFIX "Closes all file descriptors used by terminal")
{
    const std::vector<int> orig_fds = GetAllFileDescriptors();

    ShellTask shell;
    QueuedAtomicHolder<ShellTask::TaskState> shell_state(shell.State());
    REQUIRE(shell.State() == TaskState::Inactive);

    shell.SetOnStateChange([&shell_state](ShellTask::TaskState _new_state) { shell_state.store(_new_state); });

    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Shell));

    const std::vector<int> tmp_fds = GetAllFileDescriptors();
    CHECK(tmp_fds.size() > orig_fds.size());

    shell.Terminate();
    REQUIRE(shell_state.wait_to_become(5s, TaskState::Inactive));

    const std::vector<int> final_fds = GetAllFileDescriptors();
    CHECK(final_fds == orig_fds);
}

TEST_CASE(PREFIX "Doesn't allow double-launch")
{
    ShellTask shell;
    REQUIRE(shell.Launch(CommonPaths::AppTemporaryDirectory()));
    CHECK_THROWS_AS(shell.Launch(CommonPaths::AppTemporaryDirectory()), std::logic_error);
}

TEST_CASE(PREFIX "ChDir respects literal square-bracketed directory despite glob expansion")
{
    const TempTestDir dir;
    ShellTask shell;
    QueuedAtomicHolder<std::pair<std::filesystem::path, bool>> cwd;
    shell.SetOnPwdPrompt([&](const char *_cwd, bool _changed) { cwd.store({_cwd, _changed}); });

    const auto bracketedDir = dir.directory / "a[bc]d" / "";
    std::filesystem::create_directory(bracketedDir);

    SECTION("/bin/bash")
    {
        shell.SetShellPath("/bin/bash");
    }
    SECTION("/bin/zsh")
    {
        shell.SetShellPath("/bin/zsh");
    }
    SECTION("/bin/tcsh")
    {
        shell.SetShellPath("/bin/tcsh");
    }
    SECTION("/bin/csh")
    {
        shell.SetShellPath("/bin/csh");
    }

    REQUIRE(shell.Launch(dir.directory));
    REQUIRE(cwd.wait_to_become(5s, {dir.directory, false}));
    REQUIRE(shell.CWD() == dir.directory.generic_string());

    shell.ChDir(bracketedDir);
    REQUIRE(cwd.wait_to_become(5s, {bracketedDir, true}));
    CHECK(shell.CWD() == bracketedDir.generic_string());
}
