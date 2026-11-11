import Foundation
import Combine

@MainActor
final class OCRInstaller: ObservableObject {
    static let shared = OCRInstaller()
    @Published private(set) var busy = false
    @Published private(set) var step = 0
    @Published private(set) var message = "尚未检查 OCR 环境"
    @Published private(set) var ready = false
    @Published private(set) var failed = false
    private var task: Task<Void, Never>?

    func check(preferences: Preferences) {
        guard !busy else { return }
        ready = false
        failed = false
        guard OCRInstallation.filesExist(python: preferences.pythonPath, models: preferences.paddleModelPath) else {
            message = "尚未安装 OCR，点击下方按钮完成配置。"
            return
        }
        guard let script = Bundle.main.url(forResource: "paddle_ocr", withExtension: "py") else {
            message = "应用资源不完整，请重新安装 Selecta。"; failed = true; return
        }
        busy = true
        step = 0
        message = "正在检查 OCR 环境…"
        let python = preferences.pythonPath, models = preferences.paddleModelPath
        task = Task {
            defer { busy = false; task = nil }
            do {
                try await OCRSetupProcess.run(executable: python, arguments: [script.path, "--check", "--models", models], environment: OCRInstallation(paths: .current, script: script, requirements: script).environment(), timeout: 180)
                ready = true
                message = OCRInstallation.accelerated(python: python, models: models)
                    ? "OCR 已就绪（GPU 加速），可离线使用。"
                    : "OCR 已就绪，可离线使用。点击「重新安装 OCR」可启用 GPU 加速（大段文字快约 10 倍）。"
            } catch is CancellationError { message = "已取消检查。" }
            catch { failed = true; message = "环境检查失败，请点击重新安装。" }
        }
    }

    func install(preferences: Preferences) {
        guard !busy else { return }
        guard OCRInstallation.supported else {
            failed = true; message = "Selecta 仅支持 Apple Silicon Mac。"; return
        }
        guard let script = Bundle.main.url(forResource: "paddle_ocr", withExtension: "py"),
              let requirements = Bundle.main.url(forResource: "requirements-ocr", withExtension: "lock") else {
            failed = true; message = "应用安装资源不完整，请重新下载 Selecta。"; return
        }
        busy = true; failed = false; step = 0
        message = "正在准备安装…"
        task = Task {
            defer { busy = false; task = nil }
            do {
                let installer = OCRInstallation(paths: .current, script: script, requirements: requirements)
                let python = try await installer.install { [self] step, message in
                    await updateProgress(step: step, message: message)
                }
                PaddleWorker.shared.shutdown()
                preferences.pythonPath = python.path
                preferences.paddleModelPath = AppPaths.current.models.path
                OCRInstallation.removeEnvironments(in: .current, except: python)
                ready = true
                message = OCRInstallation.accelerated(python: python.path, models: AppPaths.current.models.path)
                    ? "OCR 安装完成（GPU 加速），可离线使用。"
                    : "OCR 安装完成，可离线使用。"
            } catch is CancellationError {
                message = "安装已取消。可以重新开始，已下载的依赖缓存会保留。"
            } catch {
                failed = true
                message = "\(step > 0 ? "第 \(step)/5 步失败。" : "")\(error.localizedDescription)"
            }
        }
    }
    private func updateProgress(step: Int, message: String) { self.step = step; self.message = message }
    func cancel() { task?.cancel() }
}
