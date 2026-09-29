# Bundle libmpv and ffmpeg, plus their non-system dylib dependencies, into an
# OpenFunscripter.app bundle.

cmake_minimum_required(VERSION 3.16)

if(NOT APPLE)
	message(FATAL_ERROR "BundleMacOSDependencies.cmake is only supported on macOS")
endif()

if(NOT DEFINED OFS_BUNDLE_ENABLED)
	set(OFS_BUNDLE_ENABLED ON)
endif()

foreach(_required_var OFS_APP_EXECUTABLE)
	if(NOT DEFINED ${_required_var} OR "${${_required_var}}" STREQUAL "")
		message(FATAL_ERROR "${_required_var} is required")
	endif()
endforeach()
if(NOT DEFINED OFS_MACOS_DEPLOYMENT_TARGET OR
	"${OFS_MACOS_DEPLOYMENT_TARGET}" STREQUAL "")
	message(FATAL_ERROR
		"OFS_MACOS_DEPLOYMENT_TARGET is required to validate the app bundle")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/VerifyMacOSDeploymentTarget.cmake")

if(OFS_BUNDLE_ENABLED AND (NOT DEFINED OFS_MPV_LIBRARY
	OR "${OFS_MPV_LIBRARY}" STREQUAL ""))
	message(FATAL_ERROR "OFS_MPV_LIBRARY is required when OFS_BUNDLE_ENABLED is enabled")
endif()
if(OFS_BUNDLE_ENABLED AND (NOT DEFINED OFS_FFMPEG_EXECUTABLE
	OR "${OFS_FFMPEG_EXECUTABLE}" STREQUAL ""))
	message(FATAL_ERROR "OFS_FFMPEG_EXECUTABLE is required when OFS_BUNDLE_ENABLED is enabled")
endif()

if(NOT DEFINED OFS_ADHOC_SIGN)
	set(OFS_ADHOC_SIGN ON)
endif()

find_program(OFS_OTOOL otool REQUIRED)
find_program(OFS_INSTALL_NAME_TOOL install_name_tool REQUIRED)
include("${CMAKE_CURRENT_LIST_DIR}/MacOSDependencyGraph.cmake")
if(OFS_ADHOC_SIGN)
	find_program(OFS_CODESIGN codesign REQUIRED)
else()
	find_program(OFS_CODESIGN codesign)
endif()

if(NOT EXISTS "${OFS_APP_EXECUTABLE}")
	message(FATAL_ERROR "App executable does not exist: ${OFS_APP_EXECUTABLE}")
endif()
if(OFS_BUNDLE_ENABLED AND NOT EXISTS "${OFS_MPV_LIBRARY}")
	message(FATAL_ERROR "libmpv does not exist: ${OFS_MPV_LIBRARY}")
endif()
if(OFS_BUNDLE_ENABLED AND NOT EXISTS "${OFS_FFMPEG_EXECUTABLE}")
	message(FATAL_ERROR "ffmpeg does not exist: ${OFS_FFMPEG_EXECUTABLE}")
endif()

if(OFS_BUNDLE_ENABLED)
	get_filename_component(OFS_MPV_LIBRARY_REAL "${OFS_MPV_LIBRARY}" REALPATH)
	get_filename_component(OFS_FFMPEG_EXECUTABLE_REAL "${OFS_FFMPEG_EXECUTABLE}" REALPATH)
endif()
get_filename_component(OFS_APP_MACOS_DIR "${OFS_APP_EXECUTABLE}" DIRECTORY)
get_filename_component(OFS_APP_CONTENTS_DIR "${OFS_APP_MACOS_DIR}" DIRECTORY)
get_filename_component(OFS_APP_BUNDLE "${OFS_APP_CONTENTS_DIR}" DIRECTORY)
set(OFS_FRAMEWORKS_DIR "${OFS_APP_CONTENTS_DIR}/Frameworks")
set(OFS_HELPERS_DIR "${OFS_APP_CONTENTS_DIR}/Helpers")
set(OFS_FFMPEG_HELPER "${OFS_HELPERS_DIR}/ffmpeg")

find_program(OFS_PLISTBUDDY_EXECUTABLE PlistBuddy
	PATHS /usr/libexec NO_DEFAULT_PATH)
