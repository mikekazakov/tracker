// Copyright (C) 2021 Michael Kazakov. Subject to GNU General Public License version 3.
#include "FSEventsFileUpdateImpl.h"
#include <Utility/StringExtras.h>
#include <Utility/Log.h>
#include <Habanero/CFPtr.h>
#include <Habanero/dispatch_cpp.h>
#include <iostream>

namespace nc::utility {

static const CFAbsoluteTime g_FSEventsLatency = 0.05; // 50ms
static const std::chrono::nanoseconds g_ScanInterval = std::chrono::seconds(2);
static const std::chrono::nanoseconds g_StaleInterval  = g_ScanInterval / 2;

static std::optional<struct stat> GetStat(const std::filesystem::path &_path) noexcept;

size_t
FSEventsFileUpdateImpl::PathHash::operator()(const std::filesystem::path &_path) const noexcept
{
    return robin_hood::hash_bytes(_path.native().c_str(), _path.native().size());
}

size_t FSEventsFileUpdateImpl::PathHash::operator()(const std::string_view &_path) const noexcept
{
    return robin_hood::hash_bytes(_path.data(), _path.size());
}

FSEventsFileUpdateImpl::FSEventsFileUpdateImpl()
{
    m_AsyncContext = std::make_shared<AsyncContext>();
    m_AsyncContext->me = this;
    m_WeakAsyncContext = m_AsyncContext;

    Log::Trace(SPDLOC, "FSEventsFileUpdateImpl created");
}

FSEventsFileUpdateImpl::~FSEventsFileUpdateImpl()
{
    dispatch_is_main_queue();
    // there's no need to lock here because at this point no one can touch this object anymore
    for( auto &watch : m_Watches ) {
        DeleteEventStream(watch.second.stream);
    }
    Log::Trace(SPDLOC, "FSEventsFileUpdateImpl destroyed");
}

uint64_t FSEventsFileUpdateImpl::AddWatchPath(const std::filesystem::path &_path,
                                              std::function<void()> _handler)
{
    assert(_handler);
    auto lock = std::lock_guard{m_Lock};

    const auto token = m_NextTicket++;
    Log::Debug(SPDLOC, "Adding for path: {}, token: {}", _path, token);
    const auto was_empty = m_Watches.empty();

    if( auto existing = m_Watches.find(_path); existing != m_Watches.end() ) {
        auto &watch = existing->second;
        assert(watch.handlers.contains(token) == false);
        watch.handlers.emplace(token, std::move(_handler));
    }
    else {
        auto stream = CreateEventStream(_path);
        if( stream == nullptr )
            return empty_token;
        Watch watch;
        watch.stream = stream;
        watch.handlers.emplace(token, std::move(_handler));
        watch.stat = GetStat(_path); // sync I/O here :(
        watch.snapshot_time = machtime();
        m_Watches.emplace(_path, std::move(watch));
    }
    
    if( was_empty == true && m_KickstartIsOnline == false )
        ScheduleScannerKickstart();
    
    return token;
}

void FSEventsFileUpdateImpl::RemoveWatchPathWithToken(uint64_t _token)
{
    auto lock = std::lock_guard{m_Lock};
    for( auto watch_it = m_Watches.begin(), watch_end = m_Watches.end(); watch_it != watch_end;
         ++watch_it ) {
        auto &watch = watch_it->second;
        if( watch.handlers.contains(_token) ) {
            Log::Debug(SPDLOC, "Removing a watch for token {} - {}", _token, watch_it->first);
            watch.handlers.erase(_token);
            if( watch.handlers.empty() ) {
                DeleteEventStream(watch.stream);
                m_Watches.erase(watch_it);
            }
            return;
        }
    }
    Log::Warn(SPDLOC, "Unable to remove a watch for stray token: {}", _token);
}

FSEventStreamRef FSEventsFileUpdateImpl::CreateEventStream(const std::filesystem::path &_path) const
{
    auto cf_path = base::CFPtr<CFStringRef>::adopt(CFStringCreateWithUTF8StdString(_path.native()));
    if( !cf_path )
        return nullptr;

    const auto paths_to_watch = base::CFPtr<CFArrayRef>::adopt(
        CFArrayCreate(0, reinterpret_cast<const void **>(&cf_path), 1, nullptr));
    if( !paths_to_watch )
        return nullptr;

    const auto flags = kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents;
    auto context = FSEventStreamContext{
        0, const_cast<void *>(reinterpret_cast<const void *>(this)), nullptr, nullptr, nullptr};

    FSEventStreamRef stream = nullptr;
    auto create_schedule_and_run = [&] {
        stream = FSEventStreamCreate(nullptr,
                                     &FSEventsFileUpdateImpl::CallbackFFI,
                                     &context,
                                     paths_to_watch.get(),
                                     kFSEventStreamEventIdSinceNow,
                                     g_FSEventsLatency,
                                     flags);
        if( stream == nullptr ) {
            Log::Warn(SPDLOC, "Failed to create a stream for {}", _path);
            return;
        }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        FSEventStreamStart(stream);

        Log::Debug(SPDLOC, "Started a stream for {}", _path);
    };

    if( dispatch_is_main_queue() )
        create_schedule_and_run();
    else
        dispatch_sync(dispatch_get_main_queue(), create_schedule_and_run);

    return stream;
}

void FSEventsFileUpdateImpl::DeleteEventStream(FSEventStreamRef _stream)
{
    assert(_stream != nullptr);
    dispatch_assert_main_queue();
    FSEventStreamStop(_stream);
    FSEventStreamUnscheduleFromRunLoop(_stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    // FSEventStreamInvalidate can be blocking, so let's do that in a background thread
    dispatch_to_background([_stream] {
        FSEventStreamInvalidate(_stream);
        FSEventStreamRelease(_stream);
    });
}

void FSEventsFileUpdateImpl::Callback([[maybe_unused]] ConstFSEventStreamRef _stream_ref,
                                      size_t _num,
                                      void *_paths,
                                      [[maybe_unused]] const FSEventStreamEventFlags _flags[],
                                      [[maybe_unused]] const FSEventStreamEventId _ids[])
{
    // remove any adjacent duplicates if any. we don't care about flags and ids.
    auto cpaths = reinterpret_cast<const char **>(_paths);
    std::vector<std::string_view> paths( cpaths, cpaths + _num);
    paths.erase(std::unique(paths.begin(), paths.end()), paths.end());

    auto lock = std::lock_guard{m_Lock};
    const auto now = machtime();
    for( auto path : paths ) {
        Log::Debug(SPDLOC, "Callback fired for {}", path);
        auto watches_it = m_Watches.find(path);
        if( watches_it != m_Watches.end() ) {
            watches_it->second.stat = GetStat(watches_it->first); // sync I/O :`(
            watches_it->second.snapshot_time = now;
            for( auto &handler : watches_it->second.handlers ) {
                // NB! no copy here => this call is NOT reenterant!
                handler.second();
            }
        }
    }
}

void FSEventsFileUpdateImpl::CallbackFFI(ConstFSEventStreamRef _stream_ref,
                                         void *_user_data,
                                         size_t _num,
                                         void *_paths,
                                         const FSEventStreamEventFlags _flags[],
                                         const FSEventStreamEventId _ids[])
{
    FSEventsFileUpdateImpl *me = static_cast<FSEventsFileUpdateImpl *>(_user_data);
    me->Callback(_stream_ref, _num, _paths, _flags, _ids);
}

void FSEventsFileUpdateImpl::ScheduleScannerKickstart()
{
    // no dispatch_assert_main_queue here - can be scheduled from any thread
    m_KickstartIsOnline = true;
    // schedule the next scanner execution after g_ScanInterval
    dispatch_to_main_queue_after(g_ScanInterval, [context = m_WeakAsyncContext]{
        if( auto instance = context.lock() )
            instance->me->KickstartBackgroundScanner();
    });
}

void FSEventsFileUpdateImpl::KickstartBackgroundScanner()
{
    dispatch_assert_main_queue();

    auto lock = std::lock_guard{m_Lock};

    if( m_Watches.empty() ) {
        m_KickstartIsOnline = false;
        return;
    }

    std::vector<std::filesystem::path> paths;
    paths.reserve(m_Watches.size());
    const auto now = machtime();
    for( const auto &watch : m_Watches ) {
        // check that the last snapshot is stale enough to bother
        if( watch.second.snapshot_time + g_StaleInterval < now ) {
            paths.emplace_back(watch.first);
        }
    }

    dispatch_to_background([paths = std::move(paths), context = m_WeakAsyncContext] {
        BackgroundScanner(std::move(paths), context);
    });
}

void FSEventsFileUpdateImpl::AcceptScannedStats(
    const std::vector<std::filesystem::path> &_paths,
    const std::vector<std::optional<struct stat>> &_stats)
{
    dispatch_assert_main_queue();
    auto lock = std::lock_guard{m_Lock};
    ScheduleScannerKickstart();
    
    assert( _paths.size() == _stats.size() );
    const auto now = machtime();
    for( size_t i = 0; i != _paths.size(); ++i ) {
        auto it = m_Watches.find(_paths[i]);
        if( it == m_Watches.end() )
            continue; // _paths[i] was removed in the meantime
        
        const auto changed = DidChange(it->second.stat, _stats[i]);
        it->second.stat = _stats[i];
        it->second.snapshot_time = now;
        
        if( changed ) {
            Log::Debug(SPDLOC, "Callback fired for {}", _paths[i]);
            for( auto &handler : it->second.handlers ) {
                // NB! no copy here => this call is NOT reenterant!
                handler.second();
            }
        }
    }
}

bool FSEventsFileUpdateImpl::DidChange(const std::optional<struct stat>& _was,
                                       const std::optional<struct stat>& _now ) noexcept
{
    if( _was == std::nullopt && _now != std::nullopt )
        return true;
    if( _was != std::nullopt && _now == std::nullopt )
        return true;
    if( _was == std::nullopt && _now == std::nullopt )
        return false;
    
    if( _was->st_size != _now->st_size )
        return true;
    
    // TODO: check other fields. and decide what to even consider a 'change'...

    return false;
}

void FSEventsFileUpdateImpl::BackgroundScanner(std::vector<std::filesystem::path> _paths,
                                               std::weak_ptr<AsyncContext> _context) noexcept

{
    dispatch_assert_background_queue();
    Log::Trace(SPDLOC, "FSEventsFileUpdateImpl background file scan");

    std::vector<std::optional<struct stat>> stats;
    stats.reserve(_paths.size());
    for( const auto &path : _paths )
        stats.emplace_back(GetStat(path));

    dispatch_to_main_queue([paths = std::move(_paths), stats = std::move(stats), _context] {
        if( auto instance = _context.lock() )
            instance->me->AcceptScannedStats(paths, stats);
    });
}

std::optional<struct stat> GetStat(const std::filesystem::path &_path) noexcept
{
    struct stat st;
    const int rc = stat(_path.c_str(), &st);
    if( rc == 0 )
        return st;
    else
        return std::nullopt;
}

} // namespace nc::utility
