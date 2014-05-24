//
//  PanelView.m
//  Directories
//
//  Created by Michael G. Kazakov on 08.02.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#import "PanelView.h"
#import "PanelData.h"
#import "PanelViewPresentation.h"
#import "Common.h"
#import "VFS.h"

struct CursorSelectionState
{
    enum Type
    {
        No,
        Selection,
        Unselection
    };
};

struct PanelViewStateStorage
{
    int dispay_offset;
    string focused_item;
};


////////////////////////////////////////////////////////////////////////////////

@implementation PanelView
{
    unsigned long               m_KeysModifiersFlags;
    CursorSelectionState::Type  m_CursorSelectionType;
    PanelViewPresentation      *m_Presentation;
    PanelViewState              m_State;
    
    std::map<hash<VFSPathStack>::value_type, PanelViewStateStorage> m_States;
    
    double                      m_ScrollDY;
    
    bool                        m_ReadyToDrag;
    NSPoint                     m_LButtonDownPos;
    bool                        m_DraggingIntoMe;
    bool                        m_IsCurrentlyMomentumScroll;
    bool                        m_DisableCurrentMomentumScroll;
    __weak id<PanelViewDelegate> m_Delegate;
}

- (void) setDelegate:(id<PanelViewDelegate>)delegate
{
    m_Delegate = delegate;
    if(delegate)
    {
        id<PanelViewDelegate> del = m_Delegate;
        if([del isKindOfClass:NSResponder.class])
        {
            NSResponder *r = (NSResponder*)del;
            NSResponder *current = self.nextResponder;
            super.nextResponder = r;
            r.nextResponder = current;
        }
    }
}

- (id<PanelViewDelegate>) delegate
{
    return m_Delegate;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    m_State.Active = true;
    [self setNeedsDisplay:true];
    return YES;
}

- (BOOL)resignFirstResponder
{
    m_State.Active = false;
    [self setNeedsDisplay:true];
    return YES;
}

- (void)setNextResponder:(NSResponder *)newNextResponder
{
    if(self.delegate && [self.delegate isKindOfClass:NSResponder.class])
    {
        NSResponder *r = (NSResponder*)self.delegate;
        r.nextResponder = newNextResponder;
        return;
    }
    
    [super setNextResponder:newNextResponder];
}

- (void)viewWillMoveToWindow:(NSWindow *)_wnd
{
    if(_wnd == nil && m_State.Active == true)
        [self resignFirstResponder];
}

- (bool)active
{
    return m_State.Active;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        m_KeysModifiersFlags = 0;
        m_DraggingIntoMe = false;
        m_ScrollDY = 0.0;
        m_DisableCurrentMomentumScroll = false;
        m_IsCurrentlyMomentumScroll = false;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(frameDidChange)
                                                     name:NSViewFrameDidChangeNotification
                                                   object:self];
        [self frameDidChange];
        
    }
    
    return self;
}

-(void) dealloc
{
    m_State.Data = nullptr;
    delete m_Presentation;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (!m_State.Data || !m_Presentation) return;
    m_Presentation->Draw(dirtyRect);
    
    if(m_DraggingIntoMe) {
        [NSGraphicsContext saveGraphicsState];
        NSSetFocusRingStyle(NSFocusRingOnly);
        [[NSBezierPath bezierPathWithRect:NSInsetRect([self bounds],2,2)] fill];
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (void)frameDidChange
{
    if (m_Presentation)
        m_Presentation->OnFrameChanged([self frame]);
}

- (void) SetPanelData: (PanelData*) _data
{
    m_State.Data = _data;
    [self setNeedsDisplay:true];
}

- (void) SetPresentation:(PanelViewPresentation *)_presentation
{
    if (m_Presentation) delete m_Presentation;
    m_Presentation = _presentation;
    if (m_Presentation)
    {
        m_Presentation->SetState(&m_State);
        m_Presentation->SetView(self);
        [self frameDidChange];
        [self setNeedsDisplay:true];
    }
}

- (PanelViewPresentation*) Presentation
{
    return m_Presentation;
}

- (void) HandlePrevFile
{
    int origpos = m_State.CursorPos;
    
    m_Presentation->MoveCursorToPrevItem();
    
    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:origpos];
    
    [self OnCursorPositionChanged];
}

- (void) HandleNextFile
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToNextItem();
    
    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:origpos];
    
    [self OnCursorPositionChanged];
}

