//
//  FindFileSheetController.h
//  Files
//
//  Created by Michael G. Kazakov on 12.02.14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#pragma once

#include "vfs/VFS.h"
#include "SheetController.h"

@class FindFilesSheetFoundItem;

struct FindFilesSheetControllerFoundItem
{
    string filename;
    string dir_path;
    string rel_path;
    string full_filename;
    VFSStat st;
    CFRange content_pos;
};

@interface FindFilesSheetController : SheetController<NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDataSource>

- (IBAction)OnClose:(id)sender;
- (IBAction)OnSearch:(id)sender;
- (IBAction)OnFileView:(id)sender;

@property (nonatomic) VFSHostPtr host;
@property (nonatomic) string path;

@property (strong) IBOutlet NSButton *CloseButton;
@property (strong) IBOutlet NSButton *SearchButton;
@property (strong) IBOutlet NSButton *PanelButton;
@property (strong) IBOutlet NSComboBox *MaskComboBox;
@property (strong) IBOutlet NSComboBox *TextComboBox;

@property (strong) IBOutlet NSTableView *TableView;
@property (strong) IBOutlet NSButton *CaseSensitiveButton;
@property (strong) IBOutlet NSButton *WholePhraseButton;

@property NSMutableArray *FoundItems;
@property (strong) IBOutlet NSArrayController *ArrayController;
@property (strong) IBOutlet NSPopUpButton *SizeRelationPopUp;
@property (strong) IBOutlet NSTextField *SizeTextField;
@property (strong) IBOutlet NSPopUpButton *SizeMetricPopUp;
@property (strong) IBOutlet NSButton *SearchForDirsButton;
@property (strong) IBOutlet NSButton *SearchInSubDirsButton;
@property (strong) IBOutlet NSPopUpButton *EncodingsPopUp;
@property FindFilesSheetFoundItem* focusedItem; // may be nullptr
@property function<void(const map<string, vector<string>>&_dir_to_filenames)> OnPanelize;

- (FindFilesSheetControllerFoundItem*) SelectedItem; // may be nullptr

@end
