//
//  PreferencesWindowExternalEditorsTabNewEditorSheet.h
//  Files
//
//  Created by Michael G. Kazakov on 07.04.14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "SheetController.h"
#import "ExternalEditorInfo.h"

@interface PreferencesWindowExternalEditorsTabNewEditorSheet : SheetController

@property (nonatomic, strong) ExternalEditorInfo *Info;
@property (nonatomic, readonly) bool hasTerminal;

- (IBAction)OnClose:(id)sender;
- (IBAction)OnOK:(id)sender;
- (IBAction)OnChoosePath:(id)sender;

@end
