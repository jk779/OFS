project(OpenFunscripter)

set(OPEN_FUNSCRIPTER_SOURCES
  "main.cpp"
  "OpenFunscripter.cpp"
  "OFS_ScriptingMode.cpp"
  "OFS_Project.cpp"
  
  "OFS_UndoSystem.cpp"

  "UI/OFS_Preferences.cpp"
  "UI/OFS_ScriptSimulator.cpp"
  "UI/OFS_SpecialFunctions.cpp"
  "UI/OFS_ScriptPositionsOverlays.cpp"
  "UI/OFS_DownloadFfmpeg.cpp"
  "UI/OFS_FunscriptMetadataEditor.cpp"
  "UI/OFS_ChapterManager.cpp"

  "api/OFS_WebsocketApi.cpp"
  "api/OFS_WebsocketApiClient.cpp"
  "api/OFS_WebsocketApiEvents.cpp"
  "api/OFS_WebsocketApiCommands.cpp"

  "gl/OFS_GPU.cpp"

  "state/OpenFunscripterState.cpp"

  "lua/OFS_LuaExtensions.cpp"
  "lua/OFS_LuaExtension.cpp"
  "lua/OFS_LuaCoreExtension.cpp"
  "lua/OFS_LuaExtensionAPI.cpp"
  "lua/api/OFS_LuaPlayerAPI.cpp"
  "lua/api/OFS_LuaImGuiAPI.cpp"
  "lua/api/OFS_LuaScriptAPI.cpp"
  "lua/api/OFS_LuaProcessAPI.cpp"
)

if(WIN32)
	set(OPEN_FUNSCRIPTER_SOURCES ${OPEN_FUNSCRIPTER_SOURCES} "../icon.rc")
endif()

if(APPLE)
	add_executable(${PROJECT_NAME} MACOSX_BUNDLE ${OPEN_FUNSCRIPTER_SOURCES})
elseif(WIN32)
	add_executable(${PROJECT_NAME} WIN32 ${OPEN_FUNSCRIPTER_SOURCES})
else()
	add_executable(${PROJECT_NAME} ${OPEN_FUNSCRIPTER_SOURCES})
endif()

