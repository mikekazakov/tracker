// Copyright (C) 2016-2020 Michael Kazakov. Subject to GNU General Public License version 3.
#include "FeedbackManagerImpl.h"
#include <SystemConfiguration/SystemConfiguration.h>
#include <Habanero/CFDefaultsCPP.h>
#include <NimbleCommander/Core/GoogleAnalytics.h>
#include <NimbleCommander/Bootstrap/ActivationManager.h>
#include "../GeneralUI/FeedbackWindow.h"
#include <Habanero/dispatch_cpp.h>

namespace nc {

static const auto g_RunsKey = CFSTR("feedbackApplicationRunsCount");
static const auto g_HoursKey = CFSTR("feedbackHoursUsedCount");
static const auto g_FirstRunKey = CFSTR("feedbackFirstRun");
static const auto g_LastRatingKey = CFSTR("feedbackLastRating");
static const auto g_LastRatingTimeKey = CFSTR("feedbackLastRating");

static int GetAndUpdateRunsCount()
{
    if( auto runs = CFDefaultsGetOptionalInt(g_RunsKey) ) {
        int v = *runs;
        if( v < 1 ) {
            v = 1;
            CFDefaultsSetInt(g_RunsKey, v);
        }
        else {
            dispatch_to_background([=] { CFDefaultsSetInt(g_RunsKey, v + 1); });
        }
        return v;
    }
    else {
        dispatch_to_background([=] { CFDefaultsSetInt(g_RunsKey, 1); });
        return 1;
    }
}

static double GetTotalHoursUsed()
{
    double v = CFDefaultsGetDouble(g_HoursKey);
    if( v < 0 )
        v = 0;
    return v;
}

static time_t GetOrSetFirstRunTime()
{
    const auto now = time(nullptr);
    if( auto t = CFDefaultsGetOptionalLong(g_FirstRunKey) ) {
        if( *t < now )
            return *t;
    }
    CFDefaultsSetLong(g_FirstRunKey, now);
    return now;
}

// http://stackoverflow.com/questions/7627058/how-to-determine-internet-connection-in-cocoa
static bool HasInternetConnection()
{
    bool returnValue = false;

    struct sockaddr zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sa_len = sizeof(zeroAddress);
    zeroAddress.sa_family = AF_INET;

    if( auto reachabilityRef =
            SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&zeroAddress) ) {
        SCNetworkReachabilityFlags flags = 0;
        if( SCNetworkReachabilityGetFlags(reachabilityRef, &flags) ) {
            BOOL isReachable = ((flags & kSCNetworkFlagsReachable) != 0);
            BOOL connectionRequired = ((flags & kSCNetworkFlagsConnectionRequired) != 0);
            returnValue = (isReachable && !connectionRequired) ? true : false;
        }
        CFRelease(reachabilityRef);
    }
    return returnValue;
}

FeedbackManagerImpl::FeedbackManagerImpl(nc::bootstrap::ActivationManager &_am)
    : m_ApplicationRunsCount(GetAndUpdateRunsCount()), m_TotalHoursUsed(GetTotalHoursUsed()),
      m_StartupTime(time(nullptr)), m_FirstRunTime(GetOrSetFirstRunTime()),
      m_ActivationManager(_am), m_LastRating(CFDefaultsGetOptionalInt(g_LastRatingKey)),
      m_LastRatingTime(CFDefaultsGetOptionalLong(g_LastRatingKey))
{
}

void FeedbackManagerImpl::CommitRatingOverlayResult(int _result)
{
    dispatch_assert_main_queue();

    if( _result < 0 || _result > 5 )
        return;

    const char *labels[] = {"Discard", "1 Star", "2 Stars", "3 Stars", "4 Stars", "5 Stars"};
    GA().PostEvent("Feedback", "Rating Overlay Choice", labels[_result]);

    m_LastRating = _result;
    m_LastRatingTime = time(nullptr);

    CFDefaultsSetInt(g_LastRatingKey, *m_LastRating);
    CFDefaultsSetLong(g_LastRatingTimeKey, *m_LastRatingTime);

    if( _result > 0 ) {
        // used clicked at some star - lets show a window then
        FeedbackWindow *w = [[FeedbackWindow alloc] initWithActivationManager:m_ActivationManager
                                                              feedbackManager:*this];
        w.rating = _result;
        [w showWindow:nil];
    }
}

