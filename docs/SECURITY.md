# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature instead of opening a public issue for credential exposure, arbitrary code execution, path traversal, destructive file-operation defects, or authentication bypasses.

Include the affected version, reproduction steps, expected impact, and any suggested mitigation. Do not include real credentials or private user files in the report.

## Security boundaries

- Local access is limited by the permissions granted to the PaneSpace process.
- Remote credentials must be stored in macOS Keychain.
- Provider responses, archive paths, filenames, and remote metadata are untrusted input.
- File operations must validate destinations and avoid implicit overwrites.
- Plug-ins are not supported until a signing, permission, and isolation model is designed.

Only the latest development version is supported before the 1.0 release.
