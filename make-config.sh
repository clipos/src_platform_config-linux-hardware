#!/bin/bash
# Copyright © 2018 ANSSI. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

set -e -u -o pipefail

readonly SELFNAME="${BASH_SOURCE[0]##*/}"
readonly SELFPATH="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

_version_less_or_equal() {
	gawk -f "$SELFPATH"/version_compare.awk -v A="$1" -v B="$2" <&-
	test $? "-ne" 1
}

MINICONFIG_CAT=""
MINICONFIG_SORT=""

# initial miniconfig idea from Rob Landley and Piotr Karbowski (foo-miniconfig)
generate_config() {
	local config configset subconfigset config_suffix
	local missing=()
	local unwanted=()
	local gcc=false

	MINICONFIG_CAT="$(mktemp)"
	MINICONFIG_SORT="$(mktemp)"

	config_suffix="$(sed -n -e 's/^VERSION *= *\([0-9]\+\)/\1/p' "${S}/Makefile")"
	config_suffix+=".$(sed -n -e 's/^PATCHLEVEL *= *\([0-9]\+\)/\1/p' "${S}/Makefile")"

	echo "[*] Kernel configuration set:"
	for configset in "$@"; do
		if [[ -f "${CONFIGDIR}/kernel_config/${configset}" ]]; then
			echo "[*]   ${configset}"
			cat "${CONFIGDIR}/kernel_config/${configset}" >> "${MINICONFIG_CAT}"
			for subconfigset in $(ls ${CONFIGDIR}/kernel_config/${configset}-* 2>/dev/null); do
				# FIXME: removal of a config option in a new kernel version
				# is not handled. Theoretically an option removed from Kconfig
				# should have no impact anymore in the source code, but we
				# still might want to disable an option starting from a certain
				# kernel version (e.g. disable buggy option for kernels newer
				# than 4.x).
				subconfigset="${subconfigset##${CONFIGDIR}/kernel_config/}"
				if _version_less_or_equal "${subconfigset##*-}" "${config_suffix}"; then
					echo "[*]   ${subconfigset}"
					cat "${CONFIGDIR}/kernel_config/${subconfigset}" \
						>> "${MINICONFIG_CAT}"
				fi
			done
		else
			die "There is no ${configset} configuration set"
		fi
	done
	sort -u "${MINICONFIG_CAT}" > "${MINICONFIG_SORT}"
	rm "${MINICONFIG_CAT}"

	pushd "${S}" >/dev/null
	make ARCH="${ARCH}" KCONFIG_ALLCONFIG="${MINICONFIG_SORT}" allnoconfig

	# check consistency
	while read config; do
		if ! grep -q "^${config}\$" .config; then
			missing+=("${config}")
			if ! $gcc && grep -q "CONFIG_GCC_PLUGIN" <<< "$config"; then
				gcc=true
			fi
		fi
	done < "${MINICONFIG_SORT}"
	if [[ "${#missing[@]}" -ne 0 ]]; then
		if $gcc ; then
			echo "HINT: You need a gcc with plugin support. For some distros (e.g. Debian), you may need to install the supporting headers explicitly in addition to the normal gcc package."
		fi
		die "Missing ${#missing[@]} entry from ${MINICONFIG_SORT}: ${missing[*]}"
	fi
	popd >/dev/null

	# check blacklisted options
	if $DEBUG; then
		while read config; do
			if grep -q "^${config}=" "${S}/.config"; then
				unwanted+=("${config}")
			fi
		done < "${CONFIGDIR}/kernel_config/blacklist"
		if [[ "${#unwanted[@]}" -ne 0 ]]; then
			die "${#unwanted[@]} entry blacklisted but appearing in final .config: ${unwanted[*]}"
		fi
	fi
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

_cleanup() {
	local torm
	local torm_list=("${MINICONFIG_CAT}" "${MINICONFIG_SORT}")

	set +e
	for torm in "${torm_list[@]}"; do
		if [[ -f "${torm}" ]]; then
			rm -- "${torm}"
		fi
	done
}

if [[ $# -lt 1 ]]; then
	echo "usage: $(basename -- "$0") <configset>..." >&2
	echo >&2
	echo "example: $(basename -- "$0") basic cpu/intel cpu/x86_64 misc_drivers net/basic security/basic" >&2
	exit 1
fi

set -u -e -o pipefail

if [[ -z "${CONFIGDIR:-}" ]]; then
	CONFIGDIR="$SELFPATH"
fi

if [[ -z "${S:-}" ]]; then
	S="$(pwd)"
fi

if [[ -z "${ARCH:-}" ]]; then
	ARCH="$(uname -m)"
	echo "WARNING: ARCH env variable was not specified, defaulting to x86_64"
fi

if [[ -z "${DEBUG:-}" ]]; then
	DEBUG=false
fi

if [[ ! -f "${S}/Makefile" ]]; then
	echo "Need to be run in a Linux source directory." >&2
	exit 1
fi

trap _cleanup QUIT INT TERM EXIT
generate_config "$@"

# vim: set ts=4 sts=4 sw=4 noet:
