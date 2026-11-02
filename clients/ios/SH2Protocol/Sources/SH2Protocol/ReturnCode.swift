import Foundation

/// Command return codes. Port of `RET` in `sh2-core/src/commands.mjs` and
/// §7 of `docs/protocol/ble-link.md`.
///
/// The first byte of every decoded reply is one of these.
public enum ReturnCode: UInt8, Sendable {
    case ok = 0            // RET_OK          — success
    case fail = 1          // RET_FAIL        — generic/unknown failure
    case denied = 2        // RET_DENIED      — no permission (not authenticated)
    case unimplemented = 3 // RET_UNIMPLEMENTED
    case unnecessary = 4   // RET_UNNECESSARY — (app side only)
}
