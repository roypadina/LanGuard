import AppKit
import CoreAudio
import CoreGraphics
import SwiftUI

/// One dynamic colour from a light/dark pair (plus optional Increase Contrast variants), so every Color
/// below flips with the appearance automatically.
private func dyn(light: NSColor, dark: NSColor, hcLight: NSColor? = nil, hcDark: NSColor? = nil) -> Color {
    Color(nsColor: NSColor(name: nil) {
        switch $0.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
        case .darkAqua: dark
        case .accessibilityHighContrastAqua: hcLight ?? light
        case .accessibilityHighContrastDarkAqua: hcDark ?? dark
        default: light
        }
    })
}

/// The card's colours (MeetAlert's Theme values; LanGuard has no theme file).
private enum Theme {
    /// Card base tint over .regularMaterial. Navy-ink, not neutral black.
    static let ink = dyn(light: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.45),
                         dark: NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 0.55))
    static let kofi = dyn(light: NSColor(red: 0.78, green: 0.19, blue: 0.18, alpha: 1),   // #C8302D
                          dark: NSColor(red: 1.00, green: 0.37, blue: 0.36, alpha: 1),    // #FF5E5B
                          hcLight: NSColor(red: 0.64, green: 0.14, blue: 0.13, alpha: 1), // #A32320
                          hcDark: NSColor(red: 1.00, green: 0.53, blue: 0.51, alpha: 1))  // #FF8783
    /// Ink text on the bright dark-mode fill, white on the deep light-mode fill.
    static let onSignal = dyn(light: .white, dark: NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1))
}

/// Ko-fi ask bookkeeping (UserDefaults → supportPrompt, JSON). The rules live here, pure, so tests can
/// drive them with any clock and version.
struct SupportPromptState: Codable, Equatable {
    enum Answer { case support, snooze, never }

    var shownAt: [Date] = []  // asks in the last 365 days (older ones are dropped)
    var snoozedUntil: Date?
    var neverVersion: String?  // app version when the user said "Nope, don't ask again"
    var neverAt: Date?
    var supportedAt: Date?

    static let day: TimeInterval = 24 * 3600

    init() {}

    // Tolerant decode: a missing key must not wipe the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shownAt = try c.decodeIfPresent([Date].self, forKey: .shownAt) ?? []
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        neverVersion = try c.decodeIfPresent(String.self, forKey: .neverVersion)
        neverAt = try c.decodeIfPresent(Date.self, forKey: .neverAt)
        supportedAt = try c.decodeIfPresent(Date.self, forKey: .supportedAt)
    }

    /// First ask: ≥ 7 days installed and more than 24 automatic switches. Then: snooze = 14 days,
    /// support = 180 days quiet, "never" = until the next major version AND ≥ 90 days, max 3 asks / 365 days.
    func mayAsk(now: Date, installDate: Date, autoSwitches: Int, appVersion: String) -> Bool {
        guard now >= installDate.addingTimeInterval(7 * Self.day), autoSwitches > 24 else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        if let supportedAt, now < supportedAt.addingTimeInterval(180 * Self.day) { return false }
        if let neverAt, let neverVersion,
           Self.major(appVersion) <= Self.major(neverVersion) || now < neverAt.addingTimeInterval(90 * Self.day) {
            return false
        }
        return shownAt.filter { $0 > now.addingTimeInterval(-365 * Self.day) }.count < 3
    }

    mutating func recordShown(_ now: Date) {
        shownAt = shownAt.filter { $0 > now.addingTimeInterval(-365 * Self.day) } + [now]
    }

    mutating func record(_ answer: Answer, now: Date, appVersion: String) {
        switch answer {
        case .support: supportedAt = now
        case .snooze: snoozedUntil = now.addingTimeInterval(14 * Self.day)
        case .never: neverVersion = appVersion; neverAt = now
        }
    }

    static func major(_ version: String) -> Int { Int(version.split(separator: ".").first ?? "") ?? 0 }
}

/// When LanGuard asks: ~10 s after a dock (LAN plugged in → Wi-Fi turned off) has completed, if
/// `SupportPromptState` allows it. Both directions count as switches. Counters and state live in UserDefaults.
@MainActor
enum SupportPrompt {
    private enum Keys {
        static let installDate = "installDate"  // first launch of a version with the support prompt
        static let autoSwitches = "autoSwitches"  // automatic Wi-Fi switches completed (the card's {n})
        static let wifiOffOnLAN = "autoWiFiOffOnLAN"  // the "Wi-Fi off" share of them
        static let state = "supportPrompt"
    }
    private static var defaults: UserDefaults { .standard }
    private static var chance: Task<Void, Never>?  // the pending ask after the last dock
    private static var expiry: Task<Void, Never>?  // fades an unanswered card

    /// Card on screen: mirrored in the status menu (the card never takes keyboard focus).
    static var showing = false {
        didSet { AppModel.shared.objectWillChange.send() }  // re-render the menu
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// At launch: the first launch with the support prompt starts its 7-day clock.
    nonisolated static func start() {
        if UserDefaults.standard.object(forKey: Keys.installDate) == nil {
            UserDefaults.standard.set(Date(), forKey: Keys.installDate)
        }
    }

    /// Any switch starting (automatic, Switch to Wi-Fi, Back to LAN): an open card counts as
    /// "Ask me in 2 weeks", and the pending ask from the previous switch is dropped.
    nonisolated static func switchStarted() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                chance?.cancel()
                chance = nil
                snoozeIfShowing()
            }
        }
    }

    /// An automatic switch has completed (only wired-link edges count, never user-started ones).
    /// Only a dock asks: at an unplug the user is usually leaving the desk.
    nonisolated static func switchCompleted(wifiOff: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                defaults.set(defaults.integer(forKey: Keys.autoSwitches) + 1, forKey: Keys.autoSwitches)
                guard wifiOff else { return }
                defaults.set(defaults.integer(forKey: Keys.wifiOffOnLAN) + 1, forKey: Keys.wifiOffOnLAN)
                chance?.cancel()
                chance = Task { await askAfterSwitch() }
            }
        }
    }

    /// LanGuard's own UI (Settings, About, Welcome) opening over an unanswered card snoozes it.
    static func snoozeIfShowing() {
        if showing { SupportPanel.respond(.snooze); SupportPanel.close() }
    }

    /// One try per switch: wait for the network to settle, then ask once nothing is in the way.
    private static func askAfterSwitch() async {
        try? await Task.sleep(for: .seconds(10))
        let deadline = Date().addingTimeInterval(10 * 60)  // later than that it no longer reads as "after a switch"
        // Not now: Settings/Welcome open, a hand-over running, nobody at the desk, or on a call — retry.
        while !Task.isCancelled, Date() < deadline {
            let windowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            if !showing, !windowOpen, AppModel.shared.handover.status == nil, !isAway(), !micInUse() {
                return ask()
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private static func ask() {
        let now = Date()
        var state = defaults.data(forKey: Keys.state)
            .flatMap { try? JSONDecoder().decode(SupportPromptState.self, from: $0) } ?? SupportPromptState()
        guard let installDate = defaults.object(forKey: Keys.installDate) as? Date,
              state.mayAsk(now: now, installDate: installDate,
                           autoSwitches: defaults.integer(forKey: Keys.autoSwitches), appVersion: appVersion)
        else { return }
        state.recordShown(now)
        save(state)
        present()
    }

    /// `record: false` = the ⌥ menu preview: shows the real card but never touches the ask bookkeeping.
    static func present(record: Bool = true) {
        guard !showing else { return }
        showing = true
        SupportPanel.show(autoSwitches: defaults.integer(forKey: Keys.autoSwitches),
                          wifiOffOnLAN: defaults.integer(forKey: Keys.wifiOffOnLAN),
                          onAnswer: { answer in
                              if answer == .support { NSWorkspace.shared.open(AboutInfo.koFi) }
                              guard record else { return }
                              var state = defaults.data(forKey: Keys.state)
                                  .flatMap { try? JSONDecoder().decode(SupportPromptState.self, from: $0) } ?? SupportPromptState()
                              state.record(answer, now: Date(), appVersion: appVersion)
                              save(state)
                          },
                          onClosed: { showing = false; expiry?.cancel(); expiry = nil })
        if record { expiry = Task { await fadeUnanswered() } }
    }

    /// An unanswered card fades after 5 minutes in front of the user (away time doesn't count) = a snooze.
    private static func fadeUnanswered() async {
        var seen: TimeInterval = 0
        while seen < 5 * 60 {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, showing else { return }
            if !isAway() { seen += 15 }
        }
        snoozeIfShowing()
    }

    private static func save(_ state: SupportPromptState) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Keys.state)
    }

    /// Nobody at the desk: screen locked, or no keyboard/mouse input for 2 minutes.
    private static func isAway() -> Bool {
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true { return true }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!) > 120
    }

    /// Some app is recording from the default input device (a call, a dictation). No permission needed.
    private static func micInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}

