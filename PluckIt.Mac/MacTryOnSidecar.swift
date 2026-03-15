import Foundation
import Combine

// MARK: - Errors

enum TryOnError: LocalizedError {
    case python3NotFound
    case serverStartTimeout
    case setupStepFailed(String)
    case inferenceFailed(String)
    case serverScriptMissing

    var errorDescription: String? {
        switch self {
        case .python3NotFound:
            return "Python 3 not found. Install Xcode Command Line Tools (xcode-select --install)."
        case .serverStartTimeout:
            return "The CatVTON server didn't respond within 5 minutes. Check Console logs for details."
        case .setupStepFailed(let msg):
            return "First-run setup failed: \(msg)"
        case .inferenceFailed(let msg):
            return "Inference failed: \(msg)"
        case .serverScriptMissing:
            return "server.py not found in app bundle. Re-install the app."
        }
    }
}

// MARK: - Sidecar

/// Manages the lifecycle of the bundled CatVTON Python inference server.
///
/// On first launch the sidecar creates a virtualenv in Application Support,
/// installs PyTorch + diffusers, clones the CatVTON repo and downloads the
/// model weights from HuggingFace. Subsequent launches skip setup and go
/// straight to starting the Flask server.
///
/// Communicate by observing `state`. Call `startIfNeeded()` when the Try-On
/// view appears. Call `stop()` when it disappears (or on app quit).
@MainActor
final class MacTryOnSidecar: ObservableObject {

    // MARK: State

    enum State: Equatable {
        case idle
        case settingUp(step: String)
        case starting
        case ready(port: Int)
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var isBusy: Bool {
            switch self {
            case .settingUp, .starting: return true
            default: return false
            }
        }

        var statusLine: String {
            switch self {
            case .idle:                    return "TRYON_ENGINE // idle"
            case .settingUp(let step):     return "SETUP // \(step)"
            case .starting:                return "TRYON_ENGINE // starting server…"
            case .ready(let port):         return "TRYON_ENGINE // ready on :\(port)"
            case .failed(let msg):         return "ERROR // \(msg)"
            }
        }
    }

    @Published private(set) var state: State = .idle

    // MARK: Singleton

    static let shared = MacTryOnSidecar()
    private init() {}

    // MARK: Config

    private let port = 7433
    private let serverStartTimeoutSeconds: TimeInterval = 300

    // MARK: Paths

