// Copyright (C) 2013-2018 Michael Kazakov. Subject to GNU General Public License version 3.
#include "PanelController.h"
#include <Habanero/algo.h>
#include <Utility/NSView+Sugar.h>
#include <Utility/NSMenu+Hierarchical.h>
#include "../MainWindowController.h"
#include "PanelPreview.h"
#include "MainWindowFilePanelState.h"
#include "Views/BriefSystemOverview.h"
#include <NimbleCommander/Core/Alert.h>
#include <NimbleCommander/Core/ActionsShortcutsManager.h>
#include <NimbleCommander/Core/SandboxManager.h>
#include <NimbleCommander/Bootstrap/Config.h>
#include "PanelDataPersistency.h"
#include <NimbleCommander/Bootstrap/ActivationManager.h>
#include "PanelViewLayoutSupport.h"
#include "PanelDataItemVolatileData.h"
#include "PanelDataOptionsPersistence.h"
#include <Habanero/CommonPaths.h>
#include <VFS/Native.h>
#include "PanelHistory.h"
#include <Habanero/SerialQueue.h>
#include "PanelData.h"
#include "PanelView.h"
#include "PanelDataExternalEntryKey.h"
#include "PanelDataPersistency.h"
#include <NimbleCommander/Core/VFSInstanceManager.h>
#include "ContextMenu.h"
#include "Actions/OpenFile.h"
#include "Actions/GoToFolder.h"
#include "Actions/Enter.h"
#include <Operations/Copying.h>
#include "CursorBackup.h"
#include "QuickSearch.h"
#include "PanelViewHeader.h"

using namespace nc;
using namespace nc::core;
using namespace nc::panel;

static const auto g_ConfigShowDotDotEntry
    = "filePanel.general.showDotDotEntry";
static const auto g_ConfigIgnoreDirectoriesOnMaskSelection
    = "filePanel.general.ignoreDirectoriesOnSelectionWithMask";
static const auto g_ConfigShowLocalizedFilenames
    = "filePanel.general.showLocalizedFilenames";

namespace nc::panel {

ActivityTicket::ActivityTicket():
    panel(nil),
    ticket(0)
{
}

ActivityTicket::ActivityTicket(PanelController *_panel, uint64_t _ticket):
    panel(_panel),
    ticket(_ticket)
{
}

ActivityTicket::ActivityTicket( ActivityTicket&& _rhs):
    panel(_rhs.panel),
    ticket(_rhs.ticket)
{
    _rhs.panel = nil;
    _rhs.ticket = 0;
}

ActivityTicket::~ActivityTicket()
{
    Reset();
}

void ActivityTicket::operator=(ActivityTicket&&_rhs)
{
    Reset();
    panel = _rhs.panel;
    ticket = _rhs.ticket;
    _rhs.panel = nil;
    _rhs.ticket = 0;
}

void ActivityTicket::Reset()
{
    if( ticket )
        if( PanelController *pc = panel )
            [pc finishExtActivityWithTicket:ticket];
    panel = nil;
    ticket = 0;
}
    
}

#define MAKE_AUTO_UPDATING_BOOL_CONFIG_VALUE( _name, _path )\
static bool _name()\
{\
    static const auto fetch = []{\
        return GlobalConfig().GetBool((_path));\
    };\
    static bool value = []{\
        GlobalConfig().ObserveUnticketed((_path), []{\
            value = fetch();\
        });\
        return fetch();\
    }();\
    return value;\
}

MAKE_AUTO_UPDATING_BOOL_CONFIG_VALUE(ConfigShowDotDotEntry, g_ConfigShowDotDotEntry);
MAKE_AUTO_UPDATING_BOOL_CONFIG_VALUE(ConfigShowLocalizedFilenames, g_ConfigShowLocalizedFilenames);

static void HeatUpConfigValues()
{
    ConfigShowDotDotEntry();
    ConfigShowLocalizedFilenames();
}

