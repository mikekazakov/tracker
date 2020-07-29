// Copyright (C) 2020 Michael Kazakov. Subject to GNU General Public License version 3.
#include "Parser2Impl.h"
#include <Utility/OrthodoxMonospace.h>
#include <Habanero/CFPtr.h>
#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>
#include "TranslateMaps.h"
#include <charconv>

#include <iostream>

namespace nc::term {

Parser2Impl::Parser2Impl(const Params& _params):
    m_ErrorLog(_params.error_log)
{
    Reset();
}

Parser2Impl::~Parser2Impl()
{
}

void Parser2Impl::Reset()
{
    SwitchTo(EscState::Text);
}

std::vector<input::Command> Parser2Impl::Parse( Bytes _to_parse )
{
    for( auto c: _to_parse )
        EatByte( static_cast<unsigned char>(c) );
    FlushText();
    
    return std::move(m_Output);
}

void Parser2Impl::EatByte( unsigned char _byte )
{
    while( true ) {
        const auto state = m_SubState;
        const auto consume = m_SubStates[static_cast<int>(m_SubState)].consume;
        const bool consumed = (*this.*consume)(_byte);
        if( consumed ) {
            return;
        }
        else {
            assert( state != m_SubState ); // ensure that state has changed if a current refused 
        }  
    }
}

void Parser2Impl::SwitchTo(EscState _state)
{
    if( m_SubState != _state ) {
        (*this.*m_SubStates[static_cast<int>(m_SubState)].exit)();
        m_SubState = _state;
        (*this.*m_SubStates[static_cast<int>(_state)].enter)();
    }
}

void Parser2Impl::SSTextEnter() noexcept
{
    m_TextState.UTF8StockLen = 0;
}

void Parser2Impl::SSTextExit() noexcept
{
    FlushText();
}

bool Parser2Impl::SSTextConsume(unsigned char _byte) noexcept
{    
    const unsigned char c = _byte;    
    if( c < 32 ) {
        SwitchTo(EscState::Control);
        return false;
    }
    ConsumeNextUTF8TextChar( c );
    return true;
}

void Parser2Impl::ConsumeNextUTF8TextChar( unsigned char _byte )
{
    auto &ts = m_TextState;
    if( ts.UTF8StockLen < ts.UTF8CharsStockSize ) {
        ts.UTF8CharsStock[ts.UTF8StockLen++] = (char)_byte;
    }
}

void Parser2Impl::FlushText()
{
    if( m_TextState.UTF8StockLen == 0 )
        return;
    
    using namespace input;
    UTF8Text payload;
    payload.characters.assign(m_TextState.UTF8CharsStock.data(), m_TextState.UTF8StockLen);
    
    Command command;
    command.type = Type::text;
    command.payload = std::move(payload);
    m_Output.emplace_back( std::move(command) );
    
    m_TextState.UTF8StockLen = 0;
}

Parser2Impl::EscState Parser2Impl::GetEscState() const noexcept
{
    return m_SubState;
}

void Parser2Impl::LF() noexcept
{
    m_Output.emplace_back( input::Type::line_feed );
}

void Parser2Impl::HT() noexcept
{
    m_Output.emplace_back( input::Type::horizontal_tab, 1 );
}

void Parser2Impl::CR() noexcept
{
    m_Output.emplace_back( input::Type::carriage_return );
}

void Parser2Impl::BS() noexcept
{
    m_Output.emplace_back( input::Type::back_space );
}

void Parser2Impl::BEL() noexcept
{
    // TODO: + if title
    m_Output.emplace_back( input::Type::bell );
}

void Parser2Impl::RI() noexcept
{
    m_Output.emplace_back( input::Type::reverse_index );
}

void Parser2Impl::RIS() noexcept
{
    Reset();
    m_Output.emplace_back( input::Type::reset );
}

void Parser2Impl::HTS() noexcept
{
    m_Output.emplace_back( input::Type::set_tab );
}

void Parser2Impl::SI() noexcept
{
    m_Output.emplace_back( input::Type::select_character_set, 0u );
}

void Parser2Impl::SO() noexcept
{
    m_Output.emplace_back( input::Type::select_character_set, 1u );
}

void Parser2Impl::DECSC() noexcept
{
    // TODO: save translation stuff
    m_Output.emplace_back( input::Type::save_state ); 
}

void Parser2Impl::DECRC() noexcept
{
    // TODO: restore translation stuff
    m_Output.emplace_back( input::Type::restore_state );
}

void Parser2Impl::DECALN() noexcept
{
    m_Output.emplace_back( input::Type::screen_alignment_test );
}

void Parser2Impl::LogMissedEscChar( unsigned char _c )
{
    if( m_ErrorLog ) {
        char buf[256];
        sprintf(buf, "Missed an Esc char: %d(\'%c\')", (int)_c, _c);
        m_ErrorLog(buf);
    }
}

void Parser2Impl::SSEscEnter() noexcept
{
    m_EscState.hash = false;
}

void Parser2Impl::SSEscExit() noexcept
{
}

bool Parser2Impl::SSEscConsume(unsigned char _byte) noexcept
{
    const unsigned char c = _byte;
    
    switch (c ) {
        case '#': m_EscState.hash = true; return true;
    }

    SwitchTo(EscState::Text);
    switch (c) {
        case '[': SwitchTo(EscState::CSI); return true;
        case ']': SwitchTo(EscState::OSC); return true;
        case '>':  /* Numeric keypad - ignoring now */  return true;
        case '=':  /* Appl. keypad - ignoring now */    return true;
            
            /* DECSC – Save Cursor (DEC Private)
             ESC 7     
             This sequence causes the cursor position, graphic rendition, and character set
             to be saved. */                
        case '7': DECSC(); return true;
            
        case '8':
            if ( m_EscState.hash == true )
            /* DECALN – Screen Alignment Display (DEC Private)
             ESC # 8
             This command fills the entire screen area with uppercase Es for screen focus and
             alignment. This command is used by DEC manufacturing and Field Service personnel.*/
                DECALN();
            else
            /* DECRC – Restore Cursor (DEC Private)
             ESC 8
             This sequence causes the previously saved cursor position, graphic rendition,
             and character set to be restored. */
                DECRC();
            return true;
        
            /* IND – Index
             ESC D
             This sequence causes the active position to move downward one line without
             changing the column position. If the active position is at the bottom margin, a
             scroll up is performed. */
        case 'D': LF(); return true;
        
            /*  NEL – Next Line
             ESC E     
             This sequence causes the active position to move to the first position on the
             next line downward. If the active position is at the bottom margin, a scroll up
             is performed. */
        case 'E': CR(); LF(); return true;

            /*  HTS – Tab Set
             ESC H
             Set one horizontal stop at the active position. */
        case 'H': HTS(); return true;

            /* RI – Reverse Index
             ESC M     
             Move the active position to the same horizontal position on the preceding line.
             If the active position is at the top margin, a scroll down is performed. */                                
        case 'M': RI(); return true;

            /* RIS – Reset To Initial State
             ESC c     
             Reset the VT100 to its initial state, i.e., the state it has after it is
             powered on. */                                
        case 'c': RIS(); return true;
            
        case '(':
        case ')':
        case '*':
        case '+':
            SwitchTo(EscState::DCS); return false;
        
            // For everything else, i.e. unimplemented stuff - complain in a log.
        default: LogMissedEscChar(c); return true;
    }    
    return true;
}

void Parser2Impl::SSControlEnter() noexcept
{
}

void Parser2Impl::SSControlExit() noexcept
{
}

bool Parser2Impl::SSControlConsume(unsigned char _byte) noexcept
{
    const unsigned char c = _byte;        
    if( c < 32 ) {
        switch (c) {
            case  0: SwitchTo(EscState::Text); return true;
            case  1: SwitchTo(EscState::Text); return true;
            case  2: SwitchTo(EscState::Text); return true;
            case  3: SwitchTo(EscState::Text); return true;
            case  4: SwitchTo(EscState::Text); return true;
            case  5: SwitchTo(EscState::Text); return true;
            case  6: SwitchTo(EscState::Text); return true;
            case  7: SwitchTo(EscState::Text); BEL(); return true;
            case  8: SwitchTo(EscState::Text); BS(); return true;
            case  9: SwitchTo(EscState::Text); HT(); return true;
            case 10:
            case 11:
            case 12: SwitchTo(EscState::Text); LF(); return true;
            case 13: SwitchTo(EscState::Text); CR(); return true;
            case 14: SwitchTo(EscState::Text); SO(); return true;
            case 15: SwitchTo(EscState::Text); SI(); return true;
            case 16: SwitchTo(EscState::Text); return true;
            case 17: SwitchTo(EscState::Text); return true; // xon
            case 18: SwitchTo(EscState::Text); return true;
            case 19: SwitchTo(EscState::Text); return true; // xoff
            case 20: SwitchTo(EscState::Text); return true;
            case 21: SwitchTo(EscState::Text); return true;
            case 22: SwitchTo(EscState::Text); return true;
            case 23: SwitchTo(EscState::Text); return true;
            case 24: SwitchTo(EscState::Text); return true;
            case 25: SwitchTo(EscState::Text); return true;
            case 26: SwitchTo(EscState::Text); return true;
            case 27: SwitchTo(EscState::Esc); return true;
            case 28: SwitchTo(EscState::Text); return true;
            case 29: SwitchTo(EscState::Text); return true;
            case 30: SwitchTo(EscState::Text); return true;
            case 31: SwitchTo(EscState::Text); return true;
        }
    }
    SwitchTo(EscState::Text);
    return false;
}

void Parser2Impl::SSOSCEnter() noexcept
{
    m_OSCState.buffer.clear();
    m_OSCState.got_esc = false;
}

void Parser2Impl::SSOSCExit() noexcept
{
    SSOSCSubmit();
}

bool Parser2Impl::SSOSCConsume(const unsigned char _byte) noexcept
{
    // consume the following (OSC was already consumed):
    // OSC Ps ; Pt BEL
    // OSC Ps ; Pt ST
    if( m_OSCState.got_esc ) { 
        if( _byte != '\\' ) {
            SSOSCDiscard();
        }            
        SwitchTo(EscState::Text);
    }
    else {
        if( _byte >= 32 ) {
            m_OSCState.buffer += _byte;
        }
        else {
            if( _byte == '\x07' ) {
                SwitchTo(EscState::Text);
            }
            else if( _byte == '\x1B' ) {
                m_OSCState.got_esc = true;
            }
            else {
                SSOSCDiscard();
                SwitchTo(EscState::Text);
            }
        }
    }
    return true;
}

void Parser2Impl::SSOSCDiscard() noexcept
{
    m_OSCState.buffer.clear();
}

// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html -> Operating System Commands
void Parser2Impl::SSOSCSubmit() noexcept
{
    // parse the following format: Ps ; Pt
    std::string_view s = m_OSCState.buffer;
    auto sc_pos = s.find(';');
    if( sc_pos == s.npos )
        return;
    const std::string_view pt = s.substr(sc_pos + 1);        

    unsigned ps = std::numeric_limits<unsigned>::max();    
    if( std::from_chars(s.data(), s.data() + sc_pos, ps).ec != std::errc() )
        return;
    
    using namespace input;
    // currently the parser ignores any OSC other than 0, 1, 3.    
    if( ps == 0 ) {
        // Ps = 0  ⇒  Change Icon Name and Window Title to Pt.
        m_Output.emplace_back( Type::change_title, Title{Title::IconAndWindow, std::string(pt)});
    }
    else if( ps == 1 ) {
        // Ps = 1  ⇒  Change Icon Name to Pt.
        m_Output.emplace_back( Type::change_title, Title{Title::Icon, std::string(pt)});
    }
    else if( ps == 2 ) {
        // Ps = 2  ⇒  Change Window Title to Pt.
        m_Output.emplace_back( Type::change_title, Title{Title::Window, std::string(pt)});
    }
    else {
        LogMissedOSCRequest(ps, pt);
    }
}

void Parser2Impl::LogMissedOSCRequest( unsigned _ps, std::string_view _pt )
{
    if( m_ErrorLog ) {
        using namespace std::string_literals;
        auto msg = "Missed an OSC: "s + std::to_string(_ps) + ": "s + std::string(_pt);
        m_ErrorLog( msg );
    }
}

void Parser2Impl::SSCSIEnter() noexcept
{
    m_CSIState.buffer.clear();
}

void Parser2Impl::SSCSIExit() noexcept
{
    SSCSISubmit();
}

constexpr static std::array<bool, 256> Make8BitBoolTable( std::string_view _on )
{
    std::array<bool, 256> flags{};
    std::fill(flags.begin(), flags.end(), false);
    for( auto c: _on )
        flags[(unsigned char)c] = true;
    return flags;
}

constexpr static std::array<bool, 256> g_CSI_ValidTerminal = 
    Make8BitBoolTable("@ABCDEFGHIJKLMPSTXZ^`abcdefghilmnpqrstuvwxyz{|}~");

constexpr static std::array<bool, 256> g_CSI_ValidContents =
    Make8BitBoolTable("01234567890; ?>=!\"\'$#*");

bool Parser2Impl::SSCSIConsume(unsigned char _byte) noexcept
{
    if( _byte < 32 ) {
        return SSOSCConsumeControl(_byte);
    }
    else if( g_CSI_ValidContents[_byte] ) {
        m_CSIState.buffer += static_cast<char>(_byte);
        return true;
    }
    else {
        if( g_CSI_ValidTerminal[_byte] ) {
            m_CSIState.buffer += static_cast<char>(_byte);
            SwitchTo(EscState::Text);
            return true;
        }
        else {            
            m_CSIState.buffer.clear(); // discard
            SwitchTo(EscState::Text);
            return false;
        }
    }
}

bool Parser2Impl::SSOSCConsumeControl(unsigned char _byte) noexcept
{
    switch (_byte) {
//        case  0: ???
//        case  1: ???
//        case  2: ???
//        case  3: ???
//        case  4: ???
//        case  5: ???
//        case  6: ???
//        case  7: ???
        case  8: BS(); return true;
//        case  9: ???
        case 10:
        case 11:
        case 12: LF(); return true;
        case 13: CR(); return true;
//        case 14: ???
//        case 15: ???
//        case 16: ???
//        case 17: ???
//        case 18: ???
//        case 19: ???
//        case 20: ???
//        case 21: ???
//        case 22: ???
//        case 23: ???
//        case 24: ???
//        case 25: ???
//        case 26: ???
//        case 27: ???
//        case 28: ???
//        case 29: ???
//        case 30: ???
//        case 31: ???
        default: return true;
    }
}

void Parser2Impl::SSCSISubmit() noexcept
{
    if( m_CSIState.buffer.empty() )
        return;

    const auto c = m_CSIState.buffer.back();
    switch( c ) {
        case 'A': CSI_A(); break;
        case 'B': CSI_B(); break;
        case 'C': CSI_C(); break;
        case 'D': CSI_D(); break;
        case 'E': CSI_E(); break;
        case 'F': CSI_F(); break;
        case 'G': CSI_G(); break;
        case 'H': CSI_H(); break;
        case 'I': CSI_I(); break;
        case 'J': CSI_J(); break;
        case 'K': CSI_K(); break;
        case 'L': CSI_L(); break;
        case 'M': CSI_M(); break;
        case 'P': CSI_P(); break;
        case 'S': CSI_S(); break;
        case 'T': CSI_T(); break;
        case 'X': CSI_X(); break;
        case 'Z': CSI_Z(); break;
        case 'a': CSI_a(); break;
        case 'b': CSI_b(); break;
        case 'c': CSI_c(); break;
        case 'd': CSI_d(); break;
        case 'e': CSI_e(); break;
        case 'f': CSI_f(); break;
        case 'g': CSI_g(); break;
        case 'h': CSI_hl(); break;
        case 'l': CSI_hl(); break;
        case 'm': CSI_m(); break;
        case 'n': CSI_n(); break;
        case 'r': CSI_r(); break;
        case '`': CSI_Accent(); break;
        case '@': CSI_At(); break;
        default: LogMissedCSIRequest( m_CSIState.buffer ); break;
    } 
}

void Parser2Impl::LogMissedCSIRequest( std::string_view _request )
{
    if( m_ErrorLog ) {
        auto msg = std::string("Missed a CSI: ") + std::string(_request);
        m_ErrorLog(msg);
    }
}
    
void Parser2Impl::CSI_A() noexcept
{
//    CSI Ps A - Cursor Up Ps Times (default = 1) (CUU).
//    Not implemented:
//    CSI Ps SP A - Shift right Ps columns(s) (default = 1) (SR), ECMA-48.

    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x = 0;
    cm.y = -std::max(static_cast<int>(ps), 1);
    m_Output.emplace_back( input::Type::move_cursor, cm );
}

void Parser2Impl::CSI_B() noexcept
{
//  CSI Ps B  Cursor Down Ps Times (default = 1) (CUD).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x = 0;
    cm.y = std::max(static_cast<int>(ps), 1);
    m_Output.emplace_back( input::Type::move_cursor, cm );    
}

void Parser2Impl::CSI_C() noexcept
{
// CSI Ps C  Cursor Forward Ps Times (default = 1) (CUF).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x = std::max(static_cast<int>(ps), 1);
    cm.y = 0;
    m_Output.emplace_back( input::Type::move_cursor, cm );
}

void Parser2Impl::CSI_D() noexcept
{
// CSI Ps D  Cursor Backward Ps Times (default = 1) (CUB).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x = -std::max(static_cast<int>(ps), 1);
    cm.y = 0;
    m_Output.emplace_back( input::Type::move_cursor, cm );
}

void Parser2Impl::CSI_E() noexcept
{
// CSI Ps E  Cursor Next Line Ps Times (default = 1) (CNL).
// E   CNL       Move cursor down the indicated # of rows, to column 1.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x.reset();
    cm.y = static_cast<int>(ps);
    m_Output.emplace_back( input::Type::move_cursor, cm );
    
    cm.positioning = input::CursorMovement::Absolute;
    cm.x = 0;
    cm.y.reset();
    m_Output.emplace_back( input::Type::move_cursor, cm );
}
    
void Parser2Impl::CSI_F() noexcept
{
// CSI Ps F  Cursor Preceding Line Ps Times (default = 1) (CPL).
// F   CPL       Move cursor up the indicated # of rows, to column 1.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x.reset();
    cm.y = -static_cast<int>(ps);
    m_Output.emplace_back( input::Type::move_cursor, cm );
    
    cm.positioning = input::CursorMovement::Absolute;
    cm.x = 0;
    cm.y.reset();
    m_Output.emplace_back( input::Type::move_cursor, cm );
}
    
void Parser2Impl::CSI_G() noexcept
{
//CSI Ps G  Cursor Character Absolute  [column] (default = [row,1]) (CHA).
    int x = 0;
    const auto p = CSIParamsScanner::Parse(m_CSIState.buffer);
    if( p.count >= 1 )
        x = p.values[0] > 0 ? p.values[0] - 1 : 0; 
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Absolute;
    cm.x = x;
    m_Output.emplace_back( input::Type::move_cursor, cm );   
}

void Parser2Impl::CSI_H() noexcept
{
//    CSI Ps ; Ps H
//    Cursor Position [row;column] (default = [1,1]) (CUP).
    int x = 0;
    int y = 0;
    const auto p = CSIParamsScanner::Parse(m_CSIState.buffer);
    if( p.count == 2 ) {
        y = p.values[0] > 0 ? p.values[0] - 1 : 0; 
        x = p.values[1] > 0 ? p.values[1] - 1 : 0;
    }
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Absolute;
    cm.x = x;
    cm.y = y;
    m_Output.emplace_back( input::Type::move_cursor, cm );    
}
    
void Parser2Impl::CSI_I() noexcept
{
// CSI Ps I  Cursor Forward Tabulation Ps tab stops (default = 1) (CHT).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::horizontal_tab, static_cast<int>(ps) );
}
    
void Parser2Impl::CSI_J() noexcept
{
//    CSI Ps J  Erase in Display (ED), VT100.
//    Ps = 0  ⇒  Erase Below (default).
//    Ps = 1  ⇒  Erase Above.
//    Ps = 2  ⇒  Erase All.
//    Ps = 3  ⇒  Erase Saved Lines, xterm.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 0; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    using input::DisplayErasure;
    DisplayErasure de;
    switch( ps ) {
        case 0:
            de.what_to_erase = DisplayErasure::Area::FromCursorToDisplayEnd;
            break;
        case 1:
            de.what_to_erase = DisplayErasure::Area::FromDisplayStartToCursor;
            break;
        case 2:
            de.what_to_erase = DisplayErasure::Area::WholeDisplay;
            break;
        case 3:
            de.what_to_erase = DisplayErasure::Area::WholeDisplayWithScrollback;
            break;
        default:
            return;
    };
    
    m_Output.emplace_back( input::Type::erase_in_display, de );
}

void Parser2Impl::CSI_K() noexcept
{
// CSI Ps K  Erase in Line (EL), VT100.
// Ps = 0  ⇒  Erase to Right (default).
// Ps = 1  ⇒  Erase to Left.
// Ps = 2  ⇒  Erase All.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 0; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    
    using input::LineErasure;
    LineErasure le;
    switch( ps ) {
        case 0:
            le.what_to_erase = LineErasure::Area::FromCursorToLineEnd;
            break;
        case 1:
            le.what_to_erase = LineErasure::Area::FromLineStartToCursor;
            break;
        case 2:
            le.what_to_erase = LineErasure::Area::WholeLine;
            break;
        default:
            return;
    };
    
    m_Output.emplace_back( input::Type::erase_in_line, le );
}

void Parser2Impl::CSI_L() noexcept
{
// CSI Ps L  Insert Ps Line(s) (default = 1) (IL).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::insert_lines, ps );
}

void Parser2Impl::CSI_M() noexcept
{
// CSI Ps M  Delete Ps Line(s) (default = 1) (DL).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::delete_lines, ps );
}
    
void Parser2Impl::CSI_P() noexcept
{
// CSI Ps P  Delete Ps Character(s) (default = 1) (DCH).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::delete_characters, ps );
}
    
void Parser2Impl::CSI_S() noexcept
{
// CSI Ps S  Scroll up Ps lines (default = 1) (SU), VT420, ECMA-48.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::scroll_lines, static_cast<signed>(ps) );
}
    
void Parser2Impl::CSI_T() noexcept
{
// CSI Ps T  Scroll down Ps lines (default = 1) (SD), VT420.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::scroll_lines, -static_cast<signed>(ps) );
}
    
void Parser2Impl::CSI_X() noexcept
{
// CSI Ps X  Erase Ps Character(s) (default = 1) (ECH).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::erase_characters, ps );
}
    
void Parser2Impl::CSI_Z() noexcept
{
// CSI Ps Z  Cursor Backward Tabulation Ps tab stops (default = 1) (CBT).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::horizontal_tab, -static_cast<int>(ps) );
}
    
void Parser2Impl::CSI_a() noexcept
{
// CSI Pm a  Character Position Relative  [columns] (default = [row,col+1]) (HPR).
    const std::string_view s = m_CSIState.buffer;
    int ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x = ps;
    cm.y = std::nullopt;
    m_Output.emplace_back( input::Type::move_cursor, cm );
}
    
void Parser2Impl::CSI_b() noexcept
{
// CSI Ps b  Repeat the preceding graphic character Ps times (REP).
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::repeat_last_character, ps );
}

