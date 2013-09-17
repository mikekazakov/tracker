//
//  IconsGenerator.h
//  Files
//
//  Created by Michael G. Kazakov on 04.09.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once

#import <memory>
#import <map>

#import "VFS.h"

class IconsGenerator : public std::enable_shared_from_this<IconsGenerator>
{
public:
    IconsGenerator();
    ~IconsGenerator();
    
    void SetUpdateCallback(void (^_cb)()); // callback will be executed in main thread
    void SetIconMode(int _mode);
    void SetIconSize(int _size);    
    NSImageRep *ImageFor(unsigned _no, VFSListing &_listing);
    void Flush(); // should be called on every directory changes thus loosing generating icons' ID
    
    enum IconMode
    {
        IconModeGeneric = 0,
        IconModeFileIcons,
        IconModeFileIconsThumbnails,
        IconModesCount
    };
    
private:
    enum {MaxIcons = 65535,
        MaxFileSizeForThumbnailNative = 256*1024*1024,
        MaxFileSizeForThumbnailNonNative = 1*1024*1024 // ?
    };

    
    
    struct Meta
    {
        uint64_t    file_size;
        mode_t      unix_mode;
        std::string extension;
        std::string relative_path;
        std::shared_ptr<VFSHost> host;
        
        NSImageRep *generic;   // just folder or document icon
        
        NSImageRep *filetype;  // icon generated from file's extension or taken from a bundle
        
        NSImageRep *thumbnail; // the best - thumbnail generated from file's content
        
        
    };
    
    std::map<unsigned short, std::shared_ptr<Meta>> m_Icons;
    unsigned int m_LastIconID;
    NSRect m_IconSize;    
    NSImageRep *m_GenericFileIcon;
    NSImageRep *m_GenericFolderIcon;

    dispatch_group_t m_WorkGroup;    // working queue is concurrent
    dispatch_queue_t m_ControlQueue; // linear queue

    int              m_StopWorkQueue;
    int              m_IconsMode;
    void             (^m_UpdateCallback)();
    
    void BuildGenericIcons();
    void Runner(std::shared_ptr<Meta> _meta, std::shared_ptr<IconsGenerator> _guard);
    void StopWorkQueue();
    
    
    
    // denied! (c) Quake3
    IconsGenerator(const IconsGenerator&) = delete;
    void operator=(const IconsGenerator&) = delete;
};
