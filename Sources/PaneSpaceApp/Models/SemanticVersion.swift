import Foundation

/// A Semantic Versioning 2.0 version, used to decide whether a published release is newer than the
/// running application.
///
/// Only the precedence rules of SemVer are implemented, because that is all an update check needs:
/// build metadata is parsed but never takes part in comparison, so two builds of the same version
/// compare as equal.
struct SemanticVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// Dot-separated pre-release identifiers. Empty for a stable version.
    let prereleaseIdentifiers: [String]
    /// Dot-separated build identifiers. Parsed for round-tripping only; SemVer excludes it from
    /// precedence.
    let buildMetadataIdentifiers: [String]

    var isPrerelease: Bool { !prereleaseIdentifiers.isEmpty }

    init(
        major: Int,
        minor: Int,
        patch: Int,
        prereleaseIdentifiers: [String] = [],
        buildMetadataIdentifiers: [String] = []
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }

    /// Accepts `0.2.0`, `v0.2.0`, and `0.2.0-beta.1+build.5`. Anything that is not a complete
    /// SemVer version returns nil, so a tag in another format is ignored instead of guessed at.
    init?(string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Release tags are conventionally prefixed with `v`; the version itself never is.
        if let first = text.first, first == "v" || first == "V" {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        var buildMetadata: [String] = []
        if let plus = text.firstIndex(of: "+") {
            guard let parsed = Self.identifiers(String(text[text.index(after: plus)...])) else { return nil }
            buildMetadata = parsed
            text = String(text[..<plus])
        }

        var prerelease: [String] = []
        if let dash = text.firstIndex(of: "-") {
            guard let parsed = Self.identifiers(String(text[text.index(after: dash)...])) else { return nil }
            prerelease = parsed
            text = String(text[..<dash])
        }

        let core = text.split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3 else { return nil }
        var numbers: [Int] = []
        for component in core {
            guard let value = Self.number(String(component)) else { return nil }
            numbers.append(value)
        }

        self.init(
            major: numbers[0],
            minor: numbers[1],
            patch: numbers[2],
            prereleaseIdentifiers: prerelease,
            buildMetadataIdentifiers: buildMetadata
        )
    }

    /// SemVer 2.0 §10: two versions are equal when their precedence is equal, so build metadata is
    /// not part of identity. This is written out because a synthesized `==` would compare the build
    /// identifiers too, and `1.2.3+build.1` would stop equalling `1.2.3`.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers
    }

    /// Hashes the same fields `==` compares.
    ///
    /// Written out rather than synthesized because a synthesized version would include the build
    /// identifiers, breaking the `Hashable` contract: equal versions must hash equally, otherwise a
    /// `Set` keeps `1.2.3+build.1` and `1.2.3` as two elements even though they are equal.
    func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prereleaseIdentifiers)
    }

    /// SemVer 2.0 §11: core fields numerically, then a stable version above any pre-release of the
    /// same core version, then pre-release identifiers field by field.
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prereleaseIdentifiers.isEmpty != rhs.prereleaseIdentifiers.isEmpty {
            return rhs.prereleaseIdentifiers.isEmpty
        }
        for (left, right) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if left != right { return identifierPrecedes(left, right) }
        }
        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }

    var description: String {
        var text = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            text += "-\(prereleaseIdentifiers.joined(separator: "."))"
        }
        if !buildMetadataIdentifiers.isEmpty {
            text += "+\(buildMetadataIdentifiers.joined(separator: "."))"
        }
        return text
    }

    /// SemVer 2.0 §11.4: numeric identifiers compare numerically and rank below alphanumeric ones.
    private static func identifierPrecedes(_ left: String, _ right: String) -> Bool {
        let leftIsNumeric = isNumeric(left)
        let rightIsNumeric = isNumeric(right)
        switch (leftIsNumeric, rightIsNumeric) {
        case (true, true):
            return (Int(left) ?? 0) < (Int(right) ?? 0)
        case (true, false):
            return true
        case (false, true):
            return false
        case (false, false):
            return left < right
        }
    }

    /// A dot-separated identifier list. Every part must be non-empty and alphanumeric with dashes,
    /// and a numeric part must not carry a leading zero.
    private static func identifiers(_ text: String) -> [String]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy(isIdentifier) else { return nil }
        for part in parts where isNumeric(part) {
            guard number(part) != nil else { return nil }
        }
        return parts
    }

    /// A decimal integer without a leading zero, which is what SemVer means by a numeric field.
    private static func number(_ text: String) -> Int? {
        guard isNumeric(text), text.count == 1 || !text.hasPrefix("0") else { return nil }
        return Int(text)
    }

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