/// The floating receipt card, top-right under the menu bar. Borderless, so it can never become key:
/// no keystroke can reach its buttons (a stray Return must not tip or opt out). Keyboard and
/// VoiceOver users get the same three actions in the status menu instead.
@MainActor
enum SupportPanel {
    private static var panel: NSPanel?
    private static var onAnswer: ((SupportPromptState.Answer) -> Void)?
    private static var onClosed: (() -> Void)?
    /// Transparent room around the card: shadow on top/right, coffee burst on left/bottom.
    static let insets = EdgeInsets(top: 12, leading: 48, bottom: 48, trailing: 12)

    static func show(autoSwitches: Int, wifiOffOnLAN: Int,
                     onAnswer: @escaping (SupportPromptState.Answer) -> Void,
                     onClosed: @escaping () -> Void) {
        guard panel == nil else { return }
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main else {
            return onClosed()
        }
        let p = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false  // Swift owns it via `panel`
        p.isFloatingPanel = true
        p.level = .floating
        p.hasShadow = false  // the card draws its own; a window shadow would outline the transparent margin
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: SupportPromptView(autoSwitches: autoSwitches, wifiOffOnLAN: wifiOffOnLAN))
        p.contentView = host
        let size = host.fittingSize
        let visible = screen.visibleFrame  // card lands 12pt in from the top-right corner (= the insets)
        p.setFrame(NSRect(x: visible.maxX - size.width, y: visible.maxY - size.height,
                          width: size.width, height: size.height), display: false)
        p.orderFrontRegardless()
        panel = p
        self.onAnswer = onAnswer
        self.onClosed = onClosed
        AccessibilityNotification.Announcement(
            "LanGuard: \(autoSwitches.formatted()) automatic Wi-Fi switches you didn't have to make. Tip a coffee on Ko-fi? Options are in the LanGuard menu."
        ).post()
    }

    /// One answer per card (button or menu). Records it; the caller animates and closes.
    static func respond(_ answer: SupportPromptState.Answer) {
        onAnswer?(answer)
        onAnswer = nil
    }

    static func close() {
        guard let p = panel else { return }
        panel = nil
        onAnswer = nil
        let closed = onClosed
        onClosed = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {  // AppKit calls it on the main thread; the SDK just doesn't say so
                // close + drop the view: a hidden panel keeps rendering its loops
                p.contentView = nil
                p.close()
                closed?()
            }
        })
    }

    /// Snooze: slide the window so the (SwiftUI-shrinking) card ends on the menu-bar icon.
    static func flyToStatusItem(duration: TimeInterval) {
        guard let p = panel, let target = statusItemWindow()?.frame else { return }
        let card = NSRect(x: p.frame.minX + insets.leading, y: p.frame.minY + insets.bottom,
                          width: p.frame.width - insets.leading - insets.trailing,
                          height: p.frame.height - insets.top - insets.bottom)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 0.8, 0.2)
            p.animator().setFrameOrigin(NSPoint(x: p.frame.minX + target.midX - card.midX,
                                                y: p.frame.minY + target.midY - card.midY))
        }
    }

    /// One accent-coloured flash behind the menu-bar icon, as the snoozed card lands in it.
    static func pulseStatusItem() {
        guard let view = statusItemWindow()?.contentView else { return }
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        let pulse = CAKeyframeAnimation(keyPath: "backgroundColor")
        let red = NSColor(red: 1.00, green: 0.37, blue: 0.36, alpha: 0.9).cgColor  // Ko-fi red #FF5E5B
        pulse.values = [NSColor.clear.cgColor, red, NSColor.clear.cgColor]
        pulse.keyTimes = [0, 0.3, 1]
        pulse.duration = 0.9
        view.layer?.add(pulse, forKey: "supportPulse")
    }

    // shortcut: MenuBarExtra exposes no status-item frame, so find its private NSStatusBarWindow by
    // class name; nil → snooze just fades. Upgrade if Apple ships a public frame API.
    private static func statusItemWindow() -> NSWindow? {
        NSApp.windows.first { $0.className.contains("NSStatusBarWindow") && $0.isVisible }
    }
}

/// The receipt: prints out of a slot, itemises what LanGuard did, ends in "TIP? ☕ optional".
struct SupportPromptView: View {
    let autoSwitches: Int
    let wifiOffOnLAN: Int
    var settled = false  // start fully printed, no entry animation (screenshot renders)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var shown = false
    @State private var printed: CGFloat = 0  // 0 = paper inside the slot, 1 = fully out
    @State private var paperHeight: CGFloat = 0
    @State private var buttonsShown = false
    @State private var sheen: CGFloat = -1  // sheen band position across the Support button, -1…1
    @State private var answered = false
    @State private var bursting = false
    @State private var thanked = false
    @State private var leaving = false  // never / final fade: scale 0.94 + fade
    @State private var flying = false  // snooze: shrink toward the menu-bar icon

