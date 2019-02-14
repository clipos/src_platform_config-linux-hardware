#!/usr/bin/gawk -f
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

#
# GNU Awk script to compare two version strings A and B formatted in the
# fashion of semver (but not necessarily stricly compliant with semver).
#
# Usage:
#   gawk -f version_compare.awk -v A='1.2.3' -v B='2.0-beta'
#
# Returns:
#   - 0 if the two versions strings (A and B) are equal
#   - 1 if the first version string (A) is greater than the second one (B)
#   - 2 if the first version string (A) is lower than the second one (B)
#   - 255 if one of the two version strings could not be parsed according to
#     pseudo-semver format string scheme defined in split_version_array
#     function
#

function split_version_array(version_string, version_array) {
    # Non-semver-strictly compliant version string format, but should do the
    # job most of the time (especially for the kernel version strings):
    return match(version_string,
        /^([0-9]+)(\.([0-9]+))?(\.([0-9]+))?(\-([a-zA-Z0-9\.\-]+))?(\+([a-zA-Z0-9\.\-]+))?$/,
        version_array)
    # Array indices:   (index 0 is always the full match)
    #   1 -> major number    4 -> (DO NOT USE)    7 -> pre-release tag
    #   2 -> (DO NOT USE)    5 -> micro number    8 -> (DO NOT USE)
    #   3 -> minor number    6 -> (DO NOT USE)    9 -> build tag
}

BEGIN {
    if (A == "" || B == "") {
        print "version_compare: A and B variables need to be defined (tip: gawk -f version_compare.awk -v A=... -v B=...)" > "/dev/stderr"
        exit 255
    }
    A_split_result = split_version_array(A, A_array)
    B_split_result = split_version_array(B, B_array)
    if (A_split_result == 0) {
        print "version_compare: version A parsing failed" > "/dev/stderr"
        exit 255
    }
    if (B_split_result == 0) {
        print "version_compare: version B parsing failed" > "/dev/stderr"
        exit 255
    }

    # Manage cases where minor and/or micro number are not defined by setting
    # them to 0:
    if (A_array[5] == "") A_array[5] = 0;
    if (B_array[5] == "") B_array[5] = 0;
    if (A_array[3] == "") A_array[3] = 0;
    if (B_array[3] == "") B_array[3] = 0;

    if (A_array[1] != B_array[1]) {
        exit (A_array[1] > B_array[1]) ? 1 : 2;
    } else if (A_array[3] != B_array[3]) {
        exit (A_array[3] > B_array[3]) ? 1 : 2;
    } else if (A_array[5] != B_array[5]) {
        exit (A_array[5] > B_array[5]) ? 1 : 2;
    } else if (A_array[7] != "" && B_array[7] == "") {
        exit 2
    } else if (A_array[7] == "" && B_array[7] != "") {
        exit 1
    } else if (A_array[7] != "" && B_array[7] != "") {
        exit (A_array[7] > B_array[7]) ? 1 : 2;
    }
    exit 0  # versions are equal
}

# vim: set ft=awk ts=4 sts=4 sw=4 et ai tw=79:
