import Foundation
import CoreGraphics

func typeAndSend(_ text: String) {
    // Delay to give time to focus on the desired input field
    Thread.sleep(forTimeInterval: 1)

    // Type the text
    for char in text {
        if let keyCode = char.keyCode {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            // Add a 100ms delay between keystrokes
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // Press return
    let returnKeyCode: CGKeyCode = 0x24
    let returnKeyDown = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: true)
    let returnKeyUp = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: false)
    returnKeyDown?.post(tap: .cghidEventTap)
    returnKeyUp?.post(tap: .cghidEventTap)
}

// Helper extension to get key code for a character
extension Character {
    var keyCode: CGKeyCode? {
        let keyMap: [Character: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32, " ": 0x31,
        ]
        return keyMap[self.lowercased().first ?? " "]
    }
}

// Main execution
if CommandLine.arguments.count > 1 {
    let textToType = CommandLine.arguments[1]
    typeAndSend(textToType)
} else {
    print("error: please provide a text to type as an argument")
    exit(1)
}