#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
lock_file="$project_root/cmake/macos26-bottles.lock"
cache_root="$project_root/.cache/macos26"
bottle_dir="$cache_root/bottles"
provider_prefix="$cache_root/prefix"
staged_prefix="$cache_root/.prefix-staging-$$"
previous_prefix="$cache_root/.prefix-previous-$$"
temporary_archive=""
temporary_listing=""
swapping_prefix=0

cleanup() {
	status=$?
	if [ "$swapping_prefix" -eq 1 ] && [ ! -e "$provider_prefix" ] \
		&& { [ -e "$previous_prefix" ] || [ -L "$previous_prefix" ]; }; then
		mv "$previous_prefix" "$provider_prefix" || true
	fi
	if [ -e "$staged_prefix" ] || [ -L "$staged_prefix" ]; then
		rm -rf "$staged_prefix"
	fi
	if [ -n "$temporary_archive" ]; then
		rm -f "$temporary_archive"
	fi
	if [ -n "$temporary_listing" ]; then
		rm -f "$temporary_listing"
	fi
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
	printf '%s\n' "prepare-macos26-bottles: $*" >&2
	exit 2
}

for tool in curl shasum awk sed tar readlink; do
	command -v "$tool" >/dev/null 2>&1 || fail "required tool is missing: $tool"
done
[ -f "$lock_file" ] || fail "pinned bottle lock is missing: $lock_file"
awk -F '|' '
	/^#/ { next }
	{
		if (NF != 7 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" || $6 == "" || $7 == "") {
			printf "malformed lock row %d\n", NR > "/dev/stderr"
			invalid = 1
			next
		}
		if ($1 in names) {
			printf "duplicate formula in lock: %s\n", $1 > "/dev/stderr"
			invalid = 1
		}
		names[$1] = 1
		dependencies[$1] = $7
	}
	END {
		if (!("mpv" in names) || !("ffmpeg" in names)) {
			print "lock must contain mpv and ffmpeg roots" > "/dev/stderr"
			invalid = 1
		}
		for (formula in dependencies) {
			if (dependencies[formula] == "-") continue
			count = split(dependencies[formula], dependency_names, ";")
			for (dep_index = 1; dep_index <= count; dep_index++) {
				if (!(dependency_names[dep_index] in names)) {
					printf "missing locked dependency %s referenced by %s\n", dependency_names[dep_index], formula > "/dev/stderr"
					invalid = 1
				}
			}
		}
		exit invalid
	}
' "$lock_file" || fail "the pinned bottle lock is malformed or its dependency closure is incomplete"

mkdir -p "$bottle_dir"
lock_sha256=$(shasum -a 256 "$lock_file" | awk '{print $1}')
formula_count=0
cached_count=0
downloaded_count=0

