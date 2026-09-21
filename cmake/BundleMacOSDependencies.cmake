# Bundle the non-system dylib dependency graph of the dynamically loaded
# libmpv into an OpenFunscripter.app bundle.

cmake_minimum_required(VERSION 3.16)

if(NOT APPLE)
	message(FATAL_ERROR "BundleMacOSDependencies.cmake is only supported on macOS")
endif()

foreach(_required_var OFS_APP_EXECUTABLE OFS_MPV_LIBRARY)
	if(NOT DEFINED ${_required_var} OR "${${_required_var}}" STREQUAL "")
		message(FATAL_ERROR "${_required_var} is required")
	endif()
endforeach()

if(NOT DEFINED OFS_ADHOC_SIGN)
	set(OFS_ADHOC_SIGN ON)
endif()

find_program(OFS_OTOOL otool REQUIRED)
find_program(OFS_INSTALL_NAME_TOOL install_name_tool REQUIRED)
if(OFS_ADHOC_SIGN)
	find_program(OFS_CODESIGN codesign REQUIRED)
endif()

if(NOT EXISTS "${OFS_APP_EXECUTABLE}")
	message(FATAL_ERROR "App executable does not exist: ${OFS_APP_EXECUTABLE}")
endif()
if(NOT EXISTS "${OFS_MPV_LIBRARY}")
	message(FATAL_ERROR "libmpv does not exist: ${OFS_MPV_LIBRARY}")
endif()

get_filename_component(OFS_MPV_LIBRARY_REAL "${OFS_MPV_LIBRARY}" REALPATH)
get_filename_component(OFS_APP_MACOS_DIR "${OFS_APP_EXECUTABLE}" DIRECTORY)
get_filename_component(OFS_APP_CONTENTS_DIR "${OFS_APP_MACOS_DIR}" DIRECTORY)
get_filename_component(OFS_APP_BUNDLE "${OFS_APP_CONTENTS_DIR}" DIRECTORY)
set(OFS_FRAMEWORKS_DIR "${OFS_APP_CONTENTS_DIR}/Frameworks")

if(NOT IS_DIRECTORY "${OFS_APP_BUNDLE}")
	message(FATAL_ERROR "App bundle directory does not exist: ${OFS_APP_BUNDLE}")
endif()

# The global properties form a small source-to-bundle-name table. A real file
# may be reached through several install names; the first chosen bundle name
# is reused. A name reached from two different real files is an error because
# silently replacing one dylib would leave a non-deterministic bundle.
set_property(GLOBAL PROPERTY OFS_BUNDLE_SOURCES "")
set_property(GLOBAL PROPERTY OFS_BUNDLE_NAMES "")

function(ofs_add_bundle_file source requested_name output_name)
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
	set_property(GLOBAL PROPERTY OFS_BUNDLE_SOURCES "${sources}")
	set_property(GLOBAL PROPERTY OFS_BUNDLE_NAMES "${names}")
	set(${output_name} "${requested_name}" PARENT_SCOPE)
endfunction()

function(ofs_read_dependencies binary output)
	execute_process(
		COMMAND "${OFS_OTOOL}" -L "${binary}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE listing
		ERROR_VARIABLE error_output)
	if(NOT result EQUAL 0)
		message(FATAL_ERROR "otool -L failed for ${binary}: ${error_output}")
	endif()

	set(dependencies "")
	string(REPLACE "\n" ";" lines "${listing}")
	foreach(line IN LISTS lines)
		string(STRIP "${line}" line)
		if(line MATCHES "^([^ \t]+) \\(")
			list(APPEND dependencies "${CMAKE_MATCH_1}")
		endif()
	endforeach()
	set(${output} "${dependencies}" PARENT_SCOPE)
endfunction()

function(ofs_read_rpaths binary output)
	execute_process(
		COMMAND "${OFS_OTOOL}" -l "${binary}"
		RESULT_VARIABLE result
		OUTPUT_VARIABLE listing
		ERROR_VARIABLE error_output)
	if(NOT result EQUAL 0)
		message(FATAL_ERROR "otool -l failed for ${binary}: ${error_output}")
	endif()

	set(rpaths "")
	string(REPLACE "\n" ";" lines "${listing}")
	foreach(line IN LISTS lines)
		string(STRIP "${line}" line)
		if(line MATCHES "^path ([^ \t]+) \\(offset")
			list(APPEND rpaths "${CMAKE_MATCH_1}")
		endif()
	endforeach()
	set(${output} "${rpaths}" PARENT_SCOPE)
endfunction()

