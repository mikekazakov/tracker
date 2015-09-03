//
//  variable_container.h
//  Habanero
//
//  Created by Michael G. Kazakov on 02/09/15.
//  Copyright (c) 2015 MIchael Kazakov. All rights reserved.
//

#pragma once

#include <assert.h>
#include <array>
#include <vector>
#include <unordered_map>


template <class T>
class variable_container
{
public:
    typedef T           value_type;
    typedef T&          reference;
    typedef const T&    const_reference;
    
    enum class type : char
    {
        dense   = 0,
        sparse  = 1,
        common  = 2
    };
    
    /**
     * Construction/desctuction/assigning.
     */
    variable_container( type _type );
    variable_container( const variable_container& _rhs );
    variable_container( variable_container&& _rhs );
    ~variable_container();
    const variable_container &operator=( const variable_container& _rhs );
    const variable_container &operator=( variable_container&& _rhs );
    
    /**
     * for common mode return common value.
     * for other modes uses at() of vector<> and unordered_map<>.
     */
    T &at(unsigned _at);
    const T &at(unsigned _at) const;
    
    /**
     * Can be used only with Dense mode, ignored otherwise.
     */
    void resize( unsigned _new_size );
    
    /**
     * if mode is Dense an _at is above current size -> will resize accordingly.
     * if mode is Common will ignore _at and fill common value with _value.
     */
    void insert( unsigned _at, const T& _value );
    void insert( unsigned _at, T&& _value );

    /**
     * for common mode return true always.
     * for sparse checks for presence of this item.
     * for dense check vector bounds.
     */
    bool has( unsigned _at ) const;
    
private:
    typedef value_type                          common_type;
    typedef std::unordered_map<unsigned, T>     sparse_type;
    typedef std::vector<T>                      dense_type;
    enum {
        m_StorageSize = std::max( {sizeof(common_type), sizeof(sparse_type), sizeof(dense_type)} )
    };
    
    common_type         &Common();
    const common_type   &Common() const;
    sparse_type         &Sparse();
    const sparse_type   &Sparse() const;
    dense_type          &Dense();
    const dense_type    &Dense() const;
    
    void Construct();
    void ConstructCopy(const variable_container<T>& _rhs);
    void ConstructMove(variable_container<T>&& _rhs);
    void Destruct();

    std::array<char,
               m_StorageSize>   m_Storage;
    type                        m_Type;
};

template <class T>
variable_container<T>::variable_container( type _type ) :
    m_Type(_type)
{
    Construct();
}

template <class T>
variable_container<T>::variable_container( const variable_container<T>& _rhs ):
    m_Type(_rhs.m_Type)
{
    ConstructCopy(_rhs);
}

template <class T>
variable_container<T>::variable_container( variable_container<T>&& _rhs ):
    m_Type(_rhs.m_Type)
{
    ConstructMove(move(_rhs));
}

template <class T>
variable_container<T>::~variable_container()
{
    Destruct();
}

template <class T>
const variable_container<T> &variable_container<T>::operator =(const variable_container<T>& _rhs)
{
    if( m_Type != _rhs.m_Type ) {
        Destruct();
        m_Type = _rhs.m_Type;
        ConstructCopy(_rhs);
    }
    else {
        if( m_Type == type::common )
            Common() = _rhs.Common();
        else if( m_Type == type::sparse )
            Sparse() = _rhs.Sparse();
        else if( m_Type == type::dense )
            Dense() = _rhs.Dense();
    }
}

template <class T>
const variable_container<T> &variable_container<T>::operator =(variable_container<T>&& _rhs)
{
    if( m_Type != _rhs.m_Type ) {
        Destruct();
        m_Type = _rhs.m_Type;
        ConstructMove(move(_rhs));
    }
    else {
        if( m_Type == type::common )
            Common() = move(_rhs.Common());
        else if( m_Type == type::sparse )
            Sparse() = move(_rhs.Sparse());
        else if( m_Type == type::dense )
            Dense() = move(_rhs.Dense());
    }
}

template <class T> typename variable_container<T>::common_type &variable_container<T>::Common() {
    return *reinterpret_cast<common_type*>(m_Storage.data());
}

template <class T> const typename variable_container<T>::common_type &variable_container<T>::Common() const {
    return *reinterpret_cast<const common_type*>(m_Storage.data());
}

template <class T> typename variable_container<T>::sparse_type &variable_container<T>::Sparse() {
    return *reinterpret_cast<sparse_type*>(m_Storage.data());
}