@implementation PanelController
{
    // Main controller's possessions
    data::Model                  m_Data;   // owns
    PanelView                   *m_View;  // create and owns
    
    // VFS changes observation
    vfs::HostDirObservationTicket       m_UpdatesObservationTicket;
    
    // VFS listing fetch flags
    unsigned long                       m_VFSFetchingFlags;
        
    // background operations' queues
    SerialQueue m_DirectorySizeCountingQ;
    SerialQueue m_DirectoryLoadingQ;
    SerialQueue m_DirectoryReLoadingQ;
    
    
    NCPanelQuickSearch *m_QuickSearch;
    
    // navigation support
    History m_History;
    
    // spinning indicator support
    bool                m_IsAnythingWorksInBackground;
    
    // Tickets to show some external activities on this panel
    uint64_t            m_NextActivityTicket;
    vector<uint64_t>    m_ActivitiesTickets;
    spinlock            m_ActivitiesTicketsLock;
    
    // delayed entry selection support
    struct
    {
        /**
         * Requested item name to select. Empty filename means that request is invalid.
         */
        string      filename;
        
        /**
         * Time after which request is meaningless and should be removed
         */
        nanoseconds    request_end;

        /**
         * Called when changed a cursor position
         */
        function<void()> done;
    } m_DelayedSelection;
    
    __weak MainWindowFilePanelState* m_FilePanelState;
    
    boost::container::static_vector<
        GenericConfig::ObservationTicket,2> m_ConfigObservers;
    nc::core::VFSInstanceManager       *m_VFSInstanceManager;
    shared_ptr<PanelViewLayoutsStorage> m_Layouts;
    int                                 m_ViewLayoutIndex;
    shared_ptr<const PanelViewLayout>   m_AssignedViewLayout;
    PanelViewLayoutsStorage::ObservationTicket m_LayoutsObservation;
}

@synthesize view = m_View;
@synthesize data = m_Data;
@synthesize history = m_History;
@synthesize layoutIndex = m_ViewLayoutIndex;
@synthesize vfsFetchingFlags = m_VFSFetchingFlags;

- (instancetype)initWithView:(PanelView*)_panel_view
                     layouts:(shared_ptr<nc::panel::PanelViewLayoutsStorage>)_layouts
          vfsInstanceManager:(nc::core::VFSInstanceManager&)_vfs_mgr
{
    assert( _layouts );
    
    static once_flag once;
    call_once(once, HeatUpConfigValues);

    self = [super init];
    if(self) {
        m_Layouts = move(_layouts);
        m_VFSInstanceManager = &_vfs_mgr;
        m_History.SetVFSInstanceManager(_vfs_mgr);
        m_VFSFetchingFlags = 0;
        m_NextActivityTicket = 1;
        m_IsAnythingWorksInBackground = false;
        m_ViewLayoutIndex = m_Layouts->DefaultLayoutIndex();
        m_AssignedViewLayout = m_Layouts->DefaultLayout();
        
        __weak PanelController* weakself = self;
        auto on_change = [=]{
            dispatch_to_main_queue([=]{
                [(PanelController*)weakself updateSpinningIndicator];
            });
        };
        m_DirectorySizeCountingQ.SetOnChange(on_change);
        m_DirectoryReLoadingQ.SetOnChange(on_change);
        m_DirectoryLoadingQ.SetOnChange(on_change);
        
        m_View = _panel_view;
        m_View.delegate = self;
        m_View.data = &m_Data;
        [m_View setPresentationLayout:*m_AssignedViewLayout];
        
        // wire up config changing notifications
        auto add_co = [&](const char *_path, SEL _sel) { m_ConfigObservers.
            emplace_back( GlobalConfig().Observe(_path, objc_callback(self, _sel)) );
        };
        add_co(g_ConfigShowDotDotEntry,         @selector(configVFSFetchFlagsChanged) );
        add_co(g_ConfigShowLocalizedFilenames,  @selector(configVFSFetchFlagsChanged) );
        
        m_LayoutsObservation = m_Layouts->
            ObserveChanges( objc_callback(self, @selector(panelLayoutsChanged)) );
        
        // loading config via simulating it's change
        [self configVFSFetchFlagsChanged];
        
        m_QuickSearch = [[NCPanelQuickSearch alloc] initWithView:m_View
                                                            data:m_Data
                                                          config:GlobalConfig()];

        [m_View addKeystrokeSink:self withBasePriority:view::BiddingPriority::Default];
        [m_View addKeystrokeSink:m_QuickSearch withBasePriority:view::BiddingPriority::High];
    }

    return self;
}

