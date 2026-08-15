import Foundation
import os

// A capacity test in both directions, run only when the user asks for it.
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

enum SpeedTestDirection: Equatable {
    case download, upload
}

struct SpeedTestResult: Equatable {
    let downloadMegabitsPerSecond: Double
    let downloadBytes: Int
    /// nil when the upload half did not complete. The download is a measurement either
    /// way and is still shown; the upload dial says it has nothing rather than showing
    /// a zero, because not measured and measured at zero are different statements.
    let uploadMegabitsPerSecond: Double?
    let uploadBytes: Int
    let uploadFailure: String?
    let server: String
    let finishedAt: Date

    /// The five-level rating describes the DOWNLOAD, and the interface says so where it
    /// is shown. Its boundaries - 5, 25, 100, 500 Mbit/s - were chosen for a download.
    /// Applying them to an upload would call a perfectly ordinary 25 Mbit/s upstream
    /// "slow", which is a judgement nothing here has earned. Rating the upload needs
    /// boundaries of its own, and there is no measurement behind those yet.
    var tier: SpeedTier { SpeedTier.forMegabitsPerSecond(downloadMegabitsPerSecond) }

    var totalBytes: Int { downloadBytes + uploadBytes }
}

/// What one complete test moved, kept between launches.
///
/// The point of remembering it is that the warning before the button can then be about
/// the reader's own connection. A figure measured on the author's machine is exactly
/// wrong for the people the warning exists for: on a 10 Mbit/s line the test costs
/// 12.5 MB, and telling that reader it costs 885 would frighten off the one person it
/// was written to protect.
struct SpeedTestVolume: Equatable {
    let downloadBytes: Int
    let uploadBytes: Int
    let at: Date

    var totalBytes: Int { downloadBytes + uploadBytes }
}

extension SpeedTestResult {
    /// Only a run that finished BOTH halves is worth remembering. A download-only run
    /// under-states the next full test by exactly the upload half, and a warning about
    /// what something costs is the wrong place to be short by half.
    var completedVolume: SpeedTestVolume? {
        guard uploadMegabitsPerSecond != nil, downloadBytes > 0, uploadBytes > 0 else { return nil }
        return SpeedTestVolume(downloadBytes: downloadBytes, uploadBytes: uploadBytes, at: finishedAt)
    }
}

/// Where the last complete test's volume is kept.
///
/// Three plain values rather than an encoded blob, so `defaults read` shows them: the
/// interface makes a claim from this, and a claim whose source cannot be inspected is
/// the sort of thing this application exists to avoid.
struct SpeedTestVolumeStore {
    private let defaults: UserDefaults

    private let downloadKey = "speedTest.lastDownloadBytes"
    private let uploadKey = "speedTest.lastUploadBytes"
    private let dateKey = "speedTest.lastRunAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// All three values or nothing. Half a record would be a statement about a test that
    /// did not happen.
    func read() -> SpeedTestVolume? {
        let download = defaults.integer(forKey: downloadKey)
        let upload = defaults.integer(forKey: uploadKey)
        let seconds = defaults.double(forKey: dateKey)
        guard download > 0, upload > 0, seconds > 0 else { return nil }
        return SpeedTestVolume(downloadBytes: download,
                               uploadBytes: upload,
                               at: Date(timeIntervalSinceReferenceDate: seconds))
    }

    func write(_ volume: SpeedTestVolume) {
        defaults.set(volume.downloadBytes, forKey: downloadKey)
        defaults.set(volume.uploadBytes, forKey: uploadKey)
        defaults.set(volume.at.timeIntervalSinceReferenceDate, forKey: dateKey)
    }
}

enum SpeedTestState: Equatable {
    case idle
    case locating
    /// `download` stays populated once that half is done, so the finished dial does not
    /// blank while the other one runs.
    case running(direction: SpeedTestDirection, progress: Double, download: Double?, upload: Double?)
    case finished(SpeedTestResult)
    case failed(String)
    case cancelled
}

/// What the test costs, and what M-Lab asks in return.
enum SpeedTestFacts {

    /// The test fills the link for ten seconds in each direction, so what it moves is
    /// not a property of the test at all: it is whatever the connection carries. Ten
    /// seconds at one Mbit/s is 1.25 MB, and it scales from there.
    ///
    /// This is the fallback, shown before the first run. Once a complete test has been
    /// made, the screen states what THAT test moved instead - the reader's own number
    /// rather than a rule they have to apply to themselves, or worse, a figure measured
    /// on somebody else's connection.
    ///
    /// Verified against every run measured while building this, rate against bytes for
    /// the same run: 226 Mbit/s moved 285 MB, 254 moved 318, 263 moved 335, 312 moved
    /// 390, 316 moved 395, 350 moved 437, 399 moved 503, 521 moved 652, 674 moved 885,
    /// 688 moved 860. Every one lands within two per cent of the rule except the 674
    /// run, which lasted ten and a half seconds rather than ten.
    ///
    /// The independent reference: the interface counters were read either side of one of
    /// those runs and saw 708 MB in and 529 MB out against the 652 and 503 counted here,
    /// 8.7 % and 5.2 % more. That is packet headers and the acknowledgements each
    /// direction sends back - and it is also the check that nothing compressed the
    /// upload payloads, which is why they are random rather than zeroed.
    static let megabytesPerMegabitPerSecond = 1.25

