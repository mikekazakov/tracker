// Copyright (C) 2016-2019 Michael Kazakov. Subject to GNU General Public License version 3.
#include "ActionShortcut.h"
#include <locale>
#include <vector>
#include <codecvt>
#include <Carbon/Carbon.h>

namespace nc::utility {

static_assert( sizeof(ActionShortcut) == 4 );

ActionShortcut::ActionShortcut(const std::string& _from) noexcept:
    ActionShortcut(_from.c_str())
{
}

ActionShortcut::ActionShortcut(const char* _from) noexcept: // construct from persistency string
    ActionShortcut()
{
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> convert;
    std::u16string utf16 = convert.from_bytes(_from);
    std::u16string_view v(utf16);
    uint64_t mod_flags = 0;
    while( !v.empty() ) {
        auto c = v.front();
        if( c == u'⇧' )
            mod_flags |= NSShiftKeyMask;
        else if( c == u'^' )
            mod_flags |= NSControlKeyMask;
        else if( c == u'⌥' )
            mod_flags |= NSAlternateKeyMask;
        else if( c == u'⌘' )
            mod_flags |= NSCommandKeyMask;
        else {
            if( v == u"\\r" )
                unicode = '\r';
            else if( v == u"\\t" )
                unicode = '\t';
            else
                unicode = (uint16_t)towlower( v.front() );
            break;
        }
        v.remove_prefix(1);
    }
    modifiers = mod_flags;
}

ActionShortcut::ActionShortcut(uint16_t _unicode, unsigned long long _modif) noexcept:
    unicode(_unicode),
    modifiers(0)
{
    uint64_t mod_flags = 0;
    if(_modif & NSShiftKeyMask)     mod_flags |= NSShiftKeyMask;
    if(_modif & NSControlKeyMask)   mod_flags |= NSControlKeyMask;
    if(_modif & NSAlternateKeyMask) mod_flags |= NSAlternateKeyMask;
    if(_modif & NSCommandKeyMask)   mod_flags |= NSCommandKeyMask;
    modifiers = mod_flags;
}

ActionShortcut::operator bool() const noexcept
{
    return unicode != 0;
}

std::string ActionShortcut::ToPersString() const noexcept
{
    std::string result;
    if( modifiers & NSShiftKeyMask )
        result += reinterpret_cast<const char*>(u8"⇧");
    if( modifiers & NSControlKeyMask )
        result += reinterpret_cast<const char*>(u8"^");
    if( modifiers & NSAlternateKeyMask )
        result += reinterpret_cast<const char*>(u8"⌥");
    if( modifiers & NSCommandKeyMask )
        result += reinterpret_cast<const char*>(u8"⌘");
    
    if( unicode == '\r' )
        result += "\\r";
    else if( unicode == '\t' )
        result += "\\t";
    else {
        std::u16string key_utf16;
        key_utf16.push_back(unicode);
        std::wstring_convert<std::codecvt_utf8_utf16<char16_t>,char16_t> convert;
        result += convert.to_bytes(key_utf16);
    }
    
    return result;
}

NSString *ActionShortcut::Key() const noexcept
{
    if( !*this )
        return @"";
    if( NSString *key = [NSString stringWithCharacters:&unicode length:1] )
        return key;
    return @"";
}

static NSString *StringForModifierFlags(uint64_t flags)
{
    UniChar modChars[4];  // We only look for 4 flags
    unsigned int charCount = 0;
    // These are in the same order as the menu manager shows them
    if( flags & NSControlKeyMask )   modChars[charCount++] = kControlUnicode;
    if( flags & NSAlternateKeyMask ) modChars[charCount++] = kOptionUnicode;
    if( flags & NSShiftKeyMask )     modChars[charCount++] = kShiftUnicode;
    if( flags & NSCommandKeyMask )   modChars[charCount++] = kCommandUnicode;
    if( charCount == 0 )
        return @"";
    
    return [NSString stringWithCharacters:modChars length:charCount];
}

NSString *ActionShortcut::PrettyString() const noexcept
{
    static const std::vector< std::pair<uint16_t, NSString*> > unicode_to_nice_string = {
            {NSLeftArrowFunctionKey,     @"←"},
            {NSRightArrowFunctionKey,    @"→"},
            {NSDownArrowFunctionKey,     @"↓"},
            {NSUpArrowFunctionKey,       @"↑"},
            {NSF1FunctionKey,            @"F1"},
            {NSF2FunctionKey,            @"F2"},
            {NSF3FunctionKey,            @"F3"},
            {NSF4FunctionKey,            @"F4"},
            {NSF5FunctionKey,            @"F5"},
            {NSF6FunctionKey,            @"F6"},
            {NSF7FunctionKey,            @"F7"},
            {NSF8FunctionKey,            @"F8"},
            {NSF9FunctionKey,            @"F9"},
            {NSF10FunctionKey,           @"F10"},
            {NSF11FunctionKey,           @"F11"},
            {NSF12FunctionKey,           @"F12"},
            {NSF13FunctionKey,           @"F13"},
            {NSF14FunctionKey,           @"F14"},
            {NSF15FunctionKey,           @"F15"},
            {NSF16FunctionKey,           @"F16"},
            {NSF17FunctionKey,           @"F17"},
            {NSF18FunctionKey,           @"F18"},
            {NSF19FunctionKey,           @"F19"},
            {0x2326,                     @"⌦"},
            {'\r',                       @"↩"},
            {0x3,                        @"⌅"},
            {0x9,                        @"⇥"},
            {0x2423,                     @"Space"},
            {0x0020,                     @"Space"},
            {0x8,                        @"⌫"},
            {NSClearDisplayFunctionKey,  @"Clear"},
            {0x1B,                       @"⎋"},
            {NSHomeFunctionKey,          @"↖"},
            {NSPageUpFunctionKey,        @"⇞"},
            {NSEndFunctionKey,           @"↘"},
            {NSPageDownFunctionKey,      @"⇟"},
            {NSHelpFunctionKey,          @"Help"}
    };
    if( !*this )
        return @"";
    
    NSString *vis_key;
    auto it = find_if(begin(unicode_to_nice_string),
                      end(unicode_to_nice_string),
                      [=](auto &_i){ return _i.first == unicode; });
    if( it != end(unicode_to_nice_string) )
        vis_key = it->second;
    else
        vis_key = Key().uppercaseString;
    
    return [NSString stringWithFormat:@"%@%@",
            StringForModifierFlags(modifiers),
            vis_key];
}

bool ActionShortcut::IsKeyDown(uint16_t _unicode, unsigned long long _modifiers) const noexcept
{
    if( !unicode )
        return false;

    // exclude CapsLock/NumPad/Func from our decision process
    constexpr auto mask = NSDeviceIndependentModifierFlagsMask &
        (~NSAlphaShiftKeyMask & ~NSNumericPadKeyMask & ~NSFunctionKeyMask);
    auto clean_modif = _modifiers & mask;
    
    if( unicode >= 32 && unicode < 128 && modifiers.is_empty() )
        clean_modif &= ~NSShiftKeyMask; // some chars were produced by pressing key with shift
    
    if( modifiers == NSEventModifierFlagsHolder{clean_modif} && unicode == _unicode )
        return true;
    
    if( modifiers.is_shift() && modifiers == NSEventModifierFlagsHolder{clean_modif} ) {
        if( unicode >= 97 && unicode <= 125 && unicode == _unicode + 32 )
            return true;
        if( unicode >= 65 && unicode <= 93 && unicode + 32 == _unicode )
            return true;
    }
    
    return false;
}

bool ActionShortcut::operator==(const ActionShortcut &_rhs) const noexcept
{
    return modifiers == _rhs.modifiers &&
           unicode == _rhs.unicode;
}

bool ActionShortcut::operator!=(const ActionShortcut &_rhs) const noexcept
{
    return !(*this == _rhs);
}

}

size_t std::hash<nc::utility::ActionShortcut>::
    operator()(const nc::utility::ActionShortcut& _ac) const noexcept
{
    return ((size_t)_ac.unicode) | (((size_t)_ac.modifiers.flags) << 16);
}