if(NOT OFS_PLISTBUDDY_EXECUTABLE)
	message(FATAL_ERROR "macOS PlistBuddy is required to set bundle minimum version metadata")
endif()

if(NOT IS_DIRECTORY "${OFS_APP_BUNDLE}")
	message(FATAL_ERROR "App bundle directory does not exist: ${OFS_APP_BUNDLE}")
endif()

# The global properties form a small source-to-bundle-name table. A real file
# may be reached through several install names; the first chosen bundle name
# is reused. A name reached from two different real files is an error because
# silently replacing one dylib would leave a non-deterministic bundle.
set_property(GLOBAL PROPERTY OFS_BUNDLE_SOURCES "")
set_property(GLOBAL PROPERTY OFS_BUNDLE_NAMES "")
set_property(GLOBAL PROPERTY OFS_BUNDLE_EXECUTABLE_DIRS "")

function(ofs_add_bundle_file source requested_name output_name)
	if(ARGC GREATER 3)
		set(executable_dir "${ARGV3}")
	else()
		set(executable_dir "${OFS_APP_MACOS_DIR}")
	endif()
	if(NOT EXISTS "${source}")
		message(FATAL_ERROR "Dependency does not exist: ${source}")
	endif()

	get_filename_component(real_source "${source}" REALPATH)
	get_property(sources GLOBAL PROPERTY OFS_BUNDLE_SOURCES)
	get_property(names GLOBAL PROPERTY OFS_BUNDLE_NAMES)

	list(FIND sources "${real_source}" source_index)
	if(source_index GREATER_EQUAL 0)
		list(GET names ${source_index} existing_name)
		set(${output_name} "${existing_name}" PARENT_SCOPE)
		return()
	endif()

	list(FIND names "${requested_name}" name_index)
	if(name_index GREATER_EQUAL 0)
		list(GET sources ${name_index} existing_source)
		message(FATAL_ERROR
			"Dylib basename collision for ${requested_name}:\n"
			"  ${existing_source}\n"
			"  ${real_source}")
	endif()

	list(APPEND sources "${real_source}")
	list(APPEND names "${requested_name}")
	get_property(executable_dirs GLOBAL PROPERTY OFS_BUNDLE_EXECUTABLE_DIRS)
	list(APPEND executable_dirs "${executable_dir}")
	set_property(GLOBAL PROPERTY OFS_BUNDLE_SOURCES "${sources}")
	set_property(GLOBAL PROPERTY OFS_BUNDLE_NAMES "${names}")
	set_property(GLOBAL PROPERTY OFS_BUNDLE_EXECUTABLE_DIRS "${executable_dirs}")
	set(${output_name} "${requested_name}" PARENT_SCOPE)
endfunction()

function(ofs_get_bundle_name source output)
	get_filename_component(real_source "${source}" REALPATH)
	get_property(sources GLOBAL PROPERTY OFS_BUNDLE_SOURCES)
	get_property(names GLOBAL PROPERTY OFS_BUNDLE_NAMES)
	list(FIND sources "${real_source}" source_index)
	if(source_index LESS 0)
		message(FATAL_ERROR "No bundle name was assigned to ${real_source}")
	endif()
	list(GET names ${source_index} bundle_name)
	set(${output} "${bundle_name}" PARENT_SCOPE)
endfunction()

function(ofs_get_bundle_executable_dir source output)
	get_filename_component(real_source "${source}" REALPATH)
	get_property(sources GLOBAL PROPERTY OFS_BUNDLE_SOURCES)
	get_property(executable_dirs GLOBAL PROPERTY OFS_BUNDLE_EXECUTABLE_DIRS)
	list(FIND sources "${real_source}" source_index)
	if(source_index LESS 0)
		message(FATAL_ERROR "No bundle executable context was assigned to ${real_source}")
	endif()
	list(GET executable_dirs ${source_index} executable_dir)
	set(${output} "${executable_dir}" PARENT_SCOPE)
endfunction()

