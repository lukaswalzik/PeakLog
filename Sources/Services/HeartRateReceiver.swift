import Combine
import Darwin
import Foundation
import UIKit

enum HeartRateSource: String, Equatable {
    case udp
    case appleHealth

    var displayName: String {
        switch self {
        case .udp: return "UDP Bridge"
        case .appleHealth: return "Apple Health"
        }
    }
}

struct HeartRateReading: Equatable {
    let bpm: Int
    let recordedAt: Date
}

/// Receives live heart rate BPM values over local UDP (default port: 49153, IPv4 + IPv6 loopback/any),
/// e.g. UTF-8 ASCII integers in 30...240 ("74") sent ~1x/second by airpods-hf-bridge,
/// and also accepts external live readings (e.g. from Apple HealthKit).
final class HeartRateReceiver: ObservableObject {
    static let defaultHost = "127.0.0.1"
    static let defaultPort: UInt16 = 49153
    static let validBPMRange: ClosedRange<Int> = 30...240
    static let signalTimeoutSeconds: TimeInterval = 6.0
    static let appleHealthTimeoutSeconds: TimeInterval = 15.0

    private static let enabledDefaultsKey = "strongtracker.hr.udp_receiver_enabled"
    private static let portDefaultsKey = "strongtracker.hr.udp_receiver_port"

    let host: String

    @Published var port: UInt16 {
        didSet {
            UserDefaults.standard.set(Int(port), forKey: Self.portDefaultsKey)
            if isEnabled {
                restart()
            }
        }
    }

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
    @Published private(set) var activeSource: HeartRateSource? = nil
    @Published private(set) var lastSampleAt: Date? = nil
    @Published private(set) var receivedPacketCount: Int = 0
    @Published private(set) var rawPacketCount: Int = 0
    @Published private(set) var lastRawPayload: String? = nil
    @Published private(set) var lastRawPacketAt: Date? = nil
    @Published private(set) var lastError: String? = nil

    /// Emits every valid BPM sample received on the main queue.
    let sampleSubject = PassthroughSubject<HeartRateReading, Never>()

