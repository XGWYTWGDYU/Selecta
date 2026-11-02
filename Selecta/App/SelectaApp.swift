#if !arch(arm64)
#error("Selecta supports Apple Silicon (arm64) only.")
#endif
import SwiftUI

@main
struct SelectaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}
