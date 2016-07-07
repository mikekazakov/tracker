//
//  PanelViewPresentation.h
//  Files
//
//  Created by Pavel Dogurevich on 06.05.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//

#pragma once

#include <Habanero/DispatchQueue.h>
#include "vfs/VFS.h"
#include "PanelViewTypes.h"
#include "ByteCountFormatter.h"
#include "Config.h"

@class PanelView;

class PanelViewPresentation
{
public:
    PanelViewPresentation(PanelView *_parent_view, PanelViewState *_view_state);
    PanelViewPresentation(const PanelViewPresentation&) = delete;
    void operator=(PanelViewPresentation&) = delete;
    virtual ~PanelViewPresentation();
    
    void SetCursorPos(int _pos);
    void ScrollCursor(int _idx, int _idy);
    void MoveCursorToNextItem();
    void MoveCursorToPrevItem();
    void MoveCursorToNextPage();
    void MoveCursorToPrevPage();
    void MoveCursorToNextColumn();
    void MoveCursorToPrevColumn();
    void MoveCursorToFirstItem();
    void MoveCursorToLastItem();
    
    /**
     * Will adjust scrolling position if necessary.
     */
    void EnsureCursorIsVisible();
    
    virtual void Draw(NSRect _dirty_rect) = 0;
    virtual void OnFrameChanged(NSRect _frame) = 0;
    virtual void OnDirectoryChanged();
    virtual void OnPanelTitleChanged();
    
    virtual NSRect GetItemColumnsRect() = 0;
    
    /**
     * Calculates cursor postion which corresponds to the point in view.
     * Returns -1 if point is out of the files' view area or if it doesnt belowing to item due to hit-test options.
     */
    virtual int GetItemIndexByPointInView(CGPoint _point, PanelViewHitTest::Options _opt) = 0;

    virtual NSRect ItemRect(int _item_index) const = 0;
    virtual NSRect ItemFilenameRect(int _item_index) const = 0;
    
    virtual void SetupFieldRenaming(NSScrollView *_editor, int _item_index) = 0;

    
    /**
     * Return a height of a single file item. So this height*number_of_items_vertically should be something like height of a view minus decors.
     */
    virtual double GetSingleItemHeight() = 0;
    
    bool IsItemVisible(int _item_no) const;
    
    inline ByteCountFormatter::Type FileSizeFormat() const { return m_FileSizeFormat; }
    inline ByteCountFormatter::Type SelectionSizeFormat() const { return m_SelectionSizeFormat; }
    
    inline PanelViewFilenameTrimming Trimming() const { return m_Trimming; };
    virtual void SetTrimming(PanelViewFilenameTrimming _mode);
    
protected:
    virtual int GetMaxItemsPerColumn() const = 0;
    int GetNumberOfItemColumns() const;
    int GetMaxVisibleItems() const;
    void SetViewNeedsDisplay();
    
    inline const VFSStatFS &StatFS() const { return m_StatFS; }
    void UpdateStatFS();
    
    PanelViewState * const          m_State;
    
    inline PanelView *View() { return m_View; }
private:
    void LoadSizeFormats();

    VFSStatFS                      m_StatFS;
    nanoseconds                    m_StatFSLastUpdate = 0ns;
    SerialQueue                    m_StatFSQueue = SerialQueueT::Make();
    VFSHost                       *m_StatFSLastHost = nullptr;
    string                         m_StatFSLastPath;
    
    PanelViewFilenameTrimming      m_Trimming = PanelViewFilenameTrimming::Middle;
    ByteCountFormatter::Type       m_FileSizeFormat = ByteCountFormatter::Fixed6;
    ByteCountFormatter::Type       m_SelectionSizeFormat = ByteCountFormatter::SpaceSeparated;
    __unsafe_unretained PanelView * const m_View = nil;
    vector<GenericConfig::ObservationTicket> m_ConfigObservations;
};
