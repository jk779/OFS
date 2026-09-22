project(OFS_lib)

set(OFS_LIB_SOURCES
	"event/OFS_EventSystem.cpp"
	"event/OFS_Event.cpp"

	"state/states/KeybindingState.cpp"
	"state/states/ChapterState.cpp"

	"Funscript/Funscript.cpp"
	"Funscript/FunscriptAction.cpp"
	"Funscript/FunscriptUndoSystem.cpp"
	"Funscript/FunscriptHeatmap.cpp"

	"UI/GradientBar.cpp"
	"UI/OFS_ImGui.cpp"
	"UI/OFS_VideoplayerControls.cpp"
	"UI/OFS_Videopreview.cpp"
	"UI/OFS_BlockingTask.cpp"
	
	"UI/OFS_ScriptTimeline.cpp"
	"UI/ScriptPositionsOverlayMode.cpp"
	"UI/OFS_KeybindingSystem.cpp"
	"UI/OFS_Waveform.cpp"
	
	"videoplayer/OFS_VideoplayerWindow.cpp"
	"videoplayer/impl/OFS_MpvVideoplayer.cpp"

	"state/OFS_StateManager.cpp"
	"state/OFS_LibState.cpp"


	"imgui_impl/imgui_impl_opengl3.cpp"
	"imgui_impl/imgui_impl_sdl.cpp" 

	"gl/OFS_Shader.cpp"

	"OFS_ControllerInput.cpp"

	"OFS_Serialization.cpp"
	"OFS_Util.cpp"
	"OFS_FileLogging.cpp"
	"OFS_DynamicFontAtlas.cpp"
	"OFS_MpvLoader.cpp"

	"OFS_StringsGenerated.cpp"

	"localization/OFS_Localization.cpp"
)

if(APPLE)
	list(APPEND OFS_LIB_SOURCES "OFS_MacOS.mm")
endif()

add_library(${PROJECT_NAME} STATIC ${OFS_LIB_SOURCES})

