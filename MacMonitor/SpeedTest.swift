import Foundation
import os

// A download capacity test, run only when the user asks for it.
//
// This measures something different from the throughput on the rest of the screen.
// Throughput is what is passing right now; capacity is what the link can carry when
// something deliberately fills it. Both numbers can be correct at the same time and
// disagree by four orders of magnitude, which is why they are kept apart in the
// interface and never compared.
//
// The protocol is ndt7, run against M-Lab servers. Nothing here is automatic: the app
// reports 0.00% CPU in the background and a test that started on its own would make
// that false.

let speedTestLog = Logger(subsystem: "io.github.youdcode.macmonitor", category: "speedtest")

struct SpeedTestResult: Equatable {
    let megabitsPerSecond: Double
    let bytesTransferred: Int
    let duration: TimeInterval
    let server: String
    let finishedAt: Date

    var tier: SpeedTier { SpeedTier.forMegabitsPerSecond(megabitsPerSecond) }
}

enum SpeedTestState: Equatable {
    case idle
    case locating
    case running(progress: Double, megabitsPerSecond: Double)
    case finished(SpeedTestResult)
    case failed(String)
    case cancelled
}

/// Measured while building this: one download run moved about 885 MB in 10.5 seconds.
/// The figure is stated in the interface before the button, because on a metered
/// connection it decides whether to press it.
enum SpeedTestFacts {
    static let approximateDownloadBytes = 885_000_000.0
    /// M-Lab documents a limit of 40 tests per client per day.
    static let dailyTestLimit = 40
    static let privacyNote = "M-Lab collects the IP address your provider gave you along with the result, and publishes both."
    static let privacyURL = URL(string: "https://www.measurementlab.net/privacy/")!
}

@MainActor
final class SpeedTest: ObservableObject {
    @Published private(set) var state: SpeedTestState = .idle

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let duration: TimeInterval = 10

    var isRunning: Bool {
        switch state {
        case .locating, .running: return true
        default: return false
        }
    }

    func start() {
        guard !isRunning else { return }
        state = .locating

        Task { [weak self] in
            guard let self else { return }
            do {
                let (url, machine) = try await self.locateServer()
                await self.runDownload(url: url, machine: machine)
            } catch {
                self.state = .failed(error.localizedDescription)
                speedTestLog.error("speed test failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancel() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if isRunning { state = .cancelled }
    }

    // MARK: - Locate

    private struct LocateResponse: Decodable {
        struct Result: Decodable {
            let machine: String
            let urls: [String: String]
        }
        let results: [Result]
    }

    private enum SpeedTestError: LocalizedError {
        case noServer
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noServer: return "M-Lab returned no server for this location"
            case .badResponse: return "M-Lab's server list could not be read"
            }
        }
    }

    /// The Locate API needs no key. Measured: HTTP 200 in about 0.2 s, four candidate
    /// servers, each with wss:// URLs for download and upload.
    private func locateServer() async throws -> (URL, String) {
        let locate = URL(string: "https://locate.measurementlab.net/v2/nearest/ndt/ndt7")!
        let (data, response) = try await URLSession.shared.data(from: locate)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpeedTestError.badResponse
        }
        guard let decoded = try? JSONDecoder().decode(LocateResponse.self, from: data),
              let first = decoded.results.first,
              let raw = first.urls["wss:///ndt/v7/download"],
              let url = URL(string: raw) else {
            throw SpeedTestError.noServer
        }
        return (url, first.machine)
    }

    // MARK: - Download

    private func runDownload(url: URL, machine: String) async {
        var request = URLRequest(url: url)
        request.setValue("net.measurementlab.ndt.v7", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let session = URLSession(configuration: .ephemeral)
        self.session = session
        let socket = session.webSocketTask(with: request)
        self.task = socket
        socket.resume()

        let started = Date()
        var bytes = 0
        state = .running(progress: 0, megabitsPerSecond: 0)

        while true {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= duration { break }

            do {
                let message = try await socket.receive()
                switch message {
                case .data(let d): bytes += d.count
                case .string(let s): bytes += s.utf8.count
                @unknown default: break
                }
            } catch {
                // A cancel arrives here as an error. Anything else is a real failure,
                // and it says why rather than reporting a silent zero.
                if case .cancelled = state { return }
                if bytes == 0 {
                    state = .failed(error.localizedDescription)
                    speedTestLog.error("download failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                break
            }

            let now = Date().timeIntervalSince(started)
            if now > 0.3 {
                let mbps = Double(bytes) * 8 / now / 1_000_000
                state = .running(progress: min(now / duration, 1), megabitsPerSecond: mbps)
            }
        }

        socket.cancel(with: .normalClosure, reason: nil)
        session.finishTasksAndInvalidate()
        self.task = nil
        self.session = nil

        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 0, bytes > 0 else {
            state = .failed("No data was received")
            return
        }

        state = .finished(SpeedTestResult(megabitsPerSecond: Double(bytes) * 8 / elapsed / 1_000_000,
                                          bytesTransferred: bytes,
                                          duration: elapsed,
                                          server: machine,
                                          finishedAt: Date()))
    }
}
