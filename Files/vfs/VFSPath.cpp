//
//  VFSPath.mm
//  Files
//
//  Created by Michael G. Kazakov on 20.12.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import "VFS.h"

bool VFSPathStack::Part::operator==(const Part&_r) const
{
    return fs_tag == _r.fs_tag &&
            junction == _r.junction &&
            !host.owner_before(_r.host) && !_r.host.owner_before(host) && // tricky weak_ptr comparison
            options == _r.options
            ;
}

bool VFSPathStack::Part::weak_equal(const Part&_r) const
{
    if(*this == _r)
        return true;
       
    if(fs_tag != _r.fs_tag) return false;
    if(junction != _r.junction) return false;
    if(options == nullptr && _r.options != nullptr) return false;
    if(options != nullptr && _r.options == nullptr) return false;
    if(options != nullptr && !options->Equal(*_r.options)) return false;
    return true;
}

VFSPathStack::VFSPathStack()
{
}

VFSPathStack::VFSPathStack(const VFSListing &_listing)
{
    // 1st - calculate host's depth
    int depth = 0;
    VFSHost* curr_host = _listing.Host().get();
    while(curr_host != nullptr) {
        depth++;
        curr_host = curr_host->Parent().get();
    }
    
    if(depth == 0)
        return; // we're empty - invalid case
    
    // build vfs stack
    m_Stack.resize(depth);
    curr_host = _listing.Host().get();
    do {
        m_Stack[depth-1].fs_tag = curr_host->FSTag();
        m_Stack[depth-1].junction = curr_host->JunctionPath();
        m_Stack[depth-1].host = curr_host->shared_from_this();
        m_Stack[depth-1].options = curr_host->Options();
        curr_host = curr_host->Parent().get();
        --depth;
    } while(curr_host != nullptr);
    
    // remember relative path we're at
    m_Path = _listing.RelativePath();
}

VFSPathStack::VFSPathStack(const VFSPathStack&_r):
    m_Stack(_r.m_Stack),
    m_Path(_r.m_Path)
{
}

VFSPathStack::VFSPathStack(VFSPathStack&&_r):
    m_Stack(move(_r.m_Stack)),
    m_Path(move(_r.m_Path))
{
}

bool VFSPathStack::weak_equal(const VFSPathStack&_r) const
{
    if(m_Stack.size() != _r.m_Stack.size()) return false;
    if(m_Path != _r.m_Path) return false;
    auto i = begin(m_Stack), j = begin(_r.m_Stack), e = end(m_Stack);
    for(;i != e; ++i, ++j)
        if(!i->weak_equal(*j))
            return false;
    return true;
}

string VFSPathStack::verbose_string() const
{
    if(m_Stack.empty())
        return m_Path;
    
    // TODO: real implementation
    string res;

    auto fs_tag = m_Stack.front().fs_tag;
    if( fs_tag == VFSNetFTPHost::Tag )  res += "ftp://";
    if( fs_tag == VFSNetSFTPHost::Tag ) res += "sftp://";
    if( fs_tag == VFSPSHost::Tag )      res += "[psfs]:";
    
    for( auto &i: m_Stack )
        res += i.junction;
    res += m_Path;
    return res;
}