function(ofs_install_name_tool binary)
	set(arguments ${ARGN})
	execute_process(
		COMMAND "${OFS_INSTALL_NAME_TOOL}" ${arguments} "${binary}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE output
		ERROR_VARIABLE error_output)
	if(NOT result EQUAL 0)
		message(FATAL_ERROR
			"install_name_tool failed for ${binary}: ${error_output}${output}")
	endif()
endfunction()

function(ofs_verify_no_external_homebrew_load_references binary)
	foreach(option IN ITEMS -L -l)
		execute_process(
			COMMAND "${OFS_OTOOL}" "${option}" "${binary}"
			RESULT_VARIABLE result
			OUTPUT_VARIABLE listing
			ERROR_VARIABLE error_output)
		if(NOT result EQUAL 0)
			message(FATAL_ERROR "otool ${option} failed for ${binary}: ${error_output}")
		endif()
		if(listing MATCHES "/opt/homebrew/|/usr/local/")
			message(FATAL_ERROR
				"The bundled Mach-O still references an external Homebrew path: ${binary}")
		endif()
	endforeach()
endfunction()

function(ofs_remove_signature target)
	if(NOT OFS_CODESIGN OR NOT EXISTS "${target}")
		return()
	endif()

	execute_process(
		COMMAND "${OFS_CODESIGN}" --remove-signature "${target}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE output
		ERROR_VARIABLE error_output)
	if(NOT result EQUAL 0)
		string(TOLOWER "${error_output}${output}" signature_error)
		if(NOT signature_error MATCHES "not signed")
			message(FATAL_ERROR
				"Removing the existing code signature failed for ${target}: "
				"${error_output}${output}")
		endif()
	endif()
endfunction()

# install_name_tool cannot safely update a signed executable. Remove any
# previous signature before changing its load commands; the final signing
# state is restored below according to OFS_ADHOC_SIGN.
ofs_remove_signature("${OFS_APP_EXECUTABLE}")
ofs_remove_signature("${OFS_APP_BUNDLE}")

set(OFS_APP_INFO_PLIST "${OFS_APP_CONTENTS_DIR}/Info.plist")
execute_process(
	COMMAND "${OFS_PLISTBUDDY_EXECUTABLE}"
		-c "Set :LSMinimumSystemVersion ${OFS_MACOS_DEPLOYMENT_TARGET}"
		"${OFS_APP_INFO_PLIST}"
	RESULT_VARIABLE plist_set_result
	OUTPUT_VARIABLE plist_set_output
	ERROR_VARIABLE plist_set_error)
if(NOT plist_set_result EQUAL 0)
	execute_process(
		COMMAND "${OFS_PLISTBUDDY_EXECUTABLE}"
			-c "Add :LSMinimumSystemVersion string ${OFS_MACOS_DEPLOYMENT_TARGET}"
			"${OFS_APP_INFO_PLIST}"
		RESULT_VARIABLE plist_add_result
		OUTPUT_VARIABLE plist_add_output
		ERROR_VARIABLE plist_add_error)
	if(NOT plist_add_result EQUAL 0)
		message(FATAL_ERROR
			"Could not set LSMinimumSystemVersion in ${OFS_APP_INFO_PLIST}: "
			"${plist_set_error}${plist_set_output}${plist_add_error}${plist_add_output}")
	endif()
endif()
execute_process(
	COMMAND "${OFS_PLISTBUDDY_EXECUTABLE}"
		-c "Print :LSMinimumSystemVersion"
		"${OFS_APP_INFO_PLIST}"
	RESULT_VARIABLE plist_read_result
	OUTPUT_VARIABLE plist_minimum_version
	ERROR_VARIABLE plist_read_error
	OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT plist_read_result EQUAL 0 OR
	NOT plist_minimum_version STREQUAL "${OFS_MACOS_DEPLOYMENT_TARGET}")
	message(FATAL_ERROR
		"${OFS_APP_INFO_PLIST} must declare LSMinimumSystemVersion="
		"${OFS_MACOS_DEPLOYMENT_TARGET}: ${plist_read_error}${plist_minimum_version}")
endif()

