# Shared Mach-O deployment-version checks for the provider preflight and app bundle.

find_program(OFS_DEPLOYMENT_OTOOL_EXECUTABLE otool)
if(NOT OFS_DEPLOYMENT_OTOOL_EXECUTABLE)
	message(FATAL_ERROR "otool is required to verify bundled macOS deployment targets")
endif()

function(ofs_verify_macos_binary_deployment_target binary deployment_target)
	if(NOT EXISTS "${binary}")
		message(FATAL_ERROR "Cannot verify missing Mach-O binary: ${binary}")
	endif()

	execute_process(
		COMMAND "${OFS_DEPLOYMENT_OTOOL_EXECUTABLE}" -l "${binary}"
		RESULT_VARIABLE otool_result
		OUTPUT_VARIABLE load_commands
		ERROR_VARIABLE otool_error)
	if(NOT otool_result EQUAL 0)
		message(FATAL_ERROR "otool could not inspect ${binary}: ${otool_error}")
	endif()

	set(load_command_type "")
	set(minimum_versions "")
	string(REPLACE "\n" ";" load_command_lines "${load_commands}")
	foreach(line IN LISTS load_command_lines)
		string(STRIP "${line}" line)
		if(line STREQUAL "cmd LC_BUILD_VERSION")
			set(load_command_type "build-version")
		elseif(line STREQUAL "cmd LC_VERSION_MIN_MACOSX")
			set(load_command_type "legacy-version")
		elseif(load_command_type STREQUAL "build-version"
			AND line MATCHES "^minos[ \t]+([0-9]+(\\.[0-9]+)*)$")
			list(APPEND minimum_versions "${CMAKE_MATCH_1}")
			set(load_command_type "")
		elseif(load_command_type STREQUAL "legacy-version"
			AND line MATCHES "^version[ \t]+([0-9]+(\\.[0-9]+)*)$")
			list(APPEND minimum_versions "${CMAKE_MATCH_1}")
			set(load_command_type "")
		elseif(line MATCHES "^cmd ")
			set(load_command_type "")
		endif()
	endforeach()

	if(NOT minimum_versions)
		message(FATAL_ERROR
			"Could not read a macOS minimum version from ${binary}; refusing to label it as macOS ${deployment_target} compatible")
	endif()

	foreach(minimum_version IN LISTS minimum_versions)
		if(minimum_version VERSION_GREATER "${deployment_target}")
			message(FATAL_ERROR
				"${binary} requires macOS ${minimum_version}, newer than the configured macOS ${deployment_target} deployment target")
		endif()
	endforeach()

	message(STATUS "Verified ${binary}: minimum macOS ${minimum_versions} (target ${deployment_target})")
endfunction()
