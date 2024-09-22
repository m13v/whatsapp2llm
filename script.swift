import Cocoa
import ApplicationServices
import Accessibility
import AppKit

let kAXLabelAttribute = "AXLabel" as CFString
let kAXIdentifierAttribute = "AXIdentifier" as CFString
let kAXHelpAttribute = "AXHelp" as CFString
let kAXSheetsAttribute = "AXSheets" as CFString
let kAXModalAlertSubrole = "AXModalAlert" as CFString

// Extension to remove control and invisible characters
extension String {
    func removingControlCharacters() -> String {
        return String(self.unicodeScalars.compactMap { scalar in
            (scalar.value >= 32 || scalar.value == 9) ? Character(scalar) : nil
        })
    }
}


func printElementInfo(_ element: AXUIElement, indent: String = "") {
    var value: AnyObject?
    
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let role = value as? String ?? "Unknown"
    
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
    let title = value as? String ?? "No Title"
    
    // print("\(indent)Role: \(role), Title: \(title)")
    
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            printElementInfo(child, indent: indent + "  ")
        }
    }
}

func clickSettingsMenuItem() {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { 
        $0.bundleIdentifier == "net.whatsapp.WhatsApp"
    }) else {
        print("WhatsApp is not running")
        return
    }
    
    print("Found WhatsApp application: \(app.localizedName ?? "Unknown")")
    
    let appRef = AXUIElementCreateApplication(app.processIdentifier)
    
    var value: AnyObject?
    AXUIElementCopyAttributeValue(appRef, kAXMenuBarAttribute as CFString, &value)
    let menuBar = value as! AXUIElement
    
    AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &value)
    guard let menuBarItems = value as? [AXUIElement] else {
        print("Could not find menu bar items")
        return
    }
    
    for menuBarItem in menuBarItems {
        AXUIElementCopyAttributeValue(menuBarItem, kAXTitleAttribute as CFString, &value)
        guard let title = value as? String else { continue }
        
        if title == "WhatsApp" {
            AXUIElementCopyAttributeValue(menuBarItem, kAXChildrenAttribute as CFString, &value)
            guard let menu = (value as? [AXUIElement])?.first else { continue }
            
            AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &value)
            guard let menuItems = value as? [AXUIElement] else { continue }
            
            for menuItem in menuItems {
                AXUIElementCopyAttributeValue(menuItem, kAXTitleAttribute as CFString, &value)
                guard let itemTitle = value as? String else { continue }
                
                // Use contains to match the menu item title
                if itemTitle.contains("Settings") {
                    AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
                    print("Settings menu item clicked")
                    return
                }
            }
        }
    }
    
    print("Could not find Settings menu item")
}

func clickChatsItem() {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { 
        $0.bundleIdentifier == "net.whatsapp.WhatsApp"
    }) else {
        print("whatsapp is not running")
        return
    }
    
    let appRef = AXUIElementCreateApplication(app.processIdentifier)
    
    var value: AnyObject?
    
    // get the main window
    AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &value)
    let window = value as! AXUIElement

    // navigate to the Chats element
    guard let sceneView = getChildByRole(of: window, role: "AXGroup") else {
        print("could not find sceneView")
        return
    }

    // print("clickable elements:")
    printClickableElements(window)
    
    // now click on the Chats element
    // print("attempting to click on Chats element...")
    clickElementWithLabel("Chats", in: window)
    
    // Add this line to print all children after attempting to click
    // print("all children after click attempt:")
    printAllChildren(window)
}

func printClickableElements(_ element: AXUIElement, indent: String = "") {
    var value: AnyObject?
    
    // get role (type)
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let role = value as? String ?? "Unknown"
    
    // check if the current element is potentially interactive
    if ["AXButton", "AXMenuItem", "AXRadioButton", "AXCheckBox", "AXStaticText", "AXGroup"].contains(role) {
        
        // get label
        AXUIElementCopyAttributeValue(element, kAXLabelAttribute as CFString, &value)
        let label = value as? String ?? "No Label"
        
        // get value
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let elementValue = value as? String ?? "No Value"
        
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        let title = value as? String ?? "No Title"
        
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value)
        let description = value as? String ?? "No Description"
        
        // print("\(indent)[\(role)] \(title) - \(description)")
    }
    
    // recursively check children
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            printClickableElements(child, indent: indent + "  ")
        }
    }
}

