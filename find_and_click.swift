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

func findAndClickElement(containing text: String, in startElement: AXUIElement) -> Bool {
    var queue = [QueueElement(startElement, depth: 0)]
    var visitedElements = Set<AXUIElement>()
    
    print("searching for element containing '\(text)'")
    print("first attempting full match, then partial match if necessary")
    
    // First pass: Look for full match
    let fullMatchResult = searchForMatch(in: &queue, visitedElements: &visitedElements, text: text, fullMatch: true)
    if fullMatchResult {
        print("found and clicked element with full match")
        return true
    }
    
    print("full match not found, attempting partial match")
    
    // Reset queue and visited elements for second pass
    queue = [QueueElement(startElement, depth: 0)]
    visitedElements.removeAll()
    
    // Second pass: Look for partial match
    let partialMatchResult = searchForMatch(in: &queue, visitedElements: &visitedElements, text: text, fullMatch: false)
    if partialMatchResult {
        print("found and clicked element with partial match")
        return true
    }
    
    print("no match found for '\(text)'")
    return false
}

func searchForMatch(in queue: inout [QueueElement], visitedElements: inout Set<AXUIElement>, text: String, fullMatch: Bool) -> Bool {
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
                if ["AXDescription", "AXValue", "AXTitle", "AXHelp", "AXLabel"].contains(attr) {
                    if let stringValue = value as? String {
                        let matched = fullMatch ? (stringValue == text) : stringValue.contains(text)
                        if matched {
                            print("found element containing '\(text)' at depth \(current.depth)")
                            print("match type: \(fullMatch ? "full" : "partial")")
                            return clickElement(current.element)
                        }
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

func clickElement(_ element: AXUIElement) -> Bool {
    print("attempting to click element...")
    
    // First, try using the Accessibility API to click
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result == .success {
        print("successfully clicked element using accessibility api")
        // Add a small delay after clicking
        Thread.sleep(forTimeInterval: 0.5)
        return true
    }
    
    print("accessibility api click failed, attempting simulated mouse click")
    
    // If Accessibility API fails, fall back to simulated mouse click
    var position: CFTypeRef?
    let positionResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
    
    guard positionResult == .success, let axPosition = position else {
        print("failed to get element position")
        return false
    }
    
    var point = CGPoint.zero
    AXValueGetValue(axPosition as! AXValue, .cgPoint, &point)
    
    // Adjust for screen coordinate system if necessary
    if let screenHeight = NSScreen.main?.frame.height {
        point.y = screenHeight - point.y
    }
    
    // Simulate mouse click
    let clickEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    clickEvent?.post(tap: .cghidEventTap)
    
    let releaseEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    releaseEvent?.post(tap: .cghidEventTap)
    
    print("simulated mouse click at (\(point.x), \(point.y))")
    // Add a small delay after clicking
    Thread.sleep(forTimeInterval: 0.5)
    return true
}

func findAndClickInApp(appName: String, text: String) {
    print("searching for app: \(appName)")
    
    let runningApps = NSWorkspace.shared.runningApplications
    let app = runningApps.first(where: { 
        ($0.localizedName ?? "").lowercased().contains(appName.lowercased())
    })
    
    if let app = app {
        handleFoundApp(app, text: text)
    } else {
        // Try to find similar app names
        let similarApps = runningApps.filter { app in
            let appNameWords = appName.lowercased().split(separator: " ")
            let localizedNameWords = (app.localizedName ?? "").lowercased().split(separator: " ")
            return !Set(appNameWords).isDisjoint(with: localizedNameWords)
        }
        
        if !similarApps.isEmpty {
            print("couldn't find exact match. similar apps found:")
            similarApps.forEach { app in
                print(" - \(app.localizedName ?? "Unknown")")
            }
            print("attempting to use the first similar app:")
            if let firstSimilarApp = similarApps.first {
                handleFoundApp(firstSimilarApp, text: text)
            }
        } else {
            print("no app containing given name or similar names is running")
            print("all running applications:")
            runningApps.forEach { app in
                print(" - \(app.localizedName ?? "Unknown")")
            }
        }
    }
}

func handleFoundApp(_ app: NSRunningApplication, text: String) {
    print("found app: \(app.localizedName ?? "Unknown")")
    
    // Bring the app to the foreground
    app.activate(options: [])
    
    // Wait a bit for the app to come to the foreground
    Thread.sleep(forTimeInterval: 1.0)
    
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    
    if findAndClickElement(containing: text, in: axApp) {
        print("successfully found and clicked element containing '\(text)' in \(app.localizedName ?? "Unknown")")
    } else {
        print("failed to find element containing '\(text)' in \(app.localizedName ?? "Unknown")")
    }
}

// Parse command-line arguments
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: swift find&click.swift <app_name> <text_to_find>")
    exit(1)
}

let appName = arguments[1]
let textToFind = arguments[2]

findAndClickInApp(appName: appName, text: textToFind)