    private static let width: CGFloat = 340
    private static let radius: CGFloat = 18
    // True: only switches LanGuard made itself on a wired-link change are counted.
    private var title: String { "\(autoSwitches.formatted()) switches you didn't have to make.\u{00A0}🎯" }  // no-break: 🎯 never wraps alone

    var body: some View {
        card
            .scaleEffect(flying ? 0.06 : leaving ? 0.94 : 1)
            .opacity(flying || leaving || !(shown || settled) ? 0 : 1)
            .padding(SupportPanel.insets)
            .task { await sheenLoop() }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return ZStack {
            receipt.opacity(thanked ? 0 : 1)
            if thanked { thanks }  // same card size: content crossfades, nothing jumps
        }
        .padding(14)
        .frame(width: Self.width)
        .background {
            ZStack {
                if contrast == .increased {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                    shape.fill(Theme.ink)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
        .overlay(shape.strokeBorder(contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.primary.opacity(0.12)),
                                    lineWidth: contrast == .increased ? 2 : 1))
        .overlay { if bursting { CoffeeBurst() } }
    }

    private var receipt: some View {
        VStack(spacing: 0) {
            Capsule()  // the printer slot
                .fill(LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(height: 9)
                .zIndex(1)  // the paper slides out from under the slot
                .accessibilityHidden(true)
            paper  // measured first, then printed: the card stays invisible until then (no full-paper flash)
                .background(GeometryReader { g in Color.clear.onAppear { paperHeight = g.size.height; enter() } })
                .offset(y: -(1 - (settled ? 1 : printed)) * (paperHeight + 9))  // + the torn edge
                .padding(.bottom, 9)  // room for the torn edge
                .clipped()
                .padding(.horizontal, 8)
                .padding(.top, -3)
            buttons.opacity(buttonsShown || settled ? 1 : 0)
        }
    }

    private var paper: some View {
        let ink = Color(red: 0.16, green: 0.15, blue: 0.13)
        let faded = Color(red: 0.36, green: 0.33, blue: 0.29)
        return VStack(spacing: 3) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text("LANGUARD ★ RECEIPT").font(.system(size: 11.5, weight: .bold, design: .monospaced)).tracking(1.4)
            Text(Date().formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(faded)
                .padding(.bottom, 6)
            row("Auto switches", autoSwitches.formatted())
            row("Wi-Fi turned off on LAN", wifiOffOnLAN.formatted())
            row("Price paid", "$0.00")
            Divider().overlay(faded.opacity(0.5)).padding(.vertical, 3)
            HStack { Text("TIP?"); Spacer(); Text("☕ optional") }
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
            VStack(spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text("LanGuard is free, open source and made by one person. Tip the human behind the switch?")
                    .font(.system(size: 11.5)).foregroundStyle(faded)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            Barcode().fill(ink).frame(height: 22).padding(.horizontal, 20).padding(.top, 8)
                .accessibilityHidden(true)
        }
        .foregroundStyle(ink)
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
        .background(TornPaper().fill(Color(red: 0.98, green: 0.97, blue: 0.93)).padding(.bottom, -8)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2))
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(label).fixedSize()  // the leader shrinks, never the label
            Leader().stroke(Color(red: 0.71, green: 0.68, blue: 0.62), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .frame(height: 1)
                .accessibilityHidden(true)
            Text(value).fixedSize()
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button("Tip a coffee ☕") { answer(.support) }
                .buttonStyle(SupportButtonStyle(prominent: true))
                .overlay { sheenBand }
            HStack(spacing: 6) {
                Button("Ask me in 2 weeks") { answer(.snooze) }.buttonStyle(SupportButtonStyle())
                Button("Nope, don't ask again") { answer(.never) }.buttonStyle(SupportButtonStyle())
            }
            Text("I only ask after a switch — at most 3× a year.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .padding(.top, 4)
        .disabled(answered)
    }

    private var sheenBand: some View {
        GeometryReader { g in
            LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.35)
                .offset(x: sheen * g.size.width * 0.9 + g.size.width * 0.325)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thanks: some View {
        VStack(spacing: 6) {
            Text("♥").font(.system(size: 40)).foregroundStyle(Theme.kofi)
            Text("Thank you!").font(.system(size: 16, weight: .semibold))
            Text("Opening Ko-fi…").font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    // MARK: motion

    private func enter() {
        guard !settled else { return }
        if reduceMotion {
            printed = 1
            buttonsShown = true
            withAnimation(.easeOut(duration: 0.15)) { shown = true }
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { shown = true }
        Task {
            // Stepped jerks, ~1 s total: (target, move seconds) with a short hold after each.
            for (target, seconds) in [(0.17, 0.15), (0.43, 0.19), (0.71, 0.20), (1.0, 0.30)] as [(CGFloat, Double)] {
                withAnimation(.easeOut(duration: seconds)) { printed = target }
                try? await Task.sleep(for: .seconds(seconds + 0.06))
            }
            withAnimation(.easeOut(duration: 0.3)) { buttonsShown = true }
        }
    }

    private func sheenLoop() async {
        guard !settled, !reduceMotion else { return }
        for _ in 0..<2 {  // two passes catch the eye once; an endless shine reads as nagging
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !answered else { return }
            sheen = -1
            withAnimation(.easeInOut(duration: 1.2)) { sheen = 1 }
        }
    }

    private func answer(_ a: SupportPromptState.Answer) {
        guard !answered else { return }
        answered = true
        SupportPanel.respond(a)
        Task {
            switch a {
            case .support:
                bursting = !reduceMotion
                try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.35))
                withAnimation(.easeInOut(duration: 0.3)) { thanked = true }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.25)) { leaving = true }
                try? await Task.sleep(for: .seconds(0.25))
            case .snooze where !reduceMotion:
                withAnimation(.timingCurve(0.55, 0, 0.8, 0.2, duration: 0.55)) { flying = true }
                SupportPanel.flyToStatusItem(duration: 0.55)
                try? await Task.sleep(for: .seconds(0.5))
                SupportPanel.pulseStatusItem()
            case .snooze, .never:
                withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.25)) { leaving = true }
                try? await Task.sleep(for: .seconds(0.25))
            }
            SupportPanel.close()
        }
    }
}

/// Fill-the-card buttons. Custom on purpose: the app is never active while the card shows, so
/// system bordered buttons would render in their gray inactive look.
private struct SupportButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(cfg: configuration, prominent: prominent)
    }

    private struct StyledButton: View {
        let cfg: Configuration
        let prominent: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: prominent ? 9 : 7, style: .continuous)
            cfg.label
                .font(.system(size: prominent ? 13 : 12, weight: prominent ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: prominent ? 34 : 28)
                .foregroundStyle(prominent ? AnyShapeStyle(Theme.onSignal) : AnyShapeStyle(.primary))
                .background(shape.fill(prominent ? AnyShapeStyle(Theme.kofi)
                                                 : AnyShapeStyle(Color.primary.opacity(hover ? 0.14 : 0.08))))
                .contentShape(shape)
                .opacity(prominent && hover ? 0.92 : enabled ? 1 : 0.6)
                .scaleEffect(cfg.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Coffee cups and beans flying out of the card's centre, once.
private struct CoffeeBurst: View {
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * 2.39996  // golden angle: an even, deterministic spread
                let distance = 90 + Double((i * 37) % 80)
                Group {
                    if i % 3 == 0 {
                        Text("☕").font(.system(size: 18))
                    } else {
                        Capsule().fill(Color(red: 0.42, green: 0.24, blue: 0.12)).frame(width: 7, height: 10)
                    }
                }
                .rotationEffect(.degrees(fired ? Double((i * 53) % 360) - 180 : 0))
                .scaleEffect(fired ? 1 : 0.5)
                .offset(x: fired ? cos(angle) * distance : 0, y: fired ? sin(angle) * distance - 20 : 0)
                .opacity(fired ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { fired = true } }
    }
}

/// Receipt paper with a zig-zag torn bottom edge (8pt teeth).
private struct TornPaper: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tooth: CGFloat = 12, depth: CGFloat = 8
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
        var x = r.maxX
        while x > r.minX {
            p.addLine(to: CGPoint(x: max(r.minX, x - tooth / 2), y: r.maxY))
            x -= tooth
            p.addLine(to: CGPoint(x: max(r.minX, x), y: r.maxY - depth))
        }
        p.closeSubpath()
        return p
    }
}

/// Dotted leader between a receipt label and its value.
private struct Leader: Shape {
    func path(in r: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }
    }
}

/// Decorative barcode: fixed bar widths, so it looks the same every time.
private struct Barcode: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pattern: [CGFloat] = [2, 1, 1, 3, 2, 1, 3, 1, 1, 2, 1, 1, 2, 3, 1, 2]
        var x = r.minX, i = 0
        while x < r.maxX {
            let bar = pattern[i % pattern.count]
            if i % 2 == 0 { p.addRect(CGRect(x: x, y: r.minY, width: min(bar, r.maxX - x), height: r.height)) }
            x += bar + 1
            i += 1
        }
        return p
    }
}