    /// M-Lab documents "a rate limit of 40 tests per client per day", and says a client
    /// that hits it is answered with an HTTP 204 No Content.
    ///
    /// A 204 is an HTTP status, and the only HTTP request in this file is the one for
    /// the server list. That request returns wss:// URLs for BOTH directions carrying
    /// the same access token - compared character by character, they are identical -
    /// and that one token was observed opening a download connection followed by four
    /// separate upload connections, all accepted. So a complete test in both directions
    /// costs one request and therefore one of the forty.
    ///
    /// What is NOT established: M-Lab nowhere writes the sentence "a bidirectional test
    /// counts as one". The conclusion above is drawn from where the refusal is returned
    /// and from the token being reusable, not from documentation.
    static let dailyTestLimit = 40

    static let privacyNote = "M-Lab collects the IP address your provider gave you along with the result, and publishes both."
    static let privacyURL = URL(string: "https://www.measurementlab.net/privacy/")!
}

@MainActor
final class SpeedTest: ObservableObject {
    @Published private(set) var state: SpeedTestState = .idle

    /// The last complete run, read back at launch. nil until one has been made, which is
    /// when the screen falls back to the rule.
    @Published private(set) var lastVolume: SpeedTestVolume?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var cancelled = false
    private let volumeStore: SpeedTestVolumeStore

    init(volumeStore: SpeedTestVolumeStore = SpeedTestVolumeStore()) {
        self.volumeStore = volumeStore
        self.lastVolume = volumeStore.read()
    }

    /// Ten seconds each way, which is what the ndt7 specification asks for: "the
    /// expected duration of a test is up to ten seconds".
    private let duration: TimeInterval = 10

    /// The specification's own ceiling, not a number of this application's choosing:
    /// "binary messages MUST contain between 1 << 10 and 1 << 24 bytes". Only one buffer
    /// of the current size exists at a time, so the peak cost is that buffer plus the
    /// copy in flight, for the ten seconds the upload lasts.
    private static let maximumMessageBytes = 1 << 24

    /// The dials are redrawn ten times a second at most. Without the throttle the state
    /// was published on every message received, which at a few hundred messages a second
    /// puts a redraw of the whole screen on the main actor for each one, in an
    /// application whose entire claim is that it does not load the machine.
    private var lastPublished = Date.distantPast
    private let publishInterval: TimeInterval = 0.1

    var isRunning: Bool {
        switch state {
        case .locating, .running: return true
        default: return false
        }
    }

