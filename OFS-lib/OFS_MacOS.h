#pragma once

#include <functional>
#include <string>
#include <utility>
#include <vector>

struct SDL_Window;

namespace OFS_MacOS {

enum class MenuItemRole {
    Action,
    Separator,
    Services,
    HideApplication,
    HideOtherApplications,
    ShowAllApplications,
    CloseWindow,
    MinimizeWindow,
    ZoomWindow,
    BringAllToFront,
};

struct MenuItem {
    std::string title;
    int command = 0;
    int context = 0;
    bool enabled = true;
    bool checked = false;
    MenuItemRole role = MenuItemRole::Action;
    std::vector<MenuItem> children;

    bool operator==(const MenuItem& other) const noexcept;
};

struct Menu {
    std::string title;
    bool enabled = true;
    std::vector<MenuItem> items;

    bool operator==(const Menu& other) const noexcept;
};

using MenuActionHandler = std::function<void(int command, int context)>;
using MenuTrackingHandler = std::function<void(bool opening)>;

bool OpenURL(const std::string& url) noexcept;
bool RevealInFinder(const std::string& path) noexcept;
void UpdateMainMenu(const std::vector<Menu>& menus, MenuActionHandler handler) noexcept;
void SetMenuTrackingHandler(MenuTrackingHandler handler) noexcept;
void ClearMainMenuHandler() noexcept;
void SetDocumentEdited(SDL_Window* window, bool edited) noexcept;

} // namespace OFS_MacOS
