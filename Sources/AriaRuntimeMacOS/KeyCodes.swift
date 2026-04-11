import ApplicationServices
import Foundation

enum KeyboardLayout {
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "return": 36, "enter": 36, "escape": 53, "esc": 53,
        "delete": 51, "backspace": 51, "forwarddelete": 117, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    private static let modifierFlagsMap: [String: CGEventFlags] = [
        "command": .maskCommand,
        "cmd": .maskCommand,
        "shift": .maskShift,
        "option": .maskAlternate,
        "alt": .maskAlternate,
        "control": .maskControl,
        "ctrl": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    static func modifierFlags(for keys: [String]) -> CGEventFlags {
        keys.reduce(into: CGEventFlags()) { partialResult, key in
            if let flag = modifierFlagsMap[key.lowercased()] {
                partialResult.formUnion(flag)
            }
        }
    }

    static func primaryKeyCode(for keys: [String]) -> CGKeyCode? {
        for key in keys {
            let normalized = key.lowercased()
            if modifierFlagsMap[normalized] != nil {
                continue
            }
            if let keyCode = keyCodes[normalized] {
                return keyCode
            }
        }
        return nil
    }
}
