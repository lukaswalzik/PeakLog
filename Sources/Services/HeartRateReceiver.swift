import Combine
import Darwin
import Foundation
import UIKit

struct HeartRateReading: Equatable {
    let bpm: Int
    let recordedAt: Date
}

/// Receives live heart rate BPM values over local UDP (default: 127.0.0.1:49153),
/// e.g. UTF-8 ASCII integers in 30...240 ("74") sent ~1x/second by airpods-hf-bridge.
final class HeartRateReceiver: ObservableObject {
    static let defaultHost = "127.0.0.1"
    static let defaultPort: UInt16 = 49153
    static let validBPMRange: ClosedRange<Int> = 30...240
    static let signalTimeoutSeconds: TimeInterval = 6.0

    private static let enabledDefaultsKey = "strongtracker.hr.udp_receiver_enabled"

    let host: String
    let port: UInt16

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    @Published private(set) var isListening: Bool = false
    @Published private(set) var currentBPM: Int? = nil
    @Published private(set) var lastSampleAt: Date? = nil
    @Published private(set) var receivedPacketCount: Int = 0
    @Published private(set) var lastError: String? = nil

    /// Emits every valid BPM sample received on the main queue.
    let sampleSubject = PassthroughSubject<HeartRateReading, Never>()

    private let socketQueue = DispatchQueue(label: "com.local.strongtracker.hr-udp", qos: .userInitiated)
    private var readSource: DispatchSourceRead?
    private var activeFD: Int32 = -1
    private var shouldBeListening: Bool = false
    private var stalenessTimer: Timer?
    private var foregroundObserver: NSObjectProtocol?

    var hasLiveSignal: Bool {
        currentBPM != nil
    }

    var endpointDisplay: String {
        "\(host):\(port)"
    }

    init(
        host: String = HeartRateReceiver.defaultHost,
        port: UInt16 = HeartRateReceiver.defaultPort,
        autoStart: Bool = true
    ) {
        self.host = host
        self.port = port

        let storedEnabled: Bool
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil {
            storedEnabled = true
        } else {
            storedEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        }
        self.isEnabled = storedEnabled

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.isEnabled {
                self.restart()
            }
        }

        if autoStart && storedEnabled {
            start()
        }
    }

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stalenessTimer?.invalidate()
        if let source = readSource {
            source.cancel()
        }
    }

    // MARK: - Lifecycle

    func start() {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldBeListening = true
            self.startOnQueue()
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stalenessTimer?.invalidate()
            self.stalenessTimer = nil
            self.currentBPM = nil
            self.isListening = false
            self.lastError = nil
        }
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldBeListening = false
            self.stopOnQueue()
        }
    }

    func restart() {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldBeListening = true
            self.stopOnQueue { [weak self] in
                guard let self = self, self.shouldBeListening else { return }
                self.startOnQueue()
            }
        }
    }

    // MARK: - Parsing

    /// Parses UTF-8 ASCII BPM payloads in 30...240 (e.g. "74" or "74\n").
    static func parseBPM(from data: Data) -> Int? {
        guard !data.isEmpty, data.count <= 64 else { return nil }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))
        let trimmed = raw.trimmingCharacters(in: trimChars)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else {
            return nil
        }
        guard let bpm = Int(trimmed), validBPMRange.contains(bpm) else {
            return nil
        }
        return bpm
    }

    // MARK: - Socket Implementation (socketQueue)

    private func startOnQueue() {
        guard readSource == nil else { return }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            let reason = Self.errnoDescription(Darwin.errno)
            publishSocketState(isListening: false, error: "UDP-Socket fehlgeschlagen (\(reason))")
            return
        }

        var reuseAddr: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        var reusePort: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let ptonStatus = host.withCString { cString in
            Darwin.inet_pton(AF_INET, cString, &addr.sin_addr)
        }
        guard ptonStatus == 1 else {
            Darwin.close(fd)
            publishSocketState(isListening: false, error: "Ungültige Adresse \(host)")
            return
        }

        let bindStatus: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindStatus == 0 else {
            let reason = Self.errnoDescription(Darwin.errno)
            Darwin.close(fd)
            publishSocketState(isListening: false, error: "Bind auf \(host):\(port) fehlgeschlagen (\(reason))")
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: socketQueue)
        source.setEventHandler { [weak self] in
            self?.drainSocketOnQueue(fd: fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }

        self.activeFD = fd
        self.readSource = source
        source.resume()
        publishSocketState(isListening: true, error: nil)
    }

    private func stopOnQueue(completion: (() -> Void)? = nil) {
        guard let source = readSource else {
            completion?()
            return
        }
        let fd = activeFD
        readSource = nil
        activeFD = -1
        source.setEventHandler {}
        source.setCancelHandler {
            if fd >= 0 {
                Darwin.close(fd)
            }
            completion?()
        }
        source.cancel()
    }

    private func drainSocketOnQueue(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 128)
        var iterations = 0
        while iterations < 64 {
            iterations += 1
            let bytesRead = Darwin.recv(fd, &buffer, buffer.count, MSG_DONTWAIT)
            if bytesRead > 0 {
                let payload = Data(bytes: buffer, count: bytesRead)
                if let bpm = Self.parseBPM(from: payload) {
                    let reading = HeartRateReading(bpm: bpm, recordedAt: Date())
                    DispatchQueue.main.async { [weak self] in
                        self?.handleValidReadingOnMain(reading)
                    }
                }
            } else if bytesRead < 0 {
                let err = Darwin.errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    break
                }
                if err == EINTR {
                    continue
                }
                let reason = Self.errnoDescription(err)
                publishSocketState(isListening: false, error: "UDP-Empfangsfehler (\(reason))")
                stopOnQueue()
                break
            } else {
                // 0-byte UDP datagram: ignore and check if further packets are queued.
                continue
            }
        }
    }

    private func publishSocketState(isListening: Bool, error: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isListening = isListening
            self.lastError = error
        }
    }

    private func handleValidReadingOnMain(_ reading: HeartRateReading) {
        guard isEnabled else { return }
        currentBPM = reading.bpm
        lastSampleAt = reading.recordedAt
        receivedPacketCount += 1
        lastError = nil
        sampleSubject.send(reading)
        ensureStalenessTimerRunning()
    }

    private func ensureStalenessTimerRunning() {
        guard stalenessTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let lastAt = self.lastSampleAt else {
                self.currentBPM = nil
                self.stalenessTimer?.invalidate()
                self.stalenessTimer = nil
                return
            }
            if Date().timeIntervalSince(lastAt) > Self.signalTimeoutSeconds {
                self.currentBPM = nil
                self.stalenessTimer?.invalidate()
                self.stalenessTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        stalenessTimer = timer
    }

    private static func errnoDescription(_ code: Int32) -> String {
        if let cStr = Darwin.strerror(code) {
            return String(cString: cStr)
        }
        return "errno \(code)"
    }
}
