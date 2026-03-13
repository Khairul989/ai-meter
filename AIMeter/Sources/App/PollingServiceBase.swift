import Foundation

@MainActor
class PollingServiceBase: ObservableObject {
    private var timer: Timer?

    func start(interval: TimeInterval) {
        timer?.invalidate()
        Task { await tick() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func rescheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.tick() }
        }
    }

    /// Override in subclasses to perform the actual fetch
    func tick() async {
        // Subclasses override
    }
}