func getFirstChild(of element: AXUIElement) -> AXUIElement? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    return (value as? [AXUIElement])?.first
}

func printElementAttributes(_ element: AXUIElement) {
    var attributeNames: CFArray?
    let result = AXUIElementCopyAttributeNames(element, &attributeNames)
    
    guard result == .success, let attributes = attributeNames as? [String] else {
        // print("failed to get attribute names")
        return
    }
    
    // print("element attributes:")
    for attributeName in attributes {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)
        if result == .success {
            // print("  \(attributeName): \(value.map { String(describing: $0) } ?? "nil")")
        }
    }
}

func getChildByRole(of element: AXUIElement, role: String) -> AXUIElement? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { 
        // print("no children found for element")
        return nil 
    }
    
    for child in children {
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
        if let childRole = value as? String {
            // print("found child with role: \(childRole)")
            if childRole == role {
                return child
            }
        }
    }
    
    // print("no child found with role: \(role)")
    return nil
}

func getChildrenByRole(of element: AXUIElement, role: String) -> [AXUIElement] {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { return [] }
    
    return children.filter { child in
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
        guard let childRole = value as? String else { return false }
        return childRole == role
    }
}

func findChatsElement(in element: AXUIElement) -> AXUIElement? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { return nil }
    
    for child in children {
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
        guard let role = value as? String else { continue }
        
        if role == "AXStaticText" {
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value)
            if let text = value as? String, text == "Chats" {
                return child
            }
        } else {
            // Recursively search in child elements
            if let foundElement = findChatsElement(in: child) {
                return foundElement
            }
        }
    }
    
    return nil
}

func findElementByLabelAndRole(in element: AXUIElement, label: String, role: String) -> AXUIElement? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { return nil }
    
    for child in children {
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
        guard let childRole = value as? String, childRole == role else { continue }
        
        AXUIElementCopyAttributeValue(child, kAXLabelAttribute as CFString, &value)
        if let childLabel = value as? String, childLabel == label {
            return child
        }
    }
    
    return nil
}

func printAllChildren(_ element: AXUIElement) {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { 
        // print("no children found")
        return 
    }
    
    // print("children found: \(children.count)")
    for (index, child) in children.enumerated() {
        // print("child \(index):")
        printElementAttributes(child)
    }
}

// Add this new function to click on a specific element
func clickElementWithLabel(_ label: String, in element: AXUIElement, indent: String = "") {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { 
        // print("\(indent)no children found")
        return 
    }
    
    // print("\(indent)searching through \(children.count) children")
    
    for child in children {
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
        guard let role = value as? String else { 
            // print("\(indent)  child has no role")
            continue 
        }
        
        // print("\(indent)  checking child with role: \(role)")
        
        if role == "AXStaticText" {
            // Check for description (which seems to contain the "Chats" text)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &value)
            let description = value as? String ?? ""
            
            // print("\(indent)    found AXStaticText with description: \(description)")
            
            if description.contains(label) {
                // print("\(indent)    attempting to click...")
                let result = AXUIElementPerformAction(child, kAXPressAction as CFString)
                // print("\(indent)    click result: \(result == .success ? "success" : "failure")")
                return
            }
        }
        
        // recursively search in child elements
        clickElementWithLabel(label, in: child, indent: indent + "  ")
    }
}

func reviewClickableElements(_ element: AXUIElement, indent: String = "") {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard let children = value as? [AXUIElement] else { 
        print("\(indent)no children found")
        return 
    }
    
    print("\(indent)reviewing \(children.count) children")
    
    for child in children {
        var role: String = "Unknown"
        var description: String = "No Description"
        var label: String = "No Label"
        var title: String = "No Title"
        var type: String = "No Type"
        var elementValue: String = "No Value"
        
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
        role = value as? String ?? role
        
        AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &value)
        description = value as? String ?? description
        
        AXUIElementCopyAttributeValue(child, kAXLabelAttribute as CFString, &value)
        label = value as? String ?? label
        
        AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &value)
        title = value as? String ?? title
        
        AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &value)
        type = value as? String ?? type
        
        AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value)
        elementValue = value as? String ?? elementValue
        
        if ["AXButton", "AXMenuItem", "AXRadioButton", "AXCheckBox", "AXStaticText"].contains(role) {
            // print("\(indent)[\(role)] Description: \(description), Label: \(label), Title: \(title), Type: \(type), Value: \(elementValue)")
        }
        
        // recursively review child elements
        reviewClickableElements(child, indent: indent + "  ")
    }
}