- (void) dealloc
{
    // we need to manually set data to nullptr, since PanelView can be destroyed a bit later due
    // to other strong pointers. in that case view will contain a dangling pointer, which can lead
    // to a crash.
    m_View.data = nullptr;
}

- (void)configVFSFetchFlagsChanged
{
    if( ConfigShowDotDotEntry() == false )
        m_VFSFetchingFlags |= VFSFlags::F_NoDotDot;
    else
        m_VFSFetchingFlags &= ~VFSFlags::F_NoDotDot;
    
    if( ConfigShowLocalizedFilenames() == true )
        m_VFSFetchingFlags |= VFSFlags::F_LoadDisplayNames;
    else
        m_VFSFetchingFlags &= ~VFSFlags::F_LoadDisplayNames;
    
    [self refreshPanel];
}

- (void) setState:(MainWindowFilePanelState *)state
{
    m_FilePanelState = state;
}

- (MainWindowFilePanelState*)state
{
    return m_FilePanelState;
}

- (NSWindow*) window
{
    return self.state.window;
}

- (NCMainWindowController *)mainWindowController
{
    return (NCMainWindowController*)self.window.delegate;
}

- (bool) isUniform
{
    return m_Data.Listing().IsUniform();
}

- (bool) receivesUpdateNotifications
{
    return (bool)m_UpdatesObservationTicket;
}

- (bool) ignoreDirectoriesOnSelectionByMask
{
    return GlobalConfig().GetBool(g_ConfigIgnoreDirectoriesOnMaskSelection);
}

- (void) copyOptionsFromController:(PanelController*)_pc
{
    if( !_pc )
        return;
    
    data::OptionsImporter{m_Data}.Import( data::OptionsExporter{_pc.data}.Export() );
    [self.view dataUpdated];
    [self.view dataSortingHasChanged];
    self.layoutIndex = _pc.layoutIndex;
}

- (bool) isActive
{
    return m_View.active;
}

- (void) changeSortingModeTo:(data::SortMode)_mode
{
    if( _mode != m_Data.SortMode() ) {
        CursorBackup pers(m_View, m_Data);
        
        m_Data.SetSortMode(_mode);
        
        pers.Restore();
        
        [m_View dataSortingHasChanged];
        [m_View dataUpdated];
        [self markRestorableStateAsInvalid];
    }
}

- (void) changeHardFilteringTo:(data::HardFilter)_filter
{
    if( _filter != m_Data.HardFiltering() ) {
        CursorBackup pers(m_View, m_Data);
        
        m_Data.SetHardFiltering(_filter);
        
        pers.Restore();
        [m_View dataUpdated];
        [self markRestorableStateAsInvalid];
    }
}

- (void) ReLoadRefreshedListing:(const VFSListingPtr &)_ptr
{
    assert(dispatch_is_main_queue());
    
    CursorBackup pers(m_View, m_Data);
    
    m_Data.ReLoad(_ptr);
    [m_View dataUpdated];
    
    if(![self checkAgainstRequestedFocusing])
        pers.Restore();
    
    [self onCursorChanged];
//    [self QuickSearchUpdate]; // ??????????
    [m_View setNeedsDisplay];
}

- (void) refreshPanelDiscardingCaches:(bool)_force
{
    if(m_View == nil)
        return; // guard agains calls from init process
    if( m_Data.Listing().shared_from_this() == VFSListing::EmptyListing() )
        return; // guard agains calls from init process
    
    if( !m_DirectoryLoadingQ.Empty() )
        return; //reducing overhead

    // later: maybe check PanelType somehow
    
    if( self.isUniform ) {
        const auto fetch_flags = m_VFSFetchingFlags | (_force ? VFSFlags::F_ForceRefresh : 0);
        const auto dirpath = m_Data.DirectoryPathWithTrailingSlash();
        const auto vfs = self.vfs;
        
        m_DirectoryReLoadingQ.Run([=]{
            VFSListingPtr listing;
            int ret = vfs->FetchDirectoryListing(dirpath.c_str(),
                                                 listing,
                                                 fetch_flags,
                                                 [&]{ return m_DirectoryReLoadingQ.IsStopped(); }
                                                 );
            if(ret >= 0)
                dispatch_to_main_queue( [=]{
                    [self ReLoadRefreshedListing:listing];
                });
            else
                dispatch_to_main_queue( [=]{
                    [self RecoverFromInvalidDirectory];
                });
        });
    }
    else {
        m_DirectoryReLoadingQ.Run([=]{
            auto listing = VFSListing::ProduceUpdatedTemporaryPanelListing(
                m_Data.Listing(),
                [&]{ return m_DirectoryReLoadingQ.IsStopped(); }
                );
            if( listing )
                dispatch_to_main_queue( [=]{
                    [self ReLoadRefreshedListing:listing];
                });
        });
    }
}

