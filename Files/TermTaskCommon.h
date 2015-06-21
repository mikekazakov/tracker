//
//  TermTaskCommon.h
//  Files
//
//  Created by Michael G. Kazakov on 03.04.14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#pragma once

namespace TermTask
{
    
int SetupTermios(int _fd);
    
int SetTermWindow(int _fd,
                  unsigned short _chars_width,
                  unsigned short _chars_height,
                  unsigned short _pix_width = 0,
                  unsigned short _pix_height = 0);
    
void SetupHandlesAndSID(int _slave_fd);

map<string, string> BuildEnv();
void SetEnv(const map<string, string>& _env);
    
}
