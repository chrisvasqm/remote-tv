import Testing
@testable import RemoteTV

@MainActor
struct NudgeTests {
    @Test func waitEndsAtTheLimit() async {
        let nudge = Nudge()
        let clock = ContinuousClock()
        let started = clock.now
        await nudge.wait(upTo: .milliseconds(50))
        #expect(clock.now - started >= .milliseconds(50))
    }

    @Test func fireEndsAWaitEarly() async {
        let nudge = Nudge()
        let clock = ContinuousClock()
        let started = clock.now
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            nudge.fire()
        }
        await nudge.wait(upTo: .seconds(5))
        #expect(clock.now - started < .seconds(1))
    }

    @Test func aFireWhileBusyEndsTheNextWaitAtOnce() async {
        let nudge = Nudge()
        nudge.fire()
        let clock = ContinuousClock()
        let started = clock.now
        await nudge.wait(upTo: .seconds(5))
        #expect(clock.now - started < .seconds(1))
    }
}