- (void) refreshPanel
{
   [self refreshPanelDiscardingCaches:false];
}

- (void) forceRefreshPanel
{
    [self refreshPanelDiscardingCaches:true];
}

- (int)bidForHandlingKeyDown:(NSEvent *)_event forPanelView:(PanelView*)_panel_view
{
    // this is doubtful, actually. need to figure out something clearer:
    [self clearFocusingRequest]; // on any key press we clear entry selection request, if any
    
    const auto keycode = _event.keyCode;
    if( keycode == 53 ) { // Esc button
        if( m_IsAnythingWorksInBackground )
            return panel::view::BiddingPriority::Default;
        if( self.quickLook || self.briefSystemOverview )
            return panel::view::BiddingPriority::Default;;
    }
    
    return panel::view::BiddingPriority::Skip;
}

- (void)handleKeyDown:(NSEvent *)_event forPanelView:(PanelView*)_panel_view
{
    const auto keycode = _event.keyCode;
    if( keycode == 53 ) { // Esc button
        if( m_IsAnythingWorksInBackground ) {
            [self CancelBackgroundOperations];
            return;
        }
        if( self.quickLook || self.briefSystemOverview ) {
            [self.state closeAttachedUI:self];
            return;
        }
    }
}

- (void) calculateSizesOfItems:(const vector<VFSListingItem>&) _items
{
    if( _items.empty() )
        return;
    m_DirectorySizeCountingQ.Run([=]{
        for(auto &i:_items) {
            if( !i.IsDir() )
                continue;
            if( m_DirectorySizeCountingQ.IsStopped() )
                return;
            
            auto result = i.Host()->CalculateDirectorySize(
                !i.IsDotDot() ? i.Path().c_str() : i.Directory().c_str(),
                [=]{ return m_DirectorySizeCountingQ.IsStopped(); }
                );
            if( result < 0 )
                return;
                
            dispatch_to_main_queue([=]{
                CursorBackup pers(m_View, m_Data);
                // may cause re-sorting if current sorting is by size
                const auto changed = m_Data.SetCalculatedSizeForDirectory(i.FilenameC(),
                                                                          i.Directory().c_str(),
                                                                          result);
                if( changed ) {
                    [m_View dataUpdated];
                    [m_View volatileDataChanged];
                    pers.Restore();
                }
            });
        }
    });
}

- (void) CancelBackgroundOperations
{
    m_DirectorySizeCountingQ.Stop();
    m_DirectoryLoadingQ.Stop();
    m_DirectoryReLoadingQ.Stop();
}

- (void) updateSpinningIndicator
{
    dispatch_assert_main_queue();
    
    size_t ext_activities_no = call_locked(m_ActivitiesTicketsLock,
                                           [&]{ return m_ActivitiesTickets.size(); });
    bool is_anything_working = !m_DirectorySizeCountingQ.Empty() ||
                               !m_DirectoryLoadingQ.Empty() ||
                               !m_DirectoryReLoadingQ.Empty() ||
                                ext_activities_no > 0;
    
    if( is_anything_working == m_IsAnythingWorksInBackground )
        return; // nothing to update;
        
    if( is_anything_working ) {
        // there should be 100ms of workload before the user gets the spinning indicator
        dispatch_to_main_queue_after(100ms, [=]{
                            // need to check if task was already done
                           if( m_IsAnythingWorksInBackground )
                               [m_View.busyIndicator startAnimation:nil];
                       });
    }
    else
        [m_View.busyIndicator stopAnimation:nil];
    
    m_IsAnythingWorksInBackground = is_anything_working;
}

