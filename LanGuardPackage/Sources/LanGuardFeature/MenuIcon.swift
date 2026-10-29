import SwiftUI

/// What the menu bar is currently reflecting.
public enum MenuState: Equatable, Sendable {
    case lan      // wired link active
    case wifi     // no wired link
    case paused   // auto-toggle disabled

    /// Pure mapping (unit-tested).
    public static func from(autoEnabled: Bool, wiredUp: Bool) -> MenuState {
        if !autoEnabled { return .paused }
        return wiredUp ? .lan : .wifi
    }

    public var symbol: String {
        switch self {
        case .lan:    return "cable.connector"
        case .wifi:   return "wifi"
        case .paused: return "pause.circle"
        }
    }

    public var label: String {
        switch self {
        case .lan:    return "LAN"
        case .wifi:   return "Wi-Fi"
        case .paused: return "Off"
        }
    }

    /// What VoiceOver reads for the status item (the symbol name carries neither app nor state).
    public var accessibilityName: String {
        switch self {
        case .lan:    return "LanGuard, LAN"
        case .wifi:   return "LanGuard, Wi-Fi"
        case .paused: return "LanGuard, paused"
        }
    }
}

/// User-selectable menu-bar appearance.
public enum MenuIconStyle: String, CaseIterable, Identifiable, Sendable {
    case symbol           // icon only
    case symbolWithLabel  // icon + LAN/Wi-Fi text
    case label            // text only

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .symbol:          return "Icon only"
        case .symbolWithLabel: return "Icon + label"
        case .label:           return "Label only"
        }
    }
}

/// The MenuBarExtra label view — renders the current state in the chosen style.
public struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        let state = model.menuState
        switch model.settings.menuIconStyle {
        case .symbol:
            Image(systemName: state.symbol)
                .accessibilityLabel(state.accessibilityName)
        case .symbolWithLabel:
            HStack(spacing: 3) {
                Image(systemName: state.symbol)
                Text(state.label)
            }
            .accessibilityLabel(state.accessibilityName)
        case .label:
            Text(state.label)
                .accessibilityLabel(state.accessibilityName)
        }
    }
}
