#include <sys/attr.h>
#include <sys/errno.h>
#include <sys/vnode.h>
#include <Habanero/algo.h>
#include <RoutedIO/RoutedIO.h>
#include <Utility/PathManip.h>
#include <VFS/VFSError.h>
#include "Fetching.h"

// hack to access function from libc implementation directly.
// this func does readdir but without mutex locking
struct dirent	*_readdir_unlocked(DIR *, int) __DARWIN_INODE64(_readdir_unlocked);

static mode_t VNodeToUnixMode( const fsobj_type_t _type )
{
    switch( _type ) {
        case VREG:  return S_IFREG;
        case VDIR:  return S_IFDIR;
        case VBLK:  return S_IFBLK;
        case VCHR:  return S_IFCHR;
        case VLNK:  return S_IFLNK;
        case VSOCK: return S_IFSOCK;
        case VFIFO: return S_IFIFO;
        default:    return 0;
    };
}

static int LStatByPath(PosixIOInterface &_io,
                       const char *_path,
                       const VFSNativeFetching::Callback &_cb_param)
{
    struct stat stat_buffer;
    int ret = _io.lstat(_path, &stat_buffer);
    if( ret != 0)
        return ret;
 
    VFSNativeFetching::CallbackParams params;
    params.filename = "";
    params.crt_time = stat_buffer.st_birthtimespec.tv_sec;
    params.mod_time = stat_buffer.st_mtimespec.tv_sec;
    params.chg_time = stat_buffer.st_mtimespec.tv_sec;
    params.acc_time = stat_buffer.st_ctimespec.tv_sec;
    params.add_time = -1;
    params.uid      = stat_buffer.st_uid;
    params.gid      = stat_buffer.st_gid;
    params.mode     = stat_buffer.st_mode;
    params.dev      = stat_buffer.st_dev;
    params.inode    = stat_buffer.st_ino;
    params.flags    = stat_buffer.st_flags;
    params.size     = stat_buffer.st_size;
    
    _cb_param(params);

    return 0;
}

