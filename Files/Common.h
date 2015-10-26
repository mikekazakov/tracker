//
//  Common.h
//  Directories
//
//  Created by Michael G. Kazakov on 01.03.13.
//  Copyright (c) 2013 Michael G. Kazakov. All rights reserved.
//
#pragma once

#include "path_manip.h"

// TODO: remove it.
struct DialogResult
{
    enum
    {
        Unknown = 0,
        OK,
        Cancel,
        Create,
        Copy,
        Overwrite,
        Append,
        Skip,
        SkipAll,
        Rename,
        Retry,
        Apply,
        Delete
    };
};

CFStringRef CFStringCreateWithUTF8StdStringNoCopy(const string &_s) noexcept;
CFStringRef CFStringCreateWithUTF8StringNoCopy(const char *_s) noexcept;
CFStringRef CFStringCreateWithUTF8StringNoCopy(const char *_s, size_t _len) noexcept;
CFStringRef CFStringCreateWithMacOSRomanStdStringNoCopy(const string &_s) noexcept;
CFStringRef CFStringCreateWithMacOSRomanStringNoCopy(const char *_s) noexcept;
CFStringRef CFStringCreateWithMacOSRomanStringNoCopy(const char *_s, size_t _len) noexcept;

// intended for debug and development purposes only
void SyncMessageBoxUTF8(const char *_utf8_string);

/** returns a value from NSTemporaryDirectory, once captured. Contains a path with a trailing slash. */
const string &AppTemporaryDirectory() noexcept;

struct MachTimeBenchmark
{
    MachTimeBenchmark() noexcept;
    nanoseconds Delta() const;
    void ResetNano (const char *_msg = "");
    void ResetMicro(const char *_msg = "");
    void ResetMilli(const char *_msg = "");
private:
    nanoseconds last;
};

#ifdef __OBJC__

/**
 * Returns a _T_ class object if _from_ can be converted to it.
 * If _from_ can't be converted to _T_ - returns nil.
 * If _from_ is nil - returns nil.
 */
template<typename T>
T* objc_cast(id from) noexcept {
    static const auto class_meta = [T class];
    if( [from isKindOfClass:class_meta] )
        return static_cast<T*>(from);
    return nil;
}


/**
 * Returns a weak pointer, just a syntax sugar for auto type deduction
 */
template <typename T>
__weak T* objc_weak(T* from) noexcept {
    __weak T* weak = from;
    return weak;
}

template <typename T>
T *objc_strong( T *_object ) noexcept {
    return (T*) _object;
}

void SyncMessageBoxNS(NSString *_ns_string);

typedef enum
{
    kTruncateAtStart,
    kTruncateAtMiddle,
    kTruncateAtEnd
} ETruncationType;
NSString *StringByTruncatingToWidth(NSString *str, float inWidth, ETruncationType truncationType, NSDictionary *attributes);

@interface NSView (Sugar)
- (void) setNeedsDisplay;
@end

@interface NSObject (MassObserving)
- (void)addObserver:(NSObject *)observer forKeyPaths:(NSArray*)keys;
- (void)addObserver:(NSObject *)observer forKeyPaths:(NSArray*)keys options:(NSKeyValueObservingOptions)options context:(void *)context;
- (void)removeObserver:(NSObject *)observer forKeyPaths:(NSArray*)keys;
@end

@interface NSColor (MyAdditions)
@property (readonly) CGColorRef copyCGColor;
@end

@interface NSTimer (SafeTolerance)
- (void) setSafeTolerance;
@end

@interface NSString(PerformanceAdditions)
- (const char *)fileSystemRepresentationSafe;
- (NSString*)stringByTrimmingLeadingWhitespace;
+ (instancetype)stringWithUTF8StdString:(const string&)stdstring;
+ (instancetype)stringWithUTF8StringNoCopy:(const char *)nullTerminatedCString;
+ (instancetype)stringWithUTF8StdStringNoCopy:(const string&)stdstring;
+ (instancetype)stringWithCharactersNoCopy:(const unichar *)characters length:(NSUInteger)length;
@end

@interface NSPasteboard(SyntaxSugar)
+ (void) writeSingleString:(const char *)_s;
@end

@interface NSMenu(Hierarchical)
- (NSMenuItem *)itemWithTagHierarchical:(NSInteger)tag;
- (NSMenuItem *)itemContainingItemWithTagHierarchical:(NSInteger)tag;
- (void)performActionForItemWithTagHierarchical:(NSInteger)tag;
@end

NSError* ErrnoToNSError(int _error);
inline NSError* ErrnoToNSError() { return ErrnoToNSError(errno); }

#endif

inline bool strisdot(const char *s) noexcept { return s && s[0] == '.' && s[1] == 0; }
inline bool strisdotdot(const char *s) noexcept { return s && s[0] == '.' && s[1] == '.' && s[2] == 0; }
inline bool strisdotdot(const string &s) noexcept { return strisdotdot( s.c_str() ); }

inline string EnsureTrailingSlash(string _s)
{
    if( _s.empty() || _s.back() != '/' )
        _s.push_back('/');
    return _s;
}

/**
 * return max(lower, min(n, upper));
 */
template <typename T__>
inline T__ clip(const T__& n, const T__& lower, const T__& upper)
{
    return max(lower, min(n, upper));
}
