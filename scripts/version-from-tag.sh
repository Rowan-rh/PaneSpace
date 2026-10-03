#!/bin/zsh
# Derive CFBundleShortVersionString and CFBundleVersion from a release tag.
#
# The tag is the single source of truth: `v0.2.0` -> 0.2.0 / 20099, `v0.2.0-beta.1`
# -> 0.2.0-beta.1 / 20001. Build numbers must be deterministic and monotonically
# increasing because Sparkle compares them lexicographically on CFBundleVersion:
#
#   MAJOR * 1000000 + MINOR * 10000 + PATCH * 100 + (99 for final, 1-98 for prerelease)
#
# Usage: version-from-tag.sh <tag>
# Prints two lines: "<short-version> <build-number>".
set -euo pipefail

usage() {
    print -u2 "usage: ${0:t} <tag>   # e.g. v0.2.0, v0.2.0-beta.1"
    exit 2
}

[[ $# -eq 1 ]] || usage
tag="$1"
[[ -n "$tag" ]] || usage

# Accept `v0.2.0` and `0.2.0`; anything else must fail loudly so a typo never
# silently produces a release with a wrong version.
if [[ "$tag" != v* ]]; then
    print -u2 "error: tag must start with 'v' (got '$tag')"
    exit 1
fi
version="${tag#v}"

if [[ ! "$version" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-([A-Za-z0-9]+(\.[A-Za-z0-9]+)*))?$' ]]; then
    print -u2 "error: cannot parse version '$version' from tag '$tag'"
    print -u2 "       expected MAJOR.MINOR.PATCH with optional -<id>.<n> prerelease, e.g. v0.2.0 or v0.2.0-beta.1"
    exit 1
fi

major="${match[1]}"
minor="${match[2]}"
patch="${match[3]}"
prerelease="${match[5]}"

if [[ -z "$prerelease" ]]; then
    # Final release gets the highest slot so it sorts above every prerelease of
    # the same MAJOR.MINOR.PATCH and above the previous final build.
    build=$(( major * 1000000 + minor * 10000 + patch * 100 + 99 ))
else
    # Prerelease identifier must be <alpha|beta|rc>.<n>; anything else would make
    # the ordering ambiguous, so reject it instead of guessing.
    if [[ ! "$prerelease" =~ '^(alpha|beta|rc)\.([1-9][0-9]*)$' ]]; then
        print -u2 "error: unsupported prerelease identifier '$prerelease' in tag '$tag'"
        print -u2 "       only <alpha|beta|rc>.<n> is allowed (n >= 1), e.g. v0.2.0-beta.1"
        exit 1
    fi
    prerelease_number="${match[2]}"
    if (( prerelease_number > 98 )); then
        print -u2 "error: prerelease number $prerelease_number leaves no room for the final build"
        print -u2 "       prereleases of the same version must use 1-98"
        exit 1
    fi
    build=$(( major * 1000000 + minor * 10000 + patch * 100 + prerelease_number ))
fi

print "$version $build"