function(ofs_is_system_path path output)
	if(path MATCHES "^/System/Library/"
		OR path MATCHES "^/usr/lib/"
		OR path MATCHES "^/usr/lib/swift/"
		OR path MATCHES "^/System/iOSSupport/")
		set(result TRUE)
	else()
		set(result FALSE)
	endif()
	set(${output} "${result}" PARENT_SCOPE)
endfunction()

function(ofs_expand_loader_tokens path owner_dir output)
	set(expanded "${path}")
	if(expanded MATCHES "^@loader_path(.*)$")
		set(expanded "${owner_dir}${CMAKE_MATCH_1}")
	elseif(expanded MATCHES "^@executable_path(.*)$")
		set(expanded "${OFS_APP_MACOS_DIR}${CMAKE_MATCH_1}")
	endif()
	set(${output} "${expanded}" PARENT_SCOPE)
endfunction()

function(ofs_resolve_dependency dependency owner output)
	get_filename_component(owner_dir "${owner}" DIRECTORY)
	ofs_read_rpaths("${owner}" owner_rpaths)
	set(candidates "")

	if(dependency MATCHES "^@rpath/(.*)$")
		set(rpath_suffix "${CMAKE_MATCH_1}")
		foreach(rpath IN LISTS owner_rpaths)
			ofs_expand_loader_tokens("${rpath}" "${owner_dir}" expanded_rpath)
			list(APPEND candidates "${expanded_rpath}/${rpath_suffix}")
		endforeach()
	elseif(dependency MATCHES "^@loader_path(/.*)$")
		list(APPEND candidates "${owner_dir}${CMAKE_MATCH_1}")
	elseif(dependency MATCHES "^@executable_path(/.*)$")
		list(APPEND candidates "${OFS_APP_MACOS_DIR}${CMAKE_MATCH_1}")
	elseif(IS_ABSOLUTE "${dependency}")
		list(APPEND candidates "${dependency}")
	else()
		list(APPEND candidates "${owner_dir}/${dependency}")
		foreach(rpath IN LISTS owner_rpaths)
			ofs_expand_loader_tokens("${rpath}" "${owner_dir}" expanded_rpath)
			list(APPEND candidates "${expanded_rpath}/${dependency}")
		endforeach()
	endif()

	set(resolved "")
	foreach(candidate IN LISTS candidates)
		if(EXISTS "${candidate}")
			get_filename_component(candidate_real "${candidate}" REALPATH)
			if(EXISTS "${candidate_real}")
				set(resolved "${candidate_real}")
				break()
			endif()
		endif()
	endforeach()
	set(${output} "${resolved}" PARENT_SCOPE)
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

# Seed the graph with the stable loader name expected inside the app bundle.
ofs_add_bundle_file("${OFS_MPV_LIBRARY_REAL}" "libmpv.dylib" OFS_MPV_BUNDLE_NAME)

set(graph_index 0)
while(TRUE)
	get_property(sources GLOBAL PROPERTY OFS_BUNDLE_SOURCES)
	list(LENGTH sources source_count)
	if(graph_index GREATER_EQUAL source_count)
		break()
	endif()
	list(GET sources ${graph_index} current_source)

	ofs_read_dependencies("${current_source}" dependencies)
	foreach(dependency IN LISTS dependencies)
		ofs_is_system_path("${dependency}" is_system)
		if(is_system)
			continue()
		endif()

		ofs_resolve_dependency("${dependency}" "${current_source}" resolved_dependency)
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
		ofs_add_bundle_file("${resolved_dependency}" "${dependency_name}" ignored_name)
	endforeach()

	math(EXPR graph_index "${graph_index} + 1")
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

# Rewrite each copied dylib using the original source graph. This keeps the
# operation repeatable even though the destination files were already changed
# by install_name_tool during an earlier build.
foreach(source_index RANGE 0 ${last_source_index})
	list(GET sources ${source_index} source)
	list(GET names ${source_index} bundle_name)
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
		ofs_resolve_dependency("${dependency}" "${source}" resolved_dependency)
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
			"${OFS_APP_BUNDLE}"
		RESULT_VARIABLE sign_result
		OUTPUT_VARIABLE sign_output
		ERROR_VARIABLE sign_error)
	if(NOT sign_result EQUAL 0)
		message(FATAL_ERROR
			"Ad-hoc signing failed for ${OFS_APP_BUNDLE}: ${sign_error}${sign_output}")
	endif()
endif()

message(STATUS "Bundled ${source_count} macOS dylibs into ${OFS_FRAMEWORKS_DIR}")