if(APPLE)
	set(OFS_MACOS_ICON_SOURCE "${CMAKE_SOURCE_DIR}/OpenFunScripter.icon")
	set(OFS_MACOS_ICON_NAME "OpenFunScripter")
	set(OFS_MACOS_ICON_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/macos-icon-assets")
	set(OFS_MACOS_ICON_ASSETS_CAR "${OFS_MACOS_ICON_OUTPUT_DIR}/Assets.car")
	set(OFS_MACOS_ICON_FALLBACK "${OFS_MACOS_ICON_OUTPUT_DIR}/${OFS_MACOS_ICON_NAME}.icns")
	set(OFS_MACOS_ICON_PARTIAL_PLIST "${OFS_MACOS_ICON_OUTPUT_DIR}/icon-info.plist")
	set(OFS_MACOS_ICON_BUNDLE_RESOURCES "$<TARGET_BUNDLE_DIR:${PROJECT_NAME}>/Contents/Resources")
	set(OFS_MACOS_ICON_BUNDLE_INFO_PLIST "$<TARGET_BUNDLE_DIR:${PROJECT_NAME}>/Contents/Info.plist")

	if(NOT EXISTS "${OFS_MACOS_ICON_SOURCE}/icon.json")
		message(FATAL_ERROR "Icon Composer source is missing: ${OFS_MACOS_ICON_SOURCE}/icon.json")
	endif()

	# Watch the whole Icon Composer package so edits and newly added assets
	# trigger CMake regeneration and then rerun actool.
	file(GLOB_RECURSE OFS_MACOS_ICON_INPUTS CONFIGURE_DEPENDS
		LIST_DIRECTORIES FALSE
		"${OFS_MACOS_ICON_SOURCE}/*")

	find_program(OFS_XCRUN_EXECUTABLE xcrun)
	if(NOT OFS_XCRUN_EXECUTABLE)
		message(FATAL_ERROR "xcrun is required to compile the macOS Icon Composer source")
	endif()
	find_program(OFS_PLISTBUDDY_EXECUTABLE PlistBuddy
		PATHS /usr/libexec NO_DEFAULT_PATH)
	if(NOT OFS_PLISTBUDDY_EXECUTABLE)
		message(FATAL_ERROR "macOS PlistBuddy is required to merge actool icon metadata")
	endif()

	if(CMAKE_OSX_DEPLOYMENT_TARGET)
		set(OFS_MACOS_ICON_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}")
	else()
		# Clang defaults the deployment target to the selected macOS SDK when no
		# explicit target is configured. Match that existing build behavior.
		execute_process(
			COMMAND "${OFS_XCRUN_EXECUTABLE}" --sdk macosx --show-sdk-version
			OUTPUT_VARIABLE OFS_MACOS_ICON_DEPLOYMENT_TARGET
			RESULT_VARIABLE OFS_MACOS_SDK_VERSION_RESULT
			OUTPUT_STRIP_TRAILING_WHITESPACE)
		if(NOT OFS_MACOS_SDK_VERSION_RESULT EQUAL 0 OR
			NOT OFS_MACOS_ICON_DEPLOYMENT_TARGET MATCHES "^[0-9]+(\\.[0-9]+)*$")
			message(FATAL_ERROR
				"Could not determine the selected macOS SDK version for actool deployment target")
		endif()
	endif()

	add_custom_command(
		OUTPUT
			"${OFS_MACOS_ICON_ASSETS_CAR}"
			"${OFS_MACOS_ICON_FALLBACK}"
			"${OFS_MACOS_ICON_PARTIAL_PLIST}"
		COMMAND "${CMAKE_COMMAND}" -E make_directory "${OFS_MACOS_ICON_OUTPUT_DIR}"
		COMMAND "${OFS_XCRUN_EXECUTABLE}" actool "${OFS_MACOS_ICON_SOURCE}"
			--compile "${OFS_MACOS_ICON_OUTPUT_DIR}"
			--app-icon "${OFS_MACOS_ICON_NAME}"
			--include-all-app-icons
			--target-device mac
			--platform macosx
			--minimum-deployment-target "${OFS_MACOS_ICON_DEPLOYMENT_TARGET}"
			--standalone-icon-behavior all
			--output-partial-info-plist "${OFS_MACOS_ICON_PARTIAL_PLIST}"
		DEPENDS ${OFS_MACOS_ICON_INPUTS}
		COMMENT "Compiling the OpenFunscripter Icon Composer source"
		VERBATIM)

	# Install the generated catalog and fallback after the app bundle exists,
	# then merge actool's plist additions without replacing CMake's other keys.
	add_custom_target(OFS_macos_icon_resources ALL
		COMMAND "${CMAKE_COMMAND}" -E make_directory "${OFS_MACOS_ICON_BUNDLE_RESOURCES}"
		COMMAND "${CMAKE_COMMAND}" -E copy_if_different
			"${OFS_MACOS_ICON_ASSETS_CAR}" "${OFS_MACOS_ICON_BUNDLE_RESOURCES}/Assets.car"
		COMMAND "${CMAKE_COMMAND}" -E copy_if_different
			"${OFS_MACOS_ICON_FALLBACK}"
			"${OFS_MACOS_ICON_BUNDLE_RESOURCES}/${OFS_MACOS_ICON_NAME}.icns"
		COMMAND "${OFS_PLISTBUDDY_EXECUTABLE}"
			-c "Merge \"${OFS_MACOS_ICON_PARTIAL_PLIST}\""
			"${OFS_MACOS_ICON_BUNDLE_INFO_PLIST}"
		DEPENDS
			"${OFS_MACOS_ICON_ASSETS_CAR}"
			"${OFS_MACOS_ICON_FALLBACK}"
			"${OFS_MACOS_ICON_PARTIAL_PLIST}"
		VERBATIM)
	add_dependencies(OFS_macos_icon_resources ${PROJECT_NAME})

	target_compile_definitions(${PROJECT_NAME} PRIVATE
		"OFS_MACOS_DISPLAY_TITLE=\"OpenFunscripter v3.2.0 — macOS build v1.0.0\"")

	set_target_properties(${PROJECT_NAME} PROPERTIES
		MACOSX_BUNDLE_BUNDLE_NAME "OpenFunscripter"
		MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.jk779.OpenFunscripter"
		MACOSX_BUNDLE_BUNDLE_VERSION "320.1"
		MACOSX_BUNDLE_SHORT_VERSION_STRING "3.2.0"
		MACOSX_BUNDLE_INFO_STRING "OpenFunscripter v3.2.0 — macOS build v1.0.0"
		MACOSX_BUNDLE_ICON_FILE "${OFS_MACOS_ICON_NAME}.icns"
	)
endif()

target_include_directories(${PROJECT_NAME} PUBLIC ${PROJECT_SOURCE_DIR})

# copy data directory
if(APPLE)
	add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
						COMMAND ${CMAKE_COMMAND} -E make_directory
						"$<TARGET_FILE_DIR:${PROJECT_NAME}>/../Resources"
						COMMAND ${CMAKE_COMMAND} -E copy_directory
						"${CMAKE_SOURCE_DIR}/data/" "$<TARGET_FILE_DIR:${PROJECT_NAME}>/../Resources/data")
else()
	add_custom_command(TARGET ${PROJECT_NAME} PRE_BUILD
						COMMAND ${CMAKE_COMMAND} -E copy_directory
						"${CMAKE_SOURCE_DIR}/data/" "$<TARGET_FILE_DIR:${PROJECT_NAME}>/data")
endif()

