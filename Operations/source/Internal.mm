#include "Internal.h"

namespace nc::ops {

NSBundle *Bundle()
{
    static const auto bundle_id = @"com.magnumbytes.NimbleCommander.Operations";
    static const auto bundle = [NSBundle bundleWithIdentifier:bundle_id];
    return bundle;
}

NSString *NSLocalizedString(NSString *_key, const char *_comment)
{
    return [Bundle() localizedStringForKey:_key value:@"" table:@"Localizable"];
}

}
