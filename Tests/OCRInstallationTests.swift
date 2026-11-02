import XCTest
import CryptoKit
@testable import Selecta

private final class SetupCalls: @unchecked Sendable {
    let lock = NSLock()
    private var values: [[String]] = []
    func append(_ value: [String]) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return values }
}

final class OCRInstallationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SelectaSetupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func modelFiles(_ paths: AppPaths) throws {
        for name in OCRInstallation.modelNames {
            let model = paths.models.appendingPathComponent("official_models/\(name)")
            try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
            for name in ["inference.yml", "inference.json", "inference.pdiparams"] { try Data([1]).write(to: model.appendingPathComponent(name)) }
        }
    }
    func testIncompleteModelsAreNotReady() throws {
        let home = try directory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = AppPaths(home: home)
        XCTAssertFalse(OCRInstallation.filesExist(python: "/bin/sh", models: paths.models.path))
        try modelFiles(paths)
        XCTAssertTrue(OCRInstallation.filesExist(python: "/bin/sh", models: paths.models.path))
        try FileManager.default.removeItem(at: paths.models.appendingPathComponent("official_models/PP-OCRv5_mobile_rec/inference.pdiparams"))
        XCTAssertFalse(OCRInstallation.filesExist(python: "/bin/sh", models: paths.models.path))
    }
    func testInvalidDownloadIsRejectedBeforeExecutingAnything() async throws {
        let home = try directory(); defer { try? FileManager.default.removeItem(at: home) }
        let calls = SetupCalls()
        let installer = OCRInstallation(paths: AppPaths(home: home), script: home, requirements: home, run: { executable, args, _, _ in calls.append([executable] + args) }, download: { _ in Data("invalid archive".utf8) })
        do { _ = try await installer.install { _, _ in }; XCTFail("Expected checksum failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("校验失败")) }
        XCTAssertTrue(calls.calls.isEmpty)
    }
    func testInstallValidatesBeforeReturningAndPreservesExistingEnvironment() async throws {
        let home = try directory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = AppPaths(home: home)
        try FileManager.default.createDirectory(at: paths.environment, withIntermediateDirectories: true)
        let existing = paths.environment.appendingPathComponent("keep")
        try Data("existing runtime".utf8).write(to: existing)
        let calls = SetupCalls()
        let archive = Data("verified test archive".utf8)
        var installer = OCRInstallation(paths: paths, script: home.appendingPathComponent("paddle_ocr.py"), requirements: home.appendingPathComponent("requirements.lock"), run: { executable, args, _, _ in
            calls.append([executable] + args)
            if args.first == "venv", let target = args.last {
                let bin = URL(fileURLWithPath: target).appendingPathComponent("bin")
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("python"), withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
            }
        }, download: { _ in archive })
        installer.archiveChecksum = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        try modelFiles(paths)
        let python = try await installer.install { _, _ in }
        XCTAssertTrue(python.path.hasPrefix(paths.ocr.appendingPathComponent("Environments").path))
        XCTAssertEqual(calls.calls.count, 6)
        XCTAssertTrue(calls.calls.last!.contains("--check"))
        XCTAssertTrue(calls.calls[3].contains("--only-binary"))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing runtime".utf8))
        XCTAssertTrue(OCRInstallation.filesExist(python: python.path, models: paths.models.path))
    }
    func testCancelledInstallCleansIncompleteEnvironmentAndCanRetry() async throws {
        let home = try directory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = AppPaths(home: home)
        let archive = Data("test archive".utf8)
        var installer = OCRInstallation(paths: paths, script: home, requirements: home, run: { _, args, _, _ in
            if args.first == "venv", let target = args.last {
                try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
                throw CancellationError()
            }
        }, download: { _ in archive })
        installer.archiveChecksum = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        for _ in 0..<2 {
            do { _ = try await installer.install { _, _ in }; XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.ocr.appendingPathComponent("Environments").path).isEmpty)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: paths.ocr.path).contains { $0.hasPrefix("Setup-") })
        }
    }
    func testRetryCleansInterruptedInstallsButKeepsCompletedEnvironments() async throws {
        let home = try directory(); defer { try? FileManager.default.removeItem(at: home) }
        let paths = AppPaths(home: home)
        let pending = paths.ocr.appendingPathComponent("Environments/interrupted")
        let completed = paths.ocr.appendingPathComponent("Environments/completed")
        let staleSetup = paths.ocr.appendingPathComponent("Setup-interrupted")
        for directory in [pending, completed, staleSetup] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        try Data().write(to: pending.appendingPathComponent(".installing"))
        let installer = OCRInstallation(paths: paths, script: home, requirements: home, download: { _ in Data("bad download".utf8) })
        do { _ = try await installer.install { _, _ in }; XCTFail("Expected checksum failure") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleSetup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completed.path))
    }
    func testSetupProcessCancellationAndTimeout() async throws {
        do {
            try await OCRSetupProcess.run(executable: "/bin/sleep", arguments: ["5"], environment: [:], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        let task = Task { try await OCRSetupProcess.run(executable: "/bin/sleep", arguments: ["5"], environment: [:], timeout: 10) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
