import XCTest
import SwiftUI
import AppKit
@testable import LanGuardFeature

/// Dev-only: renders README screenshots offscreen. Skipped unless RENDER_SCREENSHOTS=<output dir>.
/// Usage: RENDER_SCREENSHOTS=$PWD/../docs/screenshots swift test --filter ScreenshotRenderTests
@MainActor
final class ScreenshotRenderTests: XCTestCase {
    private func render<V: View>(_ view: V, size: CGSize, to name: String, dir: String) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.controlActiveState, .key))
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .aqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    func test_renderScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_SCREENSHOTS"] else {
            throw XCTSkip("set RENDER_SCREENSHOTS=<dir> to render")
        }
        let model = AppModel()
        for (pane, name) in [(ConfigView.Pane.interfaces, "settings-interfaces.png")] {
            try render(ConfigView(model: model, pane: pane), size: CGSize(width: 520, height: 500), to: name, dir: dir)
        }
    }
}
