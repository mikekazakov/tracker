//
//  path_manip.c
//  Files
//
//  Created by Michael G. Kazakov on 24.10.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#include <string.h>
#include <stdlib.h>
#include "path_manip.h"

bool GetFilenameFromPath(const char* _path, char *_buf)
{
    const char* last_sl  = strrchr(_path, '/');
    if(!last_sl)
        return false;
    if(last_sl == _path + strlen(_path) - 1)
        return false;
    strcpy(_buf, last_sl+1);
    return true;
}

bool GetDirectoryContainingItemFromPath(const char* _path, char *_buf)
{
    const char* last_sl = strrchr(_path, '/');
    if(!last_sl) // don't handle paths like /foo/bar/
        return false;
    memcpy(_buf, _path, last_sl - _path + 1);
    _buf[last_sl - _path + 1] = 0;
    return true;
}

bool GetFilenameFromRelPath(const char* _path, char *_buf)
{
    const char* last_sl  = strrchr(_path, '/');
    if(last_sl == 0) {
        strcpy(_buf, _path); // assume that there's no directories in this path, so return the entire original path
        return true;
    }
    else {
        if(last_sl == _path + strlen(_path) - 1)
            return false; // don't handle paths like "Dir/"
        strcpy(_buf, last_sl+1);
        return true;
    }
}

bool GetDirectoryContainingItemFromRelPath(const char* _path, char *_buf)
{
    const char* last_sl = strrchr(_path, '/');
    if(!last_sl) {
        _buf[0] = 0;
        return true;
    }
    memcpy(_buf, _path, last_sl - _path + 1);
    _buf[last_sl - _path + 1] = 0;
    return true;
}