void Parser2Impl::CSI_c() noexcept
{
// CSI Ps c  Send Device Attributes (Primary DA).
// Ps = 0  or omitted ⇒  request attributes from terminal.
    const std::string_view s = m_CSIState.buffer;
    unsigned ps = 0; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    if( ps == 0 ) {
        input::DeviceReport dr;
        dr.mode = input::DeviceReport::TerminalId;
        m_Output.emplace_back( input::Type::report, dr );
    }
}
    
void Parser2Impl::CSI_d() noexcept
{
// CSI Pm d  Line Position Absolute  [row] (default = [1,column]) (VPA).
    const std::string_view s = m_CSIState.buffer;
    int ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    ps = std::max(ps - 1, 0);
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Absolute;
    cm.x = std::nullopt;
    cm.y = ps;
    m_Output.emplace_back( input::Type::move_cursor, cm );
}

void Parser2Impl::CSI_e() noexcept
{
// CSI Pm e  Line Position Relative  [rows] (default = [row+1,column]) (VPR).
    const std::string_view s = m_CSIState.buffer;
    int ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Relative;
    cm.x = std::nullopt;
    cm.y = ps;
    m_Output.emplace_back( input::Type::move_cursor, cm );
}

void Parser2Impl::CSI_f() noexcept
{
    CSI_H();
}