    func start() {
        guard !isRunning else { return }
        cancelled = false
        state = .locating

        Task { [weak self] in
            guard let self else { return }
            do {
                let endpoints = try await self.locateServer()
                if self.cancelled { self.state = .cancelled; return }

                let down = try await self.runDownload(url: endpoints.download)
                if self.cancelled { self.state = .cancelled; return }

                let up = await self.runUpload(url: endpoints.upload, downloadSoFar: down.megabitsPerSecond)
                if self.cancelled { self.state = .cancelled; return }

                let result = SpeedTestResult(downloadMegabitsPerSecond: down.megabitsPerSecond,
                                             downloadBytes: down.bytes,
                                             uploadMegabitsPerSecond: up.megabitsPerSecond,
                                             uploadBytes: up.bytes,
                                             uploadFailure: up.failure,
                                             server: endpoints.machine,
                                             finishedAt: Date())

                // Only a complete run is remembered, and it is remembered before it is
                // shown, so what the screen says the next test will cost is the same
                // figure it is about to display.
                if let volume = result.completedVolume {
                    self.volumeStore.write(volume)
                    self.lastVolume = volume
                }

                self.publish(.finished(result), force: true)
            } catch {
                if self.cancelled {
                    self.state = .cancelled
                } else {
                    self.state = .failed(error.localizedDescription)
                    speedTestLog.error("speed test failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func cancel() {
        cancelled = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if isRunning { state = .cancelled }
    }

    private func publish(_ new: SpeedTestState, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPublished) >= publishInterval else { return }
        lastPublished = now
        state = new
    }

    // MARK: - Locate

    private struct Endpoints {
        let download: URL
        let upload: URL
        let machine: String
    }

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

    /// One request, both directions. The Locate API needs no key; measured at HTTP 200
    /// in about 0.2 s, four candidate servers, each carrying wss:// URLs for download
    /// and upload under the same access token.
    private func locateServer() async throws -> Endpoints {
        let locate = URL(string: "https://locate.measurementlab.net/v2/nearest/ndt/ndt7")!
        let (data, response) = try await URLSession.shared.data(from: locate)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpeedTestError.badResponse
        }
        guard let decoded = try? JSONDecoder().decode(LocateResponse.self, from: data),
              let first = decoded.results.first,
              let rawDownload = first.urls["wss:///ndt/v7/download"],
              let rawUpload = first.urls["wss:///ndt/v7/upload"],
              let download = URL(string: rawDownload),
              let upload = URL(string: rawUpload) else {
            throw SpeedTestError.noServer
        }
        return Endpoints(download: download, upload: upload, machine: first.machine)
    }

    private func openSocket(_ url: URL) -> URLSessionWebSocketTask {
        var request = URLRequest(url: url)
        request.setValue("net.measurementlab.ndt.v7", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let session = URLSession(configuration: .ephemeral)
        self.session = session
        let socket = session.webSocketTask(with: request)
        // "An implementation MAY choose to limit the maximum WebSocket message size, but
        // such limit MUST NOT be smaller than 1 << 24 bytes."
        socket.maximumMessageSize = Self.maximumMessageBytes
        self.task = socket
        socket.resume()
        return socket
    }

    private func closeSocket(_ socket: URLSessionWebSocketTask) {
        socket.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
        self.task = nil
        self.session = nil
    }

    // MARK: - Download

    private func runDownload(url: URL) async throws -> (megabitsPerSecond: Double, bytes: Int) {
        let socket = openSocket(url)
        let started = Date()
        var bytes = 0
        publish(.running(direction: .download, progress: 0, download: nil, upload: nil), force: true)

        while Date().timeIntervalSince(started) < duration {
            do {
                switch try await socket.receive() {
                case .data(let d): bytes += d.count
                case .string(let s): bytes += s.utf8.count
                @unknown default: break
                }
            } catch {
                // A cancel arrives here as an error, and so does the server closing at
                // the end of its own ten seconds. Anything else with nothing received is
                // a real failure, and it says why rather than reporting a silent zero.
                if cancelled { throw CancellationError() }
                if bytes == 0 { throw error }
                break
            }

            let elapsed = Date().timeIntervalSince(started)
            if elapsed > 0.3 {
                publish(.running(direction: .download,
                                 progress: min(elapsed / duration, 1) / 2,
                                 download: Double(bytes) * 8 / elapsed / 1_000_000,
                                 upload: nil))
            }
        }

        closeSocket(socket)
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 0, bytes > 0 else { throw SpeedTestError.badResponse }
        return (Double(bytes) * 8 / elapsed / 1_000_000, bytes)
    }

    // MARK: - Upload

    /// Sends for ten seconds, following the scaling rule in the specification's
    /// appendix: start at 1 << 13 bytes and double whenever the message has become
    /// smaller than a sixteenth of what has already been queued.
    ///
    /// The payloads are random. Zeroed buffers would compress to almost nothing if the
    /// connection ever negotiated permessage-deflate, and the byte count would then be a
    /// fiction with nothing inside the program able to detect it. What was measured
    /// instead: the interface counters saw 284.6 MB leave while this counted 285.2 MB
    /// queued, a ratio of 0.998, so the bytes really did go out and nothing compressed
    /// them.
    private func runUpload(url: URL, downloadSoFar: Double) async -> (megabitsPerSecond: Double?, bytes: Int, failure: String?) {
        let socket = openSocket(url)

        // The server sends its own measurements back while the upload runs. Nothing here
        // reads them - the specification recommends "application level measurements at
        // the sender" for this direction - but they are drained so they do not queue.
        let drain = Task { while true { if (try? await socket.receive()) == nil { return } } }

        var size = 1 << 13
        var payload = await Self.randomPayload(size)
        var queued = 0
        var failure: String?
        let started = Date()

        while Date().timeIntervalSince(started) < duration {
            if cancelled { break }

            if size < Self.maximumMessageBytes, Double(size) < Double(queued) / 16 {
                size <<= 1
                payload = await Self.randomPayload(size)
            }

            do {
                try await socket.send(.data(payload))
            } catch {
                // The server closes at the end of its ten seconds and the send that
                // lands on the closed socket throws. That is the end of the test, not a
                // failure - unless nothing at all went out.
                if queued == 0 { failure = error.localizedDescription }
                break
            }
            queued += size

            let elapsed = Date().timeIntervalSince(started)
            if elapsed > 0.3 {
                publish(.running(direction: .upload,
                                 progress: 0.5 + min(elapsed / duration, 1) / 2,
                                 download: downloadSoFar,
                                 upload: Double(queued) * 8 / elapsed / 1_000_000))
            }
        }

        drain.cancel()
        closeSocket(socket)

        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 0, queued > 0 else {
            return (nil, 0, failure ?? "Nothing could be sent")
        }
        return (Double(queued) * 8 / elapsed / 1_000_000, queued, nil)
    }

    /// Off the main actor: filling sixteen megabytes with random bytes takes long enough
    /// to be visible in an interface that is redrawing a dial at the same time.
    private nonisolated static func randomPayload(_ size: Int) async -> Data {
        await Task.detached(priority: .userInitiated) {
            var data = Data(count: size)
            data.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                arc4random_buf(base, size)
            }
            return data
        }.value
    }
}