- (void) HandlePrevPage
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToPrevPage();

    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:m_State.CursorPos];

    [self OnCursorPositionChanged];
}

- (void) HandleNextPage
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToNextPage();

    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:m_State.CursorPos];    

    [self OnCursorPositionChanged];
}

- (void) HandlePrevColumn
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToPrevColumn();
    
    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:m_State.CursorPos];
    
    [self OnCursorPositionChanged];
}

- (void) HandleNextColumn
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToNextColumn();

    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:m_State.CursorPos];

    [self OnCursorPositionChanged];
}

- (void) HandleFirstFile;
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToFirstItem();

    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included:m_State.CursorPos];
    
    [self OnCursorPositionChanged];
}

- (void) HandleLastFile;
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToLastItem();

    if(m_CursorSelectionType != CursorSelectionState::No)
        [self SelectUnselectInRange:origpos last_included: m_State.CursorPos];    

    [self OnCursorPositionChanged];
}

- (void) HandleInsert
{
    int origpos = m_State.CursorPos;
    m_Presentation->MoveCursorToNextItem();
    
    auto entry = m_State.Data->EntryAtRawPosition(m_State.Data->RawIndexForSortIndex(origpos));
    bool sel_now = entry->CFIsSelected();
    [self SelectUnselectInRange:origpos last_included:origpos select:!sel_now];
    
    [self OnCursorPositionChanged];
}

- (void) setCurpos:(int)_pos
{
//    assert(_pos >= 0 && _pos < m_State.Data->SortedDirectoryEntries().size());
    
    if (m_State.CursorPos == _pos) return;

    m_Presentation->SetCursorPos(_pos); // _pos wil be filtered here

    [self OnCursorPositionChanged];
}

- (int) curpos
{
    return m_State.CursorPos;
}

- (void) OnCursorPositionChanged
{
    [self setNeedsDisplay:true];
    
    if(id<PanelViewDelegate> del = self.delegate)
        if([del respondsToSelector:@selector(PanelViewCursorChanged:)])
            [del PanelViewCursorChanged:self];
}

- (void)keyDown:(NSEvent *)event
{
    if(id<PanelViewDelegate> del = self.delegate)
        if([del respondsToSelector:@selector(PanelViewProcessKeyDown:event:)])
            if([del PanelViewProcessKeyDown:self event:event])
                return;
    
    NSString* character = [event charactersIgnoringModifiers];
    if ( [character length] != 1 ) {
        [super keyDown:event];
        return;
    }
    
    auto mod = event.modifierFlags;
    auto unicode = [character characterAtIndex:0];
//    unsigned short const keycode = [event keyCode];

    switch (unicode) {
        case NSHomeFunctionKey:       [self HandleFirstFile];     return;
        case NSEndFunctionKey:        [self HandleLastFile];      return;
        case NSPageDownFunctionKey:   [self HandleNextPage];      return;
        case NSPageUpFunctionKey:     [self HandlePrevPage];      return;
        case 0x03:                    [self HandleInsert];        return;
        case NSLeftArrowFunctionKey:
            if(!(mod & NSControlKeyMask) && !(mod & NSCommandKeyMask) && !(mod & NSAlternateKeyMask) ) {
                [self HandlePrevColumn];
                return;
            }
            break;
        case NSRightArrowFunctionKey:
            if(!(mod & NSControlKeyMask) && !(mod & NSCommandKeyMask) && !(mod & NSAlternateKeyMask) ) {
                [self HandleNextColumn];
                return;
            }
            break;
        case NSUpArrowFunctionKey:
            if(!(mod & NSControlKeyMask) && !(mod & NSCommandKeyMask) && !(mod & NSAlternateKeyMask) ) {
                [self HandlePrevFile];
                return;
            }
            break;
        case NSDownArrowFunctionKey:
            if(!(mod & NSControlKeyMask) && !(mod & NSCommandKeyMask) && !(mod & NSAlternateKeyMask) ) {
                [self HandleNextFile];
                return;
            }
            break;
    }
    
    [super keyDown:event];
}

