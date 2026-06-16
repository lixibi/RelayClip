import AppKit
import Carbon
import Foundation

enum QuickPanelPlacement: String, CaseIterable, Identifiable {
    case mouse
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "鼠标位置"
        case .center: return "屏幕中央"
        }
    }
}

struct HotKeyShortcut: Equatable {
    var keyCode: UInt32?
    var carbonModifiers: UInt32

    static let defaultValue = HotKeyShortcut(keyCode: 9, carbonModifiers: UInt32(cmdKey | optionKey))
    static let off = HotKeyShortcut(keyCode: nil, carbonModifiers: 0)

    var isEnabled: Bool {
        keyCode != nil && carbonModifiers != 0
    }

    var storageValue: String {
        guard let keyCode, carbonModifiers != 0 else { return "off" }
        return "\(keyCode):\(carbonModifiers)"
    }

    var title: String {
        guard let keyCode, carbonModifiers != 0 else { return "关闭" }
        return "\(modifierTitle)\(Self.keyTitle(for: keyCode))"
    }

    init(keyCode: UInt32?, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(storageValue: String) {
        switch storageValue {
        case "off":
            self = .off
        case "commandOptionV", "":
            self = .defaultValue
        case "controlOptionV":
            self = HotKeyShortcut(keyCode: 9, carbonModifiers: UInt32(controlKey | optionKey))
        case "controlOptionSpace":
            self = HotKeyShortcut(keyCode: 49, carbonModifiers: UInt32(controlKey | optionKey))
        default:
            let parts = storageValue.split(separator: ":")
            if parts.count == 2,
               let keyCode = UInt32(parts[0]),
               let modifiers = UInt32(parts[1]),
               modifiers != 0 {
                self = HotKeyShortcut(keyCode: keyCode, carbonModifiers: modifiers)
            } else {
                self = .defaultValue
            }
        }
    }

    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0,
              !Self.isModifierOnlyKey(event.keyCode) else {
            return nil
        }
        self = HotKeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private var modifierTitle: String {
        var value = ""
        if carbonModifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value
    }

    private static func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62:
            return true
        default:
            return false
        }
    }

    private static func keyTitle(for keyCode: UInt32) -> String {
        keyTitles[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyTitles: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓",
        126: "↑"
    ]
}