func clickExportChat() {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { 
        $0.bundleIdentifier == "net.whatsapp.WhatsApp"
    }) else {
        print("WhatsApp is not running")
        return
    }

    let appRef = AXUIElementCreateApplication(app.processIdentifier)

    // Get the main window
    var value: AnyObject?
    AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &value)
    guard let mainWindow = value as! AXUIElement? else {
        print("Could not get main window")
        return
    }

    // print("Searching for 'Export chat' button...")

    let timeout: TimeInterval = 10
    let startTime = Date()

    while Date().timeIntervalSince(startTime) < timeout {
        if let exportChatButton = findElementByRoleAndAttributes(in: mainWindow, role: kAXButtonRole as String, searchText: "Export chat") {
            // print("Found 'Export chat' button, attempting to click...")
            let result = AXUIElementPerformAction(exportChatButton, kAXPressAction as CFString)
            if result == .success {
                print("Successfully clicked 'Export chat' button")
            } else {
                // print("Failed to click 'Export chat' button")
            }
            return
        } else {
            usleep(200_000) // Sleep for 200 milliseconds
        }
    }

    print("Could not find 'Export chat' button within timeout")
}


// Helper function to get a child element by index and optional role
func findElementByRoleAndAttributes(in element: AXUIElement, role: String, searchText: String, depth: Int = 0) -> AXUIElement? {
    var value: AnyObject?

    // get role of the current element
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let elementRole = value as? String ?? ""

    let indent = String(repeating: "  ", count: depth)
    // print("\(indent)checking element: role = \(elementRole)")

    // check if current element matches the role
    if elementRole == role {
        // get all attribute names for this element
        var attributeNames: CFArray?
        AXUIElementCopyAttributeNames(element, &attributeNames)
        
        if let attributeArray = attributeNames as? [String] {
            // print("\(indent)attributes found: \(attributeArray.joined(separator: ", "))")
            
            for attribute in attributeArray {
                AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
                if let attributeValue = value as? String {
                    // print("\(indent)  \(attribute) = \(attributeValue)")
                    if attributeValue.contains(searchText) {
                        // print("\(indent)found matching element with \(attribute) = \(attributeValue)")
                        return element
                    }
                }
            }
        } else {
            print("\(indent)no attributes found")
        }
    }

    // get children and search recursively
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            if let foundElement = findElementByRoleAndAttributes(in: child, role: role, searchText: searchText, depth: depth + 1) {
                return foundElement
            }
        }
    }

    return nil
}


func clickChatItem(at index: Int) -> Bool {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "net.whatsapp.WhatsApp"
    }) else {
        print("WhatsApp is not running")
        return false
    }

    let appRef = AXUIElementCreateApplication(app.processIdentifier)

    // Get the main window
    var value: AnyObject?
    AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &value)
    guard let mainWindow = value as! AXUIElement? else {
        print("Could not get main window")
        return false
    }

    // print("Searching for chat item at index \(index)...")

    // Wait for the chat list to appear
    let timeout: TimeInterval = 10
    let startTime = Date()

    while Date().timeIntervalSince(startTime) < timeout {
        var currentCount = 0
        if let chatItem = findElementByRoleAttributeValueAndIndex(
            in: mainWindow,
            role: kAXButtonRole as String,
            searchText: "Double tap to open chat",
            index: index,
            depth: 0,
            currentCount: &currentCount
        ) {
            // print("Found chat item at index \(index), attempting to click...")

            // Print more details about the found element
            var descriptionValue: AnyObject?
            AXUIElementCopyAttributeValue(chatItem, kAXDescriptionAttribute as CFString, &descriptionValue)
            let description = descriptionValue as? String ?? "No Description"
            
            var helpValue: AnyObject?
            AXUIElementCopyAttributeValue(chatItem, kAXHelpAttribute as CFString, &helpValue)
            let help = helpValue as? String ?? "No Help"
            
            print("Selected chat item: Description = '\(description)', Help = '\(help)'")

            // Ensure the element is enabled
            var isEnabledValue: AnyObject?
            if AXUIElementCopyAttributeValue(chatItem, kAXEnabledAttribute as CFString, &isEnabledValue) == .success,
               let isEnabled = isEnabledValue as? Bool {
                // print("Element isEnabled: \(isEnabled)")
            } else {
                // print("Could not determine if element is enabled")
            }

            // print("Waiting for 500 milliseconds...")
            usleep(500_000)

            // Try performing the press action
            let result = AXUIElementPerformAction(chatItem, kAXPressAction as CFString)
            if result == .success {
                // print("Successfully clicked on chat item at index \(index)")
            } else {
                print("Failed to click on the chat item")
            }
            return true
        } else {
            usleep(200_000) // Sleep for 200 milliseconds
        }
    }

    print("Could not find chat item at index \(index) within timeout. Probably reached end of chat history.")
    return false
}



