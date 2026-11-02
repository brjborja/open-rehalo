import XCTest
import CryptoKit
@testable import SH2Protocol

/// Mirrors `sh2-core/test/crypto.test.mjs`. The "device" side is simulated with a second
/// CryptoKit P256 key, exactly as the JS test uses a second `createECDH` instance.
final class CryptoTests: XCTestCase {

    func testPublicKeyXYIs64Bytes() {
        let kp = Crypto.generateKeyPair()
        XCTAssertEqual(Crypto.publicKeyXY(kp).count, 64)
    }

    func testECDHBothSidesDeriveSameKeyMaterial() throws {
        let central = Crypto.generateKeyPair()
        let device = P256.KeyAgreement.PrivateKey()
        let periphXY = Data(device.publicKey.x963Representation.dropFirst()) // 64 B
        let seed = Data([0xde, 0xad, 0xbe, 0xef])

        let keys = try Crypto.deriveSecret(privateKey: central, periphPubKeyXY: periphXY, seed: seed)

        // Device derives its own side and applies the same seed patch.
        let centralPub = try P256.KeyAgreement.PublicKey(
            x963Representation: Data([0x04]) + Crypto.publicKeyXY(central))
        var devSecret = (try device.sharedSecretFromKeyAgreement(with: centralPub))
            .withUnsafeBytes { Data($0) }
        devSecret.replaceSubrange(16..<20, with: seed)

        XCTAssertEqual(keys.key, devSecret.subdata(in: 0..<16), "AES key matches")
        XCTAssertEqual(keys.iv, devSecret.subdata(in: 16..<32), "IV matches")
    }

    func testAESRoundTripAcrossECDHPeers() throws {
        let central = Crypto.generateKeyPair()
        let device = P256.KeyAgreement.PrivateKey()
        let periphXY = Data(device.publicKey.x963Representation.dropFirst())
        let seed = Data([1, 2, 3, 4])
        let keys = try Crypto.deriveSecret(privateKey: central, periphPubKeyXY: periphXY, seed: seed)

        let centralPub = try P256.KeyAgreement.PublicKey(
            x963Representation: Data([0x04]) + Crypto.publicKeyXY(central))
        var devSecret = (try device.sharedSecretFromKeyAgreement(with: centralPub))
            .withUnsafeBytes { Data($0) }
        devSecret.replaceSubrange(16..<20, with: seed)

        let msg = Data([0, 3, 65, 66, 67]) // authenticate "ABC"
        let ct = try Crypto.encrypt(key: keys.key, iv: keys.iv, plaintext: msg)
        XCTAssertEqual(ct.count % 16, 0, "ciphertext is a multiple of 16")
        let pt = try Crypto.decrypt(
            key: devSecret.subdata(in: 0..<16),
            iv: devSecret.subdata(in: 16..<32),
            ciphertext: ct)
        XCTAssertEqual(pt, msg)
    }

    func testAESSelfRoundTrip() throws {
        let key = Data(repeating: 0xAB, count: 16)
        let iv = Data(repeating: 0xCD, count: 16)
        let msg = Data([1, 4, 1, 0])
        let ct = try Crypto.encrypt(key: key, iv: iv, plaintext: msg)
        let pt = try Crypto.decrypt(key: key, iv: iv, ciphertext: ct)
        XCTAssertEqual(pt, msg)
    }

    func testResetChallengeEqualsManualSHA256() throws {
        let seed = Data([0x11, 0x22, 0x33, 0x44])
        let salt = Data(repeating: 0xab, count: 16)
        let got = try Crypto.resetPasswordChallenge(seed: seed, salt: salt)
        var h = SHA256(); h.update(data: seed); h.update(data: salt)
        XCTAssertEqual(got, Data(h.finalize()))
        XCTAssertEqual(got.count, 32)
    }

    func testResetChallengeWithEmbeddedFirmwareSalt() throws {
        XCTAssertEqual(FirmwareConstants.authSalt.count, 16)
        // Firmware dev seed from auth.c (auth_seed before randomization) — sanity only.
        let seed = Data([0x11, 0x22, 0x33, 0x44])
        let got = try Crypto.resetPasswordChallenge(seed: seed, salt: FirmwareConstants.authSalt)
        XCTAssertEqual(got.count, 32)
    }

    func testDeriveSecretRejectsBadSizes() {
        let kp = Crypto.generateKeyPair()
        XCTAssertThrowsError(try Crypto.deriveSecret(privateKey: kp, periphPubKeyXY: Data(count: 10), seed: Data(count: 4)))
        XCTAssertThrowsError(try Crypto.deriveSecret(privateKey: kp, periphPubKeyXY: Data(count: 64), seed: Data(count: 3)))
    }
}
