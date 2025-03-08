// Copyright (C) 2014-2023 Michael Kazakov. Subject to GNU General Public License version 3.
#include "Task.h"
#include <Base/CloseFrom.h>
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <cerrno>
#include <clocale>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <termios.h>
#include <unistd.h>

namespace nc::term {

Task::Task() = default;

Task::~Task() = default;

void Task::SetOnChildOutput(std::function<void(const void *_d, size_t _sz)> _callback)
{
    auto local = std::lock_guard{m_OnChildOutputLock};
    m_OnChildOutput = std::make_shared<decltype(_callback)>(std::move(_callback));
}

void Task::DoCalloutOnChildOutput(const void *_d, size_t _sz)
{
    m_OnChildOutputLock.lock();
    auto clbk = m_OnChildOutput;
    m_OnChildOutputLock.unlock();

    if( clbk && *clbk && _sz && _d )
        (*clbk)(_d, _sz);
}

int Task::SetTermWindow(int _fd,
                        unsigned short _chars_width,
                        unsigned short _chars_height,
                        unsigned short _pix_width,
                        unsigned short _pix_height)
{
    struct winsize winsize;
    winsize.ws_col = _chars_width;
    winsize.ws_row = _chars_height;
    winsize.ws_xpixel = _pix_width;
    winsize.ws_ypixel = _pix_height;
    return ioctl(_fd, TIOCSWINSZ, &winsize);
}

int Task::SetupTermios(int _fd)
{
    struct termios term_sett; // Saved terminal settings

    // Save the defaults parameters of the slave side of the PTY
    tcgetattr(_fd, &term_sett);
    term_sett.c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT;
    term_sett.c_oflag = OPOST | ONLCR;
    term_sett.c_cflag = CREAD | CS8 | HUPCL;
    term_sett.c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;
    term_sett.c_ispeed = B230400;
    term_sett.c_ospeed = B230400;
    term_sett.c_cc[VINTR] = 3; /* CTRL+C */
    term_sett.c_cc[VEOF] = 4;  /* CTRL+D */
    return tcsetattr(_fd, /*TCSADRAIN*/ TCSANOW, &term_sett);
}

void Task::SetupHandlesAndSID(int _slave_fd)
{
    // The slave side of the PTY becomes the standard input and outputs of the child process
    close(0); // Close standard input (current terminal)
    close(1); // Close standard output (current terminal)
    close(2); // Close standard error (current terminal)

    dup(_slave_fd); // PTY becomes standard input (0)
    dup(_slave_fd); // PTY becomes standard output (1)
    dup(_slave_fd); // PTY becomes standard error (2)

    // Make the current process a new session leader
    setsid();

    // As the child is a session leader, set the controlling terminal to be the slave side of the
    // PTY (Mandatory for programs like the shell to make them manage correctly their outputs)
    ioctl(0, TIOCSCTTY, 1);
}

static std::string GetLocale()
{
    // Keep a copy of the current locale setting for this process
    char *backupLocale = setlocale(LC_CTYPE, nullptr);
    if( backupLocale != nullptr && !std::string_view{backupLocale}.empty() && std::string_view{backupLocale} != "C" ) {
        return backupLocale;
    }

    // Start with the locale
    std::string locale = "en"; // en as a backup for any possible error

    CFLocaleRef loc = CFLocaleCopyCurrent();
    CFStringRef ident = CFLocaleGetIdentifier(loc);

    if( auto l = CFStringGetCStringPtr(ident, kCFStringEncodingUTF8) )
        locale = l;
    else {
        char buf[256];
        if( CFStringGetCString(ident, buf, 255, kCFStringEncodingUTF8) )
            locale = buf;
    }
    CFRelease(loc);

    const std::string encoding = "UTF-8"; // hardcoded now. but how uses non-UTF8 nowdays?

    // check if locale + encoding is valid
    const std::string test = locale + '.' + encoding;
    if( nullptr != setlocale(LC_CTYPE, test.c_str()) )
        locale = test;

    // Check the locale is valid
    if( nullptr == setlocale(LC_CTYPE, locale.c_str()) )
        locale = "";

    // Restore locale and return
    setlocale(LC_CTYPE, backupLocale);
    return locale;
}

std::span<const std::pair<std::string, std::string>> Task::BuildEnv()
{
    [[clang::no_destroy]] static const std::vector<std::pair<std::string, std::string>> env = [] {
        std::vector<std::pair<std::string, std::string>> env;
        const std::string locale = GetLocale();
        if( !locale.empty() ) {
            env.emplace_back("LANG", locale);
            env.emplace_back("LC_COLLATE", locale);
            env.emplace_back("LC_CTYPE", locale);
            env.emplace_back("LC_MESSAGES", locale);
            env.emplace_back("LC_MONETARY", locale);
            env.emplace_back("LC_NUMERIC", locale);
            env.emplace_back("LC_TIME", locale);
        }
        else {
            env.emplace_back("LC_CTYPE", "UTF-8");
        }

        env.emplace_back("TERM", "xterm-256color");
        env.emplace_back("TERM_PROGRAM", "Nimble_Commander");
        return env;
    }();
    return env;
}

void Task::SetEnv(std::span<const std::pair<std::string, std::string>> _env)
{
    for( auto &i : _env )
        setenv(i.first.c_str(), i.second.c_str(), 1);
}

unsigned Task::ReadInputAsMuchAsAvailable(int _fd, void *_buf, unsigned _buf_sz, int _usec_wait)
{
    fd_set fdset;
    unsigned already_read = 0;
    int rc = 0;
    do {
        rc = static_cast<int>(read(_fd, static_cast<char *>(_buf) + already_read, _buf_sz - already_read));
        if( rc <= 0 )
            break;
        already_read += rc;

        FD_ZERO(&fdset);
        FD_SET(_fd, &fdset);
        timeval tt;
        tt.tv_sec = 0;
        tt.tv_usec = _usec_wait;
        rc = select(_fd + 1, &fdset, nullptr, nullptr, &tt);
    } while( rc >= 0 && FD_ISSET(_fd, &fdset) && already_read < _buf_sz );
    return already_read;
}

std::string Task::EscapeShellFeed(const std::string &_feed)
{
    static const char to_esc[] = {
        '|', '&', ';', '<', '>', '(', ')', '$', '\'', '\\', '\"', '`', ' ', '\t', '!', '[', ']'};
    std::string result;
    result.reserve(_feed.length());
    for( auto c : _feed ) {
        if( std::ranges::any_of(to_esc, [=](auto e) { return c == e; }) )
            result += '\\';
        result += c;
    }
    return result;
}

static const char *GetImgNameFromPath(const char *_path)
{
    if( !_path )
        return "";
    const char *img_name = strrchr(_path, '/');
    if( img_name )
        img_name++;
    else
        img_name = _path;
    return img_name;
}

int Task::RunDetachedProcess(const std::string &_process_path, const std::vector<std::string> &_args)
{
    if( access(_process_path.c_str(), F_OK | X_OK) < 0 )
        return -1;

    const int rc = fork();
    if( rc == 0 ) {
        char **argvs = static_cast<char **>(std::malloc(sizeof(char *) * (_args.size() + 2)));
        argvs[0] = strdup(GetImgNameFromPath(_process_path.c_str()));
        for( size_t i = 0; i < _args.size(); ++i )
            argvs[i + 1] = strdup(_args[i].c_str());
        argvs[_args.size() + 1] = nullptr;

        nc::base::CloseFrom(3);

        execvp(_process_path.c_str(), argvs);

        exit(1); // we never get here in normal condition
    }

    return rc;
}

} // namespace nc::term
