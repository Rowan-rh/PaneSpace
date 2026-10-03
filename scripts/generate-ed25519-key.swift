#!/usr/bin/env swift
// Generate an Ed25519 key pair for PaneSpace update signatures.
//
//   generate-ed25519-key.swift <private-key-out> <public-key-out>
//
// Both files hold a single base64 line: the raw 32-byte private seed and the raw
// 32-byte public key. This is the format scripts/ed25519.swift signs and
// verifies, and the same one Sparkle's EdDSA support expects.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    fail("usage: generate-ed25519-key.swift <private-key-out> <public-key-out>")
}

let key = Curve25519.Signing.PrivateKey()
let privateKey = key.rawRepresentation.base64EncodedString()
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()

do {
    try privateKey.write(toFile: arguments[0], atomically: true, encoding: .utf8)
    try (publicKey + "\n").write(toFile: arguments[1], atomically: true, encoding: .utf8)
} catch {
    fail("cannot write the key files")
}

// Print only the public key. The private seed must reach the operator through the
// file, never through a terminal that ends up in a screenshot or scrollback.
print(publicKey)
