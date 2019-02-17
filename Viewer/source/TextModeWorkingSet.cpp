#include "TextModeWorkingSet.h"
#include "TextProcessing.h"
#include <stdexcept>

namespace nc::viewer {
    
TextModeWorkingSet::TextModeWorkingSet(const Source& _source)
{
    
    if( _source.unprocessed_characters == nullptr ||
        _source.mapping_to_byte_offsets == nullptr ||
        _source.characters_number < 0 ||
        _source.bytes_offset < 0 ||
        _source.bytes_length < 0) {
        throw std::invalid_argument("TextModeWorkingSet: invalid agrument");
    }
    m_WorkingSetOffset = _source.bytes_offset;
    m_WorkingSetSize = _source.bytes_length;
    m_CharactersNumber = _source.characters_number;
    
    m_Characters = std::make_unique<char16_t[]>(_source.characters_number);
    memcpy(m_Characters.get(),
           _source.unprocessed_characters, sizeof(char16_t) * _source.characters_number);
    CleanUnicodeControlSymbols(m_Characters.get(), _source.characters_number);
    
    m_ToByteIndices = std::make_unique<int[]>(_source.characters_number + 1);
    memcpy(m_ToByteIndices.get(),
           _source.mapping_to_byte_offsets,
           sizeof(int) * _source.characters_number);
    m_ToByteIndices[ _source.characters_number ] = _source.bytes_length;
    
    m_String = CFStringCreateWithCharactersNoCopy(nullptr,
                                                  (const UniChar*)m_Characters.get(),
                                                  _source.characters_number,
                                                  kCFAllocatorNull);
    if( m_String == nullptr ) {
        throw std::invalid_argument("TextModeWorkingSet: failed to create a CFString");
    }
    
    assert( _source.characters_number == CFStringGetLength(m_String) );
}
    
TextModeWorkingSet::~TextModeWorkingSet()
{
    if( m_String ) {
        CFRelease(m_String);
    }
}

int TextModeWorkingSet::ToLocalByteOffset( int _character_index ) const
{
    if( _character_index < 0 || _character_index > m_CharactersNumber )
        throw std::out_of_range("TextModeWorkingSet::ToLocalByteOffset: out of bounds");
    return m_ToByteIndices[_character_index];
}

long TextModeWorkingSet::ToGlobalByteOffset( int _character_index ) const
{
    if( _character_index < 0 || _character_index > m_CharactersNumber )
        throw std::out_of_range("TextModeWorkingSet::ToGlobalByteOffset: out of bounds");
    return m_ToByteIndices[_character_index] + m_WorkingSetOffset;
}

}
