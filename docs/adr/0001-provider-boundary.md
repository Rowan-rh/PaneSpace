# ADR 0001: Provider boundary for storage access

- Status: Accepted
- Date: 2026-09-19

## Context

PaneSpace needs to browse local disks first and later add SFTP, SMB, WebDAV, and other storage without duplicating navigation UI or leaking protocol details into views.

## Decision

Storage access is placed behind provider contracts. Views depend on pane state; pane state depends on provider behavior. File metadata uses provider-neutral value types. Providers will expose explicit capabilities because remote systems do not uniformly support Trash, atomic rename, thumbnails, server-side copy, or file watching.

The MVP's synchronous `FileProviding` protocol is a temporary local-only seam. Before adding remote storage, it will evolve into an asynchronous, cancellable API with normalized errors and stable provider item identifiers.

## Consequences

- Navigation UI can remain shared across providers.
- Capability checks are explicit rather than inferred from URL schemes.
- Remote-provider work requires an API evolution before implementation.
- Tests can substitute deterministic provider fixtures.
