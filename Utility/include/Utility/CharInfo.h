// Copyright (C) 2013-2020 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include <stdint.h>

namespace nc::utility {

class CharInfo {
public:
    static bool IsUnicodeCombiningCharacter(uint32_t _a) noexcept;
    static bool CanCharBeTheoreticallyComposed(uint32_t _c) noexcept;
    static unsigned char WCWidthMin1(uint32_t _c) noexcept;
    static void BuildPossibleCompositionEvidenceTable();
    
private:
    static uint32_t g_PossibleCompositionEvidence[2048];
    static uint32_t g_WCWidthTableIsFullSize[2048];
};

inline bool CharInfo::IsUnicodeCombiningCharacter(uint32_t _a) noexcept
{
    return
    (_a >= 0x0300 && _a <= 0x036F) ||
    (_a >= 0x1DC0 && _a <= 0x1DFF) ||
    (_a >= 0x20D0 && _a <= 0x20FF) ||
    (_a >= 0xFE20 && _a <= 0xFE2F) ;
}

inline bool CharInfo::CanCharBeTheoreticallyComposed(uint32_t _c) noexcept
{
    if(_c >= 0x10000)
        return false;
    return (g_PossibleCompositionEvidence[_c / 32] >> (_c % 32)) & 1;
}

inline unsigned char CharInfo::WCWidthMin1(uint32_t _c) noexcept
{
    if(_c < 0x10000)
        return ((g_WCWidthTableIsFullSize[_c / 32] >> (_c % 32)) & 1) ? 2 : 1;
    else
        return
        (_c >= 0x10000 && _c <= 0x1fffd) ||
        (_c >= 0x20000 && _c <= 0x2fffd) ||
        (_c >= 0x30000 && _c <= 0x3fffd) ?
        2 : 1;
}

}
