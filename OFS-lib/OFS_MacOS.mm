#include "OFS_MacOS.h"

#import <AppKit/AppKit.h>
#import <SDL_syswm.h>

namespace {

OFS_MacOS::MenuActionHandler MenuHandler;
std::vector<OFS_MacOS::Menu> CurrentMenus;

} // namespace

@interface OFSMenuTarget : NSObject
- (void)performMenuAction:(id)sender;
@end

@implementation OFSMenuTarget
- (void)performMenuAction:(id)sender
{
    if (MenuHandler == nullptr || ![sender isKindOfClass:[NSMenuItem class]]) {
        return;
    }

    NSArray<NSNumber*>* action = [(NSMenuItem*)sender representedObject];
    if ([action count] != 2) {
        return;
    }
    MenuHandler([[action objectAtIndex:0] intValue], [[action objectAtIndex:1] intValue]);
}
@end

namespace {

OFSMenuTarget* GetMenuTarget()
{
    static OFSMenuTarget* target = [[OFSMenuTarget alloc] init];
    return target;
}

NSString* ToNSString(const std::string& value)
{
    NSString* result = [NSString stringWithUTF8String:value.c_str()];
    return result != nil ? result : @"";
}

NSMenuItem* BuildMenuItem(const OFS_MacOS::MenuItem& item)
{
    using OFS_MacOS::MenuItemRole;
    if (item.role == MenuItemRole::Separator) {
        return [NSMenuItem separatorItem];
    }

    SEL selector = nil;
    id target = nil;
    switch (item.role) {
        case MenuItemRole::Action:
            selector = @selector(performMenuAction:);
            target = GetMenuTarget();
            break;
        case MenuItemRole::HideApplication:
            selector = @selector(hide:);
            target = NSApp;
            break;
        case MenuItemRole::HideOtherApplications:
            selector = @selector(hideOtherApplications:);
            target = NSApp;
            break;
        case MenuItemRole::ShowAllApplications:
            selector = @selector(unhideAllApplications:);
            target = NSApp;
            break;
        case MenuItemRole::CloseWindow: selector = @selector(performClose:); break;
        case MenuItemRole::MinimizeWindow: selector = @selector(performMiniaturize:); break;
        case MenuItemRole::ZoomWindow: selector = @selector(performZoom:); break;
        case MenuItemRole::BringAllToFront: selector = @selector(arrangeInFront:); break;
        case MenuItemRole::Services:
        case MenuItemRole::Separator: break;
    }

    NSMenuItem* nativeItem = [[[NSMenuItem alloc] initWithTitle:ToNSString(item.title)
        action:selector keyEquivalent:@""] autorelease];
    [nativeItem setTarget:target];
    [nativeItem setEnabled:item.enabled ? YES : NO];
    [nativeItem setState:item.checked ? NSControlStateValueOn : NSControlStateValueOff];

    if (item.role == MenuItemRole::Action) {
        [nativeItem setRepresentedObject:@[@(item.command), @(item.context)]];
    }

    if (!item.children.empty() || item.role == MenuItemRole::Services) {
        NSMenu* submenu = [[[NSMenu alloc] initWithTitle:ToNSString(item.title)] autorelease];
        [submenu setAutoenablesItems:NO];
        for (const auto& child : item.children) {
            [submenu addItem:BuildMenuItem(child)];
        }
        [nativeItem setSubmenu:submenu];
        if (item.role == MenuItemRole::Services) {
            [NSApp setServicesMenu:submenu];
        }
    }
    return nativeItem;
}

} // namespace

namespace OFS_MacOS {

bool MenuItem::operator==(const MenuItem& other) const noexcept
{
    return title == other.title && command == other.command && context == other.context
        && enabled == other.enabled && checked == other.checked && role == other.role
        && children == other.children;
}

bool Menu::operator==(const Menu& other) const noexcept
{
    return title == other.title && enabled == other.enabled && items == other.items;
}

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

void UpdateMainMenu(const std::vector<Menu>& menus, MenuActionHandler handler) noexcept
{
    @autoreleasepool {
        MenuHandler = std::move(handler);
        if (menus == CurrentMenus) {
            return;
        }
        CurrentMenus = menus;

        NSMenu* mainMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        for (const auto& menu : menus) {
            NSMenuItem* rootItem = [[[NSMenuItem alloc] initWithTitle:ToNSString(menu.title)
                action:nil keyEquivalent:@""] autorelease];
            [rootItem setEnabled:menu.enabled ? YES : NO];
            NSMenu* submenu = [[[NSMenu alloc] initWithTitle:ToNSString(menu.title)] autorelease];
            [submenu setAutoenablesItems:NO];
            for (const auto& item : menu.items) {
                [submenu addItem:BuildMenuItem(item)];
            }
            [rootItem setSubmenu:submenu];
            [mainMenu addItem:rootItem];
        }
        [NSApp setMainMenu:mainMenu];
        if (menus.size() > 1) {
            for (NSInteger index = 0; index < [mainMenu numberOfItems]; ++index) {
                NSMenuItem* item = [mainMenu itemAtIndex:index];
                if ([[item title] isEqualToString:@"Window"]) {
                    [NSApp setWindowsMenu:[item submenu]];
                    break;
                }
            }
        }
    }
}

void ClearMainMenuHandler() noexcept
{
    MenuHandler = nullptr;
    CurrentMenus.clear();
}

void SetDocumentEdited(SDL_Window* window, bool edited) noexcept
{
    if (window == nullptr) {
        return;
    }

    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (SDL_GetWindowWMInfo(window, &info) == SDL_TRUE && info.subsystem == SDL_SYSWM_COCOA) {
        [info.info.cocoa.window setDocumentEdited:edited ? YES : NO];
    }
}

} // namespace OFS_MacOS