void Parser2Impl::CSI_g() noexcept
{
//    CSI Ps g  Tab Clear (TBC).
//    Ps = 0  ⇒  Clear Current Column (default).
//    Ps = 3  ⇒  Clear All.
    const std::string_view s = m_CSIState.buffer;
    int ps = 0; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    if( ps == 0 || ps == 3 ) {
        input::TabClear tc;
        tc.mode = ps == 0 ? input::TabClear::CurrentColumn : input::TabClear::All;
        m_Output.emplace_back( input::Type::clear_tab, tc );
    }
}

static std::optional<input::ModeChange::Kind> ToModeChange(unsigned _ps_number, bool _dec) noexcept
{
    using Kind = input::ModeChange::Kind;
    if( _dec ) {
        switch( _ps_number ) {
            case 1:     return Kind::ApplicationCursorKeys;
            case 3:     return Kind::Column132;
            case 4:     return Kind::SmoothScroll;
            case 5:     return Kind::ReverseVideo;
            case 6:     return Kind::Origin;
            case 7:     return Kind::AutoWrap;
            case 47:    return Kind::AlternateScreenBuffer;
            case 1049:  return Kind::AlternateScreenBuffer1049;
            default:
                return std::nullopt;
        }
    }
    else {
        switch( _ps_number ) {
            case 4:     return Kind::Insert;
            case 20:    return Kind::NewLine;
            default:
                return std::nullopt;
        }
    }
}
    