if(NOT OFS_BUNDLE_ENABLED)
	# The output bundle is shared between CMake configurations. Explicitly
	# clean artifacts from an earlier ON build so OFF is effective on reuse.
	if(EXISTS "${OFS_FRAMEWORKS_DIR}" OR IS_SYMLINK "${OFS_FRAMEWORKS_DIR}")
		file(REMOVE_RECURSE "${OFS_FRAMEWORKS_DIR}")
	endif()
	if(EXISTS "${OFS_FFMPEG_HELPER}" OR IS_SYMLINK "${OFS_FFMPEG_HELPER}")
		file(REMOVE "${OFS_FFMPEG_HELPER}")
	endif()

	ofs_read_rpaths("${OFS_APP_EXECUTABLE}" app_rpaths)
	list(FIND app_rpaths "@executable_path/../Frameworks" app_frameworks_rpath_index)
	if(app_frameworks_rpath_index GREATER_EQUAL 0)
		ofs_install_name_tool("${OFS_APP_EXECUTABLE}"
			-delete_rpath "@executable_path/../Frameworks")
	endif()

	if(OFS_ADHOC_SIGN)
		execute_process(
			COMMAND "${OFS_CODESIGN}" --force --sign - --timestamp=none
				"${OFS_APP_BUNDLE}"
			RESULT_VARIABLE sign_result
			OUTPUT_VARIABLE sign_output
			ERROR_VARIABLE sign_error)
		if(NOT sign_result EQUAL 0)
			message(FATAL_ERROR
				"Ad-hoc signing failed for ${OFS_APP_BUNDLE}: "
				"${sign_error}${sign_output}")
		endif()
	endif()

	message(STATUS "macOS dependency bundling disabled; removed stale Frameworks, ffmpeg, and rpath")
	return()
endif()

# Seed the graph with the stable loader name expected inside the app bundle.
ofs_add_bundle_file("${OFS_MPV_LIBRARY_REAL}" "libmpv.dylib" OFS_MPV_BUNDLE_NAME
	"${OFS_APP_MACOS_DIR}")

set(graph_index 0)
while(TRUE)
	get_property(sources GLOBAL PROPERTY OFS_BUNDLE_SOURCES)
	list(LENGTH sources source_count)
	if(graph_index GREATER_EQUAL source_count)
		break()
	endif()
	list(GET sources ${graph_index} current_source)
	get_property(executable_dirs GLOBAL PROPERTY OFS_BUNDLE_EXECUTABLE_DIRS)
	list(GET executable_dirs ${graph_index} current_executable_dir)

	ofs_read_dependencies("${current_source}" dependencies)
	foreach(dependency IN LISTS dependencies)
		ofs_is_system_path("${dependency}" is_system)
		if(is_system)
			continue()
		endif()

		ofs_resolve_dependency("${dependency}" "${current_source}" resolved_dependency
			"${current_executable_dir}")
		if(resolved_dependency STREQUAL "")
			message(FATAL_ERROR
				"Could not resolve non-system dependency ${dependency} of ${current_source}")
		endif()
		ofs_is_system_path("${resolved_dependency}" resolved_is_system)
		if(resolved_is_system)
			continue()
		endif()

		get_filename_component(dependency_name "${dependency}" NAME)
		if(dependency_name STREQUAL "")
			message(FATAL_ERROR
				"Could not determine a bundle name for ${dependency} of ${current_source}")
		endif()
		ofs_add_bundle_file("${resolved_dependency}" "${dependency_name}" ignored_name
			"${current_executable_dir}")
	endforeach()

	math(EXPR graph_index "${graph_index} + 1")
endwhile()

