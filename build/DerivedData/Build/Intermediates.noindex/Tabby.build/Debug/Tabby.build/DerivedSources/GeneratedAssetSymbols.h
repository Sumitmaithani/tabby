#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "BrowserArc" asset catalog image resource.
static NSString * const ACImageNameBrowserArc AC_SWIFT_PRIVATE = @"BrowserArc";

/// The "BrowserBrave" asset catalog image resource.
static NSString * const ACImageNameBrowserBrave AC_SWIFT_PRIVATE = @"BrowserBrave";

/// The "BrowserChrome" asset catalog image resource.
static NSString * const ACImageNameBrowserChrome AC_SWIFT_PRIVATE = @"BrowserChrome";

/// The "BrowserComet" asset catalog image resource.
static NSString * const ACImageNameBrowserComet AC_SWIFT_PRIVATE = @"BrowserComet";

/// The "BrowserEdge" asset catalog image resource.
static NSString * const ACImageNameBrowserEdge AC_SWIFT_PRIVATE = @"BrowserEdge";

/// The "TabbyMenuBar" asset catalog image resource.
static NSString * const ACImageNameTabbyMenuBar AC_SWIFT_PRIVATE = @"TabbyMenuBar";

#undef AC_SWIFT_PRIVATE
