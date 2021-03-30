// Copyright (C) 2013-2021 Michael Kazakov. Subject to GNU General Public License version 3.
#include <Cocoa/Cocoa.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <IOKit/IOKitLib.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mutex>
#include <Utility/ObjCpp.h>
#include <Utility/SystemInformation.h>
#include <Utility/StringExtras.h>
#include <Habanero/CFString.h>
#include <Habanero/CommonPaths.h>

namespace nc::utility {

// CPU_STATE_USER
// processor_info_array_t
int GetBSDProcessList(kinfo_proc **procList, size_t *procCount)
{
    int err;
    kinfo_proc *result;
    bool done;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    // Declaring name as const requires us to cast it when passing it to
    // sysctl because the prototype doesn't include the const modifier.
    size_t length;

    //    assert( procList != NULL);
    //    assert(*procList == NULL);
    //    assert(procCount != NULL);

    *procCount = 0;

    // We start by calling sysctl with result == NULL and length == 0.
    // That will succeed, and set length to the appropriate length.
    // We then allocate a buffer of that size and call sysctl again
    // with that buffer.  If that succeeds, we're done.  If that fails
    // with ENOMEM, we have to throw away our buffer and loop.  Note
    // that the loop causes use to call sysctl with NULL again; this
    // is necessary because the ENOMEM failure case sets length to
    // the amount of data returned, not the amount of data that
    // could have been returned.

    result = NULL;
    done = false;
    do {
        assert(result == NULL);

        // Call sysctl with a NULL buffer.

        length = 0;
        err = sysctl(
            const_cast<int *>(name), (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);
        if( err == -1 ) {
            err = errno;
        }

        // Allocate an appropriately sized buffer based on the results
        // from the previous call.

        if( err == 0 ) {
            result = static_cast<kinfo_proc *>(malloc(length));
            if( result == NULL ) {
                err = ENOMEM;
            }
        }

        // Call sysctl again with the new buffer.  If we get an ENOMEM
        // error, toss away our buffer and start again.

        if( err == 0 ) {
            err = sysctl(const_cast<int *>(name),
                         (sizeof(name) / sizeof(*name)) - 1,
                         result,
                         &length,
                         NULL,
                         0);
            if( err == -1 ) {
                err = errno;
            }
            if( err == 0 ) {
                done = true;
            }
            else if( err == ENOMEM ) {
                assert(result != NULL);
                free(result);
                result = NULL;
                err = 0;
            }
        }
    } while( err == 0 && !done );

    // Clean up and establish post conditions.

    if( err != 0 && result != NULL ) {
        free(result);
        result = NULL;
    }
    *procList = result;
    if( err == 0 ) {
        *procCount = length / sizeof(kinfo_proc);
    }

    assert((err == 0) == (*procList != NULL));

    return err;
}

bool GetMemoryInfo(MemoryInfo &_mem) noexcept
{
    static int pagesize = 0;
    static uint64_t memsize = 0;

    // get page size and hardware memory size (only once)
    static std::once_flag once;
    call_once(once, [] {
        int psmib[2] = {CTL_HW, HW_PAGESIZE};
        size_t length = sizeof(pagesize);
        sysctl(psmib, 2, &pagesize, &length, NULL, 0);

        int memsizemib[2] = {CTL_HW, HW_MEMSIZE};
        length = sizeof(memsize);
        sysctl(memsizemib, 2, &memsize, &length, NULL, 0);
    });

    // get general memory info
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    vm_statistics_data_t vmstat;
    if( host_statistics(
            mach_host_self(), HOST_VM_INFO, reinterpret_cast<host_info_t>(&vmstat), &count) !=
        KERN_SUCCESS )
        return false;

    uint64_t wired_memory = static_cast<uint64_t>(vmstat.wire_count) * pagesize;
    uint64_t active_memory = static_cast<uint64_t>(vmstat.active_count) * pagesize;
    uint64_t inactive_memory = static_cast<uint64_t>(vmstat.inactive_count) * pagesize;
    uint64_t free_memory = static_cast<uint64_t>(vmstat.free_count) * pagesize;
    uint64_t total_memory = wired_memory + active_memory + inactive_memory + free_memory;
    // NOT "memory used" in activity monitor in 10.9
    // 10.9 "memory used" = "app memory" + "file cache" + "wired memory"
    // have no ideas how to get "app memory" and "file cache"
    uint64_t used_memory = total_memory - free_memory;
    _mem.total = total_memory;
    _mem.wired = wired_memory;
    _mem.active = active_memory;
    _mem.inactive = inactive_memory;
    _mem.free = free_memory;
    _mem.used = used_memory;

    // get the swap size
    int swapmib[2] = {CTL_VM, VM_SWAPUSAGE};
    struct xsw_usage swap_info;
    size_t length = sizeof(swap_info);
    if( sysctl(swapmib, 2, &swap_info, &length, NULL, 0) < 0 )
        return false;
    _mem.swap = swap_info.xsu_used;

    _mem.total_hw = memsize;

    return true;
}

bool GetCPULoad(CPULoad &_load) noexcept
{
    unsigned int *cpuInfo;
    mach_msg_type_number_t numCpuInfo;
    natural_t numCPUs = 0;
    kern_return_t err = host_processor_info(mach_host_self(),
                                            PROCESSOR_CPU_LOAD_INFO,
                                            &numCPUs,
                                            reinterpret_cast<processor_info_array_t *>(&cpuInfo),
                                            &numCpuInfo);
    if( err != KERN_SUCCESS )
        return false;

    double system = 0.;
    double user = 0.;
    double idle = 0.;

    static unsigned int *prior =
        static_cast<unsigned int *>(calloc(CPU_STATE_MAX * numCPUs, sizeof(unsigned int)));
    static const unsigned int alloc_cpus = numCPUs;
    assert(alloc_cpus == numCPUs);

    for( unsigned i = 0; i < numCPUs; ++i ) {
        system += cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM];
        system += cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
        user += cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER];
        idle += cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];

