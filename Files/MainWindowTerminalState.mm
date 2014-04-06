//
//  MainWindowTerminalState.m
//  Files
//
//  Created by Michael G. Kazakov on 26.11.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import "MainWindowTerminalState.h"
#import "TermShellTask.h"
#import "TermScreen.h"
#import "TermParser.h"
#import "TermView.h"
#import "MainWindowController.h"
#import "MessageBox.h"
#import "FontCache.h"

#import "Common.h"

@implementation MainWindowTerminalState
{
    unique_ptr<TermShellTask>    m_Task;
    unique_ptr<TermScreen>  m_Screen;
    unique_ptr<TermParser>  m_Parser;
    TermView        *m_View;
    char            m_InitalWD[MAXPATHLEN];
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if(self)
    {
        strcpy(m_InitalWD, "/");
        GetUserHomeDirectoryPath(m_InitalWD);
        
        m_View = [[TermView alloc] initWithFrame:self.frame];
        self.documentView = m_View;
        self.hasVerticalScroller = true;
        self.borderType = NSNoBorder;
        self.verticalScrollElasticity = NSScrollElasticityNone;
        self.scrollsDynamically = true;
        self.contentView.copiesOnScroll = false;
        self.contentView.canDrawConcurrently = false;
        self.contentView.drawsBackground = false;
        
        m_Task.reset(new TermShellTask);
        auto task_ptr = m_Task.get();
        m_Screen.reset(new TermScreen(floor(frameRect.size.width / [m_View FontCache]->Width()),
                                      floor(frameRect.size.height / [m_View FontCache]->Height())));
        m_Parser = make_unique<TermParser>(m_Screen.get(),
                                           ^(const void* _d, int _sz){
                                               task_ptr->WriteChildInput(_d, _sz);
                                           });
        [m_View AttachToScreen:m_Screen.get()];
        [m_View AttachToParser:m_Parser.get()];
        
        
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(frameDidChange)
                                                   name:NSViewFrameDidChangeNotification
                                                 object:self];
    }
    return self;
}

- (void) dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSView*) ContentView
{
    return self;
}

- (void) SetInitialWD:(const char*)_wd
{
    if(_wd && strlen(_wd) > 0)
        strcpy(m_InitalWD, _wd);
}

- (void) Assigned
{
    // need right CWD here
    if(m_Task->State() == TermShellTask::StateInactive)
        m_Task->Launch(m_InitalWD, m_Screen->Width(), m_Screen->Height());
    
    __weak MainWindowTerminalState *weakself = self;
    
    m_Task->SetOnChildOutput(^(const void* _d, int _sz){
        if(MainWindowTerminalState *strongself = weakself)
        {
            bool newtitle = false;
            strongself->m_Screen->Lock();
            for(int i = 0; i < _sz; ++i)
            {
                int flags = 0;

                strongself->m_Parser->EatByte(((const char*)_d)[i], flags);

                if(flags & TermParser::Result_ChangedTitle)
                    newtitle = true;
            }
        
            strongself->m_Parser->Flush();
            strongself->m_Screen->Unlock();
        
            //            tmb.Reset("Parsed in: ");
            dispatch_to_main_queue( ^{
                [strongself->m_View adjustSizes:false];
                [strongself->m_View setNeedsDisplay:true];
                if(newtitle)
                    [strongself UpdateTitle];
            });
        }
    });
    
    m_Task->SetOnBashPrompt(^(const char *_cwd){
        if(MainWindowTerminalState *strongself = weakself)
        {
            strongself->m_Screen->SetTitle("");
            [strongself UpdateTitle];
        }
    });
    
    [self.window makeFirstResponder:m_View];
    [self UpdateTitle];
}


- (void) UpdateTitle
{
    NSString *title = 0;
    
    m_Screen->Lock();
    if(strlen(m_Screen->Title()) > 0)
        title = [NSString stringWithUTF8String:m_Screen->Title()];
    m_Screen->Unlock();
    
    if(title == 0)
    {
        m_Task->Lock();
        string cwd = m_Task->CWD();
        m_Task->Unlock();
        
        if(!cwd.empty() && cwd.back() != '/')
            cwd += '/';
        title = [NSString stringWithUTF8String:cwd.c_str()];
    }

    self.window.title = title;
}