void Parser2Impl::CSI_hl() noexcept
{
// CSI Pm h  Set Mode (SM).
// CSI ? Pm h DEC Private Mode Set (DECSET).
// CSI Pm l  Reset Mode (RM).
// CSI ? Pm l DEC Private Mode Reset (DECRST).
    std::string_view request = m_CSIState.buffer;
    assert( request.empty() == false );
    const bool on = request.back() == 'h'; // 'l' means Off
    const bool dec = request.front() == '?';
    if( dec )
        request.remove_prefix(1);
    
    const auto p = CSIParamsScanner::Parse(request);
    if( p.count != 1 ) {
        LogMissedCSIRequest(m_CSIState.buffer);
        return;
    }
    
    const auto kind = ToModeChange(p.values[0], dec);
    if( kind == std::nullopt ) {
        LogMissedCSIRequest(m_CSIState.buffer);
        return;
    }

    input::ModeChange mc;
    mc.mode = *kind;
    mc.status = on;
    m_Output.emplace_back( input::Type::change_mode, mc );
}

static std::optional<input::CharacterAttributes> SCImToCharacterAttributes(int _ps) noexcept
{
    using CA = input::CharacterAttributes;
    input::CharacterAttributes ca;
    switch( _ps ) {
        case 0: ca.mode = CA::Normal; return ca;
        case 1: ca.mode = CA::Bold; return ca;
        case 2: ca.mode = CA::Faint; return ca;
        case 3: ca.mode = CA::Italicized; return ca;
        case 4: ca.mode = CA::Underlined; return ca;
        case 5: ca.mode = CA::Blink; return ca;
        case 7: ca.mode = CA::Inverse; return ca;
        case 8: ca.mode = CA::Invisible; return ca;
        case 9: ca.mode = CA::Crossed; return ca;
        case 21: ca.mode = CA::DoublyUnderlined; return ca;
        case 22: ca.mode = CA::NotBoldNotFaint; return ca;
        case 23: ca.mode = CA::NotItalicized; return ca;
        case 24: ca.mode = CA::NotUnderlined; return ca;
        case 25: ca.mode = CA::NotBlink; return ca;
        case 27: ca.mode = CA::NotInverse; return ca;
        case 28: ca.mode = CA::NotInvisible; return ca;
        case 29: ca.mode = CA::NotCrossed; return ca;
        case 30: ca.mode = CA::ForegroundBlack; return ca;
        case 31: ca.mode = CA::ForegroundRed; return ca;
        case 32: ca.mode = CA::ForegroundGreen; return ca;
        case 33: ca.mode = CA::ForegroundYellow; return ca;
        case 34: ca.mode = CA::ForegroundBlue; return ca;
        case 35: ca.mode = CA::ForegroundMagenta; return ca;
        case 36: ca.mode = CA::ForegroundCyan; return ca;
        case 37: ca.mode = CA::ForegroundWhite; return ca;
        case 39: ca.mode = CA::ForegroundDefault; return ca;
        case 40: ca.mode = CA::BackgroundBlack; return ca;
        case 41: ca.mode = CA::BackgroundRed; return ca;
        case 42: ca.mode = CA::BackgroundGreen; return ca;
        case 43: ca.mode = CA::BackgroundYellow; return ca;
        case 44: ca.mode = CA::BackgroundBlue; return ca;
        case 45: ca.mode = CA::BackgroundMagenta; return ca;
        case 46: ca.mode = CA::BackgroundCyan; return ca;
        case 47: ca.mode = CA::BackgroundWhite; return ca;
        case 49: ca.mode = CA::BackgroundDefault; return ca;
        case 90: ca.mode = CA::ForegroundBlackBright; return ca;
        case 91: ca.mode = CA::ForegroundRedBright; return ca;
        case 92: ca.mode = CA::ForegroundGreenBright; return ca;
        case 93: ca.mode = CA::ForegroundYellowBright; return ca;
        case 94: ca.mode = CA::ForegroundBlueBright; return ca;
        case 95: ca.mode = CA::ForegroundMagentaBright; return ca;
        case 96: ca.mode = CA::ForegroundCyanBright; return ca;
        case 97: ca.mode = CA::ForegroundWhiteBright; return ca;
        case 100: ca.mode = CA::BackgroundBlackBright; return ca;
        case 101: ca.mode = CA::BackgroundRedBright; return ca;
        case 102: ca.mode = CA::BackgroundGreenBright; return ca;
        case 103: ca.mode = CA::BackgroundYellowBright; return ca;
        case 104: ca.mode = CA::BackgroundBlueBright; return ca;
        case 105: ca.mode = CA::BackgroundMagentaBright; return ca;
        case 106: ca.mode = CA::BackgroundCyanBright; return ca;
        case 107: ca.mode = CA::BackgroundWhiteBright; return ca;
        default: return std::nullopt;
    };
}

