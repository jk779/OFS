#pragma once

#include "imgui.h"
#include "SDL.h"

#include <cstdint>

namespace OFS_Platform {

// The primary modifier follows the platform convention used by built-in actions.
#if defined(__APPLE__)
inline constexpr int32_t PrimaryImGuiModifier = ImGuiMod_Super;
#else
inline constexpr int32_t PrimaryImGuiModifier = ImGuiMod_Ctrl;
#endif

inline bool IsPrimaryModifierDown() noexcept
{
#if defined(__APPLE__)
    return (SDL_GetModState() & KMOD_GUI) != 0;
#else
    return (SDL_GetModState() & KMOD_CTRL) != 0;
#endif
}

} // namespace OFS_Platform
