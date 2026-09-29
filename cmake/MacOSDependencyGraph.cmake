# Shared Mach-O dependency discovery for provider preflight and app bundling.

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

function(ofs_expand_loader_tokens path owner_dir executable_dir output)
	set(expanded "${path}")
	if(expanded MATCHES "^@loader_path(.*)$")
		set(expanded "${owner_dir}${CMAKE_MATCH_1}")
	elseif(expanded MATCHES "^@executable_path(.*)$")
		set(expanded "${executable_dir}${CMAKE_MATCH_1}")
	endif()
	set(${output} "${expanded}" PARENT_SCOPE)
endfunction()

function(ofs_map_homebrew_path path output)
	set(mapped "${path}")
	if(DEFINED OFS_BREW_PREFIX AND NOT "${OFS_BREW_PREFIX}" STREQUAL "")
		if(path MATCHES "^/opt/homebrew/(.*)$"
			OR path MATCHES "^@@HOMEBREW_PREFIX@@/(.*)$")
			set(mapped "${OFS_BREW_PREFIX}/${CMAKE_MATCH_1}")
		elseif(path MATCHES "^/usr/local/(.*)$")
			# Never let a Rosetta/Intel Homebrew prefix satisfy an arm64 bottle.
			set(mapped "${OFS_BREW_PREFIX}/${CMAKE_MATCH_1}")
		elseif(path MATCHES "^@@HOMEBREW_CELLAR@@/(.*)$")
			set(mapped "${OFS_BREW_PREFIX}/Cellar/${CMAKE_MATCH_1}")
		endif()
	endif()
	set(${output} "${mapped}" PARENT_SCOPE)
endfunction()

function(ofs_resolve_dependency dependency owner output)
	if(ARGC GREATER 3)
		set(executable_dir "${ARGV3}")
	else()
		set(executable_dir "${OFS_APP_MACOS_DIR}")
	endif()
	get_filename_component(owner_dir "${owner}" DIRECTORY)
	ofs_read_rpaths("${owner}" owner_rpaths)
	set(candidates "")

	if(dependency MATCHES "^@rpath/(.*)$")
		set(rpath_suffix "${CMAKE_MATCH_1}")
		foreach(rpath IN LISTS owner_rpaths)
			ofs_expand_loader_tokens("${rpath}" "${owner_dir}" "${executable_dir}" expanded_rpath)
			list(APPEND candidates "${expanded_rpath}/${rpath_suffix}")
		endforeach()
	elseif(dependency MATCHES "^@loader_path(/.*)$")
		list(APPEND candidates "${owner_dir}${CMAKE_MATCH_1}")
	elseif(dependency MATCHES "^@executable_path(/.*)$")
		list(APPEND candidates "${executable_dir}${CMAKE_MATCH_1}")
	elseif(dependency MATCHES "^@@HOMEBREW_(PREFIX|CELLAR)@@/")
		list(APPEND candidates "${dependency}")
	elseif(IS_ABSOLUTE "${dependency}")
		list(APPEND candidates "${dependency}")
	else()
		list(APPEND candidates "${owner_dir}/${dependency}")
		foreach(rpath IN LISTS owner_rpaths)
			ofs_expand_loader_tokens("${rpath}" "${owner_dir}" "${executable_dir}" expanded_rpath)
			list(APPEND candidates "${expanded_rpath}/${dependency}")
		endforeach()
	endif()

	set(resolved "")
	foreach(candidate IN LISTS candidates)
		# Homebrew bottle load commands retain the standard prefix. Map them to
		# the project-local bottle prefix before checking the filesystem so the
		# build never resolves a newer dylib from the host Homebrew installation.
		ofs_map_homebrew_path("${candidate}" mapped_candidate)
		if(EXISTS "${mapped_candidate}")
			get_filename_component(candidate_real "${mapped_candidate}" REALPATH)
			if(EXISTS "${candidate_real}")
				set(resolved "${candidate_real}")
				break()
			endif()
		endif()
	endforeach()
	set(${output} "${resolved}" PARENT_SCOPE)
endfunction()
