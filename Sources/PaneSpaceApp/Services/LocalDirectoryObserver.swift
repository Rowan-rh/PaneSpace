import Darwin
import Dispatch
import Foundation

@MainActor
final class LocalDirectoryObserver {
    private var source: DispatchSourceFileSystemObject?
    private var observedURL: URL?
    private var onChange: (() -> Void)?
    private var debounceTask: Task<Void, Never>?

    func observe(_ url: URL, onChange: @escaping () -> Void) {
        let url = url.standardizedFileURL
        if observedURL == url, source != nil {
            self.onChange = onChange
            return
        }
        stop()
        observedURL = url
        self.onChange = onChange
        openSource(for: url)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        observedURL = nil
        onChange = nil
    }

    private func openSource(for url: URL) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: .main
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let events = newSource?.data else { return }
            Task { @MainActor [weak self] in
                guard let self, self.observedURL == url else { return }
                self.scheduleRefresh()
                if events.contains(.delete) || events.contains(.rename) {
                    self.source?.cancel()
                    self.source = nil
                    if let observedURL = self.observedURL {
                        self.openSource(for: observedURL)
                    }
                }
            }
        }
        newSource.setCancelHandler { close(descriptor) }
        source = newSource
        newSource.resume()
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
