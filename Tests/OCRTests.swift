import AppKit
import XCTest
@testable import Selecta

final class OCRTests: XCTestCase {
    func testLocalProcessDiscardsFailureDiagnostics() async throws {
        do {
            try await LocalProcess.run(executable: "/bin/sh", arguments: ["-c", "printf 'private OCR content' >&2; exit 2"], timeout: 2)
            XCTFail("Expected process failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("private OCR content"))
        }
    }
    func testLocalProcessTimeoutAndCancellation() async throws {
        do {
            try await LocalProcess.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        let task = Task { try await LocalProcess.run(executable: "/bin/sleep", arguments: ["10"], timeout: 5) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
