//
//  VFSArchiveUnRARHost.cpp
//  Files
//
//  Created by Michael G. Kazakov on 02.03.14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#include <string.h>
#include "3rd_party/unrar/unrar-5.0.14/raros.hpp"
#include "3rd_party/unrar/unrar-5.0.14/dll.hpp"
#include "VFSNativeHost.h"
#include "VFSArchiveUnRARHost.h"
#include "VFSArchiveUnRARInternals.h"
#include "VFSArchiveUnRARListing.h"
#include "Common.h"

/*enum UNRARCALLBACK_MESSAGES {
    UCM_CHANGEVOLUME,UCM_PROCESSDATA,UCM_NEEDPASSWORD,UCM_CHANGEVOLUMEW,
    UCM_NEEDPASSWORDW
};*/

/*

 */

static time_t DosTimeToUnixTime(unsigned int _dos_time)
{
    unsigned int l = _dos_time; // a dosdate
    
    int year    =  ((l>>25)&127) + 1980;// 7 bits
    int month   =   (l>>21)&15;         // 4 bits
    int day     =   (l>>16)&31;         // 5 bits
    int hour    =   (l>>11)&31;         // 5 bits
    int minute  =   (l>>5) &63;         // 6 bits
    int second  =   (l     &31) * 2;    // 5 bits
    
    struct tm timeinfo;
    timeinfo.tm_year    = year - 1900;
    timeinfo.tm_mon     = month - 1;
    timeinfo.tm_mday    = day;
    timeinfo.tm_hour    = hour;
    timeinfo.tm_min     = minute;
    timeinfo.tm_sec     = second;
    
    return timegm(&timeinfo);
}

static int CALLBACK CallbackProc(UINT msg, long UserData, long P1, long P2) {
	UInt8 **buffer;
	
	switch(msg) {
			
		case UCM_CHANGEVOLUME:
			break;
		case UCM_PROCESSDATA:
/*			buffer = (UInt8 **) UserData;
			memcpy(*buffer, (UInt8 *)P1, P2);
			// advance the buffer ptr, original m_buffer ptr is untouched
			*buffer += P2;*/
			break;
		case UCM_NEEDPASSWORD:
			break;
	}
	return(0);
}

const char *VFSArchiveUnRARHost::Tag = "archive_unrar";

VFSArchiveUnRARHost::VFSArchiveUnRARHost(const char *_junction_path):
    VFSHost(_junction_path, VFSNativeHost::SharedHost())
{
}

VFSArchiveUnRARHost::~VFSArchiveUnRARHost()
{
}

const char *VFSArchiveUnRARHost::FSTag() const
{
    return Tag;
}

int VFSArchiveUnRARHost::Open()
{
    if(!Parent() || Parent()->IsNativeFS() == false)
        return VFSError::NotSupported;
    
	HANDLE rar_file;
    RAROpenArchiveDataEx flags;
    memset(&flags, 0, sizeof(flags));
    
//    const char *filenameData = (const char *) [rarFile UTF8String];
	flags.ArcName = (char*)JunctionPath();
//	strcpy(flags->ArcName, filenameData);
	flags.OpenMode = RAR_OM_LIST;
//    flags.Callback = CallbackProc;
    
	rar_file = RAROpenArchiveEx(&flags);
    if(rar_file == 0)
        return VFSError::UnRARFailedToOpenArchive;
    
    int ret = InitialReadFileList(rar_file);
    RARCloseArchive(rar_file);
    
    if(ret < 0)
        return ret;
    
    return 0;
}

int VFSArchiveUnRARHost::InitialReadFileList(void *_rar_handle)
{
    auto root_dir = m_PathToDir.emplace("/");
    root_dir.first->second.full_path = "/";
    
    uint32_t uuid = 1;
    RARHeaderDataEx header;
    
    int read_head_ret, proc_file_ret;
    while((read_head_ret = RARReadHeaderEx(_rar_handle, &header)) == 0)
    {
        // doing UTF32LE->UTF8 to be sure about single-byte RAR encoding
        CFStringRef utf32le = CFStringCreateWithBytesNoCopy(NULL,
                                                            (UInt8*)header.FileNameW,
                                                            wcslen(header.FileNameW)*sizeof(wchar_t),
                                                            kCFStringEncodingUTF32LE,
                                                            false,
                                                            kCFAllocatorNull);
        char utf8buf[4096] = {'/', 0};
        CFStringGetFileSystemRepresentation(utf32le, utf8buf+1, 4096-1);
//        NSLog(@"%@", (__bridge NSString*)utf32le);
        CFRelease(utf32le);
        

        const char *last_sl = strrchr(utf8buf, '/');
        assert(last_sl != 0);
        string parent_dir_path(utf8buf, last_sl + 1 - utf8buf);

        string entry_short_name(last_sl + 1);
        
        VFSArchiveUnRARDirectory    *parent_dir = FindOrBuildDirectory(parent_dir_path);
        VFSArchiveUnRAREntry        *entry = nullptr;
        
        bool is_directory = (header.Flags & RHDF_DIRECTORY) != 0;
        if(is_directory)
            for(auto &i: parent_dir->entries)
                if(i.name == entry_short_name)
                {
                    entry = &i;
                    break;
                }
        
        if(entry == nullptr)
        {
            parent_dir->entries.emplace_back();
            entry = &parent_dir->entries.back();
            entry->name = entry_short_name;
        }
        
        entry->cfname       = CFStringCreateWithUTF8StdStringNoCopy(entry->name);
        entry->rar_name     = header.FileName;
        entry->isdir        = is_directory;
        entry->unpacked_size= uint64_t(header.UnpSize) | ( uint64_t(header.UnpSizeHigh) << 32 );
        entry->time         = DosTimeToUnixTime(header.FileTime);
        entry->uuid         = uuid++;
        /*
        mode_t mode = header.FileAttr;
         // No using now. need to do some test about real POSIX mode data here, not only read-for-owner access.
         */
        
        if(is_directory)
            FindOrBuildDirectory(string(utf8buf) + '/')->time = entry->time;
        
		if ((proc_file_ret = RARProcessFile(_rar_handle, RAR_SKIP, NULL, NULL)) != 0)
            return VFSError::GenericError; // TODO: need an adequate error code here
	}
    
    m_LastItemUID = uuid - 1;
    
    return 0;
}

