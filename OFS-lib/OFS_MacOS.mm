#include "OFS_MacOS.h"

#import <AppKit/AppKit.h>

namespace OFS_MacOS {

bool OpenURL(const std::string& url) noexcept
{
    @autoreleasepool {
        NSString* urlString = [NSString stringWithUTF8String:url.c_str()];
        if (urlString == nil) {
            return false;
        }

        NSURL* urlObject = [NSURL URLWithString:urlString];
        return urlObject != nil && [[NSWorkspace sharedWorkspace] openURL:urlObject];
    }
}

bool RevealInFinder(const std::string& path) noexcept
{
    @autoreleasepool {
        NSString* pathString = [NSString stringWithUTF8String:path.c_str()];
        if (pathString == nil) {
            return false;
        }

        return [[NSWorkspace sharedWorkspace] selectFile:pathString inFileViewerRootedAtPath:@""];
    }
}

} // namespace OFS_MacOS
