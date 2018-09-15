#pragma once

#include <Cocoa/Cocoa.h>
#include <VFS/VFS.h>

namespace nc::vfsicon {
    
class IconRepository
{
public:
    virtual ~IconRepository() = default;
    
    using SlotKey = uint16_t;
    static inline const SlotKey InvalidKey = SlotKey{0};   
    
    virtual bool IsValidSlot( SlotKey _key ) const = 0;
    virtual NSImage *AvailableIconForSlot( SlotKey _key ) const = 0;
    virtual NSImage *AvailableIconForListingItem( const VFSListingItem &_item ) const = 0;
    
    virtual SlotKey Register( const VFSListingItem &_item ) = 0;
    virtual std::vector<SlotKey> AllSlots() const = 0;     
    virtual void Unregister( SlotKey _key ) = 0;
    
    virtual void ScheduleIconProduction(SlotKey _key, const VFSListingItem &_item) = 0;

    virtual void SetUpdateCallback( std::function<void(SlotKey, NSImage*)> _on_icon_updated ) = 0;
    virtual void SetPxSize( int _px_size ) = 0;    
};
    
}
