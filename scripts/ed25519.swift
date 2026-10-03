#!/usr/bin/env swift
// Ed25519 signing / verification for PaneSpace release archives.
//
// CryptoKit is used instead of OpenSSL so the behaviour does not depend on the
// OpenSSL version shipped on the runner. Signatures are raw 64-byte Ed25519
// signatures, base64 encoded, matching the Sparkle `EdDSA` file format.
//
//   ed25519.swift sign   <file> <signature-out>
//   ed25519.swift verify <file> <signature-base64> <public-key-base64>
//
// The private key is read only from the PANESPACE_ED25519_PRIVATE_KEY environment
// variable, never from argv: a process argument is visible to every other process
// on the machine and would show up in the workflow's process list. It is never
// printed either.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func base64Data(_ string: String, label: String) -> Data {
    guard let data = Data(base64Encoded: string), !data.isEmpty else {
        fail("\(label) is not valid base64")
    }
    return data
}

/// The private key is the raw 32-byte Ed25519 seed in base64, matching the file
/// written by `generate-signing-identity.sh`. Anything else is rejected rather
/// than guessed at, so a mangled secret fails the release instead of producing an
/// unverifiable signature.
func privateKey() throws -> Curve25519.Signing.PrivateKey {
    guard let value = ProcessInfo.processInfo.environment["PANESPACE_ED25519_PRIVATE_KEY"],
          !value.isEmpty else {
        fail("PANESPACE_ED25519_PRIVATE_KEY is not set")
    }
    let data = base64Data(value, label: "private key")
    guard data.count == 32 else {
        fail("private key must be a 32-byte Ed25519 seed, got \(data.count) bytes")
    }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("usage: ed25519.swift sign <file> <sig-out> | verify <file> <sig-b64> <pub-b64>")
}

switch command {
case "sign":
    guard arguments.count == 3 else {
        fail("usage: ed25519.swift sign <file> <sig-out>")
    }
    let (file, output) = (arguments[1], arguments[2])
    guard let contents = FileManager.default.contents(atPath: file) else {
        fail("cannot read \(URL(fileURLWithPath: file).lastPathComponent)")
    }
    let signature = try privateKey().signature(for: Data(contents))
    do {
        try signature.base64EncodedString().write(toFile: output, atomically: true, encoding: .utf8)
    } catch {
        fail("cannot write signature file")
    }
    print("signed \(URL(fileURLWithPath: file).lastPathComponent) -> \(URL(fileURLWithPath: output).lastPathComponent)")

case "verify":
    guard arguments.count == 4 else {
        fail("usage: ed25519.swift verify <file> <sig-b64> <pub-b64>")
    }
    let (file, signature, publicKey) = (arguments[1], arguments[2], arguments[3])
    let signatureData = base64Data(signature, label: "signature")
    let publicKeyData = base64Data(publicKey, label: "public key")
    guard signatureData.count == 64 else {
        fail("signature must be 64 raw bytes (Ed25519), got \(signatureData.count)")
    }
    guard publicKeyData.count == 32 else {
        fail("public key must be 32 raw bytes (Ed25519), got \(publicKeyData.count)")
    }
    guard let contents = FileManager.default.contents(atPath: file) else {
        fail("cannot read \(URL(fileURLWithPath: file).lastPathComponent)")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    if key.isValidSignature(signatureData, for: Data(contents)) {
        print("signature OK: \(URL(fileURLWithPath: file).lastPathComponent)")
    } else {
        fail("signature mismatch for \(URL(fileURLWithPath: file).lastPathComponent)")
    }

default:
    fail("unknown command '\(command)'")
}