// Helper function to find an element by role and attribute value
func findElementByRoleAndAttributeValue(
    in element: AXUIElement,
    role: String,
    attribute: String,
    searchText: String,
    depth: Int = 0
) -> AXUIElement? {
    var value: AnyObject?

    // Get role of the current element
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let elementRole = value as? String ?? ""

    let indent = String(repeating: "  ", count: depth)
    // print("\(indent)Checking element: Role = \(elementRole)")

    // Check if current element matches the role
    if elementRole == role {
        // Get the attribute value
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if let attributeValue = value as? String {
            // print("\(indent)  \(attribute) = \(attributeValue)")
            if attributeValue.contains(searchText) {
                // print("\(indent)Found matching element with \(attribute) = \(attributeValue)")
                return element
            }
        }
    }

    // Check AXHelp attribute for buttons
    if elementRole == "AXButton" {
        AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &value)
        if let helpValue = value as? String {
            // print("\(indent)  AXHelp = \(helpValue)")
            if helpValue.contains(searchText) {
                // print("\(indent)Found matching button with AXHelp = \(helpValue)")
                return element
            }
        }
    }

    // Get children and search recursively
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            if let foundElement = findElementByRoleAndAttributeValue(
                in: child,
                role: role,
                attribute: attribute,
                searchText: searchText,
                depth: depth + 1
            ) {
                return foundElement
            }
        }
    }

    return nil
}

func findElementByRoleAttributeValueAndIndex(
    in element: AXUIElement,
    role: String,
    searchText: String,
    index: Int,
    depth: Int = 0,
    currentCount: inout Int
) -> AXUIElement? {
    var value: AnyObject?

    // Get role of the current element
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let elementRole = value as? String ?? ""

    let indent = String(repeating: "  ", count: depth)
    // print("\(indent)Checking element: Role = \(elementRole)")

    // Check if current element matches the role
    if elementRole == role {
        // Check AXDescription attribute
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value)
        let description = value as? String ?? ""
        
        // Check AXHelp attribute
        AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &value)
        let help = value as? String ?? ""

        // print("\(indent)  Description = '\(description)', Help = '\(help)'")

        if help.contains(searchText) {
            currentCount += 1
            // print("\(indent)  Matching element found. Current count: \(currentCount)")
            if currentCount == index {
                // print("\(indent)Found matching element at index \(index)")
                return element
            }
        }
    }

    // Get children and search recursively
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            if let foundElement = findElementByRoleAttributeValueAndIndex(
                in: child,
                role: role,
                searchText: searchText,
                index: index,
                depth: depth + 1,
                currentCount: &currentCount
            ) {
                return foundElement
            }
        }
    }

    return nil
}



func printElementHierarchy(_ element: AXUIElement, depth: Int = 0) {
    var value: AnyObject?
    let indent = String(repeating: "  ", count: depth)

    // Get element attributes
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let role = value as? String ?? "Unknown"

    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
    let title = value as? String ?? "No Title"

    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value)
    let description = value as? String ?? "No Description"

    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    let elementValue = value as? String ?? "No Value"

    // print("\(indent)Role: \(role), Title: \(title), Description: \(description), Value: \(elementValue)")

    // Recursively print children
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            printElementHierarchy(child, depth: depth + 1)
        }
    }
}


