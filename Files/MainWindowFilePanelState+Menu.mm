//
//  MainWindowFilePanelState+Menu.m
//  Files
//
//  Created by Michael G. Kazakov on 19.12.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import "MainWindowFilePanelState+Menu.h"
#import "PanelController.h"
#import "FileDeletionOperation.h"
#import "FilePanelMainSplitView.h"
#import "OperationsController.h"
#import "Common.h"
#import "common_paths.h"
#import "ExternalEditorInfo.h"
#import "MainWindowController.h"

@implementation MainWindowFilePanelState (Menu)

- (IBAction)OnMoveToTrash:(id)sender
{
    if([m_MainSplitView IsViewCollapsedOrOverlayed:[self ActivePanelView]])
        return;
    
    if([self ActivePanelData]->Host()->IsNativeFS() == false &&
       [self ActivePanelData]->Host()->IsWriteable() == true )
    {
        // instead of trying to silently reap files on VFS like FTP (that means we'll erase it, not move to trash) -
        // forward request as a regular F8 delete
        [self OnDeleteCommand:self];
        return;
    }
    
    auto files = [self.ActivePanelController GetSelectedEntriesOrFocusedEntryWithoutDotDot];
    if(files.empty())
        return;
    
    FileDeletionOperation *op = [[FileDeletionOperation alloc]
                                 initWithFiles:move(files)
                                 type:FileDeletionOperationType::MoveToTrash
                                 rootpath:[self ActivePanelData]->DirectoryPathWithTrailingSlash().c_str()];
    op.TargetPanel = [self ActivePanelController];
    [m_OperationsController AddOperation:op];
}

- (IBAction)OnShowTerminal:(id)sender
{
    string path = "";
    if(self.isPanelActive && self.ActivePanelController.VFS->IsNativeFS())
        path = self.ActivePanelController.GetCurrentDirectoryPathRelativeToHost;
    [(MainWindowController*)self.window.delegate RequestTerminal:path];
}

@end
