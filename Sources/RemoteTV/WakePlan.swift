import Foundation

/// A Wake-on-LAN attempt: packets for the first few steps, a connect at each later
/// step, until the TV answers or the deadline passes.
struct WakePlan: Equatable {
    let host: String
    let mac: String
    let deadline: ContinuousClock.Instant
    var step = 0
    var nextStep: ContinuousClock.Instant
}
