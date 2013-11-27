//
//  MainWindowTerminalState.m
//  Files
//
//  Created by Michael G. Kazakov on 26.11.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import "MainWindowTerminalState.h"
#import "TermTask.h"
#import "TermScreen.h"
#import "TermParser.h"
#import "TermView.h"
#import "MainWindowController.h"

@implementation MainWindowTerminalState
{
    TermTask   *m_Task;
    TermScreen *m_Screen;
    TermParser *m_Parser;
    TermView   *m_View;
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if(self)
    {
        m_View = [[TermView alloc] initWithFrame:self.frame];
        [m_View setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self addSubview:m_View];
        NSDictionary *views = NSDictionaryOfVariableBindings(m_View);
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-(<=0)-[m_View]-(<=0)-|" options:0 metrics:nil views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(<=0)-[m_View]-(<=0)-|" options:0 metrics:nil views:views]];
        
        
        m_Task = new TermTask;
        
        m_Screen = new TermScreen([m_View SymbWidth], [m_View SymbHeight]);
        m_Parser = new TermParser(m_Screen, m_Task);
        [m_View AttachToScreen:m_Screen];
        [m_View AttachToParser:m_Parser];
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [self.window makeFirstResponder:m_View];
//        });

//        setInitialFirstResponder
        m_Task->SetOnChildOutput(^(const void* _d, int _sz){
            m_Screen->Lock();
            for(int i = 0; i < _sz; ++i)
                m_Parser->EatByte(((const char*)_d)[i]);
            
            m_Parser->Flush();
            m_Screen->Unlock();

            //    m_Screen->PrintToConsole();
            [m_View setNeedsDisplay:true];
        });

        m_Task->SetOnBashPrompt(^(const void* _d, int _sz){
            char tmp[1024];
            memcpy(tmp, _d, _sz);
            tmp[_sz] = 0;
/*            [self.CommandText setStringValue:[NSString stringWithUTF8String:tmp]];*/
//            printf("new BASH cwd: %s", tmp);
        });
        
        m_Task->Launch("/Users/migun/", [m_View SymbWidth], [m_View SymbHeight]);

        
    }
    return self;
}

- (void) dealloc
{
    delete m_Parser;
    delete m_Screen;
    delete m_Task;
}

- (NSView*) ContentView
{
    return self;
}

- (void) Assigned
{
    [self.window makeFirstResponder:m_View];
 //   [self UpdateTitle];
}

- (void)cancelOperation:(id)sender
{
    [(MainWindowController*)[[self window] delegate] ResignAsWindowState:self];
}

@end
