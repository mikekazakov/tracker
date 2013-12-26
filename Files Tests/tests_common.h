//
//  tests_common.h
//  Files
//
//  Created by Michael G. Kazakov on 26.12.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once

#import <XCTest/XCTest.h>

#define XCTAssertCPPThrows(expression, format...) \
    ({ \
        bool __caughtException = false; \
        try { \
            (expression); \
        } \
        catch (...) { \
            __caughtException = true; \
        }\
        if (!__caughtException) { \
            _XCTRegisterFailure(_XCTFailureDescription(_XCTAssertion_Throws, 0, @#expression),format); \
        } \
    })
