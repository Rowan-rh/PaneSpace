#!/usr/bin/env python3
"""Assert the generated appcast says what this release promises.

`sparkle:channel` is an element (`<sparkle:channel>beta</sparkle:channel>`),
not an attribute, so an earlier check that grepped for `channel="beta"` matched
nothing on any feed at all -- prerelease or not -- and reported success either
way. This asserts the real thing and lets the exit status carry the verdict.

  scripts/appcast-tool.py verify-appcast <appcast.xml> <true|false prerelease>
"""
import re
import sys

ENCLOSURE_RE = re.compile(r"<enclosure[^>]*?url=\"([^\"]+)\"[^>]*?(?:/>|></enclosure>)", re.S)
ITEM_RE = re.compile(r"<item>.*?</item>", re.S)
TITLE_RE = re.compile(r"<title>([^<]+)</title>")
CHANNEL_RE = re.compile(r"<sparkle:channel>([^<]+)</sparkle:channel>")
# A bare filename, i.e. an entry the tool could not resolve to a real URL.
# Anything carrying a scheme, or starting with a path segment, is fine.
BARE_URL_RE = re.compile(r"<enclosure[^>]*?url=\"(?!https?://|/)")


def verify_appcast(path, prerelease):
    xml = open(path).read()
    items = ITEM_RE.findall(xml)
    if not items:
        sys.exit("::error::generated appcast contains no items")

    # generate_appcast writes the newest item first.
    new_item = items[0]
    version_match = TITLE_RE.search(new_item)
    if version_match is None:
        sys.exit("::error::newest appcast item has no <title>")
    version = version_match.group(1)
    channel_match = CHANNEL_RE.search(new_item)
    channel = channel_match.group(1) if channel_match is not None else None

    if prerelease == "true" and channel is None:
        sys.exit(
            "::error::%s is a prerelease but its item carries no "
            "<sparkle:channel>beta</sparkle:channel>; beta users would never see it"
            % version
        )
    if prerelease != "true" and channel is not None:
        sys.exit(
            "::error::%s is a release but its item is tagged %s; stable users "
            "would be offered a prerelease" % (version, channel)
        )

    # The feed is public and its channel tags and minimumSystemVersion can be
    # edited without touching any update's own signature.
    if "<!-- sparkle-signatures:" not in xml:
        sys.exit("::error::generated appcast carries no feed signature")

    # An enclosure URL that is a bare filename resolves against the feed's own
    # location, not against a release, so it 404s for every installed client.
    for item in items:
        bare = BARE_URL_RE.search(item)
        if bare is not None:
            title = TITLE_RE.search(item)
            url = ENCLOSURE_RE.search(item)
            sys.exit(
                "::error::item %s has a bare enclosure URL (%s); it would 404 "
                "for clients. Check --download-url-prefix."
                % (title.group(1) if title is not None else "<unknown>",
                   url.group(1) if url is not None else "<unknown>")
            )

    print("appcast OK: %d item(s), newest %s, channel=%s, feed signed"
          % (len(items), version, channel or "default"))
    for item in items:
        title_match = TITLE_RE.search(item)
        if title_match is None:
            continue
        item_channel = CHANNEL_RE.search(item)
        print("  %s: %s"
              % (title_match.group(1),
                 item_channel.group(1) if item_channel is not None else "default"))


if __name__ == "__main__":
    # argv[1] is the subcommand; the rest are its arguments.
    if sys.argv[1:2] == ["verify-appcast"] and len(sys.argv) == 4:
        verify_appcast(sys.argv[2], sys.argv[3])
    else:
        sys.exit("usage: appcast-tool.py verify-appcast <appcast.xml> <true|false>")
