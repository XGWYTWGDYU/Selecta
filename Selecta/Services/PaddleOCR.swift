import Foundation

enum PaddleOCR {
    static func recognize(_ data: Data, python: String, models: String) async throws -> OCRText {
        guard OCRInstallation.filesExist(python: python, models: models),
              let script = Bundle.main.url(forResource: "paddle_ocr", withExtension: "py") else {
            throw SelectaError.message("PaddleOCR 尚未安装。请打开 Selecta 设置 → 离线 OCR，点击「下载并安装 OCR」。")
        }
        let result = try await PaddleWorker.shared.recognize(python: python, script: script.path, models: models, image: data)
        guard let json = try JSONSerialization.jsonObject(with: result) as? [String: Any] else {
            throw SelectaError.message("PaddleOCR 未返回有效结果，请检查本地模型目录。")
        }
        if let error = json["error"] as? String { throw SelectaError.message(error) }
        let text = (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SelectaError.message("PaddleOCR 未识别到文字，请重新截图。") }
        let engine = (json["engine"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "PaddleOCR · PP-OCRv5（本机 CPU）"
        return OCRText(text: text, engine: engine)
    }
}

/// Runs the local inference helper without blocking AppKit; cancellation terminates the child process.
final class LocalProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var stopped = false
    private var timedOut = false

    static func run(executable: String, arguments: [String], timeout: TimeInterval) async throws {
        let runner = LocalProcess()
        try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await runner.start(executable: executable, arguments: arguments, timeout: timeout)
                try Task.checkCancellation()
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: { runner.stop() }
    }

    private func start(executable: String, arguments: [String], timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                self.lock.lock()
                if self.stopped {
                    self.lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.process.executableURL = URL(fileURLWithPath: executable)
                self.process.arguments = arguments
                self.process.standardOutput = FileHandle.nullDevice
                self.process.standardError = FileHandle.nullDevice
                var environment = ProcessInfo.processInfo.environment
                environment["HF_HUB_OFFLINE"] = "1"
                environment["PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK"] = "True"
                self.process.environment = environment
                do { try self.process.run() } catch {
                    self.lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                self.lock.unlock()
                let deadline = DispatchWorkItem { self.stop(timeout: true) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                self.process.waitUntilExit()
                deadline.cancel()
                self.lock.lock()
                let timeoutReached = self.timedOut
                self.stopped = true
                self.lock.unlock()
                if timeoutReached {
                    continuation.resume(throwing: SelectaError.message("本地 OCR 超时。请缩小图片后重试。"))
                } else if self.process.terminationStatus != 0 {
                    continuation.resume(throwing: SelectaError.message("本地 OCR 进程失败。请检查 Python 环境和模型是否安装完整。"))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    private func stop(timeout: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        if !stopped {
            stopped = true
            timedOut = timeout
            if process.isRunning { process.terminate() }
        }
    }
}
