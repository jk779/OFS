# Inspect direct build providers before Makefile targets clean any app artifacts.

cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/VerifyMacOSDeploymentTarget.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/MacOSDependencyGraph.cmake")

find_program(OFS_OTOOL otool)
if(NOT OFS_OTOOL)
	message(FATAL_ERROR "otool is required to inspect the Homebrew provider dependency graph")
endif()

if(NOT DEFINED OFS_MACOS_DEPLOYMENT_TARGET OR
	OFS_MACOS_DEPLOYMENT_TARGET STREQUAL "")
	message(FATAL_ERROR "OFS_MACOS_DEPLOYMENT_TARGET must be set for the provider preflight")
endif()

if(NOT DEFINED OFS_MPV_ROOT OR OFS_MPV_ROOT STREQUAL "")
	message(FATAL_ERROR "OFS_MPV_ROOT must name the libmpv provider for the provider preflight")
endif()

find_file(OFS_PREFLIGHT_MPV_LIBRARY
	NAMES libmpv.dylib
	HINTS "${OFS_MPV_ROOT}/lib" "${OFS_MPV_ROOT}/opt/mpv/lib"
	NO_DEFAULT_PATH
	PATH_SUFFIXES lib)
if(NOT OFS_PREFLIGHT_MPV_LIBRARY)
	message(FATAL_ERROR
		"Could not find libmpv.dylib using only OFS_MPV_ROOT=${OFS_MPV_ROOT}; prepare the pinned macOS 26 bottles first")
endif()

set(OFS_PREFLIGHT_FFMPEG_EXECUTABLE "${OFS_FFMPEG_EXECUTABLE}")
if(NOT OFS_PREFLIGHT_FFMPEG_EXECUTABLE OR
	NOT EXISTS "${OFS_PREFLIGHT_FFMPEG_EXECUTABLE}")
	message(FATAL_ERROR
		"The configured ffmpeg executable is missing: ${OFS_PREFLIGHT_FFMPEG_EXECUTABLE}; prepare the pinned macOS 26 bottles first")
endif()

if(NOT DEFINED OFS_APP_EXECUTABLE OR "${OFS_APP_EXECUTABLE}" STREQUAL "")
	message(FATAL_ERROR "OFS_APP_EXECUTABLE must be provided to resolve @executable_path dependencies")
endif()

get_filename_component(OFS_PREFLIGHT_MPV_LIBRARY_REAL "${OFS_PREFLIGHT_MPV_LIBRARY}" REALPATH)
get_filename_component(OFS_PREFLIGHT_FFMPEG_REAL "${OFS_PREFLIGHT_FFMPEG_EXECUTABLE}" REALPATH)
get_filename_component(OFS_PREFLIGHT_APP_EXECUTABLE_DIR "${OFS_APP_EXECUTABLE}" DIRECTORY)
get_filename_component(OFS_PREFLIGHT_FFMPEG_DIR "${OFS_PREFLIGHT_FFMPEG_REAL}" DIRECTORY)

ofs_verify_macos_binary_deployment_target(
	"${OFS_PREFLIGHT_MPV_LIBRARY_REAL}" "${OFS_MACOS_DEPLOYMENT_TARGET}")
ofs_verify_macos_binary_deployment_target(
	"${OFS_PREFLIGHT_FFMPEG_REAL}" "${OFS_MACOS_DEPLOYMENT_TARGET}")

# Traverse the same two Mach-O load graphs that the app bundler consumes, so a
# bad transitive bottle is rejected before Makefile targets clean the app.
set(preflight_sources
	"${OFS_PREFLIGHT_MPV_LIBRARY_REAL}"
	"${OFS_PREFLIGHT_FFMPEG_REAL}")
set(preflight_executable_dirs
	"${OFS_PREFLIGHT_APP_EXECUTABLE_DIR}"
	"${OFS_PREFLIGHT_FFMPEG_DIR}")
set(preflight_visited "")
foreach(root_index RANGE 0 1)
	list(GET preflight_sources ${root_index} preflight_root)
	list(GET preflight_executable_dirs ${root_index} preflight_root_executable_dir)
	list(APPEND preflight_visited
		"${preflight_root}|${preflight_root_executable_dir}")
endforeach()
set(preflight_index 0)
while(TRUE)
	list(LENGTH preflight_sources preflight_source_count)
	if(preflight_index GREATER_EQUAL preflight_source_count)
		break()
	endif()
	list(GET preflight_sources ${preflight_index} preflight_source)
	list(GET preflight_executable_dirs ${preflight_index} preflight_executable_dir)
	ofs_read_dependencies("${preflight_source}" preflight_dependencies)
	foreach(dependency IN LISTS preflight_dependencies)
		ofs_is_system_path("${dependency}" dependency_is_system)
		if(dependency_is_system)
			continue()
		endif()
		ofs_resolve_dependency("${dependency}" "${preflight_source}"
			resolved_dependency "${preflight_executable_dir}")
		if(resolved_dependency STREQUAL "")
			message(FATAL_ERROR
				"Could not resolve non-system dependency ${dependency} of ${preflight_source} using only the staged providers")
		endif()
		set(resolved_key "${resolved_dependency}|${preflight_executable_dir}")
		list(FIND preflight_visited "${resolved_key}" resolved_visited_index)
		if(resolved_visited_index LESS 0)
			ofs_verify_macos_binary_deployment_target(
				"${resolved_dependency}" "${OFS_MACOS_DEPLOYMENT_TARGET}")
			list(APPEND preflight_visited "${resolved_key}")
			list(APPEND preflight_sources "${resolved_dependency}")
			list(APPEND preflight_executable_dirs "${preflight_executable_dir}")
		endif()
	endforeach()
	math(EXPR preflight_index "${preflight_index} + 1")
endwhile()
