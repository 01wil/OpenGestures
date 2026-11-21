// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import CoreGraphics

enum KeyMap {
    static let named: [String: CGKeyCode] = [
        "return": 36, "tab": 48, "space": 49, "escape": 53, "delete": 51, "forwardDelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageUp": 116, "pageDown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ].reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }

    /// ANSI (US) virtual key codes; the fallback when the current layout cannot be queried.
    static let ansi: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    /// Named keys are layout independent; a single character goes through `layout` first, then ANSI.
    static func keyCode(for key: String, layout: (Character) -> CGKeyCode?) -> CGKeyCode? {
        let key = key.lowercased()
        if let code = named[key] { return code }
        guard key.count == 1, let ch = key.first else { return nil }
        return layout(ch) ?? ansi[ch]
    }
}

enum LiveKeyboardLayout {
    /// Reverse lookup (unshifted character to key code) in the user's current layout. Main thread only:
    /// the Text Input Sources API traps off the main thread on current macOS. Not cached, so layout switches apply.
    static func keyCode(for ch: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for code in 0..<UInt16(50) {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
                if status == noErr, length == 1, Character(UnicodeScalar(chars[0]) ?? " ") == ch { return CGKeyCode(code) }
            }
            return nil
        }
    }
}
