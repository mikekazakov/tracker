#include <VFSIcon/IconRepositoryImpl.h>

namespace nc::vfsicon {

IconRepositoryImpl::IconRepositoryImpl(const std::shared_ptr<IconBuilder> &_icon_builder,
                                       std::unique_ptr<LimitedConcurrentQueue> _production_queue,
                                       const std::shared_ptr<Executor> &_client_executor,
                                       int _capacity):
    m_IconBuilder(_icon_builder),
    m_ProductionQueue(std::move(_production_queue)),
    m_ClientExecutor(_client_executor),
    m_Capacity(_capacity)
{
}
    
IconRepositoryImpl::~IconRepositoryImpl()
{
    for( auto &slot: m_Slots ) {
        if( slot.state == SlotState::Production ) {
            if( slot.production != nullptr )
                slot.production->must_stop = true;
        }
    }
    m_ProductionQueue.reset();
}

bool IconRepositoryImpl::IsValidSlot( SlotKey _key ) const
{
    return _key != InvalidKey &&
           ToIndex(_key) < m_Slots.size() &&
           IsSlotUsed(m_Slots[ToIndex(_key)]);
}
    
NSImage *IconRepositoryImpl::AvailableIconForSlot( SlotKey _key ) const
{
    if( !IsValidSlot(_key) )
        return nil;
    
    const auto slot_index = ToIndex(_key); 
    auto &slot = m_Slots[slot_index];
    
    return BestImageFromSlot(slot);
}
    
NSImage *IconRepositoryImpl::AvailableIconForListingItem( const VFSListingItem &_item ) const
{
    return nil;
}
    
IconRepositoryImpl::SlotKey IconRepositoryImpl::Register( const VFSListingItem &_item )
{
    if( NumberOfUsedSlots() == m_Capacity )
        return InvalidKey;
    
    const auto new_slot_ind = AllocateSlot();
    if( new_slot_ind < 0 )
        return InvalidKey;

    auto &slot = m_Slots[new_slot_ind]; 

    auto lr = m_IconBuilder->LookupExistingIcon(_item, m_IconPxSize);
    
    slot.state = SlotState::Initial;
    slot.thumbnail = lr.thumbnail;
    slot.filetype = lr.filetype;
    slot.generic = lr.generic;
    
    return FromIndex(new_slot_ind);
}
    
std::vector<IconRepositoryImpl::SlotKey> IconRepositoryImpl::AllSlots() const
{
    std::vector<SlotKey> slot_keys;    
    for( int i = 0, e = (int)m_Slots.size(); i != e; ++i )
        if( IsSlotUsed(m_Slots[i]) )
            slot_keys.emplace_back( FromIndex(i) );    
    return slot_keys;        
}
    
void IconRepositoryImpl::Unregister( SlotKey _key )
{    
    if( IsValidSlot(_key) == false )
        return;
    const auto index = ToIndex(_key);
    auto &slot = m_Slots[index];
    if( slot.production )
        slot.production->must_stop = true;
    m_FreeSlotsIndices.push(index);
    m_Slots[index] = Slot{};
}
    
void IconRepositoryImpl::ScheduleIconProduction(SlotKey _key, const VFSListingItem &_item)
{     
    if( IsValidSlot(_key) == false )
        return;
    
    auto slot_index = ToIndex(_key);
    auto &slot = m_Slots[slot_index];
  
    if( slot.production != nullptr )
        return; // there is an already ongoing production
        
    if( slot.state == SlotState::Production &&
        HasFileChanged(slot, _item) == false )
        return; // nothing to do
    
    auto context = std::make_shared<WorkerContext>();
    context->item = _item;
    
    slot.production = context;
    slot.file_size = _item.Size();
    slot.file_mtime = _item.MTime();
    slot.file_mode = _item.UnixMode();
    slot.state = SlotState::Production;
    
    auto work_block = [this, slot_index, context] {
        ProduceRealIcon(*context);
        if( context->must_stop == true )
            return;
        auto commit_block = [this, slot_index, context] {
            CommitProductionResult(slot_index, *context);
        };
        m_ClientExecutor->Execute(std::move(commit_block));
    };
    m_ProductionQueue->Execute(std::move(work_block));
}

void IconRepositoryImpl::ProduceRealIcon(WorkerContext &_ctx)
{
    if( _ctx.must_stop == true )
        return;
    
    auto build_result = m_IconBuilder->BuildRealIcon(_ctx.item, m_IconPxSize);
    _ctx.result_filetype = build_result.filetype;
    _ctx.result_thumbnail = build_result.thumbnail;
}
    
void IconRepositoryImpl::CommitProductionResult(int _slot_index, WorkerContext &_ctx)
{
    if( _ctx.must_stop == true )
        return;

    auto &slot = m_Slots[_slot_index];     
    assert( slot.production.get() == &_ctx );
    
    bool updated = false;
    if( _ctx.result_thumbnail != nil && _ctx.result_thumbnail != slot.thumbnail ) {
        slot.thumbnail = _ctx.result_thumbnail;
        updated = true;
    }
    if( _ctx.result_filetype != nil && _ctx.result_filetype != slot.filetype ) {
        slot.filetype = _ctx.result_filetype;
        updated = true;
    }
    
    slot.production.reset();
    
    if( updated == true ) {
        auto callback = m_IconUpdatedCallback;
        if( callback && *callback )
            (*callback)(FromIndex(_slot_index), BestImageFromSlot(slot));
    }
}
    
void IconRepositoryImpl::SetUpdateCallback(std::function<void(SlotKey, NSImage*)> _on_icon_updated)
{
    using F = std::function<void(SlotKey, NSImage*)>; 
    m_IconUpdatedCallback = std::make_shared<F>(std::move(_on_icon_updated));
}

void IconRepositoryImpl::SetPxSize( int _px_size )
{
    m_IconPxSize = _px_size;
}

int IconRepositoryImpl::NumberOfUsedSlots() const
{
    assert( m_FreeSlotsIndices.size() <= m_Slots.size() );
    return (int)m_Slots.size() - (int)m_FreeSlotsIndices.size();
}

int IconRepositoryImpl::AllocateSlot()
{
    if( m_FreeSlotsIndices.empty() == false ) {
        const auto free_slot_index = m_FreeSlotsIndices.top();
        m_FreeSlotsIndices.pop();
        return free_slot_index;
    }
    else if( m_Slots.size() < m_Capacity ) {
        m_Slots.emplace_back();
        return (int)m_Slots.size() - 1;
    }
    else 
        return -1;
}

NSImage* IconRepositoryImpl::BestImageFromSlot(const Slot& _slot)
{
    if( _slot.thumbnail )
        return _slot.thumbnail;
    if( _slot.filetype )
        return _slot.filetype;
    return _slot.generic;
}
 
bool IconRepositoryImpl::IsSlotUsed(const Slot& _slot)
{
    return _slot.state != SlotState::Empty;
}
    
IconRepository::SlotKey IconRepositoryImpl::FromIndex(int _index)
{
    assert( _index < std::numeric_limits<SlotKey>::max() );
    return SlotKey(_index+1);
}
    
int IconRepositoryImpl::ToIndex(SlotKey _key)
{
    return _key - 1;
}
 
bool IconRepositoryImpl::HasFileChanged(const Slot& _slot, const VFSListingItem &_item)
{
    return _slot.file_size != _item.Size() ||
           _slot.file_mtime != _item.MTime() ||
           _slot.file_mode != _item.UnixMode();
}
    
}