int VFSNativeFetching::ReadSingleEntryAttributesByPath(
    PosixIOInterface &_io,
    const char *_path,
    const Callback &_cb_param)
{
    struct Attrs {
        uint32_t          length;
        attribute_set_t   returned;
        dev_t             dev;
        fsobj_type_t      obj_type;
        fsobj_id_t        obj_id;
        struct timespec   crt_time;
        struct timespec   mod_time;
        struct timespec   chg_time;
        struct timespec   acc_time;
        uid_t             uid;
        gid_t             gid;
        u_int32_t         access;
        u_int32_t         flags;
        struct timespec   add_time;
        off_t             file_size;
    } __attribute__((aligned(4), packed)) attrs; // for convenience, not very used
    
    attrlist attr_list;
    memset(&attr_list, 0, sizeof(attr_list));
    attr_list.bitmapcount = ATTR_BIT_MAP_COUNT;
    attr_list.commonattr  = ATTR_CMN_RETURNED_ATTRS |
                            ATTR_CMN_DEVID          |
                            ATTR_CMN_OBJTYPE        |
                            ATTR_CMN_OBJPERMANENTID |
                            ATTR_CMN_CRTIME         |
                            ATTR_CMN_MODTIME        |
                            ATTR_CMN_CHGTIME        |
                            ATTR_CMN_ACCTIME        |
                            ATTR_CMN_ADDEDTIME      |
                            ATTR_CMN_OWNERID        |
                            ATTR_CMN_GRPID          |
                            ATTR_CMN_ACCESSMASK	    |
                            ATTR_CMN_FLAGS;
    attr_list.fileattr    = ATTR_FILE_DATALENGTH;
    
    const int fd = _io.open(_path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if( fd < 0 ) {
        int error = errno;
        if( error == ELOOP ) {
            // special treating for symlinks - they can't be opened by open(), so fall back to
            // regular stat():
            return LStatByPath(_io, _path, _cb_param);
        }
        
        return error;
    }
    auto close_fd = at_scope_end([fd]{
        close(fd);
    });

    if( fgetattrlist( fd, &attr_list, &attrs, sizeof(attrs), 0) != 0 )
        return errno;
    
    CallbackParams params;
    params.filename = "";
    
    if( attrs.returned.commonattr & ATTR_CMN_DEVID )
        params.dev = attrs.dev;
    
    params.mode = 0;
    if( attrs.returned.commonattr & ATTR_CMN_OBJTYPE )
        params.mode = VNodeToUnixMode( attrs.obj_type );
    
    if( attrs.returned.commonattr & ATTR_CMN_OBJPERMANENTID )
        params.inode = attrs.obj_id.fid_objno;
    
    if( attrs.returned.commonattr & ATTR_CMN_CRTIME )
        params.crt_time = attrs.crt_time.tv_sec;
    
    if( attrs.returned.commonattr & ATTR_CMN_MODTIME )
        params.mod_time = attrs.mod_time.tv_sec;
    
    if( attrs.returned.commonattr & ATTR_CMN_CHGTIME )
        params.chg_time = attrs.chg_time.tv_sec;
    
    if( attrs.returned.commonattr & ATTR_CMN_ACCTIME )
        params.acc_time = attrs.acc_time.tv_sec;
    
    if( attrs.returned.commonattr & ATTR_CMN_OWNERID )
        params.uid = attrs.uid;
    
    if( attrs.returned.commonattr & ATTR_CMN_GRPID )
        params.gid = attrs.gid;
    
    if( attrs.returned.commonattr & ATTR_CMN_ACCESSMASK )
        params.mode |= attrs.access;
    
    if( attrs.returned.commonattr & ATTR_CMN_FLAGS )
        params.flags = attrs.flags;
    
    if( attrs.returned.commonattr & ATTR_CMN_ADDEDTIME )
        params.add_time = attrs.add_time.tv_sec;
    else
        params.add_time = -1;
    
    if( attrs.returned.fileattr & ATTR_FILE_DATALENGTH )
        params.size = attrs.file_size;
    else
        params.size = -1;
    
    _cb_param( params );
    
    return 0;
}

// assuming this will be called when Admin Mode is on
int VFSNativeFetching::ReadDirAttributesStat(
    const int _dir_fd,
    const char *_dir_path,
    const function<void(int _fetched_now)> &_cb_fetch,
    const Callback &_cb_param)
{
    // initial directory lookup
    vector< tuple<string, uint64_t, uint8_t > > dirents; // name, inode, entry_type
    if( auto dirp = fdopendir( dup(_dir_fd) ) ) {
        auto close_dir = at_scope_end([=]{ closedir(dirp); });
        static const auto dirents_reserve_amount = 64;
        dirents.reserve( dirents_reserve_amount );
        while( auto entp = ::_readdir_unlocked(dirp, 1) ) {
            if(entp->d_ino == 0 ||          // apple's documentation suggest to skip such files
               strisdot(entp->d_name) ||    // do not process self entry
               strisdotdot(entp->d_name) )  // do not process parent entry
                continue;
            
            dirents.emplace_back(string(entp->d_name, entp->d_namlen), entp->d_ino, entp->d_type);
        }
    }
    else
        return errno;

    // call stat() for every directory entry
    auto &io = RoutedIO::Default;
    for( auto &e: dirents ) {
        // need absolute paths
        const string entry_path = _dir_path + get<0>(e);
        
        // stat the file
        struct stat stat_buffer;
        if( io.lstat(entry_path.c_str(), &stat_buffer) == 0 ) {
            CallbackParams params;
            params.filename = get<0>(e).c_str();
            params.crt_time = stat_buffer.st_birthtimespec.tv_sec;
            params.mod_time = stat_buffer.st_mtimespec.tv_sec;
            params.chg_time = stat_buffer.st_mtimespec.tv_sec;
            params.acc_time = stat_buffer.st_ctimespec.tv_sec;
            params.add_time = -1;
            params.uid      = stat_buffer.st_uid;
            params.gid      = stat_buffer.st_gid;
            params.mode     = stat_buffer.st_mode;
            params.dev      = stat_buffer.st_dev;
            params.inode    = stat_buffer.st_ino;
            params.flags    = stat_buffer.st_flags;
            params.size     = stat_buffer.st_size;
            
            _cb_fetch(1);
            _cb_param(params);
        }
    }
    
    return 0;
}

int VFSNativeFetching::ReadDirAttributesBulk(
    const int _dir_fd,
    const function<void(int _fetched_now)> &_cb_fetch,
    const Callback &_cb_param)
{
    struct Attrs {
        uint32_t          length;
        attribute_set_t   returned;
        uint32_t          error;
        attrreference_t   name_info;
        char              *name;
        dev_t             dev;
        fsobj_type_t      obj_type;
        fsobj_id_t        obj_id;
        struct timespec   crt_time;
        struct timespec   mod_time;
        struct timespec   chg_time;
        struct timespec   acc_time;
        uid_t             uid;
        gid_t             gid;
        u_int32_t         access;
        u_int32_t         flags;
        struct timespec   add_time;
        off_t             file_size;
    } __attribute__((aligned(4), packed)); // for convenience, not very used

    attrlist attr_list;
    memset(&attr_list, 0, sizeof(attr_list));
    attr_list.bitmapcount = ATTR_BIT_MAP_COUNT;
    attr_list.commonattr  = ATTR_CMN_RETURNED_ATTRS |
                            ATTR_CMN_NAME           |
                            ATTR_CMN_ERROR          |
                            ATTR_CMN_DEVID          |    
                            ATTR_CMN_OBJTYPE        |
                            ATTR_CMN_OBJPERMANENTID |
                            ATTR_CMN_CRTIME         |
                            ATTR_CMN_MODTIME        |
                            ATTR_CMN_CHGTIME        |
                            ATTR_CMN_ACCTIME        |
                            ATTR_CMN_ADDEDTIME      |
                            ATTR_CMN_OWNERID        |
                            ATTR_CMN_GRPID          |
                            ATTR_CMN_ACCESSMASK	    |
                            ATTR_CMN_FLAGS;
    attr_list.fileattr    = ATTR_FILE_DATALENGTH;
    

    char attr_buf[65536];
    CallbackParams params;
    while( true ) {
        const int retcount = getattrlistbulk(_dir_fd,
                                             &attr_list,
                                             &attr_buf[0],
                                             sizeof(attr_buf),
                                             0);
        if( retcount < 0 )
            return errno;
        else if (retcount == 0)
            return 0;
        else {
            _cb_fetch(retcount);
            
            char *entry_start = &attr_buf[0];
            for( int index = 0; index < retcount; index++ ) {
                Attrs attrs = {0};
                
                char *field = entry_start;
                attrs.length = *(uint32_t *)field;
                field += sizeof(uint32_t);
                
                entry_start += attrs.length;
                
                attrs.returned = *(attribute_set_t *)field;
                field += sizeof(attribute_set_t);
                
                if( attrs.returned.commonattr & ATTR_CMN_ERROR ) {
                    attrs.error = *(uint32_t *)field;
                    field += sizeof(uint32_t);
                }
                
                if( attrs.error != 0 )
                    continue;
                
                if ( attrs.returned.commonattr & ATTR_CMN_NAME ) {
                    params.filename = field + ((attrreference_t *)field)->attr_dataoffset;
                    field += sizeof(attrreference_t);
                }
                else
                    continue; // can't work without filename
                
                if( attrs.returned.commonattr & ATTR_CMN_DEVID ) {
                    params.dev = *(dev_t*)field;
                    field += sizeof(dev_t);
                }
                
                params.mode = 0;
                if( attrs.returned.commonattr & ATTR_CMN_OBJTYPE ) {
                    params.mode = VNodeToUnixMode(*(fsobj_type_t *)field);
                    field += sizeof(fsobj_type_t);
                }
                
                if( attrs.returned.commonattr & ATTR_CMN_OBJPERMANENTID ) {
                    params.inode = ((fsobj_id_t*)field)->fid_objno;
                    field += sizeof(fsobj_id_t);
                }

                if( attrs.returned.commonattr & ATTR_CMN_CRTIME ) {
                    params.crt_time = ((timespec*)field)->tv_sec;
                    field += sizeof(timespec);
                }
                
                if( attrs.returned.commonattr & ATTR_CMN_MODTIME ) {
                    params.mod_time = ((timespec*)field)->tv_sec;
                    field += sizeof(timespec);
                }

                if( attrs.returned.commonattr & ATTR_CMN_CHGTIME ) {
                    params.chg_time = ((timespec*)field)->tv_sec;
                    field += sizeof(timespec);
                }

                if( attrs.returned.commonattr & ATTR_CMN_ACCTIME ) {
                    params.acc_time = ((timespec*)field)->tv_sec;
                    field += sizeof(timespec);
                }
                
                if( attrs.returned.commonattr & ATTR_CMN_OWNERID ) {
                    params.uid = *(uid_t*)field;
                    field += sizeof(uid_t);
                }

                if( attrs.returned.commonattr & ATTR_CMN_GRPID ) {
                    params.gid = *(gid_t*)field;
                    field += sizeof(gid_t);
                }

                if( attrs.returned.commonattr & ATTR_CMN_ACCESSMASK ) {
                    params.mode |= ((*(u_int32_t*)field) & (~S_IFMT));
                    field += sizeof(u_int32_t);
                }
                
                if( attrs.returned.commonattr & ATTR_CMN_FLAGS ) {
                    params.flags = *(uint32_t*)field;
                    field += sizeof(u_int32_t);
                }
                
                if( attrs.returned.commonattr & ATTR_CMN_ADDEDTIME ) {
                    params.add_time = ((timespec*)field)->tv_sec;
                    field += sizeof(timespec);
                }
                else
                    params.add_time = -1;
                
                if( attrs.returned.fileattr & ATTR_FILE_DATALENGTH ) {
                    params.size = *(off_t*)field;
                    /* field += sizeof(off_t); */
                }
                else
                    params.size = -1;
                    
                _cb_param( params );
            }
        }
    }
}

int VFSNativeFetching::CountDirEntries( const int _dir_fd )
{
    struct Count {
        u_int32_t length;
        u_int32_t count;
    } __attribute__((aligned(4), packed)) count;

    struct attrlist attr_list;
    memset(&attr_list, 0, sizeof(attr_list));
    attr_list.bitmapcount = ATTR_BIT_MAP_COUNT;
    attr_list.dirattr = ATTR_DIR_ENTRYCOUNT;
    if( fgetattrlist( _dir_fd, &attr_list, &count, sizeof(count), 0 ) == 0 )
        return count.count;
    return VFSError::FromErrno();
}
