import Foundation

/// Constants extracted verbatim from the public SmartHalo 2 firmware source.
///
/// Port target: these are the magic values the JS `sh2-core` reads from the firmware
/// at runtime (`clients/linux/src/find-salt.mjs`). On iOS we embed them as constants.
public enum FirmwareConstants {
    /// 16-byte reset-challenge salt.
    ///
    /// Source: the public firmware source (`auth.c`)
    /// `Code/Firmware/shapp/src/auth.c:198`
    /// ```c
    /// ```
    /// Used by `Crypto.resetPasswordChallenge` = SHA-256(seed(4) ‖ salt(16)), matching
    /// `auth.c::auth_cmd_resetPassword` (sha256_update(seed,4); sha256_update(salt,16)).
    public static let authSalt = Data([
        0x70, 0x5f, 0x71, 0xc5, 0x90, 0x61, 0x9e, 0x0c,
        0xb9, 0x9d, 0x34, 0x70, 0x7d, 0x23, 0x60, 0xd8,
    ])
}