VFSArchiveUnRARDirectory *VFSArchiveUnRARHost::FindOrBuildDirectory(const string& _path_with_tr_sl)
{
    auto i = m_PathToDir.find(_path_with_tr_sl);
    if(i != m_PathToDir.end())
        return &i->second;
    
    auto last_sl = _path_with_tr_sl.size() - 2;
    while(_path_with_tr_sl[last_sl] != '/')
        --last_sl;
    
    auto parent_dir = FindOrBuildDirectory( string(_path_with_tr_sl, 0, last_sl + 1) );
    auto &entries = parent_dir->entries;

    string short_name(_path_with_tr_sl, last_sl + 1, _path_with_tr_sl.size() - last_sl - 2);
    
    if( find_if(begin(entries), end(entries), [&](const VFSArchiveUnRAREntry&i) {return i.name == short_name;} )
       == end(parent_dir->entries) ) {
        parent_dir->entries.emplace_back();
        parent_dir->entries.back().name = short_name;
    }
    
    auto dir = m_PathToDir.emplace(_path_with_tr_sl);
    dir.first->second.full_path = _path_with_tr_sl;
    return &dir.first->second;
}

int VFSArchiveUnRARHost::FetchDirectoryListing(const char *_path,
                                               shared_ptr<VFSListing> *_target,
                                               int _flags,
                                               bool (^_cancel_checker)())
{
    string path = _path;
    if(path.back() != '/')
        path += '/';
    
    auto i = m_PathToDir.find(path);
    if(i == m_PathToDir.end())
        return VFSError::NotFound;
    
    auto listing = make_shared<VFSArchiveUnRARListing>(i->second, path.c_str(), _flags, SharedPtr());
    
    if(_cancel_checker && _cancel_checker())
        return VFSError::Cancelled;
    
    *_target = listing;
    
    return VFSError::Ok;
}

int VFSArchiveUnRARHost::Stat(const char *_path, VFSStat &_st, int _flags, bool (^_cancel_checker)())
{
    if(_path == 0)
        return VFSError::InvalidCall;
    
    if(_path[0] != '/')
        return VFSError::NotFound;
    
    if(strlen(_path) == 1)
    {
        // we have no info about root dir - dummy here
        memset(&_st, 0, sizeof(_st));
        _st.mode = S_IRUSR | S_IWUSR | S_IFDIR;
        return VFSError::Ok;
    }
    
    auto it = FindEntry(_path);
    if(it)
    {
        memset(&_st, 0, sizeof(_st));
        _st.size = it->unpacked_size;
        _st.mode = S_IRUSR | S_IWUSR | (it->isdir ? S_IFDIR : 0);
        _st.atime.tv_sec = it->time;
        _st.mtime.tv_sec = it->time;
        _st.ctime.tv_sec = it->time;
        _st.btime.tv_sec = it->time;
        return VFSError::Ok;
    }
    
    return VFSError::NotFound;
}

const VFSArchiveUnRAREntry *VFSArchiveUnRARHost::FindEntry(const string &_full_path)
{
    if(_full_path.empty())
        return nullptr;
    if(_full_path[0] != '/')
        return nullptr;
    if(_full_path.length() == 1 && _full_path[0] == '/')
        return nullptr;
    
    string path = _full_path;
    if(path.back() == '/')
        path.pop_back();
    
    auto last_sl = path.rfind('/');
    assert(last_sl != string::npos);
    string parent_dir(path, 0, last_sl + 1);
    
    auto directory = m_PathToDir.find(parent_dir);
    if(directory == m_PathToDir.end())
        return nullptr;

    string filename(path.c_str() + last_sl + 1);
    for(const auto &it: directory->second.entries)
        if(it.name == filename)
            return &it;

    return nullptr;
}
