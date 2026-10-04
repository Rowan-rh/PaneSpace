#!/usr/bin/env python3
"""Assert the generated appcast says what this release promises.

  scripts/appcast-tool.py verify-appcast <appcast.xml> <version> <true|false>

`version` is the CFBundleShortVersionString of the release being published.

Two mistakes this replaces, both of which reported success while checking
nothing:

  * `sparkle:channel` is an element (`<sparkle:channel>beta</sparkle:channel>`),
    not an attribute, so a grep for `channel="beta"` matched no feed at all.
  * Items are ordered by CFBundleVersion, not by publish time. `build-app.sh`
    encodes that as major*1000000 + minor*10000 + patch*100 + channel, so a
    0.3.1 patch released after 0.4.0 sorts below it, and a 0.5.0 beta released
    before a 0.4.1 release also sorts above it. Taking the first item would
    check the wrong entry, or fail a perfectly good feed. The entry is located
    by its own short version string instead.
"""
import re
import sys

ENCLOSURE_RE = re.compile(r"<enclosure[^>]*?url=\"([^\"]+)\"", re.S)
ITEM_RE = re.compile(r"<item>.*?</item>", re.S)
TITLE_RE = re.compile(r"<title>([^<]+)</title>")
SHORT_VERSION_RE = re.compile(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>")
CHANNEL_RE = re.compile(r"<sparkle:channel>([^<]+)</sparkle:channel>")
# A bare filename, i.e. an entry the tool could not resolve to a real URL.
# Anything carrying a scheme, or starting with a path segment, is fine.
BARE_URL_RE = re.compile(r"<enclosure[^>]*?url=\"(?!https?://|/)")


def fail(message):
    sys.exit("::error::%s" % message)


def short_version_of(item):
    match = SHORT_VERSION_RE.search(item)
    return match.group(1) if match is not None else None


def find_release_item(items, version):
    """The single item for `version`, or an error naming what is actually there.

    Exactly one item must match. Zero means the release never made it into the
    feed -- worth catching, since the point of the step is to publish a feed
    that offers this release. More than one would mean a duplicate, and
    asserting against an arbitrary one of them would hide it.
    """
    matches = [item for item in items if short_version_of(item) == version]
    if len(matches) == 1:
        return matches[0]
    present = sorted(v for v in (short_version_of(i) for i in items) if v is not None)
    if not matches:
        fail("the appcast has no item for %s (it holds %s). The release was not "
             "added to the feed." % (version, ", ".join(present) or "no versions"))
    fail("the appcast has %d items for %s, expected exactly one. The feed "
         "holds %s." % (len(matches), version, ", ".join(present)))


def verify_appcast(path, version, prerelease):
    xml = open(path).read()
    items = ITEM_RE.findall(xml)
    if not items:
        fail("generated appcast contains no items")

    item = find_release_item(items, version)
    title_match = TITLE_RE.search(item)
    shown = title_match.group(1) if title_match is not None else version
    channel_match = CHANNEL_RE.search(item)
    channel = channel_match.group(1) if channel_match is not None else None

    if prerelease == "true" and channel is None:
        fail("%s is a prerelease but its item carries no "
             "<sparkle:channel>beta</sparkle:channel>; beta users would never see it"
             % version)
    if prerelease != "true" and channel is not None:
        fail("%s is a release but its item is tagged %s; stable users would be "
             "offered a prerelease" % (version, channel))

    # The feed is public and its channel tags and minimumSystemVersion can be
    # edited without touching any update's own signature.
    if "<!-- sparkle-signatures:" not in xml:
        fail("generated appcast carries no feed signature")

    # An enclosure URL that is a bare filename resolves against the feed's own
    # location, not against a release, so it 404s for every installed client.
    for candidate in items:
        if BARE_URL_RE.search(candidate) is not None:
            other = TITLE_RE.search(candidate)
            url = ENCLOSURE_RE.search(candidate)
            fail("item %s has a bare enclosure URL (%s); it would 404 for "
                 "clients. Check --download-url-prefix."
                 % (other.group(1) if other is not None else "<unknown>",
                    url.group(1) if url is not None else "<unknown>"))

    print("appcast OK: %d item(s); %s (shown as %s) is on channel %s; feed signed"
          % (len(items), version, shown, channel or "default"))
    for candidate in items:
        short = short_version_of(candidate)
        if short is None:
            continue
        item_channel = CHANNEL_RE.search(candidate)
        label = "default"
        if item_channel is not None:
            label = item_channel.group(1)
        print("  %s: %s" % (short, label))


if __name__ == "__main__":
    if sys.argv[1:2] != ["verify-appcast"] or len(sys.argv) != 5:
        sys.exit("usage: appcast-tool.py verify-appcast <appcast.xml> <version> <true|false>")
    verify_appcast(sys.argv[2], sys.argv[3], sys.argv[4])