- (void) ChDir:(const char*)_new_dir
{
    m_Task->ChDir(_new_dir);
}

- (void) Execute:(const char *)_short_fn at:(const char*)_at
{
    m_Task->Execute(_short_fn, _at, nullptr);
}

- (void) Execute:(const char *)_short_fn at:(const char*)_at with_parameters:(const char*)_params
{
    m_Task->Execute(_short_fn, _at, _params);
}

- (void) Execute:(const char *)_full_fn with_parameters:(const char*)_params
{
    m_Task->ExecuteWithFullPath(_full_fn, _params);    
}

- (void)scrollWheel:(NSEvent *)theEvent
{
    NSRect scrollRect;
    scrollRect = [self documentVisibleRect];
    scrollRect.origin.y -= theEvent.deltaY * self.verticalLineScroll;
    [self.documentView scrollRectToVisible:scrollRect];
}

- (bool)WindowShouldClose:(MainWindowController*)sender
{
//    NSLog(@"1! %ld", CFGetRetainCount((__bridge CFTypeRef)self));
    
    if(m_Task->State() == TermShellTask::StateDead ||
       m_Task->State() == TermShellTask::StateInactive ||
       m_Task->State() == TermShellTask::StateShell)
        return true;
    
    vector<string> children;
    m_Task->GetChildrenList(children);
    if(children.empty())
        return true;

    MessageBox *dialog = [[MessageBox alloc] init];
    dialog.messageText = @"Do you want to close this window?";
    NSMutableString *cap = [NSMutableString new];
    [cap appendString:@"Closing this window will terminate the running processes: "];
    for(int i = 0; i < children.size(); ++i)
    {
        [cap appendString:[NSString stringWithUTF8String:children[i].c_str()]];
        if(i != children.size() - 1)
            [cap appendString:@", "];
    }
    [cap appendString:@"."];
    dialog.informativeText = cap;
    [dialog addButtonWithTitle:@"Terminate And Close"];
    [dialog addButtonWithTitle:@"Cancel"];
    [dialog ShowSheetWithHandler:self.window handler:^(int result) {
        if (result == NSAlertFirstButtonReturn)
        {
            [dialog.window orderOut:nil];
            [sender.window close];
        }
    }];
    
    return false;
}

- (void)frameDidChange
{
    if(self.frame.size.width != m_View.frame.size.width)
    {
        NSRect dr = m_View.frame;
        dr.size.width = self.frame.size.width;
        [m_View setFrame:dr];
    }
    
    int sy = floor(self.frame.size.height / [m_View FontCache]->Height());
    int sx = floor(m_View.frame.size.width / [m_View FontCache]->Width());

    m_Screen->ResizeScreen(sx, sy);
    m_Task->ResizeWindow(sx, sy);
    m_Parser->Resized();
    
    [m_View adjustSizes:true];
}

- (IBAction)paste:(id)sender
{
    if(m_Task->State() == TermShellTask::StateDead ||
       m_Task->State() == TermShellTask::StateInactive )
        return;

    NSPasteboard *paste_board = [NSPasteboard generalPasteboard];
    NSString *best_type = [paste_board availableTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]];
    if(!best_type)
        return;
    
    NSString *text = [paste_board stringForType:NSStringPboardType];
    if(!text)
        return;

    const char* utf8str = [text UTF8String];
    m_Task->WriteChildInput(utf8str, (int)strlen(utf8str));
}

- (bool) IsAnythingRunning
{
    auto state = m_Task->State();
    return state == TermShellTask::StateProgramExternal || state == TermShellTask::StateProgramInternal;
}

- (void) Terminate
{
    m_Task->Terminate();
}

- (bool) GetCWD:(char *)_cwd
{
    if(m_Task->State() == TermShellTask::StateInactive ||
       m_Task->State() == TermShellTask::StateDead)
        return false;
    
    if(strlen(m_Task->CWD()) == 0)
       return 0;
    
    strcpy(_cwd, m_Task->CWD());
    return true;
}

- (IBAction)OnShowTerminal:(id)sender
{
    [(MainWindowController*)self.window.delegate ResignAsWindowState:self];
}

@end