- (void) ModifierFlagsChanged:(unsigned long)_flags
{
    m_KeysModifiersFlags = _flags; // ??
    if((m_KeysModifiersFlags & NSShiftKeyMask) == 0)
    { // clear selection type when user releases SHIFT button
        m_CursorSelectionType = CursorSelectionState::No;
    }
    else
    {
        if(m_CursorSelectionType == CursorSelectionState::No)
        { // lets decide if we need to select or unselect files when user will use navigation arrows
            if(const auto *item = self.item)
            {
                if(!item->IsDotDot())
                { // regular case
                    if(item->CFIsSelected()) m_CursorSelectionType = CursorSelectionState::Unselection;
                    else                     m_CursorSelectionType = CursorSelectionState::Selection;
                }
                else
                { // need to look at a first file (next to dotdot) for current representation if any.
                    if(m_State.Data->SortedDirectoryEntries().size() > 1)
                    { // using [1] item
                        const auto &item = m_State.Data->DirectoryEntries()[ m_State.Data->SortedDirectoryEntries()[1] ];
                        if(item.CFIsSelected()) m_CursorSelectionType = CursorSelectionState::Unselection;
                        else                     m_CursorSelectionType = CursorSelectionState::Selection;
                    }
                    else
                    { // singular case - selection doesn't matter - nothing to select
                        m_CursorSelectionType = CursorSelectionState::Selection;
                    }
                }
            }
        }
    }
}


- (void) mouseDown:(NSEvent *)_event
{
    if (!m_State.Active)
        if(id<PanelViewDelegate> del = self.delegate)
            if([del respondsToSelector:@selector(PanelViewRequestsActivation:)])
                [del PanelViewRequestsActivation:self];
    
    NSPoint event_location = [_event locationInWindow];
    NSPoint local_point = [self convertPoint:event_location fromView:nil];
    
    int cursor_pos = m_Presentation->GetItemIndexByPointInView(local_point);
    if (cursor_pos == -1) return;
    
    NSUInteger modifier_flags = _event.modifierFlags & NSDeviceIndependentModifierFlagsMask;
    if ((modifier_flags & NSShiftKeyMask) == NSShiftKeyMask)
    {
        // Select range of items with shift+click.
        // If clicked item is selected, then deselect the range instead.
        assert(cursor_pos < m_State.Data->SortedDirectoryEntries().size());
        int raw_pos = m_State.Data->SortedDirectoryEntries()[cursor_pos];
        assert(raw_pos < m_State.Data->DirectoryEntries().Count());
        const auto &click_entry = m_State.Data->DirectoryEntries()[raw_pos];
        
        bool deselect = click_entry.CFIsSelected();
        if (m_State.CursorPos == -1) m_State.CursorPos = 0; // ?????????
        [self SelectUnselectInRange:m_State.CursorPos last_included:cursor_pos select:!deselect];
    }
    
    m_Presentation->SetCursorPos(cursor_pos);
    
    if ((modifier_flags & NSCommandKeyMask) == NSCommandKeyMask)
    {
        // Select or deselect a single item with cmd+click.
        const auto *entry = self.item;
        assert(entry);
        bool select = !entry->CFIsSelected();
        [self SelectUnselectInRange:m_State.CursorPos last_included:m_State.CursorPos
                             select:select];
    }
    
    [self OnCursorPositionChanged];

    m_ReadyToDrag = true;
    m_LButtonDownPos = local_point;
}