        system -= prior[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM];
        system -= prior[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
        user -= prior[(CPU_STATE_MAX * i) + CPU_STATE_USER];
        idle -= prior[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
    }

    memcpy(prior, cpuInfo, sizeof(integer_t) * numCpuInfo);
    vm_deallocate(mach_task_self(),
                  reinterpret_cast<vm_address_t>(cpuInfo),
                  sizeof(unsigned int) * numCpuInfo);

    double total = system + user + idle;
    system /= total;
    user /= total;
    idle /= total;

    _load.system = system;
    _load.user = user;
    _load.idle = idle;

    return true;
}

static const OSXVersion g_Version = [] {
    const auto sys_ver = NSProcessInfo.processInfo.operatingSystemVersion;
    if( sys_ver.majorVersion == 11 )
        return OSXVersion::macOS_11;
    if( sys_ver.majorVersion == 10 )
        switch( sys_ver.minorVersion ) {
            case 15:
                return OSXVersion::OSX_15;
            case 14:
                return OSXVersion::OSX_14;
            case 13:
                return OSXVersion::OSX_13;
            case 12:
                return OSXVersion::OSX_12;
            case 11:
                return OSXVersion::OSX_11;
            case 10:
                return OSXVersion::OSX_10;
            case 9:
                return OSXVersion::OSX_9;
        }
    return OSXVersion::OSX_Unknown;
}();

OSXVersion GetOSXVersion() noexcept
{
    return g_Version;
}

static std::string ExtractReadableModelNameFromFrameworks(std::string_view _coded_name)
{
    NSDictionary *dict;

    // 1st attempt: ServerInformation.framework
    const auto server_information_framework =
        @"/System/Library/PrivateFrameworks/ServerInformation.framework";
    if( auto bundle = [NSBundle bundleWithPath:server_information_framework] )
        if( auto path = [bundle pathForResource:@"SIMachineAttributes" ofType:@"plist"] )
            dict = [NSDictionary dictionaryWithContentsOfFile:path];

    // 2nd attempt: ServerKit.framework
    const auto server_kit_framework = @"/System/Library/PrivateFrameworks/ServerKit.framework";
    if( dict == nil )
        if( auto bundle = [NSBundle bundleWithPath:server_kit_framework] )
            if( auto path = [bundle pathForResource:@"XSMachineAttributes" ofType:@"plist"] )
                dict = [NSDictionary dictionaryWithContentsOfFile:path];

    if( dict == nil )
        return {};

    const auto coded_name = [NSString stringWithUTF8StdStringView:_coded_name];
    if( coded_name == nil )
        return {};

    const auto info = objc_cast<NSDictionary>(dict[coded_name]);
    if( info == nil )
        return {};

    const auto localizable = objc_cast<NSDictionary>(info[@"_LOCALIZABLE_"]);
    if( localizable == nil )
        return {};

    const auto loc_model = objc_cast<NSString>(localizable[@"model"]);
    if( loc_model == nil )
        return {};

    auto human_model = loc_model;
    if( auto market_model = objc_cast<NSString>(localizable[@"marketingModel"]) ) {
        const auto cs = [NSCharacterSet characterSetWithCharactersInString:@"()"];
        const auto splitted = [market_model componentsSeparatedByCharactersInSet:cs];
        if( splitted.count == 3 )
            human_model = [NSString stringWithFormat:@"%@ (%@)", loc_model, splitted[1]];
    }

    return human_model.UTF8String;
}

static std::string ExtractReadableModelNameFromSystemProfiler()
{
    const auto path = base::CommonPaths::Library() + "Preferences/com.apple.SystemProfiler.plist";
    const auto url = [NSURL fileURLWithFileSystemRepresentation:path.c_str()
                                                    isDirectory:false
                                                  relativeToURL:nil];
    if( url == nil )
        return {};

    const auto prefs = [NSDictionary dictionaryWithContentsOfURL:url];
    if( prefs == nil )
        return {};

    const auto names = objc_cast<NSDictionary>(prefs[@"CPU Names"]);
    if( names == nil )
        return {};

    const auto country_id = NSLocale.autoupdatingCurrentLocale.countryCode;
    for( const id key in names.allKeys ) {
        if( [objc_cast<NSString>(key) hasSuffix:country_id] ) {
            if( const auto name = objc_cast<NSString>(names[key]) ) {
                return name.UTF8String;
            }
        }
    }
    return {};
}

bool GetSystemOverview(SystemOverview &_overview)
{
    // get machine name everytime
    if( auto computer_name = SCDynamicStoreCopyComputerName(nullptr, nullptr) ) {
        _overview.computer_name = ((__bridge NSString *)computer_name).UTF8String;
        CFRelease(computer_name);
    }

    // get user name everytime
    _overview.user_name = NSUserName().UTF8String;

    // get full user name everytime
    _overview.user_full_name = NSFullUserName().UTF8String;

    // get machine model once
    [[clang::no_destroy]] static std::string coded_model = "unknown";
    [[clang::no_destroy]] static std::string human_model = "N/A";
    static std::once_flag once;
    call_once(once, [] {
        char hw_model[256];
        size_t len = 256;
        if( sysctlbyname("hw.model", hw_model, &len, NULL, 0) != 0 )
            return;
        coded_model = hw_model;

        if( auto name1 = ExtractReadableModelNameFromFrameworks(coded_model); name1 != "" ) {
            human_model = name1;
        }
        else if( auto name2 = ExtractReadableModelNameFromSystemProfiler(); name2 != "" ) {
            human_model = name2;
        }
    });

    _overview.human_model = human_model;
    _overview.coded_model = coded_model;

    return true;
}

bool IsThisProcessSandboxed() noexcept
{
    static const bool is_sandboxed = getenv("APP_SANDBOX_CONTAINER_ID") != nullptr;
    return is_sandboxed;
}

const std::string &GetBundleID() noexcept
{
    using namespace std::string_literals;
    [[clang::no_destroy]] static const std::string bundle_id = [] {
        if( CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle()) )
            return CFStringGetUTF8StdString(bid);
        else
            return "unknown"s;
    }();
    return bundle_id;
}

}