template <class T> const typename variable_container<T>::sparse_type &variable_container<T>::Sparse() const {
    return *reinterpret_cast<const sparse_type*>(m_Storage.data());
}

template <class T> typename variable_container<T>::dense_type &variable_container<T>::Dense() {
    return *reinterpret_cast<dense_type*>(m_Storage.data());
}

template <class T> const typename variable_container<T>::dense_type &variable_container<T>::Dense() const {
    return *reinterpret_cast<const dense_type*>(m_Storage.data());
}

template <class T>
void variable_container<T>::Construct()
{
    if( m_Type == type::common )
        new (&Common()) common_type;
    else if( m_Type == type::sparse )
        new (&Sparse()) sparse_type;
    else if( m_Type == type::dense )
        new (&Dense()) dense_type;
    else
        throw std::logic_error("invalid type in variable_container<T>::Contruct()");
}

template <class T>
void variable_container<T>::ConstructCopy(const variable_container<T>& _rhs)
{
    assert( m_Type == _rhs.m_Type );
    
    if( m_Type == type::common )
        new (&Common()) common_type( _rhs.Common() );
    else if( m_Type == type::sparse )
        new (&Sparse()) sparse_type( _rhs.Sparse() );
    else if( m_Type == type::dense )
        new (&Dense()) dense_type( _rhs.Dense() );
}

template <class T>
void variable_container<T>::ConstructMove(variable_container<T>&& _rhs)
{
    assert( m_Type == _rhs.m_Type );
    
    if( m_Type == type::common )
        new (&Common()) common_type( move(_rhs.Common()) );
    else if( m_Type == type::sparse )
        new (&Sparse()) sparse_type( move(_rhs.Sparse()) );
    else if( m_Type == type::dense )
        new (&Dense()) dense_type( move(_rhs.Dense()) );
}

template <class T>
void variable_container<T>::Destruct()
{
    if( m_Type == type::common )
        Common().~common_type();
    else if( m_Type == type::sparse )
        Sparse().~sparse_type();
    else if( m_Type == type::dense )
        Dense().~dense_type();
}

template <class T>
T &variable_container<T>::at(unsigned _at)
{
    if( m_Type == type::common )
        return Common();
    else if( m_Type == type::dense )
        return Dense().at(_at);
    else if( m_Type == type::sparse )
        return Sparse().at(_at);
    else
        throw std::logic_error("invalid type in variable_container<T>::at");
}

template <class T>
const T &variable_container<T>::at(unsigned _at) const
{
    if( m_Type == type::common )
        return Common();
    else if( m_Type == type::dense )
        return Dense().at(_at);
    else if( m_Type == type::sparse )
        return Sparse().at(_at);
    else
        throw std::logic_error("invalid type in variable_container<T>::at");
}

template <class T>
void variable_container<T>::resize( unsigned _new_size )
{
    if( m_Type == type::Dense )
        Dense().resize( _new_size );
}

template <class T>
void variable_container<T>::insert( unsigned _at, const T& _value )
{
    if( m_Type == type::common ) {
        Common() = _value;
    }
    else if( m_Type == type::dense ) {
        if( Dense().size() <= _at  )
            Dense().resize( _at + 1 );
        Dense()[_at] = _value;
    }
    else if( m_Type == type::sparse ) {
        auto r = Sparse().insert( typename sparse_type::value_type( _at, _value ) );
        if( !r.second )
            r.first->second = _value;
    }
    else
        throw std::logic_error("invalid type in variable_container<T>::insert");
}

template <class T>
void variable_container<T>::insert( unsigned _at, T&& _value )
{
    if( m_Type == type::common ) {
        Common() = move(_value);
    }
    else if( m_Type == type::dense ) {
        if( Dense().size() <= _at  )
            Dense().resize( _at + 1 );
        Dense()[_at] = move(_value);
    }
    else if( m_Type == type::sparse ) {
        auto i = Sparse().find( _at );
        if( i == end(Sparse()) )
            Sparse().insert( typename sparse_type::value_type( _at, move(_value) ) );
        else
            i->second = move(_value);
    }
    else
        throw std::logic_error("invalid type in variable_container<T>::insert");
}

template <class T>
bool variable_container<T>::has( unsigned _at ) const
{
    if( m_Type == type::common )
        return true;
    else if( m_Type == type::dense )
        return _at < Dense().size();
    else if( m_Type == type::sparse )
        return Sparse().find(_at) != end(Sparse());
    else
        throw std::logic_error("invalid type in variable_container<T>::has");
}
