import Foundation
import CryptoKit
import Darwin

struct OCRInstallation {
    static let uvVersion = "0.13.6"
    static let uvChecksum = "60fbd5c8a1ed681845eea28d9d622fcde03c51e91a43465b64a1e17db1ed3472"
    static let modelNames = ["PP-OCRv5_mobile_det", "PP-OCRv5_mobile_rec"]

    static var supported: Bool {
        var value: Int32 = 0
        var size = MemoryLayout.size(ofValue: value)
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
    static func filesExist(python: String, models: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: python) && modelNames.allSatisfy { name in
            ["inference.yml", "inference.json", "inference.pdiparams"].allSatisfy {
                FileManager.default.fileExists(atPath: URL(fileURLWithPath: models).appendingPathComponent("official_models/\(name)/\($0)").path)
            }
        }
    }
    static func verifyArchive(_ data: Data, checksum: String = uvChecksum) throws {
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == checksum else {
            throw SelectaError.message("下载文件校验失败，请重新安装。")
        }
    }

    let paths: AppPaths
    let script: URL
    let requirements: URL
    var run: @Sendable (String, [String], [String: String], TimeInterval) async throws -> Void = { executable, arguments, environment, timeout in
        try await OCRSetupProcess.run(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
    }
    var download: @Sendable (URL) async throws -> Data = { url in
        try await HTTPClient().data(URLRequest(url: url, timeoutInterval: 600))
    }

    var archiveChecksum = Self.uvChecksum

    func environment() -> [String: String] {
        ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
         "TMPDIR": FileManager.default.temporaryDirectory.path,
         "UV_CACHE_DIR": paths.caches.appendingPathComponent("uv").path,
         "UV_PYTHON_INSTALL_DIR": paths.pythonInstallations.path,
         "UV_PYTHON_INSTALL_BIN": "0", "UV_NO_CONFIG": "1", "UV_NO_PROGRESS": "1",
         "UV_LINK_MODE": "copy", "UV_HTTP_TIMEOUT": "120", "UV_HTTP_RETRIES": "3",
         "SELECTA_CACHE_DIR": paths.caches.path, "SELECTA_SUPPORT_DIR": paths.applicationSupport.path,
         "PADDLE_PDX_MODEL_SOURCE": "bos", "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK": "True"]
    }

    func install(progress: @Sendable @escaping (Int, String) async -> Void) async throws -> URL {
        try paths.prepare()
        let lockURL = paths.ocr.appendingPathComponent(".installation.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SelectaError.message("无法写入 OCR 数据目录。") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw SelectaError.message("另一个 Selecta 正在安装 OCR，请稍后重试。") }
        defer { flock(descriptor, LOCK_UN) }
        for directory in (try? FileManager.default.contentsOfDirectory(at: paths.ocr, includingPropertiesForKeys: nil)) ?? [] where directory.lastPathComponent.hasPrefix("Setup-") {
            try? FileManager.default.removeItem(at: directory)
        }
        let environments = paths.ocr.appendingPathComponent("Environments", isDirectory: true)
        for directory in (try? FileManager.default.contentsOfDirectory(at: environments, includingPropertiesForKeys: nil)) ?? [] {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".installing").path) { try? FileManager.default.removeItem(at: directory) }
        }
        let staging = paths.ocr.appendingPathComponent("Setup-\(UUID().uuidString)", isDirectory: true)
        let target = paths.ocr.appendingPathComponent("Environments/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var complete = false
        defer {
            try? FileManager.default.removeItem(at: staging)
            if !complete { try? FileManager.default.removeItem(at: target) }
        }
        let env = environment()
        await progress(1, "下载并校验安装工具")
        let archive = try await download(URL(string: "https://github.com/astral-sh/uv/releases/download/\(Self.uvVersion)/uv-aarch64-apple-darwin.tar.gz")!)
        try Task.checkCancellation()
        try Self.verifyArchive(archive, checksum: archiveChecksum)
        let file = staging.appendingPathComponent("uv.tar.gz")
        try archive.write(to: file, options: .atomic)
        try await run("/usr/bin/tar", ["-xzf", file.path, "-C", staging.path], env, 60)
        let uv = staging.appendingPathComponent("uv-aarch64-apple-darwin/uv").path
        await progress(2, "下载独立 Python 3.12")
        try await run(uv, ["python", "install", "3.12", "--no-bin"], env, 900)
        await progress(3, "创建环境并安装 OCR 依赖")
        try await run(uv, ["venv", "--managed-python", "--python", "3.12", target.path], env, 120)
        let pending = target.appendingPathComponent(".installing")
        try Data().write(to: pending)
        let python = target.appendingPathComponent("bin/python")
        try await run(uv, ["pip", "install", "--python", python.path, "--only-binary", ":all:", "--index-url", "https://pypi.org/simple", "-r", requirements.path], env, 1800)
        await progress(4, "下载百度 PP-OCRv5 模型")
        try await run(python.path, [script.path, "--prepare", "--models", paths.models.path], env, 1200)
        await progress(5, "验证离线 OCR 环境")
        try await run(python.path, [script.path, "--check", "--models", paths.models.path], env, 180)
        try Task.checkCancellation()
        guard Self.filesExist(python: python.path, models: paths.models.path) else { throw SelectaError.message("OCR 安装文件不完整，请重新安装。") }
        try FileManager.default.removeItem(at: pending)
        complete = true
        return python
    }
}

final class OCRSetupProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false

    static func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws {
        let runner = OCRSetupProcess()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await runner.start(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
            try Task.checkCancellation()
        } onCancel: { runner.stop() }
    }
    private func start(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                self.lock.lock()
                guard !self.cancelled else { self.lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.process.executableURL = URL(fileURLWithPath: executable)
                self.process.arguments = arguments
                self.process.environment = environment
                self.process.standardInput = FileHandle.nullDevice
                self.process.standardOutput = FileHandle.nullDevice
                self.process.standardError = FileHandle.nullDevice
                do { try self.process.run() } catch { self.lock.unlock(); continuation.resume(throwing: error); return }
                self.lock.unlock()
                let deadline = DispatchWorkItem { self.stop(timeout: true) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                self.process.waitUntilExit()
                deadline.cancel()
                self.lock.lock()
                let cancelled = self.cancelled, timedOut = self.timedOut
                self.lock.unlock()
                if cancelled { continuation.resume(throwing: CancellationError()) }
                else if timedOut { continuation.resume(throwing: SelectaError.message("下载或安装超时，请检查网络后重试。")) }
                else if self.process.terminationStatus != 0 { continuation.resume(throwing: SelectaError.message("此步骤未完成，请检查网络连接和剩余磁盘空间后重试。")) }
                else { continuation.resume() }
            }
        }
    }
    private func stop(timeout: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if timeout { timedOut = true } else { cancelled = true }
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                if self.process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }
}
