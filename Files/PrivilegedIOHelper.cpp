//
//  PrivilegedIOHelper.c
//  Files
//
//  Created by Michael G. Kazakov on 29/11/14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <xpc/xpc.h>
#include <syslog.h>
#include <errno.h>
#include <stdio.h>

void send_reply_error(xpc_object_t _from_event, int _error)
{
    xpc_connection_t remote = xpc_dictionary_get_remote_connection(_from_event);
    xpc_object_t reply = xpc_dictionary_create_reply(_from_event);
    xpc_dictionary_set_int64(reply, "error", _error);
    xpc_connection_send_message(remote, reply);
    xpc_release(reply);
}

void send_reply_ok(xpc_object_t _from_event)
{
    xpc_connection_t remote = xpc_dictionary_get_remote_connection(_from_event);
    xpc_object_t reply = xpc_dictionary_create_reply(_from_event);
    xpc_dictionary_set_bool(reply, "ok", true);
    xpc_connection_send_message(remote, reply);
    xpc_release(reply);
}

void send_reply_fd(xpc_object_t _from_event, int _fd)
{
    xpc_connection_t remote = xpc_dictionary_get_remote_connection(_from_event);
    xpc_object_t reply = xpc_dictionary_create_reply(_from_event);
    xpc_dictionary_set_fd(reply, "fd", _fd);
    xpc_connection_send_message(remote, reply);
    xpc_release(reply);
}

// return true if has replied with something
static bool ProcessOperation(const char *_operation,  xpc_object_t _event)
{
    if( strcmp(_operation, "heartbeat") == 0 ) {
        syslog(LOG_NOTICE, "processing heartbeat request");
        send_reply_ok(_event);
    }
    else if( strcmp(_operation, "removeyourself") == 0 ) {
        char path[1024];
        uint32_t size = sizeof(path);
        _NSGetExecutablePath(path, &size);
        if(unlink(path) == 0)
            send_reply_ok(_event);
        else
            send_reply_error(_event, errno);
    }
    else if( strcmp(_operation, "exit") == 0 ) {
        // no responce here
        syslog(LOG_NOTICE, "goodbye, cruel world!");
        exit(0);
    }
    else if( strcmp(_operation, "open") == 0 ) {
        xpc_object_t xpc_path = xpc_dictionary_get_value(_event, "path");
        if( xpc_path == nullptr || xpc_get_type(xpc_path) != XPC_TYPE_STRING )
            return false;
        const char *path = xpc_string_get_string_ptr(xpc_path);
        
        xpc_object_t xpc_flags = xpc_dictionary_get_value(_event, "flags");
        if( xpc_flags == nullptr || xpc_get_type(xpc_flags) != XPC_TYPE_INT64 )
            return false;
        int flags = (int)xpc_int64_get_value(xpc_flags);
        
        xpc_object_t xpc_mode = xpc_dictionary_get_value(_event, "mode");
        if( xpc_mode == nullptr || xpc_get_type(xpc_mode) != XPC_TYPE_INT64 )
            return false;
        int mode = (int)xpc_int64_get_value(xpc_mode);
        
        int fd = open(path, flags, mode);
        if(fd >= 0) {
            send_reply_fd(_event, fd);
            close(fd);
        }
        else {
            send_reply_error(_event, errno);
        }
    }
    else if( strcmp(_operation, "stat") == 0 ) {
        xpc_object_t xpc_path = xpc_dictionary_get_value(_event, "path");
        if( xpc_path == nullptr || xpc_get_type(xpc_path) != XPC_TYPE_STRING )
            return false;
        
        const char *path = xpc_string_get_string_ptr(xpc_path);
        struct stat st;
        int ret = stat(path, &st);
        if(ret == 0) {
            xpc_connection_t remote = xpc_dictionary_get_remote_connection(_event);
            xpc_object_t reply = xpc_dictionary_create_reply(_event);
            xpc_dictionary_set_data(reply, "st", &st, sizeof(st));
            xpc_connection_send_message(remote, reply);
            xpc_release(reply);
        }
        else {
            send_reply_error(_event, errno);
        }
    }
    else if( strcmp(_operation, "lstat") == 0 ) {
        xpc_object_t xpc_path = xpc_dictionary_get_value(_event, "path");
        if( xpc_path == nullptr || xpc_get_type(xpc_path) != XPC_TYPE_STRING )
            return false;
        
        const char *path = xpc_string_get_string_ptr(xpc_path);
        struct stat st;
        int ret = lstat(path, &st);
        if(ret == 0) {
            xpc_connection_t remote = xpc_dictionary_get_remote_connection(_event);
            xpc_object_t reply = xpc_dictionary_create_reply(_event);
            xpc_dictionary_set_data(reply, "st", &st, sizeof(st));
            xpc_connection_send_message(remote, reply);
            xpc_release(reply);
        }
        else {
            send_reply_error(_event, errno);
        }
    }
    else
        return false;
    
    return true;
}

static void XPC_Peer_Event_Handler(xpc_connection_t _peer, xpc_object_t _event)
{
   syslog(LOG_NOTICE, "Received event");
    
    xpc_type_t type = xpc_get_type(_event);
    
    if (type == XPC_TYPE_ERROR) {
        if (_event == XPC_ERROR_CONNECTION_INVALID) {
            // The client process on the other end of the connection has either
            // crashed or cancelled the connection. After receiving this error,
            // the connection is in an invalid state, and you do not need to
            // call xpc_connection_cancel(). Just tear down any associated state
            // here.
            
        } else if (_event == XPC_ERROR_TERMINATION_IMMINENT) {
            // Handle per-connection termination cleanup.
        }
        xpc_release(_peer);
        
    } else if(type == XPC_TYPE_DICTIONARY) {
        
        if( const char *op = xpc_dictionary_get_string(_event, "operation") ) {
            syslog(LOG_NOTICE, "received operation request: %s", op);
            
            if( ProcessOperation(op, _event) )
                return;
        }
        
        send_reply_error(_event, EINVAL);
    }
}

static void XPC_Connection_Handler(xpc_connection_t connection)  {
    syslog(LOG_NOTICE, "Configuring message event handler for helper.");
    
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        XPC_Peer_Event_Handler(connection, event);
    });
    
    xpc_connection_resume(connection);
}

// TODO: filter incoming connections at least with
//xpc_connection_get_name

int main(int argc, const char *argv[])
{
    
    syslog(LOG_NOTICE, "main() start");

    
    xpc_connection_t service = xpc_connection_create_mach_service("info.filesmanager.Files.PrivilegedIOHelper",
                                                                  dispatch_get_main_queue(),
                                                                  XPC_CONNECTION_MACH_SERVICE_LISTENER);
    
    if (!service) {
        syslog(LOG_NOTICE, "Failed to create service.");
        exit(EXIT_FAILURE);
    }
    
    syslog(LOG_NOTICE, "Configuring connection event handler for helper");
    xpc_connection_set_event_handler(service, ^(xpc_object_t connection) {
        XPC_Connection_Handler((xpc_connection_t)connection);
    });
    
    xpc_connection_resume(service);
    
    syslog(LOG_NOTICE, "runs dispatch_main()");
    dispatch_main();
    
    return EXIT_SUCCESS;
}
