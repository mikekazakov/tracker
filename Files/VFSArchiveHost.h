//
//  VFSArchiveHost.h
//  Files
//
//  Created by Michael G. Kazakov on 27.08.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once

#import <map>
#import <list>
#import "VFSHost.h"
#import "VFSFile.h"


struct VFSArchiveMediator;
struct VFSArchiveDir;
struct VFSArchiveDirEntry;
struct VFSArchiveSeekCache;

class VFSArchiveHost : public VFSHost
{
public:
    VFSArchiveHost(const char *_junction_path,
                   shared_ptr<VFSHost> _parent);
    ~VFSArchiveHost();
    
    virtual const char *FSTag() const override;
    
    int Open(); // flags will be added later

    
    
    virtual bool IsDirectory(const char *_path,
                             int _flags,
                             bool (^_cancel_checker)()) override;
    
    virtual int StatFS(const char *_path, VFSStatFS &_stat, bool (^_cancel_checker)()) override;    
    virtual int Stat(const char *_path, struct stat &_st, int _flags, bool (^_cancel_checker)()) override;    
    
    virtual int CreateFile(const char* _path,
                           shared_ptr<VFSFile> *_target,
                           bool (^_cancel_checker)()) override;
    
    virtual int FetchDirectoryListing(const char *_path,
                                      shared_ptr<VFSListing> *_target,
                                      int _flags,                                      
                                      bool (^_cancel_checker)()) override;
    
    virtual int IterateDirectoryListing(const char *_path, bool (^_handler)(dirent &_dirent)) override;
    
    virtual int CalculateDirectoriesSizes(
                                          FlexChainedStringsChunk *_dirs, // transfered ownership
                                          const string &_root_path, // relative to current host path
                                          bool (^_cancel_checker)(),
                                          void (^_completion_handler)(const char* _dir_sh_name, uint64_t _size)
                                          ) override;
    virtual int CalculateDirectoryDotDotSize( // will pass ".." as _dir_sh_name upon completion
                                             const string &_root_path, // relative to current host path
                                             bool (^_cancel_checker)(),
                                             void (^_completion_handler)(const char* _dir_sh_name, uint64_t _size)
                                             ) override;
    
    // Caching section - to reduce seeking overhead:
    
    // return zero on not found
    uint32_t ItemUID(const char* _filename);

    // destruct call - will override currently stored one
    void CommitSeekCache(shared_ptr<VFSArchiveSeekCache> _sc);
    
    // destructive call - host will no longer hold returned seek cache
    // if there're no caches, that can satisfy this call - zero ptr is returned
    shared_ptr<VFSArchiveSeekCache> SeekCache(uint32_t _requested_item);
    
    
    shared_ptr<VFSFile> ArFile() const;
    
    struct archive* Archive();
    
    shared_ptr<const VFSArchiveHost> SharedPtr() const {return static_pointer_cast<const VFSArchiveHost>(VFSHost::SharedPtr());}
    shared_ptr<VFSArchiveHost> SharedPtr() {return static_pointer_cast<VFSArchiveHost>(VFSHost::SharedPtr());}
private:
    int ReadArchiveListing();
    VFSArchiveDir* FindOrBuildDir(const char* _path_with_tr_sl);
    const VFSArchiveDirEntry *FindEntry(const char* _path);
    
    void InsertDummyDirInto(VFSArchiveDir *_parent, const char* _dir_name);
    
    shared_ptr<VFSFile>                m_ArFile;
    shared_ptr<VFSArchiveMediator>     m_Mediator;
    struct archive                         *m_Arc;
    map<string, VFSArchiveDir*>   m_PathToDir;
    uint64_t                                m_ArchiveFileSize;
    uint64_t                                m_ArchivedFilesTotalSize;
    uint32_t                                m_LastItemUID;
    
    list<shared_ptr<VFSArchiveSeekCache>> m_SeekCaches;
    
    dispatch_queue_t                        m_SeekCacheControl;
};
