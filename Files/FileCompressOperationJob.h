//
//  FileCompressOperationJob.h
//  Files
//
//  Created by Michael G. Kazakov on 21.10.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once

#import <vector>
#import "FlexChainedStringsChunk.h"
#import "VFS.h"
#import "OperationJob.h"

@class FileCompressOperation;

class FileCompressOperationJob : public OperationJob
{
public:
    FileCompressOperationJob();
    ~FileCompressOperationJob();
    
    void Init(FlexChainedStringsChunk* _src_files,
              const char*_src_root,
              std::shared_ptr<VFSHost> _src_vfs,
              const char* _dst_root,
              std::shared_ptr<VFSHost> _dst_vfs,
              FileCompressOperation *_operation);
    
private:
    virtual void Do();
    void ScanItems();
    void ScanItem(const char *_full_path, const char *_short_path, const FlexChainedStringsChunk::node *_prefix);
    void ProcessItems();
    void ProcessItem(const FlexChainedStringsChunk::node *_node, int _number);
    bool FindSuitableFilename(char* _full_filename);
    static ssize_t	la_archive_write_callback(struct archive *, void *_client_data, const void *_buffer, size_t _length);
    
    enum class ItemFlags
    {
        no_flags    = 0,
        is_dir      = 1 << 0,
    };
    
    
    __weak FileCompressOperation    *m_Operation;
    FlexChainedStringsChunk         *m_InitialItems,
                                    *m_ScannedItems,
                                    *m_ScannedItemsLast;
    char                            m_SrcRoot[MAXPATHLEN];
    std::shared_ptr<VFSHost>        m_SrcVFS;
    char                            m_DstRoot[MAXPATHLEN];
    std::shared_ptr<VFSHost>        m_DstVFS;
    bool m_SkipAll;
    const FlexChainedStringsChunk::node *m_CurrentlyProcessingItem;
    uint64_t                        m_SourceTotalBytes;
    uint64_t                        m_TotalBytesProcessed;
    std::vector<uint8_t>            m_ItemFlags;
    struct archive                  *m_Archive;
    std::shared_ptr<VFSFile>        m_TargetFile;
};

