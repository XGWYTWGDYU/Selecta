import Foundation
import Darwin

/// Serial requests share a single loaded PaddleOCR process.
final class PaddleWorker: @unchecked Sendable {
    static let shared = PaddleWorker()
    private let queue = DispatchQueue(label: "org.ra055814ae03f470d982b.selecta.paddle", qos: .userInitiated)
    private let lock = NSLock()
    private var process: Process?
    private var activeID: UUID?
    private var input: FileHandle?
    private var output: FileHandle?
    private var configuration = ""

    private final class Request: @unchecked Sendable {
        let id = UUID()
        let lock = NSLock()
        var cancelled = false
        var timedOut = false
        func state() -> (Bool, Bool) { lock.lock(); defer { lock.unlock() }; return (cancelled, timedOut) }
        func cancel(timeout: Bool) { lock.lock(); defer { lock.unlock() }; cancelled = !timeout; timedOut = timeout }
    }

    func recognize(python: String, script: String, models: String, image: Data) async throws -> Data {
        let request = Request()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                queue.async {
                    do {
                        if request.state().0 { throw CancellationError() }
                        try self.start(python: python, script: script, models: models, request: request)
                        let deadline = DispatchWorkItem { [weak self] in
                            request.cancel(timeout: true)
                            self?.abort(request.id)
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: deadline)
                        defer { deadline.cancel() }
                        let data = try JSONSerialization.data(withJSONObject: ["id": request.id.uuidString, "image": image.base64EncodedString()])
                        try self.input?.write(contentsOf: data + Data([10]))
                        var line = Data()
                        var complete = false
                        while let byte = try self.output?.read(upToCount: 1), !byte.isEmpty {
                            if byte.first == 10 {
                                if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any], json["id"] as? String == request.id.uuidString {
                                    complete = true
                                    break
                                }
                                line.removeAll(keepingCapacity: true)
                            } else { line.append(byte) }
                        }
                        let (cancelled, timedOut) = request.state()
                        if cancelled { throw CancellationError() }
                        if timedOut { throw SelectaError.message("PaddleOCR 识别超时，请缩小截图范围后重试。") }
                        guard complete else { throw SelectaError.message("PaddleOCR 进程退出，请检查模型和 Python 环境后重试。") }
                        self.lock.lock(); self.activeID = nil; self.lock.unlock()
                        continuation.resume(returning: line)
                    } catch {
                        self.shutdown()
                        continuation.resume(throwing: request.state().0 ? CancellationError() : error)
                    }
                }
            }
        } onCancel: {
            request.cancel(timeout: false)
            self.abort(request.id)
        }
    }

    private func start(python: String, script: String, models: String, request: Request) throws {
        let key = [python, script, models].joined(separator: "\n")
        lock.lock()
        defer { lock.unlock() }
        if request.state().0 { throw CancellationError() }
        activeID = request.id
        if configuration == key, process?.isRunning == true { return }
        if process?.isRunning == true { process?.terminate() }
        try? input?.close(); try? output?.close()
        let child = Process()
        let send = Pipe(), receive = Pipe()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = [script, "--worker", "--models", models]
        child.standardInput = send
        child.standardOutput = receive
        child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
        child.environment = environment
        process = child
        try child.run()
        input = send.fileHandleForWriting
        output = receive.fileHandleForReading
        _ = fcntl(send.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        configuration = key
    }
    private func abort(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        if activeID == id, process?.isRunning == true { process?.terminate() }
    }
    func shutdown() {
        lock.lock(); defer { lock.unlock() }
        if process?.isRunning == true { process?.terminate() }
        process = nil
        activeID = nil
    }
}
