//
//  MainWindowFilePanelState+Menu.m
//  Files
//
//  Created by Michael G. Kazakov on 19.12.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import <pwd.h>
#import <assert.h>
#import "MainWindowFilePanelState+Menu.h"
#import "PanelController.h"
#import "FilePanelMainSplitView.h"
#import "GoToFolderSheetController.h"
#import "Common.h"

@implementation MainWindowFilePanelState (Menu)

- (IBAction)OnOpen:(id)sender
{
    [[self ActivePanelController] HandleReturnButton];
}

- (IBAction)OnOpenNatively:(id)sender
{
    [[self ActivePanelController] HandleShiftReturnButton];
}

- (IBAction)OnGoToHome:(id)sender
{
    [self DoGoToNativeDirectoryFromMenuItem:getpwuid(getuid())->pw_dir];
}

- (IBAction)OnGoToDocuments:(id)sender
{
    NSArray* paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    [self DoGoToNativeDirectoryFromMenuItem: [[paths objectAtIndex:0] fileSystemRepresentation]];
}

- (IBAction)OnGoToDesktop:(id)sender
{
    NSArray* paths = [[NSFileManager defaultManager] URLsForDirectory:NSDesktopDirectory inDomains:NSUserDomainMask];
    [self DoGoToNativeDirectoryFromMenuItem: [[paths objectAtIndex:0] fileSystemRepresentation]];    
}

- (IBAction)OnGoToDownloads:(id)sender
{
    NSArray* paths = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask];
    [self DoGoToNativeDirectoryFromMenuItem: [[paths objectAtIndex:0] fileSystemRepresentation]];
}

- (IBAction)OnGoToApplications:(id)sender
{
    [self DoGoToNativeDirectoryFromMenuItem:"/Applications/"];
}

- (IBAction)OnGoToUtilities:(id)sender
{
    [self DoGoToNativeDirectoryFromMenuItem:"/Applications/Utilities/"];
}

- (IBAction)OnGoToLibrary:(id)sender
{
    NSArray* paths = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask];
    [self DoGoToNativeDirectoryFromMenuItem: [[paths objectAtIndex:0] fileSystemRepresentation]];
}

- (void) DoGoToNativeDirectoryFromMenuItem: (const char*)_path
{
    if(_path == 0) return;
    
    if(m_ActiveState == StateLeftPanel)
    {
        [m_MainSplitView SetLeftOverlay:0]; // seem to be a redundant
        [m_LeftPanelController GoToGlobalHostsPathAsync:_path];
    }
    else if(m_ActiveState == StateRightPanel)
    {
        [m_MainSplitView SetRightOverlay:0]; // seem to be a redundant
        [m_RightPanelController GoToGlobalHostsPathAsync:_path];
    }
}

- (IBAction)OnGoBack:(id)sender
{
    [self.ActivePanelController OnGoBack];
}

- (IBAction)OnGoForward:(id)sender
{
    [self.ActivePanelController OnGoForward];
}

- (IBAction)OnGoToFolder:(id)sender
{
    GoToFolderSheetController *sheet = [GoToFolderSheetController new];
    [sheet ShowSheet:self.window handler:^int(){
        string path = [sheet.Text.stringValue fileSystemRepresentation];
        assert(!path.empty());
        if(path[0] == '/') {
            // absolute path
            return [self.ActivePanelController GoToGlobalHostsPathSync: path.c_str()];
        } else if(path[0] == '~') {
            // relative to home
            path.replace(0, 1, getpwuid(getuid())->pw_dir);
            return [self.ActivePanelController GoToGlobalHostsPathSync: path.c_str()];
        } else {
            // sub-dir
            char cwd[MAXPATHLEN];
            if([self.ActivePanelController GetCurrentDirectoryPathRelativeToHost:cwd]) {
                path.insert(0, cwd);
                return [self.ActivePanelController GoToGlobalHostsPathSync:path.c_str()];
            }
        }

        return 0;
    }];
}


@end