if(APPLE)
	# AppleClang rejects the pinned sol2 optional<T&>::emplace overload because
	# its forwarding implementation is not valid for a reference specialization.
	# Keep the original sol2 pin and patch only this header in the build tree.
	set(OFS_SOL2_OPTIONAL_SOURCE
		"${CMAKE_SOURCE_DIR}/lib/sol2/include/sol/optional_implementation.hpp")
	set(OFS_SOL2_COMPAT_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/sol2-compat")
	set(OFS_SOL2_OPTIONAL_COMPAT_HEADER
		"${OFS_SOL2_COMPAT_INCLUDE_DIR}/sol/optional_implementation.hpp")

	if(NOT EXISTS "${OFS_SOL2_OPTIONAL_SOURCE}")
		message(FATAL_ERROR
			"Pinned sol2 optional implementation was not found: ${OFS_SOL2_OPTIONAL_SOURCE}")
	endif()

	file(READ "${OFS_SOL2_OPTIONAL_SOURCE}" OFS_SOL2_OPTIONAL_CONTENT)
	set(OFS_SOL2_OPTIONAL_OLD_SNIPPET [=[
		template <class... Args>
		T& emplace(Args&&... args) noexcept {
			static_assert(std::is_constructible<T, Args&&...>::value, "T must be constructible with Args");

			*this = nullopt;
			this->construct(std::forward<Args>(args)...);
		}
]=])
	set(OFS_SOL2_OPTIONAL_NEW_SNIPPET [=[
		T& emplace(T& arg) noexcept {
			*this = nullopt;
			m_value = &arg;
			return **this;
		}
]=])

	string(FIND "${OFS_SOL2_OPTIONAL_CONTENT}" "${OFS_SOL2_OPTIONAL_OLD_SNIPPET}"
		OFS_SOL2_OPTIONAL_PATCH_OFFSET)
	if(OFS_SOL2_OPTIONAL_PATCH_OFFSET EQUAL -1)
		message(FATAL_ERROR
			"Pinned sol2 optional<T&>::emplace snippet was not found in ${OFS_SOL2_OPTIONAL_SOURCE}; refusing to patch an unknown version")
	endif()

	string(LENGTH "${OFS_SOL2_OPTIONAL_OLD_SNIPPET}" OFS_SOL2_OPTIONAL_PATCH_LENGTH)
	math(EXPR OFS_SOL2_OPTIONAL_PATCH_TAIL_OFFSET
		"${OFS_SOL2_OPTIONAL_PATCH_OFFSET} + ${OFS_SOL2_OPTIONAL_PATCH_LENGTH}")
	string(SUBSTRING "${OFS_SOL2_OPTIONAL_CONTENT}" 0
		"${OFS_SOL2_OPTIONAL_PATCH_OFFSET}" OFS_SOL2_OPTIONAL_PATCH_PREFIX)
	string(SUBSTRING "${OFS_SOL2_OPTIONAL_CONTENT}" "${OFS_SOL2_OPTIONAL_PATCH_TAIL_OFFSET}" -1
		OFS_SOL2_OPTIONAL_PATCH_SUFFIX)
	string(FIND "${OFS_SOL2_OPTIONAL_PATCH_SUFFIX}" "${OFS_SOL2_OPTIONAL_OLD_SNIPPET}"
		OFS_SOL2_OPTIONAL_SECOND_PATCH_OFFSET)
	if(OFS_SOL2_OPTIONAL_SECOND_PATCH_OFFSET GREATER -1)
		message(FATAL_ERROR
			"Pinned sol2 optional<T&>::emplace snippet occurs more than once in ${OFS_SOL2_OPTIONAL_SOURCE}; refusing an ambiguous patch")
	endif()

	file(MAKE_DIRECTORY "${OFS_SOL2_COMPAT_INCLUDE_DIR}/sol")
	file(WRITE "${OFS_SOL2_OPTIONAL_COMPAT_HEADER}"
		"${OFS_SOL2_OPTIONAL_PATCH_PREFIX}${OFS_SOL2_OPTIONAL_NEW_SNIPPET}${OFS_SOL2_OPTIONAL_PATCH_SUFFIX}")
	if(NOT TARGET sol2)
		message(FATAL_ERROR "The sol2 target is required for the macOS compatibility shim")
	endif()
	target_include_directories(sol2 BEFORE INTERFACE
		"$<BUILD_INTERFACE:${OFS_SOL2_COMPAT_INCLUDE_DIR}>")
	message(STATUS "Using generated macOS sol2 optional<T&>::emplace compatibility header")
endif()

target_include_directories(${PROJECT_NAME} PUBLIC
	"${PROJECT_SOURCE_DIR}/event/"
	"${PROJECT_SOURCE_DIR}/Funscript/"
	"${PROJECT_SOURCE_DIR}/UI/"
	"${PROJECT_SOURCE_DIR}/imgui_impl/"
	"${PROJECT_SOURCE_DIR}/gl/"
	"${PROJECT_SOURCE_DIR}/"
	"${PROJECT_SOURCE_DIR}/player/"
	"${PROJECT_SOURCE_DIR}/localization/"
	"${PROJECT_SOURCE_DIR}/videoplayer/"
	"${PROJECT_SOURCE_DIR}/state/"
	"${CMAKE_CURRENT_BINARY_DIR}"
)

add_custom_command(OUTPUT "OFS_StringsGenerated.cpp" "OFS_StringsGenerated.h"
                   COMMAND gen_localization ARGS "${CMAKE_SOURCE_DIR}/localization/localization.csv"
                   MAIN_DEPENDENCY "${CMAKE_SOURCE_DIR}/localization/localization.csv"
                   DEPENDS gen_localization
                   VERBATIM)

target_link_libraries(${PROJECT_NAME} PUBLIC
	SDL2-static
	SDL2main
	nlohmann_json
	glad2
	imgui
	imgui_stdlib
	tinyfiledialogs
	glm
	bitsery
	refl-cpp
	eventpp
)

target_compile_features(${PROJECT_NAME} PUBLIC cxx_std_17)

find_package(Git)
execute_process(
    COMMAND ${GIT_EXECUTABLE} --git-dir=${CMAKE_SOURCE_DIR}/.git describe --abbrev=0 --tags
    RESULT_VARIABLE result
    OUTPUT_VARIABLE LATEST_GIT_TAG)

execute_process(
    COMMAND ${GIT_EXECUTABLE} --git-dir=${CMAKE_SOURCE_DIR}/.git rev-parse --short HEAD
    RESULT_VARIABLE result
    OUTPUT_VARIABLE LATEST_GIT_HASH)


string(REGEX REPLACE "\n$" "" LATEST_GIT_TAG "${LATEST_GIT_TAG}")
set(LATEST_GIT_TAG "\"${LATEST_GIT_TAG}\"")
message("Compiling with git tag: ${LATEST_GIT_TAG}")

string(REGEX REPLACE "\n$" "" LATEST_GIT_HASH "${LATEST_GIT_HASH}")
set(LATEST_GIT_HASH "\"${LATEST_GIT_HASH}\"")
message("Compiling with git hash: ${LATEST_GIT_HASH}")

target_compile_definitions(${PROJECT_NAME} PUBLIC 
	"OFS_LATEST_GIT_TAG=${LATEST_GIT_TAG}"
	"OFS_LATEST_GIT_HASH=${LATEST_GIT_HASH}"
	"IMGUI_IMPL_OPENGL_LOADER_GLAD2"
	"MPV_ENABLE_DEPRECATED=0"
)

if(OFS_PROFILE)
	target_compile_definitions(${PROJECT_NAME} PUBLIC OFS_PROFILE_ENABLED=1)
	target_link_libraries(${PROJECT_NAME} PUBLIC tracy)
	message("== ${PROJECT_NAME} - Profiling enabled.")
else()
	target_compile_definitions(${PROJECT_NAME} PUBLIC OFS_PROFILE_ENABLED=0)
endif()


if(WIN32)
	target_include_directories(${PROJECT_NAME} PUBLIC 
		"../lib/libmpv/include"
	)
	target_compile_definitions(${PROJECT_NAME} PUBLIC
		"NOMINMAX"
	)
elseif(UNIX AND NOT APPLE AND NOT EMSCRIPTEN)
	# linux etc. 
	find_package(PkgConfig REQUIRED) 
	pkg_check_modules(mpv REQUIRED IMPORTED_TARGET mpv)
	
	# mpv is required for the headers
	# but not linked
	# instead libmpv.so.1 is loaded at runtime
	# this avoids linking issues with mpv and lua symbols
elseif(APPLE)
	# libmpv is loaded at runtime. The headers are required to compile, while
	# an optional discovered dylib path is passed to the runtime loader.
	set(OFS_MPV_ROOT "" CACHE PATH "Root directory of a libmpv installation")

	find_path(MPV_INCLUDE_DIR
		NAMES mpv/client.h
		DOC "Directory containing mpv/client.h"
		HINTS
			"${OFS_MPV_ROOT}/include"
			"/opt/homebrew/include"
			"/usr/local/include"
			"${CMAKE_SOURCE_DIR}/lib/libmpv/include"
		PATH_SUFFIXES include
	)
	if (NOT MPV_INCLUDE_DIR)
		message(FATAL_ERROR "libmpv headers were not found. Set MPV_INCLUDE_DIR or OFS_MPV_ROOT.")
	endif()

	find_file(MPV_LIBRARY
		NAMES libmpv.dylib
		DOC "Path to the libmpv dylib"
		HINTS
			"${OFS_MPV_ROOT}/lib"
			"${OFS_MPV_ROOT}/opt/mpv/lib"
			"/opt/homebrew/lib"
			"/opt/homebrew/opt/mpv/lib"
			"/usr/local/lib"
			"/usr/local/opt/mpv/lib"
		PATH_SUFFIXES lib
	)
	if (MPV_LIBRARY)
		message(STATUS "Found libmpv at ${MPV_LIBRARY}")
		# Keep the discovered path available to sibling directories. The runtime
		# loader still receives the developer path as a fallback, while src/ uses
		# this value as the seed for the optional app-bundle dependency graph.
		set(OFS_MPV_LIBRARY "${MPV_LIBRARY}" CACHE INTERNAL
			"Discovered macOS libmpv dylib used for optional app bundling" FORCE)
		target_compile_definitions(${PROJECT_NAME} PUBLIC
			"OFS_MPV_LIBRARY_PATH=\"${MPV_LIBRARY}\""
		)
	else()
		message(STATUS "libmpv dylib not found at configure time; runtime fallback paths will be tried")
		set(OFS_MPV_LIBRARY "" CACHE INTERNAL
			"Discovered macOS libmpv dylib used for optional app bundling" FORCE)
	endif()
	target_include_directories(${PROJECT_NAME} PUBLIC
		"${MPV_INCLUDE_DIR}"
	)

	find_library(OFS_APPKIT_FRAMEWORK AppKit REQUIRED)
	target_link_libraries(${PROJECT_NAME} PUBLIC "${OFS_APPKIT_FRAMEWORK}")
endif()