- (void) selectEntriesWithFilenames:(const vector<string>&)_filenames
{
    for( auto &i: _filenames )
        m_Data.CustomFlagsSelectSorted( m_Data.SortedIndexForName(i.c_str()), true );
    [m_View volatileDataChanged];
}

- (void) setEntriesSelection:(const vector<bool>&)_selection
{
    if( m_Data.CustomFlagsSelectSorted(_selection) )
        [m_View volatileDataChanged];
}

- (void) onPathChanged
{
    // update directory changes notification ticket
    __weak PanelController *weakself = self;
    m_UpdatesObservationTicket.reset();    
    if( self.isUniform ) {
        auto dir_change_callback = [=]{
            dispatch_to_main_queue([=]{
                [(PanelController *)weakself refreshPanel];
            });
        };
        m_UpdatesObservationTicket = self.vfs->DirChangeObserve(self.currentDirectoryPath.c_str(),
                                                                move(dir_change_callback));
    }
    
    [self clearFocusingRequest];
    [m_QuickSearch setSearchCriteria:nil];
    
    [self.state PanelPathChanged:self];
    [self onCursorChanged];
    [self updateAttachedBriefSystemOverview];
    m_History.Put(m_Data.Listing());
    
    [self markRestorableStateAsInvalid];
}

- (void) markRestorableStateAsInvalid
{
    if( auto wc = objc_cast<NCMainWindowController>(self.state.window.delegate) )
        [wc invalidateRestorableState];
}

- (void) onCursorChanged
{
    [self updateAttachedQuickLook];
}

- (void)updateAttachedQuickLook
{
    if( auto ql = self.quickLook )
        if( auto i = self.view.item )
            [ql previewVFSItem:VFSPath{i.Host(), i.Path()}
                      forPanel:self];
}

- (void)updateAttachedBriefSystemOverview
{
    if( const auto bso = self.briefSystemOverview ) {
        if( auto i = self.view.item )
            [bso UpdateVFSTarget:i.Directory() host:i.Host()];
        else if( self.isUniform )
            [bso UpdateVFSTarget:self.currentDirectoryPath host:self.vfs];
    }
}

- (void) PanelViewCursorChanged:(PanelView*)_view
{
    [self onCursorChanged];
}

- (NSMenu*) panelView:(PanelView*)_view requestsContextMenuForItemNo:(int)_sort_pos
{
    dispatch_assert_main_queue();
    
    const auto clicked_item = m_Data.EntryAtSortPosition(_sort_pos);
    if( !clicked_item || clicked_item.IsDotDot() )
        return nil;
    
    const auto clicked_item_vd = m_Data.VolatileDataAtSortPosition(_sort_pos);
    
    vector<VFSListingItem> vfs_items;
    if( clicked_item_vd.is_selected() == false)
        vfs_items.emplace_back(clicked_item); // only clicked item
    else
        vfs_items = m_Data.SelectedEntries(); // all selected items
    
    for( auto &i: vfs_items )
        m_Data.VolatileDataAtRawPosition(i.Index()).toggle_highlight(true);
    [_view volatileDataChanged];
    
    const auto menu = [[NCPanelContextMenu alloc] initWithItems:move(vfs_items)
                                                        ofPanel:self];
    return menu;
}

- (void) contextMenuDidClose:(NSMenu*)_menu
{
    m_Data.CustomFlagsClearHighlights();
    [m_View volatileDataChanged];
}


static void ShowAlertAboutInvalidFilename( const string &_filename )
{
    Alert *a = [[Alert alloc] init];
    auto fn = [NSString stringWithUTF8StdString:_filename];
    if( fn.length > 256 )
        fn = [[fn substringToIndex:256] stringByAppendingString:@"..."];
    
    const auto msg = NSLocalizedString(@"The name “%@” can’t be used.",
                                       "Message text when user is entering an invalid filename");
    a.messageText = [NSString stringWithFormat:msg, fn];
    const auto info = NSLocalizedString(
        @"Try using a name with fewer characters or without punctuation marks.",
        "Informative text when user is entering an invalid filename");
    a.informativeText = info;
    a.alertStyle = NSCriticalAlertStyle;
    [a runModal];
}