void Parser2Impl::CSI_m() noexcept
{
// CSI Pm m  Character Attributes (SGR).
// Ps = 0  ⇒  Normal (default), VT100.
// Ps = 1  ⇒  Bold, VT100.
// Ps = 2  ⇒  Faint, decreased intensity, ECMA-48 2nd.
// Ps = 3  ⇒  Italicized, ECMA-48 2nd.
// Ps = 4  ⇒  Underlined, VT100.
// Ps = 5  ⇒  Blink, VT100.
// Ps = 7  ⇒  Inverse, VT100.
// Ps = 8  ⇒  Invisible, i.e., hidden, ECMA-48 2nd, VT300.
// Ps = 9  ⇒  Crossed-out characters, ECMA-48 3rd.
// Ps = 2 1  ⇒  Doubly-underlined, ECMA-48 3rd.
// Ps = 2 2  ⇒  Normal (neither bold nor faint), ECMA-48 3rd.
// Ps = 2 3  ⇒  Not italicized, ECMA-48 3rd.
// Ps = 2 4  ⇒  Not underlined, ECMA-48 3rd.
// Ps = 2 5  ⇒  Steady (not blinking), ECMA-48 3rd.
// Ps = 2 7  ⇒  Positive (not inverse), ECMA-48 3rd.
// Ps = 2 8  ⇒  Visible, i.e., not hidden, ECMA-48 3rd, VT300.
// Ps = 2 9  ⇒  Not crossed-out, ECMA-48 3rd.
// Ps = 3 0  ⇒  Set foreground color to Black.
// Ps = 3 1  ⇒  Set foreground color to Red.
// Ps = 3 2  ⇒  Set foreground color to Green.
// Ps = 3 3  ⇒  Set foreground color to Yellow.
// Ps = 3 4  ⇒  Set foreground color to Blue.
// Ps = 3 5  ⇒  Set foreground color to Magenta.
// Ps = 3 6  ⇒  Set foreground color to Cyan.
// Ps = 3 7  ⇒  Set foreground color to White.
// Ps = 3 9  ⇒  Set foreground color to default, ECMA-48 3rd.
// Ps = 4 0  ⇒  Set background color to Black.
// Ps = 4 1  ⇒  Set background color to Red.
// Ps = 4 2  ⇒  Set background color to Green.
// Ps = 4 3  ⇒  Set background color to Yellow.
// Ps = 4 4  ⇒  Set background color to Blue.
// Ps = 4 5  ⇒  Set background color to Magenta.
// Ps = 4 6  ⇒  Set background color to Cyan.
// Ps = 4 7  ⇒  Set background color to White.
// Ps = 4 9  ⇒  Set background color to default, ECMA-48 3rd.
// Ps = 9 0  ⇒  Set foreground color to Bright Black.
// Ps = 9 1  ⇒  Set foreground color to Bright Red.
// Ps = 9 2  ⇒  Set foreground color to Bright Green.
// Ps = 9 3  ⇒  Set foreground color to Bright Yellow.
// Ps = 9 4  ⇒  Set foreground color to Bright Blue.
// Ps = 9 5  ⇒  Set foreground color to Bright Magenta.
// Ps = 9 6  ⇒  Set foreground color to Bright Cyan.
// Ps = 9 7  ⇒  Set foreground color to Bright White.
// Ps = 1 0 0  ⇒  Set background color to Bright Black.
// Ps = 1 0 1  ⇒  Set background color to Bright Red.
// Ps = 1 0 2  ⇒  Set background color to Bright Green.
// Ps = 1 0 3  ⇒  Set background color to Bright Yellow.
// Ps = 1 0 4  ⇒  Set background color to Bright Blue.
// Ps = 1 0 5  ⇒  Set background color to Bright Magenta.
// Ps = 1 0 6  ⇒  Set background color to Bright Cyan.
// Ps = 1 0 7  ⇒  Set background color to Bright White.
    const std::string_view s = m_CSIState.buffer;
    
    auto params = CSIParamsScanner::Parse(s);
    if( params.count == 0 )
        params.values[params.count++] = 0;
    
    for( int i = 0; i != params.count; ++i ) {
        const auto ps = params.values[i];
        auto attrs = SCImToCharacterAttributes(ps);
        if( attrs ) {
            m_Output.emplace_back( input::Type::set_character_attributes, *attrs );
        }
        else {
            LogMissedCSIRequest( s );
        }
    }
}

