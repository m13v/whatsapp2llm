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

func printAllAttributeValues(_ startElement: AXUIElement, to fileHandle: FileHandle?) {
    var queue = [QueueElement(startElement, depth: 0)]
    var visitedElements = Set<AXUIElement>()
    var printedValues = Set<String>()
    let unwantedValues = ["0", "", "", "3", ""]
    
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
                // Expand the list of attributes we're interested in
                if ["AXDescription", "AXValue", "AXLabel", "AXRoleDescription", "AXHelp"].contains(attr) {
                    let valueStr = describeValue(value)
                    if !valueStr.isEmpty && !unwantedValues.contains(valueStr) && valueStr.count > 1 && !printedValues.contains(valueStr) {  // Skip empty, unwanted, single-character, and duplicate values
                        let output = "[\(current.depth)] \(valueStr)\n"
                        print(output, terminator: "")
                        fileHandle?.write(output.data(using: .utf8)!)
                        printedValues.insert(valueStr)
                    }
                }
                
                // Add all child elements to the queue, regardless of attribute name
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
}

func describeValue(_ value: AnyObject?) -> String {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    case let point as NSPoint:
        return "(\(point.x), \(point.y))"
    case let size as NSSize:
        return "w=\(size.width) h=\(size.height)"
    case let rect as NSRect:
        return "x=\(rect.origin.x) y=\(rect.origin.y) w=\(rect.size.width) h=\(rect.size.height)"
    case let range as NSRange:
        return "loc=\(range.location) len=\(range.length)"
    case let url as URL:
        return url.absoluteString
    case let array as [AnyObject]:
        return array.isEmpty ? "Empty array" : "Array with \(array.count) elements"
    case let axValue as AXValue:
        return describeAXValue(axValue)
    case is AXUIElement:
        return "AXUIElement"
    case .none:
        return "None"
    default:
        return String(describing: value)
    }
}

func describeAXValue(_ axValue: AXValue) -> String {
    let type = AXValueGetType(axValue)
    switch type {
    case .cgPoint:
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return "(\(point.x), \(point.y))"
    case .cgSize:
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return "w=\(size.width) h=\(size.height)"
    case .cgRect:
        var rect = CGRect.zero
        AXValueGetValue(axValue, .cgRect, &rect)
        return "x=\(rect.origin.x) y=\(rect.origin.y) w=\(rect.size.width) h=\(rect.size.height)"
    case .cfRange:
        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(axValue, .cfRange, &range)
        return "loc=\(range.location) len=\(range.length)"
    default:
        return "Unknown AXValue type"
    }
}

func printAllAttributeValuesForCurrentApp() {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        print("couldn't get frontmost application")
        return
    }
    
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    
    let fileName = "accessibility_attributes.txt"
    let fileManager = FileManager.default
    let currentPath = fileManager.currentDirectoryPath
    let outputPath = (currentPath as NSString).appendingPathComponent(fileName)
    
    guard fileManager.createFile(atPath: outputPath, contents: nil, attributes: nil) else {
        print("couldn't create file")
        return
    }
    
    guard let fileHandle = FileHandle(forWritingAtPath: outputPath) else {
        print("couldn't open file for writing")
        return
    }
    defer {
        fileHandle.closeFile()
    }
    
    let header = "attribute values for \(app.localizedName ?? "unknown app"):\n"
    print(header, terminator: "")
    fileHandle.write(header.data(using: .utf8)!)
    
    printAllAttributeValues(axApp, to: fileHandle)
    
    print("output written to \(outputPath) and printed to terminal")
}

// usage
printAllAttributeValuesForCurrentApp()