- (NSMenu *)menuForEvent:(NSEvent *)_event
{
    [self mouseDown:_event]; // interpret right mouse downs or ctrl+left mouse downs as regular mouse down
    
    NSPoint event_location = [_event locationInWindow];
    NSPoint local_point = [self convertPoint:event_location fromView:nil];
    int cursor_pos = m_Presentation->GetItemIndexByPointInView(local_point);
    if (cursor_pos >= 0)
        if(id<PanelViewDelegate> del = self.delegate)
            if([del respondsToSelector:@selector(PanelViewRequestsContextMenu:)])
                return [del PanelViewRequestsContextMenu:self];
    return nil;
}

- (void) mouseDragged:(NSEvent *)_event
{
    if(m_ReadyToDrag)
    {
        NSPoint event_location = [_event locationInWindow];
        NSPoint local_point = [self convertPoint:event_location fromView:nil];
        

        double dist = hypot(local_point.x - m_LButtonDownPos.x,
                       local_point.y - m_LButtonDownPos.y);
        
        if(dist > 5)
        {
            if(id<PanelViewDelegate> del = self.delegate)
                if([del respondsToSelector:@selector(PanelViewWantsDragAndDrop:event:)])
                    [del PanelViewWantsDragAndDrop:self event:_event];
        
            m_ReadyToDrag = false;
        }
    }
}

- (void) mouseUp:(NSEvent *)_event
{
    m_ReadyToDrag = false;
    
    if ([_event clickCount] == 2)
    {
        // Handle double click.
        NSPoint event_location = [_event locationInWindow];
        NSPoint local_point = [self convertPoint:event_location fromView:nil];
        
        int cursor_pos = m_Presentation->GetItemIndexByPointInView(local_point);
        if (cursor_pos < 0 || cursor_pos != m_State.CursorPos)
            return;
        
        if(id<PanelViewDelegate> del = self.delegate)
            if([del respondsToSelector:@selector(PanelViewDoubleClick:atElement:)])
                [del PanelViewDoubleClick:self atElement:cursor_pos];
    }
}

- (void)scrollWheel:(NSEvent *)_event
{
    if (!m_State.Active) // will react only on active panels
        return;
    
    if(m_DisableCurrentMomentumScroll == true &&
       _event.phase == NSEventPhaseNone &&
       _event.momentumPhase != NSEventPhaseNone )
        return; // momentum scroll is temporary disabled due to folder change.
    m_DisableCurrentMomentumScroll = false;    
    if(_event.momentumPhase == NSEventPhaseBegan)
        m_IsCurrentlyMomentumScroll = true;
    else if(_event.momentumPhase == NSEventPhaseEnded)
        m_IsCurrentlyMomentumScroll = false;
    
    const double item_height = m_Presentation->GetSingleItemHeight();
    m_ScrollDY += _event.hasPreciseScrollingDeltas ? _event.scrollingDeltaY : _event.deltaY * item_height;
    int idx = int(_event.deltaX/2.0); // less sensitive than vertical scrolling
    int old_curpos = m_State.CursorPos, old_offset = m_State.ItemsDisplayOffset;
    
    if(fabs(m_ScrollDY) >= item_height) {
        const double sgn = m_ScrollDY / fabs(m_ScrollDY);
        for(;fabs(m_ScrollDY) >= item_height; m_ScrollDY -= item_height * sgn)
            m_Presentation->ScrollCursor(0, int(sgn));
    }
    else if(idx != 0)
        m_Presentation->ScrollCursor(idx, 0);

    if(old_curpos != m_State.CursorPos || old_offset != m_State.ItemsDisplayOffset)
        [self OnCursorPositionChanged];
}

- (const VFSListingItem*)item
{
    return m_State.Data->EntryAtSortPosition(m_State.CursorPos);
}

- (void) SelectUnselectInRange:(int)_start last_included:(int)_end select:(BOOL)_select
{
    
    // we never want to select a first (dotdot) entry
    assert(_start >= 0 && _start < m_State.Data->SortedDirectoryEntries().size());
    assert(_end >= 0 && _end < m_State.Data->SortedDirectoryEntries().size());
    if(_start > _end)
    {
        int t = _start;
        _start = _end;
        _end = t;
    }
    
    if(m_State.Data->DirectoryEntries()[m_State.Data->SortedDirectoryEntries()[_start]].IsDotDot())
        ++_start; // we don't want to select or unselect a dotdot entry - they are higher than that stuff
    
    for(int i = _start; i <= _end; ++i)
        m_State.Data->CustomFlagsSelectSorted(i, _select);
}