// New function to click the "Without media" button
func clickWithoutMediaButton() {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "net.whatsapp.WhatsApp"
    }) else {
        print("WhatsApp is not running")
        return
    }

    let appRef = AXUIElementCreateApplication(app.processIdentifier)

    // print("Searching for 'Without media' button by identifier in application...")

    // Search recursively in the application
    if let withoutMediaButton = findElementByRoleAndIdentifier(
        in: appRef,
        role: kAXButtonRole as String,
        identifier: "action-button--998"
    ) {
        // print("Found 'Without media' button, attempting to click...")
        performClickOnElement(withoutMediaButton, app: app)
        return
    } else {
        print("Could not find 'Without media' button in application by identifier")
    }
}

func findElementByRoleAndIdentifier(
    in element: AXUIElement,
    role: String,
    identifier: String,
    depth: Int = 0
) -> AXUIElement? {
    var value: AnyObject?
    let indent = String(repeating: "  ", count: depth)

    // Get the role of the current element
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let elementRole = value as? String ?? ""

    // Get the identifier of the current element
    AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value)
    let elementIdentifier = value as? String ?? ""

    // For debugging
    // print("\(indent)Role: \(elementRole), Identifier: \(elementIdentifier)")

    if elementRole == role && elementIdentifier == identifier {
        // print("\(indent)Found matching element with role: \(role), identifier: \(identifier)")
        return element
    }

    // Recursively search children
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            if let foundElement = findElementByRoleAndIdentifier(
                in: child,
                role: role,
                identifier: identifier,
                depth: depth + 1
            ) {
                return foundElement
            }
        }
    }

    return nil
}

// Function to perform click on an element
func performClickOnElement(_ element: AXUIElement, app: NSRunningApplication) {
    // Try performing the press action
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result == .success {
        // print("Successfully clicked button")
    } else {
        print("Failed to click 'Without media' button, attempting to simulate mouse click...")

        // Get the position and size of the button
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let position = positionValue as? CGPoint,
           let size = sizeValue as? CGSize {

            // Calculate the center point
            let centerPoint = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)

            // Adjust for screen coordinate system
            if let screenHeight = NSScreen.main?.frame.height {
                let adjustedPoint = CGPoint(x: centerPoint.x, y: screenHeight - centerPoint.y)

                // Bring the app to the front
                app.activate(options: .activateIgnoringOtherApps)

                // Simulate mouse click
                clickAtPoint(point: adjustedPoint)
                // print("Simulated mouse click at \(adjustedPoint)")
            } else {
                print("Could not get screen height")
            }
        } else {
            print("Could not get button position and size")
        }
    }
}

// Function to simulate mouse click at a point
func clickAtPoint(point: CGPoint) {
    let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    mouseDown?.post(tap: .cghidEventTap)
    mouseUp?.post(tap: .cghidEventTap)
}

func findElementByRoleAndTitleContains(
    in element: AXUIElement,
    role: String,
    titleContains: String,
    depth: Int = 0
) -> AXUIElement? {
    var value: AnyObject?
    let indent = String(repeating: "  ", count: depth)

    // Get role and title of the current element
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let elementRole = value as? String ?? ""

    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
    let elementTitleRaw = value as? String ?? ""

    // Normalize the title
    let elementTitle = elementTitleRaw
        .replacingOccurrences(of: "\u{200E}", with: "")
        .removingControlCharacters()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let searchTitle = titleContains
        .removingControlCharacters()
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // For debugging
    // print("\(indent)Role: \(elementRole), Title: '\(elementTitle)'")

    if elementRole == role && elementTitle.localizedCaseInsensitiveContains(searchTitle) {
        // print("\(indent)Found matching element with role: \(role), title contains: '\(elementTitle)'")
        return element
    }

    // Recursively search children
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            if let foundElement = findElementByRoleAndTitleContains(
                in: child,
                role: role,
                titleContains: titleContains,
                depth: depth + 1
            ) {
                return foundElement
            }
        }
    }

    return nil
}


