#!/bin/zsh
# Derive CFBundleShortVersionString and CFBundleVersion from a release tag.
#
# The tag is the single source of truth: `v0.2.0` -> 0.2.0 / 20099, `v0.2.0-beta.1`
# -> 0.2.0-beta.1 / 20030. Build numbers must be deterministic and monotonically
# increasing, because Sparkle compares the numeric segments of CFBundleVersion
# (not the string lexicographically) to decide whether an update is newer:
#
#   MAJOR * 1000000 + MINOR * 10000 + PATCH * 100 + channel
#
# The channel segment is what orders the prerelease track. Reusing one number for
# every channel (as an earlier revision did) collides: `alpha.5` and `beta.5` both
# produced 20005, and `rc.1` produced 20001, which sorts *below* `beta.2` (20002),
# so a user on beta.2 would never be offered the rc. Each channel therefore gets
# its own band inside the 0-99 segment, and the ordering the bands must satisfy is:
#
#   alpha.1-29  -> +1  .. +29
#   beta.1-29   -> +30 .. +58
#   rc.1-38     -> +60 .. +97
#   final       -> +99
#
# so alpha.29 < beta.1 < beta.29 < rc.1 < rc.38 < final. The gaps at 59 and 98 are
# deliberate spacers that keep a mistaken tag from landing on a live build number.
#
# MINOR and PATCH must stay below 100, otherwise the next version's channel band
# would overflow into it and two different releases would derive the same build
# number (v0.1.100 and v0.2.0 both yielded 20099).
#
# Usage: version-from-tag.sh <tag>
# Prints one line: "<short-version> <build-number>".
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

# Reject MINOR or PATCH >= 100: it spills into the next segment and makes the
# channel band meaningless.
if (( minor > 99 || patch > 99 )); then
    print -u2 "error: MINOR and PATCH must be 0-99 in tag '$tag' (got $minor.$patch)"
    print -u2 "       a value >= 100 overflows the build-number segment and collides with another release"
    exit 1
fi

# 0.0.x is semantically below the shipped 0.1.2, so releasing it would be
# confusing regardless of the build number it derives.
if (( major == 0 && minor == 0 )); then
    print -u2 "error: tag '$tag' is below the current release"
    print -u2 "       0.0.x is older than the published 0.1.2 and must not be released"
    exit 1
fi

if [[ -z "$prerelease" ]]; then
    # The final release takes the top of the band, so it sorts above every
    # prerelease of the same MAJOR.MINOR.PATCH.
    channel=99
else
    # Prerelease identifier must be <alpha|beta|rc>.<n>; anything else would make
    # the ordering ambiguous, so reject it instead of guessing.
    if [[ ! "$prerelease" =~ '^(alpha|beta|rc)\.([1-9][0-9]*)$' ]]; then
        print -u2 "error: unsupported prerelease identifier '$prerelease' in tag '$tag'"
        print -u2 "       only <alpha|beta|rc>.<n> is allowed (n >= 1), e.g. v0.2.0-beta.1"
        exit 1
    fi
    prerelease_id="${match[1]}"
    prerelease_number="${match[2]}"
    # Per-channel band base. Limits keep every band below the next one.
    case "$prerelease_id" in
        alpha) band=1; limit=29 ;;
        beta)  band=30; limit=29 ;;
        rc)    band=60; limit=38 ;;
    esac
    if (( prerelease_number > limit )); then
        print -u2 "error: $prerelease_id.$prerelease_number is out of range in tag '$tag'"
        print -u2 "       $prerelease_id allows 1-$limit (bands must not overlap: alpha 1-29, beta 1-29, rc 1-38)"
        exit 1
    fi
    channel=$(( band + prerelease_number - 1 ))
fi

build=$(( major * 1000000 + minor * 10000 + patch * 100 + channel ))

print "$version $build"