void Parser2Impl::CSI_n() noexcept
{
//CSI Ps n  Device Status Report (DSR).
//            Ps = 5  ⇒  Status Report.
//          Result ("OK") is CSI 0 n
//            Ps = 6  ⇒  Report Cursor Position (CPR) [row;column].
//          Result is CSI r ; c R
    const std::string_view s = m_CSIState.buffer;
    int ps = 0;
    auto result = std::from_chars(s.data(), s.data() + s.size(), ps);
    if( result.ec == std::errc{} ) {
        if( ps == 5 ) {
            input::DeviceReport dr;
            dr.mode = input::DeviceReport::DeviceStatus;
            m_Output.emplace_back( input::Type::report, dr );
        }
        if( ps == 6 ) {
            input::DeviceReport dr;
            dr.mode = input::DeviceReport::CursorPosition;
            m_Output.emplace_back( input::Type::report, dr );
        }
    }
}

void Parser2Impl::CSI_r() noexcept
{
// CSI Ps ; Ps r
//    Set Scrolling Region [top;bottom] (default = full size of window) (DECSTBM), VT100.
    std::string_view request = m_CSIState.buffer;
    const auto p = CSIParamsScanner::Parse(request);
    if( p.count == 0 ){
        input::ScrollingRegion scrolling_region;
        m_Output.emplace_back( input::Type::set_scrolling_region, scrolling_region );
    }
    else if (p.count == 2) {
        input::ScrollingRegion scrolling_region;
        if( p.values[0] >= 1 && p.values[1] >= 1 && p.values[1] > p.values[0] )
            scrolling_region.range = input::ScrollingRegion::Range{
                static_cast<int>(p.values[0]-1),
                static_cast<int>(p.values[1])};
        m_Output.emplace_back( input::Type::set_scrolling_region, scrolling_region );
    }
    else {
        LogMissedCSIRequest(m_CSIState.buffer);
        return;
    }
}

