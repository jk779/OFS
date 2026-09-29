#include "OFS_DynamicFontAtlas.h"
#include "OFS_Localization.h"
#include "OFS_Util.h"
#include "OFS_Profiling.h"
#include "OFS_GL.h"
#if defined(__APPLE__)
#include "OFS_MacOS.h"
#endif

#include "imgui.h"
#include "SDL_rwops.h"
#include "SDL_timer.h"

#include <vector>

OFS_DynFontAtlas* OFS_DynFontAtlas::ptr = nullptr;


ImFont* OFS_DynFontAtlas::DefaultFont = nullptr;
ImFont* OFS_DynFontAtlas::DefaultFont2 = nullptr;
ImFont* OFS_DynFontAtlas::MonoFont = nullptr;

std::string OFS_DynFontAtlas::FontOverride;

OFS_DynFontAtlas::OFS_DynFontAtlas() noexcept
{
    config.OversampleH = 2;
    config.FontDataOwnedByAtlas = false;
    checkIfRebuildNeeded = true;

    auto& io = ImGui::GetIO();
    builder.AddRanges(io.Fonts->GetGlyphRangesDefault());
    // Keep every character used by the changing video time display in the atlas.
    builder.AddText(" 0123456789:./x()");

    builder.AddText(ICON_FOLDER_OPEN);
    builder.AddText(ICON_VOLUME_UP);
    builder.AddText(ICON_VOLUME_OFF);
    builder.AddText(ICON_LONG_ARROW_UP);
    builder.AddText(ICON_LONG_ARROW_DOWN);
    builder.AddText(ICON_LONG_ARROW_RIGHT);
    builder.AddText(ICON_ARROW_RIGHT);
    builder.AddText(ICON_PLAY);
    builder.AddText(ICON_PAUSE);
    builder.AddText(ICON_GAMEPAD);
    builder.AddText(ICON_HAND_RIGHT);
    builder.AddText(ICON_BACKWARD);
    builder.AddText(ICON_FORWARD);
    builder.AddText(ICON_STEP_BACKWARD);
    builder.AddText(ICON_STEP_FORWARD);
    builder.AddText(ICON_GITHUB);
    builder.AddText(ICON_SHARE);
    builder.AddText(ICON_EXCLAMATION);
    builder.AddText(ICON_REFRESH);
    builder.AddText(ICON_TRASH);
    builder.AddText(ICON_RANDOM);
    builder.AddText(ICON_WARNING_SIGN);
    builder.AddText(ICON_LINK);
    builder.AddText(ICON_UNLINK);
    builder.AddText(ICON_COPY);
    builder.AddText(ICON_LEAF);

    for (auto defaultStr : OFS_DefaultStrings::Default) {
        builder.AddText(defaultStr);
    }

    LastUsedChars.resize(builder.UsedChars.Size);
}

void OFS_DynFontAtlas::AddTranslationText() noexcept
{
    auto atlas = OFS_DynFontAtlas::ptr;
    for (auto defaultStr : OFS_Translator::ptr->Translation) {
        atlas->builder.AddText(defaultStr);
    }
    atlas->checkIfRebuildNeeded = true;
}

static ImFont* AddFontFromFile(OFS_DynFontAtlas* builder, const char* path, float fontSize, bool merge) noexcept
{
    auto& io = ImGui::GetIO();
    builder->config.MergeMode = merge;
    return io.Fonts->AddFontFromFileTTF(path, fontSize, &builder->config, builder->UsedRanges.Data);
    return nullptr;
}

static ImFont* AddDefaultFont(OFS_DynFontAtlas* builder, float fontSize) noexcept
{
    auto& io = ImGui::GetIO();
    ImFontConfig config = builder->config;
    config.MergeMode = false;
    config.SizePixels = fontSize;
    config.GlyphRanges = builder->UsedRanges.Data;
    return io.Fonts->AddFontDefault(&config);
}

