#!/bin/zsh
# Generate the PaneSpace release signing material. Run this on Rowan's own Mac;
# the real key material never enters the repository or an agent workspace.
#
#   scripts/generate-signing-identity.sh <output-directory>
#
# Produces, in <output-directory> (created if missing, mode 700):
#   panespace-signing.p12      10-year self-signed code-signing certificate
#   panespace-signing-pass.txt random .p12 password, mode 600
#   ed25519-private-key.txt    base64 32-byte Ed25519 seed, mode 600
#   ed25519-public-key.txt     base64 32-byte Ed25519 public key, mode 644
#
# The script prints which GitHub Actions secrets to create. It does not create
# them, does not upload anything, and never prints the password or private key.
set -euo pipefail

die() {
    print -u2 "error: $1"
    exit 1
}

[[ $# -eq 1 ]] || die "usage: ${0:t} <output-directory>"
output_dir="$1"
[[ -n "$output_dir" ]] || die "output directory must not be empty"

# Refuse to write into the repository: these files must never be committed.
project_dir="${0:A:h:h}"
output_dir="${output_dir:A}"
if [[ "$output_dir" == "$project_dir" || "$output_dir" == "$project_dir"/* ]]; then
    die "refusing to write key material inside the repository ($project_dir)"
fi

command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v security >/dev/null 2>&1 || die "security(1) is required"
command -v swift >/dev/null 2>&1 || die "swift is required"

mkdir -p "$output_dir"
chmod 700 "$output_dir"
# Generated artefacts are sensitive; keep them out of shell history and Spotlight
# index growth.
umask 077

p12_path="$output_dir/panespace-signing.p12"
password_path="$output_dir/panespace-signing-pass.txt"
private_key_path="$output_dir/ed25519-private-key.txt"
public_key_path="$output_dir/ed25519-public-key.txt"

# Random per-run passwords: reusing one would let a leaked .p12 unlock every
# future release.
password="$(openssl rand -base64 32 | tr -d '\n' | tr '/+' '_-')"
if (( ${#password} < 24 )); then
    die "failed to generate a strong password"
fi

# Subject and extensions chosen for a free self-signed code-signing certificate.
# extendedKeyUsage=codeSigning is what makes codesign accept it; keyUsage
# d(nl)igitalSignature is required for signing to be valid. A 10-year validity
# keeps every installed copy's TCC grants valid without re-authorising users.
subject="/CN=PaneSpace Self-Signed/O=PaneSpace"
days=3650

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
openssl req -x509 -newkey rsa:4096 -sha256 -days "$days" -nodes \
    -keyout "$tmp_dir/key.pem" -out "$tmp_dir/cert.pem" \
    -subj "$subject" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" \
    2>/dev/null || die "failed to create the self-signed certificate"

# Validate the produced certificate before handing it over, so a missing
# extension is caught here instead of at codesign time in CI.
#
# The output is read into a variable before it is matched, for the reason given in
# f4847d0 for build-app.sh: under `set -o pipefail`, `openssl ... | grep -q` is a
# coin flip, because grep exits on the first match and the tool still writing gets
# SIGPIPE, which pipefail reports as a failed pipeline. It does not bite at this
# size -- the text of one certificate is ~3 KB and fits in the pipe buffer -- but
# the check would then pass or fail for reasons unrelated to the certificate.
certificate_text="$(openssl x509 -in "$tmp_dir/cert.pem" -noout -text 2>/dev/null)"
if [[ "$certificate_text" != *"Code Signing"* ]]; then
    die "generated certificate is missing extendedKeyUsage=codeSigning"
fi

# OpenSSL 3 writes PKCS#12 with AES-256-CBC/PBES2, which `security import`
# rejects; -legacy emits the classic algorithms the macOS keychain understands.
# -passout env: keeps the password out of argv, where any other process on the
# machine could read it.
P12_PASSWORD="$password" openssl pkcs12 -export -legacy \
    -inkey "$tmp_dir/key.pem" -in "$tmp_dir/cert.pem" \
    -out "$p12_path" -passout env:P12_PASSWORD \
    2>/dev/null || die "failed to export the .p12 (OpenSSL 3 needs -legacy)"

# Prove the .p12 is importable before printing success: an unusable .p12 would
# only fail later inside CI. Create the probe keychain first, then import into it.
probe_keychain="$tmp_dir/probe.keychain-db"
security create-keychain -p "$password" "$probe_keychain" >/dev/null 2>&1 \
    || die "failed to create a temporary probe keychain"
security unlock-keychain -p "$password" "$probe_keychain" >/dev/null 2>&1
if ! security import "$p12_path" -k "$probe_keychain" -P "$password" \
    -T /usr/bin/codesign -A >/dev/null 2>&1; then
    die "the .p12 could not be imported by security(1); check the OpenSSL version"
fi
security delete-keychain "$probe_keychain" >/dev/null 2>&1

# Ed25519 update-signing key, generated through CryptoKit so the format matches
# what scripts/ed25519.swift and Sparkle expect (raw seed/public key, base64).
"$project_dir/scripts/generate-ed25519-key.swift" "$private_key_path" "$public_key_path" \
    || die "failed to generate the Ed25519 key pair"

print -n "$password" > "$password_path"
chmod 600 "$p12_path" "$password_path" "$private_key_path"
chmod 644 "$public_key_path"

public_key="$(cat "$public_key_path")"
if [[ ! "$public_key" =~ '^[A-Za-z0-9+/]{43}=$' ]]; then
    die "generated public key is not a base64 32-byte Ed25519 key"
fi

# -r keeps the backslashes in the commands below literal. Without it zsh's print
# interprets the escapes and the emitted `tr -d '\n'` is split across two lines.
print "PaneSpace signing material written to: $output_dir"
print ""
print "Next steps. These commands pipe the files straight into gh, so the secret"
print "never lands in your shell history or on the clipboard:"
print ""
print -r -- "  gh secret set PANESPACE_CERT_P12_BASE64 --repo Rowan-rh/PaneSpace \\"
print -r -- "    < <(base64 -i '$p12_path' | tr -d '\n')"
print -r -- "  gh secret set PANESPACE_CERT_P12_PASSWORD --repo Rowan-rh/PaneSpace \\"
print -r -- "    < '$password_path'"
print -r -- "  gh secret set PANESPACE_ED25519_PRIVATE_KEY --repo Rowan-rh/PaneSpace \\"
print -r -- "    < '$private_key_path'"
print ""
print "  Then commit the PUBLIC key to scripts/update-public-ed25519.txt:"
print "    $public_key"
print ""
print "Keep the directory out of version control and delete it once the secrets exist."
