import Foundation

/// Logical session over a connectable BLE `Transport`. Orchestrates the ECDH→AES handshake and
/// `transceive` sequencing with bslink framing.
///
/// 1:1 port of `sh2-core/src/session.mjs`. The JS version relies on Node's single-threaded event
/// loop to keep notification callbacks ordered; here the same ordering is provided by a single
/// consumer loop over `Transport.notificationStream()`, and all mutable state is isolated to this
/// actor.
public actor Session {

    public enum SessionError: Error, Sendable {
        case transceiveInProgress
        case commandFailed(step: String, code: UInt8?)
        case malformedReply(step: String)
        case closed
        /// The device never replied to a command within the timeout window.
        case timeout(step: String)
        /// The BLE link dropped while a command was in flight (common right after `resetPassword`,
        /// which un-pairs the device and may reset the connection).
        case disconnected
    }

    /// Per round-trip reply timeout. A healthy device answers in well under a second; 8s leaves
    /// generous headroom while still breaking the previously-infinite wait.
    public static var replyTimeout: Duration = .seconds(8)

    private let transport: Transport
    private var cipher: Crypto.LinkKeys?

    // DOWN channel accumulation (request/reply).
    private var downAccum = Data()
    private var pending: CheckedContinuation<Data, Error>?
    /// Monotonic id of the in-flight request, so a late timeout only fires for its own request.
    private var pendingID: UInt64 = 0
    /// Human label of the in-flight request, for log lines.
    private var pendingLabel = ""

    // UP channel accumulation (unsolicited notifications).
    private var upAccum = Data()
    private var notificationHandler: (@Sendable (Data) -> Void)?

    private var consumer: Task<Void, Never>?

    /// True once `authenticate` has succeeded.
    public private(set) var isAuthenticated = false

    public init(transport: Transport) {
        self.transport = transport
    }

    /// Demo/testing ONLY: mark the session authenticated without the ECDH→AES handshake, so a mock
    /// transport that replies in plaintext can drive the full command path. The real cipher stays
    /// `nil`, so every `transceive` is sent in plaintext. Never used against a real device.
    public func authenticateForDemo() {
        isAuthenticated = true
    }

    /// Port of `Session.open()`: enable notifications and start consuming the notification stream.
    public func open() async throws {
        SH2Log.log("session: enabling notifications…")
        try await transport.enableNotifications()
        SH2Log.log("session: notifications enabled, consuming")
        let stream = transport.notificationStream()
        consumer = Task { [weak self] in
            // Single sequential consumer → notifications are handled strictly in arrival order.
            for await note in stream {
                await self?.handle(note)
            }
            // The stream only ends when the transport tears down — i.e. the link dropped. Break any
            // in-flight request instead of letting its `await` hang forever.
            await self?.onStreamEnded()
        }
    }

    private func onStreamEnded() {
        SH2Log.log("session: notification stream ended — BLE link closed")
        failPending(SessionError.disconnected)
    }

    /// Stop consuming and fail any in-flight request.
    public func close() {
        consumer?.cancel()
        consumer = nil
        failPending(SessionError.closed)
    }

    /// Install a handler for unsolicited UP-channel notifications (e.g. alarm reports).
    public func setNotificationHandler(_ handler: (@Sendable (Data) -> Void)?) {
        notificationHandler = handler
    }

    // MARK: - Notification routing (runs serially, in order)

    private func handle(_ note: SH2Notification) {
        let u = note.uuid.uppercased()
        if Frame.UUIDs.payload.contains(u) {
            downAccum.append(note.data)
        } else if u == Frame.UUIDs.ctrl {
            onCtrl(note.data)
        } else if Frame.UUIDs.upPayload.contains(u) {
            upAccum.append(note.data)
        } else if u == Frame.UUIDs.upCtrl {
            onUpCtrl(note.data)
        }
        // Unknown UUIDs are ignored.
    }

    /// Port of `_onCtrl`: a DOWN CTRL completes the pending reply.
    private func onCtrl(_ ctrl: Data) {
        guard let p = pending else { downAccum = Data(); return }
        pending = nil
        do {
            let reply = try Frame.decodeReply(ctrl: ctrl, payloadAccum: downAccum, cipher: cipher)
            downAccum = Data()
            SH2Log.log("← \(pendingLabel)  [\(SH2Log.hex(reply))]")
            p.resume(returning: reply)
        } catch {
            downAccum = Data()
            SH2Log.log("✗ \(pendingLabel): decode failed — \(error)")
            p.resume(throwing: error)
        }
    }

    /// Port of `_onUpCtrl`: a UP CTRL completes an unsolicited notification.
    private func onUpCtrl(_ ctrl: Data) {
        do {
            let data = try Frame.decodeReply(ctrl: ctrl, payloadAccum: upAccum, cipher: cipher)
            upAccum = Data()
            notificationHandler?(data)
        } catch {
            upAccum = Data()
        }
    }

    private func failPending(_ error: Error) {
        guard let p = pending else { return }
        pending = nil
        downAccum = Data()
        SH2Log.log("✗ \(pendingLabel): \(error)")
        p.resume(throwing: error)
    }

    /// Fail the in-flight request if it is still the one identified by `id` (a late timeout must not
    /// clobber a subsequent request that already reused the `pending` slot).
    private func timeoutGuard(_ id: UInt64) async {
        try? await Task.sleep(for: Session.replyTimeout)
        guard pending != nil, pendingID == id else { return }
        SH2Log.log("✗ \(pendingLabel): no reply within \(Session.replyTimeout)")
        failPending(SessionError.timeout(step: pendingLabel))
    }

    // MARK: - transceive

    /// Send an application payload and await the reply. Port of `Session.transceive`.
    ///
    /// `crypted == nil` means "encrypt iff a cipher has been established" (matches the JS default).
    /// The REQUEST's encryption is controlled by this flag; the REPLY is decoded according to the
    /// `crypted` bit in its own CTRL using whatever cipher is currently set — which is why the
    /// handshake sets `cipher` *before* sending `setCentralPubKey` (the device encrypts that reply).
    @discardableResult
    public func transceive(_ appData: Data, crypted: Bool? = nil, label: String = "") async throws -> Data {
        if pending != nil { throw SessionError.transceiveInProgress }
        let useCipher = (crypted ?? (cipher != nil)) ? cipher : nil
        let encoded = try Frame.encodeMessage(appData, cipher: useCipher)
        let tag = label.isEmpty ? "cmd \(SH2Log.hex(appData, max: 4))" : label
        SH2Log.log("→ \(tag)  [\(SH2Log.hex(appData))]")

        pendingID &+= 1
        let myID = pendingID
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            // `pending` is committed here (synchronously, on the actor) BEFORE any write is sent,
            // so the reply — which can only arrive after the device receives our CTRL — always
            // finds it. The device cannot reply before the final CTRL write completes.
            self.pending = cont
            self.pendingLabel = tag
            Task { await self.sendFrames(encoded) }
            // Backstop: if no reply (device ignored the command, or the link stalled without a
            // clean disconnect), fail after the timeout instead of hanging forever.
            Task { await self.timeoutGuard(myID) }
        }
    }

    private func sendFrames(_ encoded: Frame.Encoded) async {
        do {
            for (i, chunk) in encoded.chunks.enumerated() {
                try await transport.writeNoResponse(uuid: Frame.UUIDs.payload[i], data: chunk)
            }
            // The CTRL write triggers processing on the device (`bslink_recv`).
            try await transport.writeNoResponse(uuid: Frame.UUIDs.ctrl, data: encoded.ctrl)
        } catch {
            failPending(error)
        }
    }

    // MARK: - Handshake

    /// Full handshake. After success, frames are encrypted and the session is authenticated.
    /// Port of `Session.handshake(password)`. Pass empty `Data()` for an unpaired device.
    public func handshake(password: Data) async throws {
        SH2Log.log("handshake: start (password \(password.isEmpty ? "EMPTY/unpaired" : "\(password.count)B"))")
        // 1. getPeriphPubKey (plaintext) -> [OK, pub(64), seed(4)]
        let r = try await transceive(Commands.getPeriphPubKey(), crypted: false, label: "getPeriphPubKey")
        let rb = [UInt8](r)
        guard rb.count >= 69 else { throw SessionError.malformedReply(step: "getPeriphPubKey") }
        guard rb[0] == ReturnCode.ok.rawValue else {
            throw SessionError.commandFailed(step: "getPeriphPubKey", code: rb.first)
        }
        let periphPub = Data(rb[1..<65])
        let seed = Data(rb[65..<69])

        // 2. derive secret, and set the cipher BEFORE setCentralPubKey (see transceive note).
        let kp = Crypto.generateKeyPair()
        let keys = try Crypto.deriveSecret(privateKey: kp, periphPubKeyXY: periphPub, seed: seed)
        cipher = keys
        SH2Log.log("handshake: ECDH secret derived (seed \(SH2Log.hex(seed)))")

        // 3. setCentralPubKey (plaintext request) -> [OK]
        let r2 = try await transceive(Commands.setCentralPubKey(Crypto.publicKeyXY(kp)), crypted: false, label: "setCentralPubKey")
        guard [UInt8](r2).first == ReturnCode.ok.rawValue else {
            throw SessionError.commandFailed(step: "setCentralPubKey", code: [UInt8](r2).first)
        }

        // 4. authenticate (encrypted) -> [OK]
        let r3 = try await transceive(Commands.authenticate(password), crypted: true, label: "authenticate")
        guard [UInt8](r3).first == ReturnCode.ok.rawValue else {
            throw SessionError.commandFailed(step: "authenticate", code: [UInt8](r3).first)
        }
        isAuthenticated = true
        SH2Log.log("handshake: OK — authenticated, link encrypted")
    }

    /// Convenience overload: UTF-8 encode a string password (device passwords are 32 ASCII chars).
    public func handshake(password: String) async throws {
        try await handshake(password: Data(password.utf8))
    }
}