- (void) requestQuickRenamingOfItem:(VFSListingItem)_item to:(const string&)_filename
{
    if( _filename == "." ||
        _filename == ".." ||
        !_item ||
        _item.IsDotDot() ||
        !_item.Host()->IsWritable() ||
        _filename == _item.Filename())
        return;
    
    const auto target_fn = _filename;
 
    // checking for invalid symbols
    if( !_item.Host()->ValidateFilename(target_fn.c_str()) ) {
        ShowAlertAboutInvalidFilename(target_fn);
        return;
    }
    
    nc::ops::CopyingOptions opts;
    opts.docopy = false;

    const auto op = make_shared<nc::ops::Copying>(vector<VFSListingItem>{_item},
                                                  _item.Directory() + target_fn,
                                                  _item.Host(),
                                                  opts);

    if( self.isUniform && m_View.item && m_View.item.Filename() == _item.Filename() ) {
        string curr_path = self.currentDirectoryPath;
        auto curr_vfs = self.vfs;
        op->ObserveUnticketed(nc::ops::Operation::NotifyAboutCompletion, [=]{
            if(self.currentDirectoryPath == curr_path && self.vfs == curr_vfs)
                dispatch_to_main_queue( [=]{
                    DelayedFocusing req;
                    req.filename = target_fn;
                    [self scheduleDelayedFocusing:req];
                    [self refreshPanel];
                } );
        });
    }
    
    [self.mainWindowController enqueueOperation:op];
}

- (void) panelViewDidBecomeFirstResponder
{
    [self.state activePanelChangedTo:self];
    [self updateAttachedQuickLook];
    [self updateAttachedBriefSystemOverview];
}

+ (bool) ensureCanGoToNativeFolderSync:(const string&)_path
{
    return SandboxManager::EnsurePathAccess(_path);
}

- (bool)ensureCanGoToNativeFolderSync:(const string&)_path
{
    return [PanelController ensureCanGoToNativeFolderSync:_path];
}

- (void)changeDataOptions:(const function<void(nc::panel::data::Model& _data)>&)_workload
{
    assert(dispatch_is_main_queue());    
    assert( _workload );
    
    CursorBackup pers(m_View, m_Data);
    
    _workload(m_Data);
    
    [m_View dataUpdated];
    [m_View dataSortingHasChanged];
    pers.Restore();
}

- (ActivityTicket) registerExtActivity
{
    auto ticket = call_locked(m_ActivitiesTicketsLock, [&]{
        m_ActivitiesTickets.emplace_back( m_NextActivityTicket );
        return ActivityTicket(self, m_NextActivityTicket++);
    });
    dispatch_to_main_queue([=]{
        [self updateSpinningIndicator];
    });
    return ticket;
}

- (void) finishExtActivityWithTicket:(uint64_t)_ticket
{
    LOCK_GUARD(m_ActivitiesTicketsLock) {
        auto i = find(begin(m_ActivitiesTickets), end(m_ActivitiesTickets), _ticket);
        if( i == end(m_ActivitiesTickets) )
            return;
        m_ActivitiesTickets.erase(i);
    }
    dispatch_to_main_queue([=]{
        [self updateSpinningIndicator];
    });
}

- (void) setLayoutIndex:(int)layoutIndex
{
    if( m_ViewLayoutIndex != layoutIndex ) {
        if( auto l = m_Layouts->GetLayout(layoutIndex) )
            if( !l->is_disabled() ) {
                m_ViewLayoutIndex = layoutIndex;
                m_AssignedViewLayout = l;
                [m_View setPresentationLayout:*l];
                [self markRestorableStateAsInvalid];                
            }
    }
}

- (void) panelLayoutsChanged
{
    if( auto l = m_Layouts->GetLayout(m_ViewLayoutIndex) ) {
        if( m_AssignedViewLayout && *m_AssignedViewLayout == *l )
            return;
        
        if( !l->is_disabled() ) {
            m_AssignedViewLayout = l;
            [m_View setPresentationLayout:*l];
        }
        else {
            m_AssignedViewLayout = m_Layouts->LastResortLayout();
            [m_View setPresentationLayout:*m_AssignedViewLayout];
        }
    }
}

- (void) panelViewDidChangePresentationLayout
{
    PanelViewLayout layout;
    layout.name = m_AssignedViewLayout->name;
    layout.layout = [m_View presentationLayout];

    if( layout != *m_AssignedViewLayout )
        m_Layouts->ReplaceLayout( move(layout), m_ViewLayoutIndex );
}