void Parser2Impl::CSI_Accent() noexcept
{
// CSI Pm `  Character Position Absolute  [column] (default = [row,1]) (HPA).
    const std::string_view s = m_CSIState.buffer;
    int ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    ps = std::max(ps - 1, 0);
    input::CursorMovement cm;
    cm.positioning = input::CursorMovement::Absolute;
    cm.x = ps;
    cm.y = std::nullopt;
    m_Output.emplace_back( input::Type::move_cursor, cm );
}

void Parser2Impl::CSI_At() noexcept
{
// CSI Ps @  Insert Ps (Blank) Character(s) (default = 1) (ICH).
    const std::string_view s = m_CSIState.buffer;
    int ps = 1; // default value
    std::from_chars(s.data(), s.data() + s.size(), ps);
    m_Output.emplace_back( input::Type::insert_characters, static_cast<unsigned>(ps) );    
}

void Parser2Impl::SSDCSEnter() noexcept
{
    m_DCSState.buffer.clear();
}

static std::optional<unsigned> DCS_Target(const char _c) noexcept
{
    switch( _c ) {
        case '(': return 0;
        case ')': return 1;
        case '*': return 2;
        case '+': return 3;
        default: return std::nullopt;
    }
}

static std::optional<input::CharacterSetDesignation::Set>
DCS_Set( const std::string_view _str ) noexcept
{
    using CSD = input::CharacterSetDesignation;
    if( _str == "0" ) return CSD::DECSpecialGraphics;
    if( _str == "1" ) return CSD::AlternateCharacterROMStandardCharacters;
    if( _str == "2" ) return CSD::AlternateCharacterROMSpecialGraphics;
    if( _str == "A" ) return CSD::UK;
    if( _str == "B" ) return CSD::USASCII;
    return std::nullopt;
}

