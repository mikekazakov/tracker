#include "CopyToPasteboard.h"
#include "../PanelController.h"
#include "../Helpers/Pasteboard.h"

// TODO: move localizable string to a new file. FilePanelsContextMenu.string was a bad idea!

namespace panel::actions {

bool CopyToPasteboard::Predicate( PanelController *_target ) const
{
    const auto &stats = _target.data.Stats();
    if( stats.selected_entries_amount > 0 )
        return true;
    return _target.view.item;
}

bool CopyToPasteboard::ValidateMenuItem( PanelController *_target, NSMenuItem *_item ) const
{
    const auto &stats = _target.data.Stats();
    if( stats.selected_entries_amount > 0 ) {
        _item.title = [NSString stringWithFormat:
            NSLocalizedStringFromTable(@"Copy %lu Items",
                                       @"FilePanelsContextMenu",
                                       "Copy many items"),
                       stats.selected_entries_amount];
    }
    else {
        if( auto item = _target.view.item ) {
            _item.title = [NSString stringWithFormat:
                NSLocalizedStringFromTable(@"Copy \u201c%@\u201d",
                                           @"FilePanelsContextMenu",
                                           "Copy one item"),
                          item.NSDisplayName()];
        }
        else
            _item.title = @"";
    }
    return Predicate(_target);
}

void CopyToPasteboard::PerformWithItems( const vector<VFSListingItem> &_items ) const
{
    if( !panel::PasteboardSupport::WriteFilesnamesPBoard(_items, NSPasteboard.generalPasteboard) )
        NSBeep();
}

void CopyToPasteboard::Perform( PanelController *_target, id _sender ) const
{
    PerformWithItems( _target.selectedEntriesOrFocusedEntryWithDotDot );
}

context::CopyToPasteboard::CopyToPasteboard(const vector<VFSListingItem> &_items):
    m_Items(_items)
{
    if( _items.empty() )
        throw invalid_argument("CopyToPasteboard was made with empty items set");
}

bool context::CopyToPasteboard::Predicate( PanelController *_target ) const
{
// currently there's a difference with previous predicate form context menu:
//        if( m_CommonHost && m_CommonHost->IsNativeFS() ) {
// such thing works only on native file systems
    return !m_Items.empty();
}

bool context::CopyToPasteboard::ValidateMenuItem(PanelController *_target,
                                                 NSMenuItem *_item ) const
{
    if(m_Items.size() > 1)
        _item.title = [NSString stringWithFormat:
            NSLocalizedStringFromTable(@"Copy %lu Items",
                                       @"FilePanelsContextMenu",
                                       "Copy many items"),
                       m_Items.size()];
    else
        _item.title = [NSString stringWithFormat:
            NSLocalizedStringFromTable(@"Copy \u201c%@\u201d",
                                       @"FilePanelsContextMenu",
                                       "Copy one item"),
                       m_Items.front().NSDisplayName()];
    return Predicate(_target);
}

void context::CopyToPasteboard::Perform( PanelController *_target, id _sender ) const
{
    PerformWithItems( m_Items );
}

}