    private let socketQueue = DispatchQueue(label: "com.local.strongtracker.hr-udp", qos: .userInitiated)
    private var readSourceV4: DispatchSourceRead?
    private var readSourceV6: DispatchSourceRead?
    private var activeFDV4: Int32 = -1
    private var activeFDV6: Int32 = -1
    private var boundPort: UInt16 = HeartRateReceiver.defaultPort
    private var shouldBeListening: Bool = false
    private var lastUDPSampleAt: Date? = nil
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
        port: UInt16? = nil,
        autoStart: Bool = true
    ) {
        self.host = host

        let resolvedPort: UInt16
        if let explicitPort = port {
            resolvedPort = explicitPort
        } else {
            let storedPort = UserDefaults.standard.integer(forKey: Self.portDefaultsKey)
            if storedPort >= 1024 && storedPort <= 65535 {
                resolvedPort = UInt16(storedPort)
            } else {
                resolvedPort = Self.defaultPort
            }
        }
        self.port = resolvedPort
        self.boundPort = resolvedPort

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
        readSourceV4?.cancel()
        readSourceV6?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        let targetPort = port
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.boundPort = targetPort
            self.shouldBeListening = true
            self.startOnQueue()
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.activeSource == .udp {
                self.stalenessTimer?.invalidate()
                self.stalenessTimer = nil
                self.currentBPM = nil
                self.activeSource = nil
            }
            self.isListening = false
            self.lastError = nil
        }
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.shouldBeListening = false
            self.stopOnQueue()
        }
    }

    /// Ingests a live heart rate sample from an external source such as Apple HealthKit.
    func ingestExternalReading(bpm: Int, recordedAt: Date = Date(), source: HeartRateSource) {
        guard Self.validBPMRange.contains(bpm) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if source == .appleHealth,
               let lastUDP = self.lastUDPSampleAt,
               Date().timeIntervalSince(lastUDP) < 4.0 {
                return
            }
            let reading = HeartRateReading(bpm: bpm, recordedAt: recordedAt)
            self.currentBPM = bpm
            self.activeSource = source
            self.lastSampleAt = recordedAt
            self.receivedPacketCount += 1
            self.sampleSubject.send(reading)
            self.ensureStalenessTimerRunning()
        }
    }

    func restart() {
        let targetPort = port
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.boundPort = targetPort
            self.shouldBeListening = true
            self.stopOnQueue { [weak self] in
                guard let self = self, self.shouldBeListening else { return }
                self.startOnQueue()
            }
        }
    }

    /// Sends a local loopback UDP test datagram (e.g. "74") to verify the receiver end-to-end.
    func sendTestPacket(bpm: Int = 74) {
        let targetPort = port
        let payload = Array("\(bpm)".utf8)
        socketQueue.async {
            let txFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard txFD >= 0 else { return }
            defer { Darwin.close(txFD) }

            var dest = sockaddr_in()
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = targetPort.bigEndian
            let ok = "127.0.0.1".withCString { cStr in
                Darwin.inet_pton(AF_INET, cStr, &dest.sin_addr)
            }
            guard ok == 1 else { return }

            _ = payload.withUnsafeBytes { rawBuf in
                withUnsafePointer(to: &dest) { destPtr in
                    destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        Darwin.sendto(
                            txFD,
                            rawBuf.baseAddress,
                            rawBuf.count,
                            0,
                            sockaddrPtr,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Parsing

    /// Parses UTF-8 ASCII BPM payloads in 30...240 (e.g. "74", "74\n", "74.0", "74 bpm", or JSON {"bpm":74}).
    static func parseBPM(from data: Data) -> Int? {
        guard !data.isEmpty, data.count <= 256 else { return nil }

        if let raw = String(data: data, encoding: .utf8) {
            let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))
            let trimmed = raw.trimmingCharacters(in: trimChars)
            guard !trimmed.isEmpty else { return nil }

            // Fast path 1: strict ASCII integer ("74")
            if trimmed.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
               let exact = Int(trimmed),
               validBPMRange.contains(exact) {
                return exact
            }

            // Fast path 2: decimal number ("74.0" or "74,5")
            let normalizedDecimal = trimmed.replacingOccurrences(of: ",", with: ".")
            if let dbl = Double(normalizedDecimal) {
                let rounded = Int(dbl.rounded())
                if validBPMRange.contains(rounded) {
                    return rounded
                }
            }

            // Fallback: extract first numeric token in valid BPM range (e.g. "74 bpm" or {"bpm": 74})
            var token = ""
            func evaluateToken() -> Int? {
                defer { token = "" }
                guard !token.isEmpty else { return nil }
                let cleaned = token.replacingOccurrences(of: ",", with: ".")
                guard let val = Double(cleaned) else { return nil }
                let rounded = Int(val.rounded())
                return validBPMRange.contains(rounded) ? rounded : nil
            }

            for scalar in trimmed.unicodeScalars {
                let v = scalar.value
                let isAsciiDigit = v >= 48 && v <= 57
                if isAsciiDigit || (v == 46 && !token.isEmpty) || (v == 44 && !token.isEmpty) {
                    token.unicodeScalars.append(scalar)
                } else if let found = evaluateToken() {
                    return found
                }
            }
            if let found = evaluateToken() {
                return found
            }
            return nil
        }

        // Binary single-byte fallback if payload is non-UTF-8
        if data.count == 1 {
            let val = Int(data[0])
            return validBPMRange.contains(val) ? val : nil
        }
        return nil
    }

    private static func describeRawPayload(_ data: Data) -> String {
        if let str = String(data: data, encoding: .utf8) {
            let cleaned = str
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(48))
            }
        }
        return data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // MARK: - Socket Implementation (socketQueue)

    private func startOnQueue() {
        guard readSourceV4 == nil && readSourceV6 == nil else { return }

        let v4Result = openIPv4Socket(port: boundPort)
        let v6Result = openIPv6Socket(port: boundPort)

        if v4Result.source == nil && v6Result.source == nil {
            let reason = v4Result.error ?? v6Result.error ?? "Unbekannter Fehler"
            publishSocketState(isListening: false, error: "Bind auf Port \(boundPort) fehlgeschlagen (\(reason))")
            return
        }

        readSourceV4 = v4Result.source
        activeFDV4 = v4Result.fd
        readSourceV6 = v6Result.source
        activeFDV6 = v6Result.fd

        readSourceV4?.resume()
        readSourceV6?.resume()
        publishSocketState(isListening: true, error: nil)
    }

    private func openIPv4Socket(port: UInt16) -> (source: DispatchSourceRead?, fd: Int32, error: String?) {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            return (nil, -1, Self.errnoDescription(Darwin.errno))
        }

        var reuseAddr: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        var reusePort: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout<Int32>.size))

        // Bind to INADDR_ANY (0.0.0.0) so packets sent to 127.0.0.1 or any local IPv4 address are received.
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindStatus: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindStatus == 0 else {
            let reason = Self.errnoDescription(Darwin.errno)
            Darwin.close(fd)
            return (nil, -1, reason)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: socketQueue)
        source.setEventHandler { [weak self] in
            self?.drainSocketOnQueue(fd: fd, isIPv6: false)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        return (source, fd, nil)
    }

    private func openIPv6Socket(port: UInt16) -> (source: DispatchSourceRead?, fd: Int32, error: String?) {
        let fd = Darwin.socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            return (nil, -1, Self.errnoDescription(Darwin.errno))
        }

        var reuseAddr: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        var reusePort: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout<Int32>.size))
        var v6Only: Int32 = 1
        _ = Darwin.setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size))

        // Zero-initialized sin6_addr is :: (in6addr_any), receiving ::1 and any local IPv6 address.
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian

        let bindStatus: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }

        guard bindStatus == 0 else {
            let reason = Self.errnoDescription(Darwin.errno)
            Darwin.close(fd)
            return (nil, -1, reason)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: socketQueue)
        source.setEventHandler { [weak self] in
            self?.drainSocketOnQueue(fd: fd, isIPv6: true)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        return (source, fd, nil)
    }

    private func stopOnQueue(completion: (() -> Void)? = nil) {
        let sources: [(DispatchSourceRead, Int32)] = [
            readSourceV4.map { ($0, activeFDV4) },
            readSourceV6.map { ($0, activeFDV6) }
        ].compactMap { $0 }

        readSourceV4 = nil
        readSourceV6 = nil
        activeFDV4 = -1
        activeFDV6 = -1

        guard !sources.isEmpty else {
            completion?()
            return
        }

        var remaining = sources.count
        for (source, fd) in sources {
            source.setEventHandler {}
            source.setCancelHandler {
                if fd >= 0 {
                    Darwin.close(fd)
                }
                remaining -= 1
                if remaining == 0 {
                    completion?()
                }
            }
            source.cancel()
        }
    }

    private func drainSocketOnQueue(fd: Int32, isIPv6: Bool) {
        var buffer = [UInt8](repeating: 0, count: 256)
        var iterations = 0
        while iterations < 64 {
            iterations += 1
            let bytesRead = Darwin.recv(fd, &buffer, buffer.count, MSG_DONTWAIT)
            if bytesRead > 0 {
                let payload = Data(bytes: buffer, count: bytesRead)
                let now = Date()
                let rawPreview = Self.describeRawPayload(payload)
                let parsedBPM = Self.parseBPM(from: payload)
                DispatchQueue.main.async { [weak self] in
                    self?.handleDatagramOnMain(bpm: parsedBPM, rawPreview: rawPreview, receivedAt: now)
                }
            } else if bytesRead < 0 {
                let err = Darwin.errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    break
                }
                if err == EINTR {
                    continue
                }
                if isIPv6 {
                    readSourceV6?.cancel()
                    readSourceV6 = nil
                    activeFDV6 = -1
                } else {
                    readSourceV4?.cancel()
                    readSourceV4 = nil
                    activeFDV4 = -1
                }
                if readSourceV4 == nil && readSourceV6 == nil {
                    let reason = Self.errnoDescription(err)
                    publishSocketState(isListening: false, error: "UDP-Empfangsfehler (\(reason))")
                }
                break
            } else {
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

    private func handleDatagramOnMain(bpm: Int?, rawPreview: String, receivedAt: Date) {
        guard isEnabled else { return }
        rawPacketCount += 1
        lastRawPayload = rawPreview
        lastRawPacketAt = receivedAt
        lastError = nil

        guard let bpm = bpm else { return }
        let reading = HeartRateReading(bpm: bpm, recordedAt: receivedAt)
        currentBPM = bpm
        activeSource = .udp
        lastUDPSampleAt = receivedAt
        lastSampleAt = receivedAt
        receivedPacketCount += 1
        sampleSubject.send(reading)
        ensureStalenessTimerRunning()
    }

    private func ensureStalenessTimerRunning() {
        guard stalenessTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let lastAt = self.lastSampleAt else {
                self.currentBPM = nil
                self.activeSource = nil
                self.stalenessTimer?.invalidate()
                self.stalenessTimer = nil
                return
            }
            let timeout = self.activeSource == .appleHealth
                ? Self.appleHealthTimeoutSeconds
                : Self.signalTimeoutSeconds
            if Date().timeIntervalSince(lastAt) > timeout {
                self.currentBPM = nil
                self.activeSource = nil
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