bool FeedbackManagerImpl::ShouldShowRatingOverlayView()
{
    if( m_ShownRatingOverlay )
        return false; // show only once per run anyway

    if( IsEligibleForRatingOverlay() )
        if( HasInternetConnection() ) {
            GA().PostEvent("Feedback", "Rating Overlay Shown", "Shown");
            return m_ShownRatingOverlay = true;
        }

    return false;
}

bool FeedbackManagerImpl::IsEligibleForRatingOverlay() const
{
    const auto now = time(nullptr);
    const auto repeated_show_delay_on_result = 90l * 24l * 3600l; // 90 days
    const auto repeated_show_delay_on_discard = 7l * 24l * 3600l; // 7 days
    const auto min_runs = 20;
    const auto min_hours = 10;
    const auto min_days = 10;

    if( m_LastRating ) {
        // user had reacted to rating overlay at least once
        const auto when = m_LastRatingTime.value_or(0);
        if( *m_LastRating == 0 ) {
            // user has discarded question
            if( now - when > repeated_show_delay_on_discard ) {
                // we can let ourselves to try to bother user again
                return true;
            }
        }
        else {
            // used has clicked to some star
            if( now - when > repeated_show_delay_on_result ) {
                // it was a long time ago, we can ask for rating again
                return true;
            }
        }
    }
    else {
        // nope, user did never reacted to rating overlay - just check input params to find if it's
        // time to show
        const auto runs = m_ApplicationRunsCount;
        const auto hours_used = m_TotalHoursUsed;
        const auto days_since_first_run = (time(nullptr) - m_FirstRunTime) / (24l * 3600l);

        if( runs >= min_runs && hours_used >= min_hours && days_since_first_run >= min_days )
            return true;
    }

    return false;
}

void FeedbackManagerImpl::ResetStatistics()
{
    CFDefaultsRemoveValue(g_RunsKey);
    CFDefaultsRemoveValue(g_HoursKey);
    CFDefaultsRemoveValue(g_FirstRunKey);
    CFDefaultsRemoveValue(g_LastRatingKey);
    CFDefaultsRemoveValue(g_LastRatingTimeKey);
}

void FeedbackManagerImpl::UpdateStatistics()
{
    auto d = time(nullptr) - m_StartupTime;
    if( d < 0 )
        d = 0;
    CFDefaultsSetDouble(g_HoursKey, m_TotalHoursUsed + (double)d / 3600.);
}

void FeedbackManagerImpl::EmailFeedback()
{
    GA().PostEvent("Feedback", "Action", "Email Feedback");
    NSString *toAddress = @"feedback@magnumbytes.com";
    NSString *subject = [NSString
        stringWithFormat:@"Feedback on %@ version %@ (%@)",
                         [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleName"],
                         [NSBundle.mainBundle.infoDictionary
                             objectForKey:@"CFBundleShortVersionString"],
                         [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleVersion"]];
    NSString *bodyText = @"Please write your feedback here.";
    NSString *mailtoAddress =
        [NSString stringWithFormat:@"mailto:%@?Subject=%@&body=%@", toAddress, subject, bodyText];

    NSString *urlstring = [mailtoAddress
        stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet
                                                               .URLQueryAllowedCharacterSet];
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:urlstring]];
}

void FeedbackManagerImpl::EmailSupport()
{
    GA().PostEvent("Feedback", "Action", "Email Support");
    NSString *toAddress = @"support@magnumbytes.com";
    NSString *subject = [NSString
        stringWithFormat:@"Support on %@ version %@ (%@)",
                         [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleName"],
                         [NSBundle.mainBundle.infoDictionary
                             objectForKey:@"CFBundleShortVersionString"],
                         [NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleVersion"]];
    NSString *bodyText = @"Please describle your issues with Nimble Commander here.";
    NSString *mailtoAddress =
        [NSString stringWithFormat:@"mailto:%@?Subject=%@&body=%@", toAddress, subject, bodyText];
    NSString *urlstring = [mailtoAddress
        stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet
                                                               .URLQueryAllowedCharacterSet];
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:urlstring]];
}

void FeedbackManagerImpl::RateOnAppStore()
{
    GA().PostEvent("Feedback", "Action", "Rate on AppStore");
    NSString *mas_url = [NSString stringWithFormat:@"macappstore://itunes.apple.com/app/id%s",
                                                   m_ActivationManager.AppStoreID().c_str()];
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:mas_url]];
}

int FeedbackManagerImpl::ApplicationRunsCount()
{
    return m_ApplicationRunsCount;
}

}