    private var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PluckIt/tryon", isDirectory: true)
    }

    private var venvDir:     URL { supportDir.appendingPathComponent("venv") }
    private var weightsDir:  URL { supportDir.appendingPathComponent("weights") }
    private var repoDir:     URL { supportDir.appendingPathComponent("CatVTON") }
    private var logFile:     URL { supportDir.appendingPathComponent("server.log") }
    private var setupMarker: URL { supportDir.appendingPathComponent(".setup_complete") }

    private var pythonBin: URL { venvDir.appendingPathComponent("bin/python3") }
    private var pipBin:    URL { venvDir.appendingPathComponent("bin/pip") }

    private var serverScript: URL? {
        Bundle.main.url(forResource: "server", withExtension: "py")
    }

    // MARK: Private state

    private var serverProcess: Process?

    // MARK: - Public API

    /// True when the one-time setup has already been completed.
    var isSetupComplete: Bool {
        FileManager.default.fileExists(atPath: setupMarker.path)
    }

    /// Starts the server if setup is already done. Does NOT trigger setup.
    /// Call `enableAndStart()` to run setup for the first time.
    func startIfNeeded() async {
        guard case .idle = state else { return }
        guard isSetupComplete else { return }

        do {
            try await launchServer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Runs first-time setup (user-initiated) then starts the server.
    func enableAndStart() async {
        guard case .idle = state else { return }

        do {
            if !isSetupComplete {
                try await firstRunSetup()
            }
            try await launchServer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        serverProcess?.terminate()
        serverProcess = nil
        state = .idle
    }

    // MARK: - First-Run Setup

    private func firstRunSetup() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportDir,  withIntermediateDirectories: true)
        try fm.createDirectory(at: weightsDir,  withIntermediateDirectories: true)

        let python3 = try findPython3()

        // 1. Virtual environment
        setStep("Creating Python environment…")
        try await shell(python3, "-m", "venv", venvDir.path)

        // 2. pip upgrade
        setStep("Upgrading pip…")
        try await shell(pipBin.path, "install", "--upgrade", "pip", "--quiet")

        // 3. PyTorch + ML deps
        setStep("Installing PyTorch, diffusers, transformers (~2 GB, one-time)…")
        try await shell(pipBin.path, "install", "--quiet",
                        "torch", "torchvision",
                        "diffusers", "transformers", "accelerate",
                        "huggingface_hub",
                        "flask",
                        "Pillow",
                        "numpy",
                        "opencv-python-headless")

        // 4. Clone CatVTON source (pipeline code, not weights)
        setStep("Cloning CatVTON…")
        if !fm.fileExists(atPath: repoDir.path) {
            try await shell("/usr/bin/git", "clone", "--depth=1",
                            "https://github.com/Zheng-Chong/CatVTON.git",
                            repoDir.path)
        }

        // 5. Download model weights via HuggingFace
        setStep("Downloading CatVTON weights (~2.5 GB)…")
        let catvtonDest = weightsDir.appendingPathComponent("catvton").path
        let downloadScript = """
import sys
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="zhengchong/CatVTON",
    local_dir="\(catvtonDest)",
    ignore_patterns=["*.git*", "*.gitattributes"]
)
print("weights downloaded", flush=True)
"""
        try await shell(pythonBin.path, "-c", downloadScript)

        // 6. Pre-download SD inpainting base model (required by CatVTON at load time)
        setStep("Downloading SD inpainting base model (~1.7 GB)…")
        let sdDownloadScript = """
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="runwayml/stable-diffusion-inpainting",
    ignore_patterns=["*.git*", "*.gitattributes"]
)
print("sd base model cached", flush=True)
"""
        try await shell(pythonBin.path, "-c", sdDownloadScript)

        // 7. Pre-warm cloth-segmentation model cache
        setStep("Downloading cloth-segmentation model…")
        let segWarmScript = """
from transformers import pipeline as hf_pipeline
hf_pipeline("image-segmentation", model="mattmdjaga/segformer_b2_clothes", device=-1)
print("seg model cached", flush=True)
"""
        try await shell(pythonBin.path, "-c", segWarmScript)

        // 7. Mark complete
        fm.createFile(atPath: setupMarker.path, contents: Data("ok".utf8))
    }

    // MARK: - Launch Server

    private func launchServer() async throws {
        guard let script = serverScript else { throw TryOnError.serverScriptMissing }

        // Kill any stale server still occupying the port (e.g. from a previous run)
        try? await shell("/bin/sh", "-c", "lsof -ti :\(port) | xargs kill -9 2>/dev/null; true")

        state = .starting

        let process = Process()
        process.executableURL = pythonBin
        process.arguments     = [script.path, "\(port)"]
        process.environment   = [
            "TRYON_WEIGHTS_DIR": weightsDir.path,
            "TRYON_REPO_DIR":    repoDir.path,
            "PATH":              "/usr/bin:/bin:/usr/local/bin",
        ]

        // Route stdout + stderr to a log file for debugging
        let logHandle: FileHandle = {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: logFile.path) else {
                print("[MacTryOnSidecar] Unable to open log file at \(logFile.path); using standardError.")
                return FileHandle.standardError
            }
            return handle
        }()
        process.standardOutput = logHandle
        process.standardError  = logHandle

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                if case .ready = self?.state { return }
                self?.state = .failed("Server process exited unexpectedly.")
            }
        }

        try process.run()
        serverProcess = process

        try await waitForReady()
        state = .ready(port: port)
    }

    private func waitForReady() async throws {
        let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
        let deadline  = Date().addingTimeInterval(serverStartTimeoutSeconds)

        while Date() < deadline {
            // Fail fast if the process already died
            if let p = serverProcess, !p.isRunning {
                let log = (try? String(contentsOf: logFile, encoding: .utf8)) ?? "(no log)"
                let tail = log.components(separatedBy: "\n").suffix(20).joined(separator: "\n")
                throw TryOnError.setupStepFailed("Server process exited early.\n\n\(tail)")
            }

            if let (data, _) = try? await URLSession.shared.data(from: healthURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let ready = json["ready"] as? Bool, ready { return }
                // Surface model load errors immediately rather than timing out
                if let err = json["error"] as? String, !err.isEmpty {
                    throw TryOnError.setupStepFailed("Model load failed:\n\(err)")
                }
            }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw TryOnError.serverStartTimeout
    }

    // MARK: - Helpers

    private func setStep(_ step: String) {
        state = .settingUp(step: step)
    }

    private func findPython3() throws -> String {
        let candidates = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        throw TryOnError.python3NotFound
    }

    /// Runs a command-line tool. stdout/stderr go to the log file AND are
    /// captured so we can include the last 2 KB in any thrown error.
    private func shell(_ executable: String, _ args: String...) async throws {
        let logPath  = logFile.path
        let execName = URL(fileURLWithPath: executable).lastPathComponent

        // Ensure log file exists before appending
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        // Write a header line so we can track which command ran
        let header = "\n==> \(execName) \(args.joined(separator: " "))\n"
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile()
            h.write(Data(header.utf8))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments     = args

                // Capture stderr separately so we can surface it on failure
                let stderrPipe = Pipe()
                let stdoutPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                // Tee both pipes to the log file in real time
                func tee(_ pipe: Pipe) {
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        if let logHandle = FileHandle(forWritingAtPath: logPath) {
                            logHandle.seekToEndOfFile()
                            logHandle.write(data)
                        }
                    }
                }
                tee(stdoutPipe)
                tee(stderrPipe)

                process.terminationHandler = { p in
                    // Stop handlers before reading final output
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    if p.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        // Read tail of stderr for a useful error message
                        let errData   = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errText   = String(data: errData, encoding: .utf8) ?? ""
                        let tail      = errText.components(separatedBy: "\n").suffix(8).joined(separator: "\n")
                        let message   = tail.trimmingCharacters(in: .whitespacesAndNewlines)
                        let formatted = message.isEmpty
                            ? "\(execName) exited \(p.terminationStatus)"
                            : "\(execName) exited \(p.terminationStatus):\n\(message)"
                        continuation.resume(throwing: TryOnError.setupStepFailed(formatted))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