func waitForExportCompletionAlertAndClickOK(timeout: TimeInterval) -> Bool {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "net.whatsapp.WhatsApp"
    }) else {
        print("WhatsApp is not running")
        return false
    }

    let appRef = AXUIElementCreateApplication(app.processIdentifier)

    // print("Waiting for export completion alert...")

    let startTime = Date()

    while Date().timeIntervalSince(startTime) < timeout {
        let alertSheets = findAllAlertSheets(in: appRef)
        if alertSheets.isEmpty {
            // print("No alert sheets found")
        } else {
            for alertSheet in alertSheets {
                if let okButton = findElementByRoleAndTitleContains(
                    in: alertSheet,
                    role: kAXButtonRole as String,
                    titleContains: "OK"
                ) {
                    print("Found 'OK' button in alert, attempting to click...")
                    performClickOnElement(okButton, app: app)
                    return true
                }
            }
        }
        usleep(100_000) // Sleep for 100ms before next check
    }

    print("Did not find export completion alert within timeout")
    return false
}

func listButtonsInAlert(_ alertSheet: AXUIElement) {
    // print("Listing buttons in alert sheet:")
    var value: AnyObject?
    AXUIElementCopyAttributeValue(alertSheet, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
            let role = value as? String ?? ""
            if role == kAXButtonRole as String {
                AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &value)
                let title = value as? String ?? ""
                // print("  Button with title: '\(title)'")
            }
        }
    }
}

func findAllAlertSheets(in element: AXUIElement) -> [AXUIElement] {
    var alertSheets: [AXUIElement] = []
    var value: AnyObject?

    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &value)
            let role = value as? String ?? ""
            if role == kAXSheetRole as String {
                // Check subrole to ensure it's an alert
                AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &value)
                let subrole = value as? String ?? ""
                if subrole == kAXModalAlertSubrole as String {
                    alertSheets.append(child)
                }
            }
            // Recursively search in children
            alertSheets.append(contentsOf: findAllAlertSheets(in: child))
        }
    }
    return alertSheets
}

func findElementByRoleAndSubrole(
    in element: AXUIElement,
    role: String,
    subrole: String,
    depth: Int = 0
) -> AXUIElement? {
    var value: AnyObject?
    let indent = String(repeating: "  ", count: depth)

    // Get role and subrole of the current element
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    let elementRole = value as? String ?? ""

    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
    let elementSubrole = value as? String ?? ""

    // For debugging
    // print("\(indent)Role: \(elementRole), Subrole: \(elementSubrole)")

    if elementRole == role && elementSubrole == subrole {
        // print("\(indent)Found matching element with role: \(role), subrole: \(subrole)")
        return element
    }

    // Recursively search children
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    if let children = value as? [AXUIElement] {
        for child in children {
            if let foundElement = findElementByRoleAndSubrole(
                in: child,
                role: role,
                subrole: subrole,
                depth: depth + 1
            ) {
                return foundElement
            }
        }
    }

    return nil
}

func getAllChildren(of element: AXUIElement) -> [AXUIElement] {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    return value as? [AXUIElement] ?? []
}

func exportChats(startIndex: Int, count: Int) {
    print("Starting export process for \(count) chats, beginning at index \(startIndex)...")

    for i in startIndex...(startIndex + count - 1) {
        print("\n--- Processing chat \(i - startIndex + 1) of \(count) (index: \(i)) ---")        
        if !clickChatItem(at: i) {
            print("Exiting export process.")
            break
        }
        usleep(500_000)
        clickWithoutMediaButton()
        usleep(200_000)
        // Wait for the export completion alert and click OK
        if waitForExportCompletionAlertAndClickOK(timeout: 60) { // 60 second timeout
            print("Successfully exported chat \(i)")
        } else {
            print("Failed to export chat \(i) or timed out waiting for completion")
        }
    }
    print("Finished processing \(count) chats")
}

// Main execution
clickSettingsMenuItem()
usleep(500_000) // Wait for 500ms after clicking Settings
clickChatsItem()
usleep(500_000) // Wait for 500ms after clicking Chats
clickExportChat()
usleep(200_000)
exportChats(startIndex: 16, count: 17)