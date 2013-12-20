//
//  BigFileViewDataBackend.h
//  Files
//
//  Created by Michael G. Kazakov on 29.09.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once
#import "FileWindow.h"
#import <memory>

// this class encapsulates working with file windows and decoding raw data into UniChars
// BigFileViewDataBackend has no ownership on FileWindow, it should be released by caller's code
class BigFileViewDataBackend : public enable_shared_from_this<BigFileViewDataBackend>
{
public:
    BigFileViewDataBackend(FileWindow *_fw, int _encoding);
    ~BigFileViewDataBackend();

    ////////////////////////////////////////////////////////////////////////////////////////////
    // settings
    int Encoding() const;
    void SetEncoding(int _encoding);

    ////////////////////////////////////////////////////////////////////////////////////////////
    // operations
    int MoveWindowSync(uint64_t _pos); // return VFS error code
    
    ////////////////////////////////////////////////////////////////////////////////////////////
    // data access
    bool        IsFullCoverage() const; // returns true if FileWindow is buffering whole file contents
                                        // thus no window movements is needed (and cannot be done)
    
    uint64_t    FileSize() const;       // whole file size
    uint64_t    FilePos()  const;       // position of a file window (offset of it's first byte from the beginning of a file)
    
    const void *Raw() const;            // data of current file window
    uint64_t    RawSize() const;        // file window size. it will not change with this object lives
    
    UniChar     *UniChars() const;      // decoded buffer
    uint32_t    *UniCharToByteIndeces() const;  // byte indeces within file window of decoded unichars
    uint32_t    UniCharsSize() const;   // decoded buffer size in unichars

    ////////////////////////////////////////////////////////////////////////////////////////////
    // handlers
    void SetOnDecoded(void (^_handler)());
private:
    void DecodeBuffer(); // called by internal update logic
    
    FileWindow *m_FileWindow;
    int         m_Encoding;
    void        (^m_OnDecoded)();
    
    UniChar         *m_DecodeBuffer;        // decoded buffer with unichars
                                            // useful size of m_DecodedBufferSize
    uint32_t        *m_DecodeBufferIndx;    // array indexing every m_DecodeBuffer unicode character into a
                                            // byte offset within original file window
                                            // useful size of m_DecodedBufferSize
    size_t          m_DecodedBufferSize;    // amount of unichars
    
    BigFileViewDataBackend(const BigFileViewDataBackend&) = delete;
    void operator=(const BigFileViewDataBackend&) = delete;
};


inline uint64_t BigFileViewDataBackend::FileSize() const
{
    return m_FileWindow->FileSize();
}

inline uint64_t BigFileViewDataBackend::FilePos() const
{
    return m_FileWindow->WindowPos();
}

inline const void *BigFileViewDataBackend::Raw() const
{
    return m_FileWindow->Window();
}

inline uint64_t BigFileViewDataBackend::RawSize() const
{
    return m_FileWindow->WindowSize();
}

inline UniChar *BigFileViewDataBackend::UniChars() const
{
    return m_DecodeBuffer;
}

inline uint32_t *BigFileViewDataBackend::UniCharToByteIndeces() const
{
    return m_DecodeBufferIndx;
}

inline uint32_t BigFileViewDataBackend::UniCharsSize() const
{
    return (uint32_t)m_DecodedBufferSize;
}

inline bool BigFileViewDataBackend::IsFullCoverage() const
{
    return m_FileWindow->FileSize() == m_FileWindow->WindowSize();
}