# Walk ffmpeg's graph separately because @executable_path entries in its
# dylibs are relative to the ffmpeg binary, not OpenFunscripter's executable.
# The shared bundle-name table still detects basename collisions with libmpv.
get_filename_component(OFS_FFMPEG_EXECUTABLE_DIR "${OFS_FFMPEG_EXECUTABLE_REAL}" DIRECTORY)
set(ffmpeg_graph_sources "${OFS_FFMPEG_EXECUTABLE_REAL}")
set(ffmpeg_graph_index 0)
while(TRUE)
	list(LENGTH ffmpeg_graph_sources ffmpeg_graph_count)
	if(ffmpeg_graph_index GREATER_EQUAL ffmpeg_graph_count)
		break()
	endif()
	list(GET ffmpeg_graph_sources ${ffmpeg_graph_index} current_source)
	ofs_read_dependencies("${current_source}" dependencies)
	foreach(dependency IN LISTS dependencies)
		ofs_is_system_path("${dependency}" is_system)
		if(is_system)
			continue()
		endif()
		ofs_resolve_dependency("${dependency}" "${current_source}" resolved_dependency
			"${OFS_FFMPEG_EXECUTABLE_DIR}")
		if(resolved_dependency STREQUAL "")
			message(FATAL_ERROR
				"Could not resolve non-system dependency ${dependency} of ${current_source}")
		endif()
		ofs_is_system_path("${resolved_dependency}" resolved_is_system)
		if(resolved_is_system)
			continue()
		endif()
		get_filename_component(dependency_name "${dependency}" NAME)
		if(dependency_name STREQUAL "")
			message(FATAL_ERROR
				"Could not determine a bundle name for ${dependency} of ${current_source}")
		endif()
		ofs_add_bundle_file("${resolved_dependency}" "${dependency_name}" ignored_name
			"${OFS_FFMPEG_EXECUTABLE_DIR}")
		list(FIND ffmpeg_graph_sources "${resolved_dependency}" ffmpeg_dependency_index)
		if(ffmpeg_dependency_index LESS 0)
			list(APPEND ffmpeg_graph_sources "${resolved_dependency}")
		endif()
	endforeach()
	math(EXPR ffmpeg_graph_index "${ffmpeg_graph_index} + 1")
endwhile()

file(MAKE_DIRECTORY "${OFS_FRAMEWORKS_DIR}")
# Remove files from an earlier graph so a changed Homebrew installation cannot
# leave stale dylibs with old absolute references in an incremental bundle.
file(GLOB existing_bundle_entries RELATIVE "${OFS_FRAMEWORKS_DIR}" "${OFS_FRAMEWORKS_DIR}/*")
foreach(entry IN LISTS existing_bundle_entries)
	file(REMOVE_RECURSE "${OFS_FRAMEWORKS_DIR}/${entry}")
endforeach()

get_property(sources GLOBAL PROPERTY OFS_BUNDLE_SOURCES)
get_property(names GLOBAL PROPERTY OFS_BUNDLE_NAMES)
list(LENGTH sources source_count)
math(EXPR last_source_index "${source_count} - 1")
foreach(source_index RANGE 0 ${last_source_index})
	list(GET sources ${source_index} source)
	list(GET names ${source_index} bundle_name)
	set(destination "${OFS_FRAMEWORKS_DIR}/${bundle_name}")

	execute_process(
		COMMAND "${CMAKE_COMMAND}" -E copy_if_different
			"${source}" "${destination}"
		RESULT_VARIABLE copy_result
		ERROR_VARIABLE copy_error)
	if(NOT copy_result EQUAL 0)
		message(FATAL_ERROR "Could not copy ${source} to ${destination}: ${copy_error}")
	endif()
	execute_process(COMMAND chmod u+rw "${destination}")
endforeach()

file(MAKE_DIRECTORY "${OFS_HELPERS_DIR}")
execute_process(
	COMMAND "${CMAKE_COMMAND}" -E copy_if_different
		"${OFS_FFMPEG_EXECUTABLE_REAL}" "${OFS_FFMPEG_HELPER}"
	RESULT_VARIABLE ffmpeg_copy_result
	ERROR_VARIABLE ffmpeg_copy_error)
if(NOT ffmpeg_copy_result EQUAL 0)
	message(FATAL_ERROR
		"Could not copy ${OFS_FFMPEG_EXECUTABLE_REAL} to ${OFS_FFMPEG_HELPER}: ${ffmpeg_copy_error}")
endif()
execute_process(
	COMMAND chmod u+rw,u+x "${OFS_FFMPEG_HELPER}"
	RESULT_VARIABLE ffmpeg_chmod_result
	ERROR_VARIABLE ffmpeg_chmod_error)
if(NOT ffmpeg_chmod_result EQUAL 0)
	message(FATAL_ERROR "Could not make bundled ffmpeg executable: ${ffmpeg_chmod_error}")
endif()
ofs_remove_signature("${OFS_FFMPEG_HELPER}")

