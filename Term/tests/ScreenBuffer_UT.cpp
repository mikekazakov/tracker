// Copyright (C) 2015-2020 Michael Kazakov. Subject to GNU General Public License version 3.

#include "Tests.h"

// TODO: Fixme, please... 🤦
#define private public
#include <ScreenBuffer.h>

using namespace nc::term;
#define PREFIX "nc::term::ScreenBuffer "

TEST_CASE(PREFIX"Init")
{
    SECTION("Normal case"){
        ScreenBuffer buffer(3,4);
        REQUIRE(buffer.Width() == 3);
        REQUIRE(buffer.Height() == 4);
        (buffer.LineFromNo(0).first)->l = 'A';
        (buffer.LineFromNo(3).second-1)->l = 'B';
        REQUIRE( buffer.DumpScreenAsANSI() ==
                "A  "
                "   "
                "   "
                "  B");
        REQUIRE( buffer.LineWrapped(3) == false );
        buffer.SetLineWrapped(3, true);
        REQUIRE( buffer.LineWrapped(3) == true );
    }
    SECTION("Empty buffer"){
        ScreenBuffer buffer(0,0);
        REQUIRE(buffer.Width() == 0);
        REQUIRE(buffer.Height() == 0);
        auto l1 = buffer.LineFromNo(0);
        REQUIRE( l1.first == nullptr );
        REQUIRE( l1.second == nullptr );
        auto l2 = buffer.LineFromNo(10);
        REQUIRE( l2.first == nullptr );
        REQUIRE( l2.second == nullptr );
        auto l3 = buffer.LineFromNo(-1);
        REQUIRE( l3.first == nullptr );
        REQUIRE( l3.second == nullptr );
    }
    SECTION("Zero width"){
        ScreenBuffer buffer(0,2);
        REQUIRE(buffer.Width() == 0);
        REQUIRE(buffer.Height() == 2);
        auto l1 = buffer.LineFromNo(0);
        auto l2 = buffer.LineFromNo(0);
        REQUIRE( l1.first == l1.second );
        REQUIRE( l2.first == l2.second );
        REQUIRE( l1.first == l2.first  );
    }
}

TEST_CASE(PREFIX"ComposeContinuousLines")
{
    ScreenBuffer buffer(3,4);
    (buffer.LineFromNo(0).second-1)->l = 'A';
    (buffer.LineFromNo(2).second-1)->l = 'B';
    REQUIRE( buffer.DumpScreenAsANSI() ==
            "  A"
            "   "
            "  B"
            "   ");
    
    auto cl1 = buffer.ComposeContinuousLines(0, 4);
    REQUIRE( cl1.size() == 4 );
    REQUIRE( cl1[0].size() == 3 );
    REQUIRE( cl1[0].at(2).l == 'A' );
    REQUIRE( cl1[2].size() == 3 );
    REQUIRE( cl1[2].at(2).l == 'B' );
    
    buffer.SetLineWrapped(0, true);
    auto cl2 = buffer.ComposeContinuousLines(0, 4);
    REQUIRE( cl2.size() == 3 );
    REQUIRE( cl2[0].size() == 3 );
    REQUIRE( cl2[0].at(2).l == 'A' );
    REQUIRE( cl2[1].size() == 3 );
    REQUIRE( cl2[1].at(2).l == 'B' );
    
    buffer.SetLineWrapped(1, true);
    auto cl3 = buffer.ComposeContinuousLines(0, 4);
    REQUIRE( cl3.size() == 2 );
    REQUIRE( cl3[0].size() == 6 );
    REQUIRE( cl3[0].at(2).l == 'A' );
    REQUIRE( cl3[0].at(4).l == 0 );
    REQUIRE( cl3[0].at(5).l == 'B');
}