- (void) commitCancelableLoadingTask:(function<void(const function<bool()> &_is_cancelled)>) _task
{
    auto sq = &m_DirectoryLoadingQ;
    m_DirectoryLoadingQ.Run([=]{
        _task( [sq]{ return sq->IsStopped(); } );
    });
}

- (void) GoToVFSPromise:(const VFSInstanceManager::Promise&)_promise onPath:(const string&)_directory
{
    m_DirectoryLoadingQ.Run([=](){
        VFSHostPtr host;
        try {
            host = m_VFSInstanceManager->RetrieveVFS(_promise,
                                                     [&]{ return m_DirectoryLoadingQ.IsStopped(); }
                                                     );
        } catch (VFSErrorException &e) {
            return; // TODO: something
        }
        
        // TODO: need an ability to show errors at least
        dispatch_to_main_queue([=]{
            [self GoToDir:_directory
                      vfs:host
             select_entry:""
        loadPreviousState:true
                    async:true];
        });
    });
}

- (void) goToPersistentLocation:(const PersistentLocation &)_location
{
    m_DirectoryLoadingQ.Run([=]{
        VFSHostPtr host;
        const auto rc = PanelDataPersisency::CreateVFSFromLocation(_location,
                                                                   host,
                                                                   *m_VFSInstanceManager);
        if( rc == VFSError::Ok ) {
            string path = _location.path;
            dispatch_to_main_queue([=]{
                auto context = make_shared<DirectoryChangeRequest>();
                context->VFS = host;
                context->PerformAsynchronous = true;
                context->RequestedDirectory = path;
                [self GoToDirWithContext:context];
            });
        }
    });
}

- (int) GoToDir:(const string&)_dir
            vfs:(VFSHostPtr)_vfs
   select_entry:(const string&)_filename
          async:(bool)_asynchronous
{
    return [self GoToDir:_dir
                     vfs:_vfs
            select_entry:_filename
       loadPreviousState:false
                   async:_asynchronous];
}

- (int) GoToDir:(const string&)_dir
            vfs:(VFSHostPtr)_vfs
   select_entry:(const string&)_filename
loadPreviousState:(bool)_load_state
          async:(bool)_asynchronous
{
    auto c = make_shared<DirectoryChangeRequest>();
    c->RequestedDirectory = _dir;
    c->VFS = _vfs;
    c->RequestFocusedEntry = _filename;
    c->LoadPreviousViewState = _load_state;
    c->PerformAsynchronous = _asynchronous;
    
    return [self GoToDirWithContext:c];
}

- (int) GoToDirWithContext:(shared_ptr<DirectoryChangeRequest>)_context
{
    auto &c = _context;
    if(c->RequestedDirectory.empty() ||
       c->RequestedDirectory.front() != '/' ||
       !c->VFS)
        return VFSError::InvalidCall;
    
    if(c->PerformAsynchronous == false) {
        assert(dispatch_is_main_queue());
        m_DirectoryLoadingQ.Stop();
        m_DirectoryLoadingQ.Wait();
    }
    else {
        if(!m_DirectoryLoadingQ.Empty())
            return 0;
    }
    
    auto workblock = [=]() {
        try {
            shared_ptr<VFSListing> listing;
            c->LoadingResultCode = c->VFS->FetchDirectoryListing(
                c->RequestedDirectory.c_str(),
                listing,
                m_VFSFetchingFlags,
                [&] { return m_DirectoryLoadingQ.IsStopped(); });
            if( c->LoadingResultCallback )
                c->LoadingResultCallback( c->LoadingResultCode );
            
            if( c->LoadingResultCode < 0 )
                return;
            // TODO: need an ability to show errors at least
            
            [self CancelBackgroundOperations]; // clean running operations if any
            dispatch_or_run_in_main_queue([=]{
                [m_View savePathState];
                m_Data.Load(listing, data::Model::PanelType::Directory);
                for( auto &i: c->RequestSelectedEntries )
                    m_Data.CustomFlagsSelectSorted( m_Data.SortedIndexForName(i.c_str()), true );
                [m_View dataUpdated];
                [m_View panelChangedWithFocusedFilename:c->RequestFocusedEntry
                                      loadPreviousState:c->LoadPreviousViewState];
                [self onPathChanged];
            });
        }
        catch(exception &e) {
            ShowExceptionAlert(e);
        }
        catch(...){
            ShowExceptionAlert();
        }
    };
    
    if( c->PerformAsynchronous == false ) {
        workblock();
        return c->LoadingResultCode;
    }
    else {
        m_DirectoryLoadingQ.Run(workblock);
        return 0;
    }
}

