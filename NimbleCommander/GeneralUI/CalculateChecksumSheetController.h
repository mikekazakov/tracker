// Copyright (C) 2014-2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include <Utility/SheetController.h>
#include <VFS/VFS.h>

@interface CalculateChecksumSheetController : SheetController<NSTableViewDataSource, NSTableViewDelegate>

@property (strong) IBOutlet NSPopUpButton *HashMethod;
@property (strong) IBOutlet NSTableView *Table;
@property (strong) IBOutlet NSProgressIndicator *Progress;
@property bool isWorking;
@property bool sumsAvailable;
@property (nonatomic) bool didSaved;
@property (nonatomic, readonly) string savedFilename;
@property (strong) IBOutlet NSTableColumn *filenameTableColumn;
@property (strong) IBOutlet NSTableColumn *checksumTableColumn;

- (id)initWithFiles:(vector<string>)files
          withSizes:(vector<uint64_t>)sizes
             atHost:(const VFSHostPtr&)host
             atPath:(string)path;

- (IBAction)OnClose:(id)sender;
- (IBAction)OnCalc:(id)sender;
- (IBAction)OnSave:(id)sender;

@end
