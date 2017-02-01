//
//  PreferencesWindowExternalEditorsTab.m
//  Files
//
//  Created by Michael G. Kazakov on 07.04.14.
//  Copyright (c) 2014 Michael G. Kazakov. All rights reserved.
//

#include <NimbleCommander/Bootstrap/AppDelegate.h>
#include <NimbleCommander/States/FilePanels/ExternalEditorInfo.h>
#include "PreferencesWindowExternalEditorsTabNewEditorSheet.h"
#include "PreferencesWindowExternalEditorsTab.h"

#define MyPrivateTableViewDataType @"PreferencesWindowExternalEditorsTabPrivateTableViewDataType"

@interface PreferencesWindowExternalEditorsTab ()

@property (nonatomic) NSMutableArray *ExtEditors;
@property (strong) IBOutlet NSArrayController *ExtEditorsController;
@property (strong) IBOutlet NSTableView *TableView;

- (IBAction)OnNewEditor:(id)sender;

@end

@implementation PreferencesWindowExternalEditorsTab
{
    NSMutableArray *m_Editors;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:NSStringFromClass(self.class) bundle:nibBundleOrNil];
    if (self) {
    
        auto v = AppDelegate.me.externalEditorsStorage.AllExternalEditors();
        m_Editors = [NSMutableArray new];
        for( auto i: v ) {
            ExternalEditorInfo *ed = [ExternalEditorInfo new];
            ed.name = [NSString stringWithUTF8StdString:i->Name()];
            ed.path = [NSString stringWithUTF8StdString:i->Path()];
            ed.arguments = [NSString stringWithUTF8StdString:i->Arguments()];
            ed.mask = [NSString stringWithUTF8StdString:i->Mask()];
            ed.only_files = i->OnlyFiles();
            ed.max_size = i->MaxFileSize();
            ed.terminal = i->OpenInTerminal();
            [m_Editors addObject:ed];
        }
    }
    
    return self;
}

- (void)loadView
{
    [super loadView];
    
    self.TableView.target = self;
    self.TableView.doubleAction = @selector(OnTableDoubleClick:);
    self.TableView.dataSource = self;
    [self.TableView registerForDraggedTypes:@[MyPrivateTableViewDataType]];
    [self.view layoutSubtreeIfNeeded];    
}

-(NSString*)identifier{
    return NSStringFromClass(self.class);
}
-(NSImage*)toolbarItemImage{
    return [NSImage imageNamed:@"PreferencesIcons_ExtEditors"];
}
-(NSString*)toolbarItemLabel{
    return NSLocalizedStringFromTable(@"Editors",
                                      @"Preferences",
                                      "General preferences tab title");
}

- (NSMutableArray *) ExtEditors
{
    return m_Editors;
}

- (void) setExtEditors:(NSMutableArray *)ExtEditors
{
    m_Editors = ExtEditors;
    vector< shared_ptr<ExternalEditorStartupInfo> > eds;
    for( ExternalEditorInfo *i in m_Editors )
        eds.emplace_back( [i toStartupInfo] );
    
    AppDelegate.me.externalEditorsStorage.SetExternalEditors( eds );
}

- (IBAction)OnNewEditor:(id)sender
{
    PreferencesWindowExternalEditorsTabNewEditorSheet *sheet = [PreferencesWindowExternalEditorsTabNewEditorSheet new];
    sheet.Info = [ExternalEditorInfo new];
    sheet.Info.mask = @"*";
    [sheet beginSheetForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if(returnCode == NSModalResponseOK)
            [self.ExtEditorsController insertObject:sheet.Info atArrangedObjectIndex:0];
    }];    
}

- (void)OnTableDoubleClick:(id)table
{
    NSInteger row = [self.TableView clickedRow];
    if(row >= [self.ExtEditorsController.arrangedObjects count])
        return;
        
    ExternalEditorInfo *item = [self.ExtEditorsController.arrangedObjects objectAtIndex:row];
    PreferencesWindowExternalEditorsTabNewEditorSheet *sheet = [PreferencesWindowExternalEditorsTabNewEditorSheet new];
    sheet.Info = [item copy];
    [sheet beginSheetForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
            if(returnCode == NSModalResponseOK) {
                [self.ExtEditorsController removeObjectAtArrangedObjectIndex:row];
                [self.ExtEditorsController insertObject:sheet.Info atArrangedObjectIndex:row];
            }
        }
     ];
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    return operation == NSTableViewDropOn ? NSDragOperationNone : NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
    [pboard declareTypes:@[MyPrivateTableViewDataType]
                   owner:self];
    [pboard setData:[NSKeyedArchiver archivedDataWithRootObject:rowIndexes]
            forType:MyPrivateTableViewDataType];
    return true;
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)drag_to
    dropOperation:(NSTableViewDropOperation)operation
{
    NSData* data = [info.draggingPasteboard dataForType:MyPrivateTableViewDataType];
    NSIndexSet* inds = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    NSInteger drag_from = inds.firstIndex;
  
    if(drag_to == drag_from || // same index, above
       drag_to == drag_from + 1) // same index, below
        return false;
    
    assert(drag_from < [self.ExtEditorsController.arrangedObjects count]);
    if(drag_from < drag_to)
        drag_to--;
    
    ExternalEditorInfo *item = [self.ExtEditorsController.arrangedObjects objectAtIndex:drag_from];
    [self.ExtEditorsController removeObject:item];
    [self.ExtEditorsController insertObject:item atArrangedObjectIndex:drag_to];
    return true;
}

@end
