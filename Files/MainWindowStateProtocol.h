//
//  MainWindowStateProtocol.h
//  Files
//
//  Created by Michael G. Kazakov on 04.06.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once

@class MainWindowController;
@class MyToolbar;

@protocol MainWindowStateProtocol <NSObject>
- (NSView*) windowContentView;
- (NSToolbar*) toolbar;

@optional
- (void)Assigned;
- (void)Resigned;
- (void)didBecomeKeyWindow;
- (void)WindowDidResize;
- (void)WindowWillClose;
- (void)WindowWillBeginSheet;
- (void)WindowDidEndSheet;
- (bool)WindowShouldClose:(MainWindowController*)sender;
//- (void)SkinSettingsChanged;
- (void)OnApplicationWillTerminate;
- (bool)needsWindowTitle;
@end