while IFS='|' read -r formula version cellar_version bottle_tag bottle_url expected_sha256 dependencies; do
	case "$formula" in ''|'#'*) continue ;; esac
	formula_count=$((formula_count + 1))
	case "$formula/$cellar_version" in *..*|/*) fail "unsafe formula or version in lock: $formula $cellar_version" ;; esac
	case "$bottle_tag" in arm64_tahoe|all) ;; *) fail "unsupported bottle tag for $formula: $bottle_tag" ;; esac
	case "$expected_sha256" in *[!0123456789abcdef]*|'') fail "invalid SHA256 for $formula" ;; esac
	[ "${#expected_sha256}" -eq 64 ] || fail "invalid SHA256 length for $formula"
	case "$bottle_url" in
		https://ghcr.io/v2/homebrew/core/*/blobs/sha256:"$expected_sha256") ;;
		*) fail "unexpected bottle URL for $formula" ;;
	esac
	[ -n "$dependencies" ] || fail "missing dependency field for $formula"

	archive="$bottle_dir/$formula-$cellar_version.$bottle_tag.tar.gz"
	legacy_archive="$bottle_dir/$formula-$version.$bottle_tag.tar.gz"
	if [ ! -f "$archive" ] && [ "$legacy_archive" != "$archive" ] && [ -f "$legacy_archive" ]; then
		legacy_sha256=$(shasum -a 256 "$legacy_archive" | awk '{print $1}')
		if [ "$legacy_sha256" = "$expected_sha256" ]; then
			mv "$legacy_archive" "$archive"
		fi
	fi
	archive_sha256=""
	if [ -f "$archive" ]; then
		archive_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
	fi
	if [ "$archive_sha256" != "$expected_sha256" ]; then
		printf 'Downloading pinned Homebrew bottle %s %s (%s)\n' \
			"$formula" "$version" "$bottle_tag"
		bottle_repository=${bottle_url#https://ghcr.io/v2/}
		bottle_repository=${bottle_repository%/blobs/sha256:$expected_sha256}
		token_scope="repository:$bottle_repository:pull"
		token_json=$(curl -fsSL --connect-timeout 30 --max-time 60 \
			"https://ghcr.io/token?scope=$token_scope") || \
			fail "could not get an anonymous GHCR pull token for $formula"
		ghcr_pull_token=$(printf '%s' "$token_json" | \
			sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
		unset token_json
		[ -n "$ghcr_pull_token" ] || fail "GHCR returned no anonymous pull token for $formula"
		temporary_archive="$bottle_dir/.download-$formula-$$"
		curl -fLsS --retry 2 --connect-timeout 30 --max-time 900 \
			-H "Authorization: Bearer $ghcr_pull_token" \
			"$bottle_url" -o "$temporary_archive" || \
			fail "could not download the pinned bottle for $formula"
		unset ghcr_pull_token
		actual_sha256=$(shasum -a 256 "$temporary_archive" | awk '{print $1}')
		[ "$actual_sha256" = "$expected_sha256" ] || \
			fail "SHA256 mismatch for downloaded $formula bottle: expected $expected_sha256, got $actual_sha256"
		mv "$temporary_archive" "$archive"
		temporary_archive=""
		downloaded_count=$((downloaded_count + 1))
	else
		cached_count=$((cached_count + 1))
	fi
done < "$lock_file"

[ "$formula_count" -gt 0 ] || fail "the pinned bottle lock contains no formulas"
printf 'Verified %s pinned bottle archives (%s cached, %s downloaded)\n' \
	"$formula_count" "$cached_count" "$downloaded_count"

provider_is_current=0
if [ -f "$provider_prefix/.ofs-bottle-lock-sha256" ]; then
	staged_lock_sha256=$(cat "$provider_prefix/.ofs-bottle-lock-sha256")
	if [ "$staged_lock_sha256" = "$lock_sha256" ] \
		&& [ -f "$provider_prefix/opt/mpv/lib/libmpv.dylib" ] \
		&& [ -x "$provider_prefix/opt/ffmpeg/bin/ffmpeg" ]; then
		provider_is_current=1
		while IFS='|' read -r formula version cellar_version bottle_tag bottle_url expected_sha256 dependencies; do
			case "$formula" in ''|'#'*) continue ;; esac
			link_target=$(readlink "$provider_prefix/opt/$formula" 2>/dev/null || true)
			if [ ! -d "$provider_prefix/Cellar/$formula/$cellar_version" ] \
				|| [ "$link_target" != "../Cellar/$formula/$cellar_version" ]; then
				provider_is_current=0
				break
			fi
		done < "$lock_file"
	fi
fi
if [ "$provider_is_current" -eq 1 ]; then
	printf 'Pinned macOS 26 providers are already staged at %s\n' "$provider_prefix"
	exit 0
fi

printf 'Extracting %s pinned bottles into the project-local provider prefix...\n' "$formula_count"
mkdir -p "$staged_prefix/Cellar" "$staged_prefix/opt"
temporary_listing="$cache_root/.members-$$"

while IFS='|' read -r formula version cellar_version bottle_tag bottle_url expected_sha256 dependencies; do
	case "$formula" in ''|'#'*) continue ;; esac
	archive="$bottle_dir/$formula-$cellar_version.$bottle_tag.tar.gz"
	actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
	[ "$actual_sha256" = "$expected_sha256" ] || \
		fail "cached bottle failed revalidation before extraction: $formula"
	tar -tzf "$archive" > "$temporary_listing" || fail "could not read bottle archive for $formula"
	while IFS= read -r member; do
		case "$member" in
			"$formula/$cellar_version"|"$formula/$cellar_version/"*) ;;
			*) fail "unexpected archive path in the pinned $formula bottle: $member" ;;
		esac
		case "/$member/" in */../*) fail "unsafe archive path in the pinned $formula bottle: $member" ;; esac
	done < "$temporary_listing"
	tar -xzf "$archive" -C "$staged_prefix/Cellar" || \
		fail "could not extract bottle for $formula"
	[ -d "$staged_prefix/Cellar/$formula/$cellar_version" ] || \
		fail "bottle did not contain the locked Cellar path for $formula"
	ln -s "../Cellar/$formula/$cellar_version" "$staged_prefix/opt/$formula"
done < "$lock_file"

[ -f "$staged_prefix/opt/mpv/lib/libmpv.dylib" ] || \
	fail "staged mpv bottle does not contain libmpv.dylib"
[ -x "$staged_prefix/opt/ffmpeg/bin/ffmpeg" ] || \
	fail "staged ffmpeg bottle does not contain its executable"
printf '%s\n' "$lock_sha256" > "$staged_prefix/.ofs-bottle-lock-sha256"

if [ -e "$provider_prefix" ] || [ -L "$provider_prefix" ]; then
	mv "$provider_prefix" "$previous_prefix" || fail "could not preserve the prior provider prefix"
	swapping_prefix=1
fi
mv "$staged_prefix" "$provider_prefix" || fail "could not activate the staged provider prefix"
swapping_prefix=0
if [ -e "$previous_prefix" ] || [ -L "$previous_prefix" ]; then
	rm -rf "$previous_prefix"
fi
printf 'Pinned macOS 26 providers staged at %s\n' "$provider_prefix"
