import Foundation
import SwiftUI

/// Shared TenX preview hooks injected into generated projects.
enum TenXPreviewSupport {
    /// The file used by preview capture to discover the currently visible screen.
    private static let viewLogURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("tenx-view-log.json")
    }()

    /// Records the visible screen for TenX preview capture.
    static func track(_ viewName: String) {
        let entry: [String: Any] = [
            "view": viewName,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: entry) {
            try? data.write(to: viewLogURL, options: .atomic)
        }
    }
}

/// Backward-compatible tracking shim for older generated screen code.
enum TenXViewTracker {
    static func track(_ viewName: String) {
        TenXPreviewSupport.track(viewName)
    }
}

struct TenXPreviewTrackerModifier: ViewModifier {
    let viewName: String

    func body(content: Content) -> some View {
        content
            .task(id: viewName) {
                TenXPreviewSupport.track(viewName)
            }
            .onAppear {
                TenXPreviewSupport.track(viewName)
            }
    }
}

extension View {
    /// Manual opt-in hook if generated code wants to track a view explicitly.
    func trackView(_ name: String) -> some View {
        modifier(TenXPreviewTrackerModifier(viewName: name))
    }
}