void OFS_DynFontAtlas::RebuildFont(float fontSize) noexcept
{
    OFS_PROFILE(__FUNCTION__);
    assert(ptr->builder.UsedChars.size_in_bytes() == ptr->LastUsedChars.size_in_bytes());

    if (ptr->forceRebuild || memcmp(ptr->builder.UsedChars.Data, ptr->LastUsedChars.Data, ptr->builder.UsedChars.size_in_bytes()) != 0) {
        // rebuild atlas
        memcpy(ptr->LastUsedChars.Data, ptr->builder.UsedChars.Data, ptr->builder.UsedChars.size_in_bytes());
        ptr->checkIfRebuildNeeded = false;
        ptr->forceRebuild = false;

        ptr->UsedRanges.clear();
        ptr->builder.BuildRanges(&ptr->UsedRanges);

        auto& io = ImGui::GetIO();
        GLuint fontTexture = (GLuint)(intptr_t)io.Fonts->TexID;
        io.Fonts->Clear();
        io.FontDefault = nullptr;
        ptr->DefaultFont = nullptr;
        ptr->DefaultFont2 = nullptr;
        ptr->MonoFont = nullptr;

        auto roboto = Util::Resource("fonts/RobotoMono-Regular.ttf");
#if defined(__APPLE__)
        auto defaultFont = FontOverride.empty() ? OFS_MacOS::SystemFontPath(fontSize) : FontOverride;
        if (defaultFont.empty()) {
            LOGF_WARN("%s", "Unable to resolve the macOS system font; using bundled Roboto Mono");
        }
#else
        auto defaultFont = roboto;
#endif
        auto mainFont = FontOverride.empty() ? defaultFont : FontOverride;
        auto fontawesome = Util::Resource("fonts/fontawesome-webfont.ttf");
        auto notoCJK = Util::Resource("fonts/NotoSansCJKjp-Regular.otf");

        ImFont* font = nullptr;
        std::string resolvedMainFont;
        bool usingBuiltInFallback = false;
        {
            OFS_PROFILE("Main font");
            if (!mainFont.empty()) {
                font = AddFontFromFile(ptr, mainFont.c_str(), fontSize, false);
            }
            if (!font) {
                if (!mainFont.empty()) {
                    LOGF_ERROR("Failed to load \"%s\"", mainFont.c_str());
                }
                font = AddFontFromFile(ptr, roboto.c_str(), fontSize, false);
                if (font) {
                    resolvedMainFont = roboto;
                } else {
                    LOGF_ERROR("Failed to load \"%s\"", roboto.c_str());
                    font = AddDefaultFont(ptr, fontSize);
                    usingBuiltInFallback = font != nullptr;
                }
            }
            io.FontDefault = font;
            ptr->DefaultFont = font;
            if (font && resolvedMainFont.empty() && !usingBuiltInFallback) {
                resolvedMainFont = mainFont;
            }
        }
        {
            OFS_PROFILE("Load fontawesome font");
            font = AddFontFromFile(ptr, fontawesome.c_str(), fontSize, true);
            if (!font) {
                LOGF_ERROR("Failed to load \"%s\"", fontawesome.c_str());
            }
        }
        {
            OFS_PROFILE("Load NotoSansCJK");
            font = AddFontFromFile(ptr, notoCJK.c_str(), fontSize, true);
            if (!font) {
                LOGF_ERROR("Failed to load \"%s\"", notoCJK.c_str());
            }
        }
        {
            OFS_PROFILE("Load main font (2x)");
            if (usingBuiltInFallback) {
                font = AddDefaultFont(ptr, fontSize * 2.f);
            } else if (!resolvedMainFont.empty()) {
                font = AddFontFromFile(ptr, resolvedMainFont.c_str(), fontSize * 2.f, false);
            }
            if (!font) {
                LOGF_WARN("%s", "Failed to load the 2x main font; using the regular main font");
                font = ptr->DefaultFont;
            }
            ptr->DefaultFont2 = font;
        }
        {
            OFS_PROFILE("Load video time monospace font");
            ptr->MonoFont = AddFontFromFile(ptr, roboto.c_str(), fontSize, false);
            if (!ptr->MonoFont) {
                LOGF_WARN("Failed to load \"%s\" for the video time display; using the main font", roboto.c_str());
            }
        }
        unsigned char* pixels;
        int width, height;
        double fontBuildDuration;
        {
            double startCount = SDL_GetPerformanceCounter();
            io.Fonts->GetTexDataAsRGBA32(&pixels, &width, &height);
            double endCount = SDL_GetPerformanceCounter();
            fontBuildDuration = (endCount - startCount) / (double)SDL_GetPerformanceFrequency();
        }

        // Upload texture to graphics system
        if (!fontTexture) {
            // If the font texture is not set it will be created by ImGui_ImplOpenGL3_CreateFontsTexture
            // in the imgui_impl_opengl3.cpp
            return;
        }
        glBindTexture(GL_TEXTURE_2D, fontTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glTexImage2D(GL_TEXTURE_2D, 0, OFS_InternalTexFormat, width, height, 0, OFS_TexFormat, GL_UNSIGNED_BYTE, pixels);

        io.Fonts->ClearTexData();
        io.Fonts->SetTexID((void*)(intptr_t)fontTexture);

        LOGF_INFO("Font atlas was rebuilt. Took %0.3lf seconds.", fontBuildDuration);
        LOGF_INFO("New font atlas size: %dx%d", width, height);
    }
}