- (void) loadListing:(const shared_ptr<VFSListing>&)_listing
{
    [self CancelBackgroundOperations]; // clean running operations if any
    dispatch_or_run_in_main_queue([=]{
        [m_View savePathState];
        if( _listing->IsUniform() )
            m_Data.Load(_listing, data::Model::PanelType::Directory);
        else
            m_Data.Load(_listing, data::Model::PanelType::Temporary);
        [m_View dataUpdated];
        [m_View panelChangedWithFocusedFilename:"" loadPreviousState:false];
        [self onPathChanged];
    });
}

- (void) RecoverFromInvalidDirectory
{
    path initial_path = self.currentDirectoryPath;
    auto initial_vfs = self.vfs;
    m_DirectoryLoadingQ.Run([=]{
        // 1st - try to locate a valid dir in current host
        path path = initial_path;
        auto vfs = initial_vfs;
        
        while(true)
        {
            if(vfs->IterateDirectoryListing(path.c_str(), [](const VFSDirEnt &_dirent) {
                    return false;
                }) >= 0) {
                dispatch_to_main_queue([=]{
                    [self GoToDir:path.native()
                              vfs:vfs
                     select_entry:""
                            async:true];
                });
                break;
            }
            
            if(path == "/")
                break;
            
            if(path.filename() == ".") path.remove_filename();
            path = path.parent_path();
        }
        
        // we can't work on this vfs. currently for simplicity - just go home
        dispatch_to_main_queue([=]{
            [self GoToDir:CommonPaths::Home()
                      vfs:VFSNativeHost::SharedHost()
             select_entry:""
                    async:true];
        });
    });
}

- (void) scheduleDelayedFocusing:(DelayedFocusing)request
{
    assert(dispatch_is_main_queue()); // to preserve against fancy threading stuff
    // we assume that _item_name will not contain any forward slashes
    
    if(request.filename.empty())
        return;
    
    m_DelayedSelection.request_end = machtime() + request.timeout;
    m_DelayedSelection.filename = request.filename;
    m_DelayedSelection.done = request.done;
    
    if(request.check_now)
        [self checkAgainstRequestedFocusing];
}

- (bool) checkAgainstRequestedFocusing
{
    assert(dispatch_is_main_queue()); // to preserve against fancy threading stuff
    if( m_DelayedSelection.filename.empty() )
        return false;
    
    if( machtime() > m_DelayedSelection.request_end ) {
        m_DelayedSelection.filename.clear();
        m_DelayedSelection.done = nullptr;
        return false;
    }
    
    // now try to find it
    int raw_index = m_Data.RawIndexForName(m_DelayedSelection.filename.c_str());
    if( raw_index < 0 )
        return false;
        
    // we found this entry. regardless of appearance of this entry in current directory presentation
    // there's no reason to search for it again
    auto done = move(m_DelayedSelection.done);
    
    int sort_index = m_Data.SortedIndexForRawIndex(raw_index);
    if( sort_index >= 0 ) {
        m_View.curpos = sort_index;
        if( !self.isActive )
            [self.state ActivatePanelByController:self];
        if( done )
            done();
    }
    return true;
}

- (void) clearFocusingRequest
{
    m_DelayedSelection.filename.clear();
    m_DelayedSelection.done = nullptr;
}

- (BriefSystemOverview*) briefSystemOverview
{
    return [self.state briefSystemOverviewForPanel:self make:false];
}

- (id<NCPanelPreview>)quickLook
{
    return [self.state quickLookForPanel:self make:false];
}

- (nc::panel::PanelViewLayoutsStorage&)layoutStorage
{
    return *m_Layouts;
}

- (nc::core::VFSInstanceManager&) vfsInstanceManager
{
    return *m_VFSInstanceManager;
}

@end
