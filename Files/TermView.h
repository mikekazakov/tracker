//
//  TermView.h
//  TermPlays
//
//  Created by Michael G. Kazakov on 17.11.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//


#import "FPSLimitedDrawer.h"

class TermScreen;
class TermParser;
class FontCache;

enum class TermViewCursor
{
    Block       = 0,
    Underline   = 1,
    VerticalBar = 2
};

@interface TermView : NSView

@property (readonly) FPSLimitedDrawer *FPSDrawer;
@property (nonatomic, readonly) const FontCache &fontCache;
@property (nonatomic, readonly) TermParser *parser; // may be nullptr

- (void) reloadSettings;
- (void) AttachToScreen:(TermScreen*)_scr;
- (void) AttachToParser:(TermParser*)_par;

- (void) adjustSizes:(bool)_mandatory; // implicitly calls scrollToBottom when full height changes
- (void) scrollToBottom;

@end
