import Darwin
import Foundation
import Synchronization

/// Bytes finished by a running copy, shared between the copying task and the queue that shows it.
final class TransferByteCounter: Sendable {
    private let bytes = Mutex<Int64>(0)

    var value: Int64 {
        bytes.withLock { $0 }
    }

    func set(_ newValue: Int64) {
        bytes.withLock { $0 = newValue }
    }
}

/// Copies a local item with `copyfile(3)` so the transfer can report bytes and stop mid-file.
///
/// The flags match what `FileManager.copyItem` preserves (data, extended attributes, ACLs and
/// timestamps; symbolic links are copied as links) and ask for an APFS clone when possible. A
/// clone finishes instantly without data callbacks, so finished files count their full size.
enum LocalFileCopier {
    static func copy(from source: URL, to destination: URL, progress: TransferByteCounter?) throws {
        let context = CopyContext(counter: progress)
        let unmanaged = Unmanaged.passRetained(context)
        defer { unmanaged.release() }

        guard let state = copyfile_state_alloc() else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { copyfile_state_free(state) }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyCallback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), unmanaged.toOpaque())

        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_CLONE)
        let result = copyfile(source.path, destination.path, state, flags)
        let failure = errno
        if context.wasCancelled || Task.isCancelled {
            throw CancellationError()
        }
        guard result == 0 else {
            throw error(for: failure, source: source)
        }
    }

    /// Logical size of an item and everything inside it, without following symbolic links.
    static func byteCount(of url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = FileManager().enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let childValues = try? child.resourceValues(forKeys: keys)
            if childValues?.isDirectory != true {
                total += Int64(childValues?.fileSize ?? 0)
            }
        }
        return total
    }

    private static func error(for code: Int32, source: URL) -> Error {
        let userInfo: [String: Any] = [NSFilePathErrorKey: source.path]
        switch code {
        case EACCES, EPERM:
            return CocoaError(.fileWriteNoPermission, userInfo: userInfo)
        case ENOSPC:
            return CocoaError(.fileWriteOutOfSpace, userInfo: userInfo)
        case ENOENT:
            return CocoaError(.fileReadNoSuchFile, userInfo: userInfo)
        case EEXIST:
            return CocoaError(.fileWriteFileExists, userInfo: userInfo)
        default:
            return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: userInfo)
        }
    }
}

private final class CopyContext {
    let counter: TransferByteCounter?
    var finishedFileBytes: Int64 = 0
    var wasCancelled = false

    init(counter: TransferByteCounter?) {
        self.counter = counter
    }
}

// The callback runs synchronously on the thread of the task that called `copyfile`, so
// `Task.isCancelled` reflects that task.
private let copyCallback: copyfile_callback_t = { what, stage, state, source, _, contextPointer in
    guard let contextPointer else { return COPYFILE_CONTINUE }
    let context = Unmanaged<CopyContext>.fromOpaque(contextPointer).takeUnretainedValue()
    if Task.isCancelled {
        context.wasCancelled = true
        return COPYFILE_QUIT
    }
    if stage == COPYFILE_ERR {
        return COPYFILE_QUIT
    }
    if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
        var copied: off_t = 0
        copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
        context.counter?.set(context.finishedFileBytes + Int64(copied))
    } else if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH {
        var status = stat()
        if let source, lstat(source, &status) == 0 {
            context.finishedFileBytes += Int64(status.st_size)
        }
        context.counter?.set(context.finishedFileBytes)
    }
    return COPYFILE_CONTINUE
}
