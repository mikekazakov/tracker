// Copyright (C) 2016-2018 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once


class TemporaryNativeFileChangesSentinel
{
public:
    static TemporaryNativeFileChangesSentinel &Instance();
    
    /**
     * Callback function will be called in main thread.
     * This method is thread-safe.
     * @param _path filepath to watch for content changes
     * @param _on_file_changed callback on change event
     * @param _check_delay delay on FSEvent after which background content checking should start
     * @param _drop_delay time threshold after which file watch should drop if no file changes occured in that time
     */
    bool WatchFile(const string& _path,
                   function<void()> _on_file_changed,
                   std::chrono::milliseconds _check_delay = std::chrono::seconds{5},
                   std::chrono::milliseconds _drop_delay = std::chrono::hours{1} );
    
    /**
     * Stops file watching. If background checking currently goes on then one more callback event may occur.
     * This method is thread-safe.
     * @param _path filepath to stop watching at
     */
    bool StopFileWatch( const string& _path );
    
private:
    struct Meta {
        string                          path;
        shared_ptr<function<void()>>    callback;
        uint64_t                        fswatch_ticket = 0;
        vector<uint8_t>                 last_md5_hash;
        std::chrono::milliseconds       drop_time;
        std::chrono::milliseconds       check_delay;
        std::chrono::milliseconds       drop_delay;
        std::atomic_bool                checking_now;
    };
    
    void FSEventCallback( shared_ptr<Meta> _meta );
    void BackgroundItemCheck( shared_ptr<Meta> _meta );
    void ScheduleItemDrop( const shared_ptr<Meta> &_meta );

    spinlock                    m_WatchesLock;
    vector<shared_ptr<Meta>>    m_Watches;
};
