#pragma once

#include <string>

namespace OFS_MacOS {

bool OpenURL(const std::string& url) noexcept;
bool RevealInFinder(const std::string& path) noexcept;

} // namespace OFS_MacOS
