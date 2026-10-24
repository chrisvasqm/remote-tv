/// A screen off/on the user asked for. The panel shows `off` at once; `previous` is
/// put back if the TV refuses and no newer change is waiting.
struct ScreenChange {
    let off: Bool
    let previous: Bool
}