void Parser2Impl::SSDCSExit() noexcept
{
    const std::string_view buffer = m_DCSState.buffer;
    if( buffer.length() < 2 )
        return;
    
    const auto target = DCS_Target(buffer.front());
    if( target == std::nullopt )
        return;
    
    const auto set = DCS_Set(buffer.substr(1));
    if( set == std::nullopt )
        return;
    
    input::CharacterSetDesignation csd;
    csd.target = *target;
    csd.set = *set;
    m_Output.emplace_back( input::Type::designate_character_set, csd );
}

constexpr static std::array<bool, 256> g_DCS_ValidTerminal =
    Make8BitBoolTable("?=<>012345679ABCEHKQRfYZ");

constexpr static std::array<bool, 256> g_DCS_ValidContents =
    Make8BitBoolTable("()*+\"%`&");

bool Parser2Impl::SSDCSConsume(unsigned char _byte) noexcept
{
     if( g_DCS_ValidContents[_byte] ) {
         m_DCSState.buffer += static_cast<char>(_byte);
         return true;
     }
     else {
         if( g_DCS_ValidTerminal[_byte] ) {
             m_DCSState.buffer += static_cast<char>(_byte);
             SwitchTo(EscState::Text);
             return true;
         }
         else {
             m_DCSState.buffer.clear(); // discard
             SwitchTo(EscState::Text);
             return false;
         }
     }
}

Parser2Impl::CSIParamsScanner::Params
Parser2Impl::CSIParamsScanner::Parse(std::string_view _csi) noexcept
{
    Params p;
    auto string = _csi;
    while( true ) {
        if( p.count == p.values.size() )
            break;
        unsigned value = 0;
        auto result = std::from_chars(string.data(), string.data() + string.size(), value); 
        if( result.ec == std::errc{} ) {
            p.values[p.count++] = value;
            
            string.remove_prefix( result.ptr - string.data() );
            if( string.empty() || string.front() != ';' )
                break;
            string.remove_prefix(1);
        }
        else {
            if( !string.empty() && string.front() == ';' ) {
                p.values[p.count++] = 0;
                string.remove_prefix(1);
            }
            else {
                break;
            }
        }
    }
    return p;
} 

}