# Rewrite each copied dylib using the original source graph. This keeps the
# operation repeatable even though the destination files were already changed
# by install_name_tool during an earlier build.
foreach(source_index RANGE 0 ${last_source_index})
	list(GET sources ${source_index} source)
	list(GET names ${source_index} bundle_name)
	ofs_get_bundle_executable_dir("${source}" source_executable_dir)
	set(destination "${OFS_FRAMEWORKS_DIR}/${bundle_name}")
	set(install_arguments -id "@rpath/${bundle_name}")

	ofs_read_rpaths("${source}" source_rpaths)
	foreach(source_rpath IN LISTS source_rpaths)
		ofs_is_system_path("${source_rpath}" source_rpath_is_system)
		if(NOT source_rpath_is_system
			AND NOT source_rpath STREQUAL "@loader_path"
			AND NOT source_rpath STREQUAL "@executable_path/../Frameworks")
			list(APPEND install_arguments -delete_rpath "${source_rpath}")
		endif()
	endforeach()

	list(FIND source_rpaths "@loader_path" loader_rpath_index)
	if(loader_rpath_index LESS 0)
		list(APPEND install_arguments -add_rpath "@loader_path")
	endif()

	ofs_read_dependencies("${source}" dependencies)
	foreach(dependency IN LISTS dependencies)
		ofs_is_system_path("${dependency}" is_system)
		if(is_system)
			continue()
		endif()
		ofs_resolve_dependency("${dependency}" "${source}" resolved_dependency
			"${source_executable_dir}")
		if(resolved_dependency STREQUAL "")
			message(FATAL_ERROR
				"Could not resolve non-system dependency ${dependency} of ${source}")
		endif()
		ofs_is_system_path("${resolved_dependency}" resolved_is_system)
		if(resolved_is_system)
			continue()
		endif()
		ofs_get_bundle_name("${resolved_dependency}" resolved_name)
		list(APPEND install_arguments -change "${dependency}" "@rpath/${resolved_name}")
	endforeach()

	ofs_install_name_tool("${destination}" ${install_arguments})
endforeach()

# Give the bundled helper an rpath to Contents/Frameworks and rewrite its
# non-system dependencies to the dylib names in the shared bundle graph.
set(ffmpeg_install_arguments)
ofs_read_dependencies("${OFS_FFMPEG_EXECUTABLE_REAL}" ffmpeg_dependencies)
ofs_read_rpaths("${OFS_FFMPEG_EXECUTABLE_REAL}" ffmpeg_source_rpaths)
foreach(source_rpath IN LISTS ffmpeg_source_rpaths)
	ofs_is_system_path("${source_rpath}" source_rpath_is_system)
	if(NOT source_rpath_is_system
		AND NOT source_rpath STREQUAL "@executable_path/../Frameworks")
		list(APPEND ffmpeg_install_arguments -delete_rpath "${source_rpath}")
	endif()
endforeach()
list(FIND ffmpeg_source_rpaths "@executable_path/../Frameworks" ffmpeg_frameworks_rpath_index)
if(ffmpeg_frameworks_rpath_index LESS 0)
	list(APPEND ffmpeg_install_arguments -add_rpath "@executable_path/../Frameworks")
endif()

foreach(dependency IN LISTS ffmpeg_dependencies)
	ofs_is_system_path("${dependency}" is_system)
	if(is_system)
		continue()
	endif()
	ofs_resolve_dependency("${dependency}" "${OFS_FFMPEG_EXECUTABLE_REAL}" resolved_dependency
		"${OFS_FFMPEG_EXECUTABLE_DIR}")
	if(resolved_dependency STREQUAL "")
		message(FATAL_ERROR
			"Could not resolve non-system dependency ${dependency} of ${OFS_FFMPEG_EXECUTABLE_REAL}")
	endif()
	ofs_is_system_path("${resolved_dependency}" resolved_is_system)
	if(resolved_is_system)
		continue()
	endif()
	ofs_get_bundle_name("${resolved_dependency}" resolved_name)
	list(APPEND ffmpeg_install_arguments -change "${dependency}" "@rpath/${resolved_name}")
