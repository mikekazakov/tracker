//
//  MainWindow.m
//  Files
//
//  Created by Michael G. Kazakov on 01/11/14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#include <Utility/SystemInformation.h>
#include <NimbleCommander/Core/ActionsShortcutsManager.h>
#include <NimbleCommander/Core/Theming/CocoaAppearanceManager.h>
#include "MainWindow.h"
#include "MainWindowController.h"

static const auto g_Identifier = NSStringFromClass(MainWindow.class);

@implementation MainWindow

+ (NSString*) defaultIdentifier
{
    return g_Identifier;
}

- (instancetype) init
{
    static const auto flags =
        NSResizableWindowMask|NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|
        NSTexturedBackgroundWindowMask|NSWindowStyleMaskFullSizeContentView;
    
    if( self = [super initWithContentRect:NSMakeRect(100, 100, 1000, 600)
                                styleMask:flags
                                  backing:NSBackingStoreBuffered
                                    defer:false] ) {
        
        self.minSize = NSMakeSize(640, 480);
        self.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        self.restorable = YES;
        self.identifier = g_Identifier;
        self.title = @"";
        if( ![self setFrameUsingName:g_Identifier] )
            [self center];
        if( sysinfo::GetOSXVersion() >= sysinfo::OSXVersion::OSX_12 )
            self.tabbingMode = NSWindowTabbingModeDisallowed;
        
        [self setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
        [self setContentBorderThickness:40 forEdge:NSMinYEdge];
        self.contentView.wantsLayer = YES;
        CocoaAppearanceManager::Instance().ManageWindowApperance(self);
        [self invalidateShadow];
    }
    return self;
}

- (void) dealloc
{
    [self saveFrameUsingName:g_Identifier];
}

+ (BOOL) allowsAutomaticWindowTabbing
{
    return false;
}

- (BOOL) validateMenuItem:(NSMenuItem *)item
{
    auto tag = item.tag;
    
    IF_MENU_TAG("menu.file.close") {
        item.title = NSLocalizedString(@"Close Window", "Menu item title");
        return true;
    }
    IF_MENU_TAG("menu.file.close_window") {
        item.hidden = true;
        return true;
    }
    
    return [super validateMenuItem:item];
}

- (IBAction)OnFileCloseWindow:(id)sender { /* dummy, never called */ }

- (IBAction)toggleToolbarShown:(id)sender
{
    if( auto wc = objc_cast<MainWindowController>(self.windowController) )
        [wc OnShowToolbar:sender];
    else
        [super toggleToolbarShown:sender];
}

@end