if(APPLE)
	if(OFS_BUNDLE_MACOS_LIBMPV AND NOT OFS_MPV_LIBRARY)
		message(FATAL_ERROR
			"OFS_BUNDLE_MACOS_LIBMPV is enabled, but no libmpv.dylib was discovered. "
			"Set OFS_MPV_ROOT or disable OFS_BUNDLE_MACOS_LIBMPV.")
	endif()
	if(OFS_BUNDLE_MACOS_LIBMPV AND NOT OFS_FFMPEG_EXECUTABLE)
		message(FATAL_ERROR
			"OFS_BUNDLE_MACOS_LIBMPV is enabled, but no ffmpeg executable was discovered. "
			"Put ffmpeg on PATH or set OFS_FFMPEG_EXECUTABLE.")
	endif()

	# This is intentionally an always-run target. The Homebrew dependency graph
	# and the existing app bundle are external to CMake's timestamp graph, so a
	# stamp can leave stale dylibs or an old Frameworks rpath behind.
	add_custom_target(OFS_macos_bundle_libmpv ALL
		COMMAND ${CMAKE_COMMAND}
			"-DOFS_APP_EXECUTABLE=$<TARGET_FILE:${PROJECT_NAME}>"
			"-DOFS_MACOS_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}"
			"-DOFS_BREW_PREFIX=${OFS_BREW_PREFIX}"
			"-DOFS_BUNDLE_ENABLED=${OFS_BUNDLE_MACOS_LIBMPV}"
			"-DOFS_MPV_LIBRARY=${OFS_MPV_LIBRARY}"
			"-DOFS_FFMPEG_EXECUTABLE=${OFS_FFMPEG_EXECUTABLE}"
			"-DOFS_ADHOC_SIGN=${OFS_MACOS_ADHOC_SIGN}"
			-P "${CMAKE_SOURCE_DIR}/cmake/BundleMacOSDependencies.cmake"
		DEPENDS
			${PROJECT_NAME}
			"${CMAKE_SOURCE_DIR}/cmake/BundleMacOSDependencies.cmake"
			"${CMAKE_SOURCE_DIR}/cmake/MacOSDependencyGraph.cmake"
		VERBATIM)
	add_dependencies(OFS_macos_bundle_libmpv OFS_macos_icon_resources)
endif()


target_link_libraries(${PROJECT_NAME} PUBLIC
  lua
  sol2
  OFS_lib
  civetweb
)

if(WIN32)
  # download mpv binaries
  if (NOT EXISTS "${CMAKE_BINARY_DIR}/mpv-2.dll")
    file(DOWNLOAD "https://www.7-zip.org/a/7zr.exe" "7zr.exe" SHOW_PROGRESS)
    file(DOWNLOAD "https://sourceforge.net/projects/mpv-player-windows/files/libmpv/mpv-dev-x86_64-v3-20220925-git-56e24d5.7z/download" "mpv-dev.7z" SHOW_PROGRESS)
    add_custom_command(TARGET ${PROJECT_NAME} PRE_BUILD
        COMMAND "${CMAKE_BINARY_DIR}/7zr.exe" "x" "-y" "mpv-dev.7z" "mpv-2.dll" 
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        BYPRODUCTS "${CMAKE_BINARY_DIR}/mpv-2.dll"
        DEPENDS "${CMAKE_BINARY_DIR}/mpv-dev.7z")    
  endif()

	# copy mpv-2.dll to bin dir
	add_custom_command(TARGET ${PROJECT_NAME} PRE_BUILD
                   COMMAND ${CMAKE_COMMAND} -E copy
                   "${CMAKE_BINARY_DIR}/mpv-2.dll" "$<TARGET_FILE_DIR:${PROJECT_NAME}>/mpv-2.dll"
				   DEPENDS "${CMAKE_BINARY_DIR}/mpv-2.dll")
endif()

target_compile_definitions(${PROJECT_NAME} PUBLIC
	"_CRT_SECURE_NO_WARNINGS"
)

target_include_directories(${PROJECT_NAME} PRIVATE 
	"${PROJECT_SOURCE_DIR}/"
	"${PROJECT_SOURCE_DIR}/UI/"
	"${PROJECT_SOURCE_DIR}/Funscript/"
	"${PROJECT_SOURCE_DIR}/gl/"
	"${PROJECT_SOURCE_DIR}/event/"
	"${PROJECT_SOURCE_DIR}/lua/"
	"${PROJECT_SOURCE_DIR}/api/"
)

# c++17
target_compile_features(${PROJECT_NAME} PUBLIC cxx_std_17)

if(WIN32)
	if(CMAKE_BUILD_TYPE MATCHES "Release" OR CMAKE_BUILD_TYPE MATCHES "RelWithDebInfo") 
		target_compile_options(${PROJECT_NAME} PUBLIC /GL)
		target_link_options(${PROJECT_NAME} PUBLIC /LTCG)
		message("== ${PROJECT_NAME} - Whole program optimization enabled.")
	endif()
elseif(UNIX AND NOT APPLE) # clang/gcc
    target_compile_options(${PROJECT_NAME} PUBLIC -fpermissive)
	install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION "bin/")
elseif(APPLE)
	target_compile_options(${PROJECT_NAME} PUBLIC -fpermissive)
	# Note Mac specific extension .app
	set(APPS "\${CMAKE_INSTALL_PREFIX}/${PROJECT_NAME}.app")
endif()


if(OFS_SNAP_IMAGE)
# this is awful
target_compile_definitions(${PROJECT_NAME} PRIVATE
	"OFS_SNAP_IMAGE")
install(DIRECTORY "../data" DESTINATION "bin/")
endif()