endforeach()
ofs_install_name_tool("${OFS_FFMPEG_HELPER}" ${ffmpeg_install_arguments})

ofs_read_rpaths("${OFS_APP_EXECUTABLE}" app_rpaths)
set(app_install_arguments)
foreach(app_rpath IN LISTS app_rpaths)
	ofs_is_system_path("${app_rpath}" app_rpath_is_system)
	if(NOT app_rpath_is_system
		AND NOT app_rpath STREQUAL "@executable_path/../Frameworks")
		list(APPEND app_install_arguments -delete_rpath "${app_rpath}")
	endif()
endforeach()
list(FIND app_rpaths "@executable_path/../Frameworks" app_frameworks_rpath_index)
if(app_frameworks_rpath_index LESS 0)
	list(APPEND app_install_arguments -add_rpath
		"@executable_path/../Frameworks")
endif()
if(app_install_arguments)
	ofs_install_name_tool("${OFS_APP_EXECUTABLE}" ${app_install_arguments})
endif()

# The final app must load only its bundled Homebrew dependencies, never a
# build-host installation that could be a newer macOS bottle.
ofs_verify_no_external_homebrew_load_references("${OFS_APP_EXECUTABLE}")
ofs_verify_no_external_homebrew_load_references("${OFS_FFMPEG_HELPER}")
foreach(source_index RANGE 0 ${last_source_index})
	list(GET names ${source_index} bundle_name)
	ofs_verify_no_external_homebrew_load_references(
		"${OFS_FRAMEWORKS_DIR}/${bundle_name}")
endforeach()

# Check the app and every copied dependency after load-path rewriting and
# before either ad-hoc or Developer ID signing takes place.
ofs_verify_macos_binary_deployment_target(
	"${OFS_APP_EXECUTABLE}" "${OFS_MACOS_DEPLOYMENT_TARGET}")
ofs_verify_macos_binary_deployment_target(
	"${OFS_FFMPEG_HELPER}" "${OFS_MACOS_DEPLOYMENT_TARGET}")
foreach(source_index RANGE 0 ${last_source_index})
	list(GET names ${source_index} bundle_name)
	set(bundled_dylib "${OFS_FRAMEWORKS_DIR}/${bundle_name}")
	ofs_verify_macos_binary_deployment_target(
		"${bundled_dylib}" "${OFS_MACOS_DEPLOYMENT_TARGET}")
endforeach()

if(OFS_ADHOC_SIGN)
	foreach(source_index RANGE 0 ${last_source_index})
		list(GET names ${source_index} bundle_name)
		execute_process(
			COMMAND "${OFS_CODESIGN}" --force --sign - --timestamp=none
				"${OFS_FRAMEWORKS_DIR}/${bundle_name}"
			RESULT_VARIABLE sign_result
			OUTPUT_VARIABLE sign_output
			ERROR_VARIABLE sign_error)
		if(NOT sign_result EQUAL 0)
			message(FATAL_ERROR
				"Ad-hoc signing failed for ${bundle_name}: ${sign_error}${sign_output}")
		endif()
	endforeach()

	execute_process(
		COMMAND "${OFS_CODESIGN}" --force --sign - --timestamp=none
			"${OFS_FFMPEG_HELPER}"
		RESULT_VARIABLE sign_result
		OUTPUT_VARIABLE sign_output
		ERROR_VARIABLE sign_error)
	if(NOT sign_result EQUAL 0)
		message(FATAL_ERROR
			"Ad-hoc signing failed for bundled ffmpeg: ${sign_error}${sign_output}")
	endif()

	execute_process(
		COMMAND "${OFS_CODESIGN}" --force --sign - --timestamp=none
			"${OFS_APP_BUNDLE}"
		RESULT_VARIABLE sign_result
		OUTPUT_VARIABLE sign_output
		ERROR_VARIABLE sign_error)
	if(NOT sign_result EQUAL 0)
		message(FATAL_ERROR
			"Ad-hoc signing failed for ${OFS_APP_BUNDLE}: ${sign_error}${sign_output}")
	endif()
endif()

message(STATUS "Bundled ffmpeg and ${source_count} macOS dylibs into ${OFS_APP_CONTENTS_DIR}")
