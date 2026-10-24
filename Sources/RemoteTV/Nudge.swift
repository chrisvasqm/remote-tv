/// Lets the driver sleep until a deadline or until an intent needs it, whichever comes first.
@MainActor
final class Nudge {
    private var waiter: CheckedContinuation<Void, Never>?
    /// A `fire()` while the driver was busy, so its next wait returns at once.
    private var pending = false

    /// Returns after `limit`, or earlier when `fire()` is called.
    func wait(upTo limit: Duration) async {
        if pending {
            pending = false
            return
        }
        await withCheckedContinuation { continuation in
            waiter = continuation
            // A timer from an earlier wait may end this one early; the driver just loops again.
            Task {
                try? await Task.sleep(for: limit)
                resume()
            }
        }
    }

    func fire() {
        if waiter == nil { pending = true }
        resume()
    }

    private func resume() {
        waiter?.resume()
        waiter = nil
    }
}