- (void) SelectUnselectInRange:(int)_start last_included:(int)_end
{
    assert(m_CursorSelectionType != CursorSelectionState::No);
    [self SelectUnselectInRange:_start last_included:_end
                         select:m_CursorSelectionType == CursorSelectionState::Selection];
}

- (void) setType:(PanelViewType)_type
{
    m_State.ViewType = _type;
    if (m_Presentation) m_Presentation->EnsureCursorIsVisible();
    [self setNeedsDisplay:true];
}

- (PanelViewType)type
{
    return m_State.ViewType;
}

- (void) SavePathState
{
    if(!m_State.Data)
        return;
    
    auto listing = m_State.Data->Listing();
    if(listing.get() == nullptr)
        return;
    
    auto item = self.item;
    if(item == nullptr)
        return;
    
    auto path = VFSPathStack(listing);
    auto &storage = m_States[hash<VFSPathStack>()(path)];
    
    storage.focused_item = item->Name();
    storage.dispay_offset = m_State.ItemsDisplayOffset;
}

- (void) LoadPathState
{
    if(!m_State.Data)
        return;
    
    auto listing = m_State.Data->Listing();
    if(listing.get() == nullptr)
        return;
    
    auto path = VFSPathStack(listing);
    auto it = m_States.find(hash<VFSPathStack>()(path));
    if(it == end(m_States))
        return;
    
    auto &storage = it->second;
    int cursor = m_State.Data->SortedIndexForName(storage.focused_item.c_str());
    if(cursor < 0)
        return;
    
    m_State.ItemsDisplayOffset = storage.dispay_offset;
    m_Presentation->SetCursorPos(cursor);
    [self OnCursorPositionChanged];
}

- (void) DirectoryChanged:(const char*)_focused_filename
{
    m_State.ItemsDisplayOffset = 0;
    m_State.CursorPos = -1;
    
    [self LoadPathState];
    
    int cur = m_State.Data->SortedIndexForName(_focused_filename);
    if(cur >= 0) {
        m_Presentation->SetCursorPos(cur);
        [self OnCursorPositionChanged];
    }
    
    if(m_State.CursorPos < 0 &&
       m_State.Data->SortedDirectoryEntries().size() > 0) {
        m_Presentation->SetCursorPos(0);
        [self OnCursorPositionChanged];        
    }
    
    if(m_IsCurrentlyMomentumScroll)
        m_DisableCurrentMomentumScroll = true;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    NSDragOperation result = NSDragOperationNone;
    if(id<PanelViewDelegate> del = self.delegate)
        if([del respondsToSelector:@selector(PanelViewDraggingEntered:sender:)])
            result = [del PanelViewDraggingEntered:self sender:sender];

    if(result != NSDragOperationNone && m_DraggingIntoMe == false) {
        m_DraggingIntoMe = true;
        [self setNeedsDisplay];
    }
    
    return result;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    NSDragOperation result = NSDragOperationNone;
    if(id<PanelViewDelegate> del = self.delegate)
        if([del respondsToSelector:@selector(PanelViewDraggingUpdated:sender:)])
            result = [del PanelViewDraggingUpdated:self sender:sender];
    
    if(result != NSDragOperationNone && m_DraggingIntoMe == false) {
        m_DraggingIntoMe = true;
        [self setNeedsDisplay];
    }
    
    return result;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
    m_DraggingIntoMe = false;
    [self setNeedsDisplay];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    m_DraggingIntoMe = false;
    [self setNeedsDisplay];
    // possibly add some checking stage here later
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    if(id<PanelViewDelegate> del = self.delegate)
        if([del respondsToSelector:@selector(PanelViewPerformDragOperation:sender:)])
            return [del PanelViewPerformDragOperation:self sender:sender];
    return NO;
}

@end
