//
//  SavedNetworkConnectionsManager.h
//  Files
//
//  Created by Michael G. Kazakov on 22/12/14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#pragma once

class SavedNetworkConnectionsManager
{
public:
    struct AbstractConnection;
    struct FTPConnection;
    struct SFTPConnection;

    static SavedNetworkConnectionsManager &Instance();
    
    /**
     * inserts a connection in front of connections list.
     * remove duplicates if any
     */
    void InsertConnection(const shared_ptr<AbstractConnection> &_conn);
    
    vector<shared_ptr<FTPConnection>> GetFTPConnections() const;
    void EraseAllFTPConnections();
    
    bool SetPassword(const shared_ptr<AbstractConnection> &_conn, const string& _password);
    bool GetPassword(const shared_ptr<AbstractConnection> &_conn, string& _password);
private:
    SavedNetworkConnectionsManager();
    static void SaveConnections(const vector<shared_ptr<AbstractConnection>> &_conns);
    static vector<shared_ptr<AbstractConnection>> LoadConnections();
    
    vector<shared_ptr<AbstractConnection>> m_Connections;
    mutable mutex m_Lock;
};

struct SavedNetworkConnectionsManager::AbstractConnection
{
    AbstractConnection();
    virtual ~AbstractConnection();
    
    virtual bool Equal(const AbstractConnection& _rhs) const = 0;
    virtual string KeychainWhere() const = 0;
    virtual string KeychainAccount() const = 0;
};

struct SavedNetworkConnectionsManager::FTPConnection : AbstractConnection
{
    FTPConnection( const string &_user, const string &_host, const string &_path, long  _port );
    const string user;
    const string host;
    const string path;
    const long   port;

    virtual bool Equal(const AbstractConnection& _rhs) const override;
    virtual string KeychainWhere() const override;
    virtual string KeychainAccount() const override;
};
