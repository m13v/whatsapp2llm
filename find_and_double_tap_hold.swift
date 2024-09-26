import Cocoa
import ApplicationServices
import Foundation

class QueueElement {
    let element: AXUIElement
    let depth: Int
    
    init(_ element: AXUIElement, depth: Int) {
        self.element = element
        self.depth = depth
    }
}

func findAndClickDropdownButton(containing text: String, in startElement: AXUIElement) -> Bool {
    var queue = [QueueElement(startElement, depth: 0)]
    var visitedElements = Set<AXUIElement>()
    
    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard !visitedElements.contains(current.element) else { continue }
        visitedElements.insert(current.element)
        
        var attributeNames: CFArray?
        let result = AXUIElementCopyAttributeNames(current.element, &attributeNames)
        
        guard result == .success, let attributes = attributeNames as? [String] else { continue }
        
        for attr in attributes {
            var value: AnyObject?
            let valueResult = AXUIElementCopyAttributeValue(current.element, attr as CFString, &value)
            if valueResult == .success {
                if ["AXDescription", "AXValue", "AXTitle"].contains(attr) {
                    if let stringValue = value as? String, stringValue.contains(text) {
                        print("found element containing '\(text)' at depth \(current.depth)")
                        return clickDropdownButton(current.element)
                    }
                }
                
                if let elementArray = value as? [AXUIElement] {
                    for childElement in elementArray {
                        queue.append(QueueElement(childElement, depth: current.depth + 1))
                    }
                } else if let childElement = value as! AXUIElement? {
                    queue.append(QueueElement(childElement, depth: current.depth + 1))
                }
            }
        }
    }
    
    return false
}

func clickDropdownButton(_ element: AXUIElement) -> Bool {
    var position: CFTypeRef?
    var size: CFTypeRef?
    
    // get position
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
          let positionValue = position as! AXValue? else {
        print("failed to get element position")
        return false
    }
    
    // get size
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
          let sizeValue = size as! AXValue? else {
        print("failed to get element size")
        return false
    }
    
    var point = CGPoint.zero
    var elementSize = CGSize.zero
    
    AXValueGetValue(positionValue, .cgPoint, &point)
    AXValueGetValue(sizeValue, .cgSize, &elementSize)
    
    // calculate the position of the dropdown button (slightly to the left and top of the bottom-right corner)
    let clickPoint = CGPoint(x: point.x + elementSize.width - 10, y: point.y + elementSize.height - 10)
    
    // move cursor to the dropdown button
    CGDisplayMoveCursorToPoint(CGMainDisplayID(), clickPoint)
    
    // wait for 200ms
    Thread.sleep(forTimeInterval: 0.2)
    
    // perform click
    let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left)
    let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left)
    
    clickDown?.post(tap: CGEventTapLocation.cghidEventTap)
    clickUp?.post(tap: CGEventTapLocation.cghidEventTap)
    
    print("clicked dropdown button for element")
    return true
}

func findAndDoubleTapHoldInApp(appName: String, text: String) {
    print("searching for app: \(appName)")
    // print("all running applications:")
    NSWorkspace.shared.runningApplications.forEach { app in
        // print(" - \(app.localizedName ?? "unknown")")
    }
    
    guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").lowercased().contains("whatsapp") }) else {
        print("no app containing given name is running")
        return
    }
    
    // bring the app to the foreground
    app.activate(options: [])
    
    // wait a bit for the app to come to the foreground
    Thread.sleep(forTimeInterval: 1.0)
    
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    
    if findAndClickDropdownButton(containing: text, in: axApp) {
        print("successfully found and clicked dropdown button for element containing '\(text)' in \(appName)")
    } else {
        print("failed to find element containing '\(text)' in \(appName)")
    }
}

// parse command-line arguments
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: swift find_and_double_tap_hold.swift <app_name> <text_to_find>")
    exit(1)
}

let appName = arguments[1]
let textToFind = arguments[2]

findAndDoubleTapHoldInApp(appName: appName, text: textToFind)