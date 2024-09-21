import Foundation
import OpenAIClient
import Cocoa
import ApplicationServices

// Add this function at the top of the file
func checkOpenAIAPIKey() {
    let client = OpenAIClient()
    // The initialization of OpenAIClient will trigger the API key check
    print("openai api key check completed")
}

class ElementMonitor: NSObject {
    private var lastElement: AXUIElement?
    private var timer: Timer?
    private var overlayWindow: NSWindow?
    private var overlayTextField: NSTextField?
    private lazy var openAIClient: OpenAIClient = {
        return OpenAIClient()
    }()
    private var loadingSpinner: NSProgressIndicator?

    override init() {
        super.init()
        setupOverlayWindow()
    }

    private func setupOverlayWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        window.level = .floating
        window.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let textField = NSTextField(frame: NSRect(x: 10, y: 10, width: 580, height: 380))
        textField.isEditable = false
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = .clear
        textField.textColor = .white
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.cell?.wraps = true
        textField.cell?.truncatesLastVisibleLine = true
        textField.maximumNumberOfLines = 0 // Allow multiple lines
        textField.lineBreakMode = .byWordWrapping

        let spinner = NSProgressIndicator(frame: NSRect(x: 290, y: 190, width: 20, height: 20))
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        window.contentView?.addSubview(spinner)

        window.contentView?.addSubview(textField)

        self.overlayWindow = window
        self.overlayTextField = textField
        self.loadingSpinner = spinner

        print("Overlay window and text field set up")
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkElementUnderMouse()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        overlayWindow?.orderOut(nil)
    }

    private func checkElementUnderMouse() {
        guard let element = getElementUnderMouse() else {
            print("no element under mouse")
            overlayWindow?.orderOut(nil)
            return
        }
        if element != lastElement {
            lastElement = element
            if let (conversationName, unreadCount) = getChatInfo(element) {
                print("chat info found: \(conversationName), \(unreadCount) unread messages")
                printElementInfo(element)
                let filteredConversation = filterConversation(conversationName, lastMessages: unreadCount)
                // print("filtered conversation: \(filteredConversation)")
                updateOverlay(with: "unread messages: \(unreadCount)\n\n\(filteredConversation)")
                
                // Request summary
                summarizeConversation(conversationName: conversationName, unreadCount: unreadCount, filteredConversation: filteredConversation)
            } else {
                print("no chat info found for element")
                overlayWindow?.orderOut(nil)
            }
        }
    }

    private func summarizeConversation(conversationName: String, unreadCount: Int, filteredConversation: String) {
        let prompt = "you are helping user get up to speed on unread message, provide a very brief (1-2 sentences) summary of unread messages, start response with important points discussed in these \(unreadCount) "
        
        DispatchQueue.main.async {
            self.loadingSpinner?.startAnimation(nil)
            self.updateOverlay(with: "unread messages: \(unreadCount)\n\nsummary: Loading...\n\n\(filteredConversation)")
        }
        
        openAIClient.sendCompletion(prompt: prompt, chatHistory: filteredConversation) { [weak self] result in
            DispatchQueue.main.async {
                self?.loadingSpinner?.stopAnimation(nil)
                switch result {
                case .success(let summary):
                    self?.updateOverlay(with: "unread messages: \(unreadCount)\n\nsummary: \(summary)\n\n\(filteredConversation)")
                case .failure(let error):
                    print("error summarizing conversation: \(error.localizedDescription)")
                    self?.updateOverlay(with: "unread messages: \(unreadCount)\n\nsummary: Error loading summary\n\n\(filteredConversation)")
                }
            }
        }
    }

    private func getChatInfo(_ element: AXUIElement) -> (String, Int)? {
        var description: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        print("get description result: \(result)")
        
        guard result == .success,
              let descriptionString = description as? String else {
            print("failed to get description or cast to string")
            return nil
        }
        
        print("description: \(descriptionString)")
        
        guard descriptionString.contains("unread messages") else {
            print("description doesn't contain 'unread messages'")
            return nil
        }
        
        // Use regular expression to extract conversation name and unread count
        let pattern = "(.*), ‎(\\d+) unread messages"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: descriptionString, options: [], range: NSRange(descriptionString.startIndex..., in: descriptionString)) else {
            print("failed to match regex pattern")
            return nil
        }
        
        let conversationName = String(descriptionString[Range(match.range(at: 1), in: descriptionString)!])
        guard let unreadCount = Int(descriptionString[Range(match.range(at: 2), in: descriptionString)!]) else {
            print("failed to parse unread count")
            return nil
        }
        
        print("parsed chat info: \(conversationName), \(unreadCount)")
        return (conversationName, unreadCount)
    }

    private func getElementUnderMouse() -> AXUIElement? {
        let mouseLocation = NSEvent.mouseLocation
        let systemWideElement = AXUIElementCreateSystemWide()
        
        // Get the main display's bounds
        guard let mainDisplay = CGMainDisplayID() as CGDirectDisplayID? else {
            print("error: couldn't get main display")
            return nil
        }
        let displayBounds = CGDisplayBounds(mainDisplay)
        
        // Adjust coordinates
        let adjustedX = Float(mouseLocation.x)
        let adjustedY = Float(displayBounds.height - mouseLocation.y)
        
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, adjustedX, adjustedY, &element)
        
        guard result == .success else {
            print("error: failed to get element at position")
            return nil
        }
        
        return element
    }

    private func updateOverlay(with text: String) {
        let lines = text.components(separatedBy: "\n")
        let unreadCount = lines.first { $0.starts(with: "unread messages:") } ?? ""
        let summary = lines.drop(while: { !$0.starts(with: "summary:") }).prefix(1).first ?? ""
        let messages = lines.drop(while: { !$0.contains(":") }).joined(separator: "\n")

        let formattedText = """
        \(unreadCount)

        \(summary)

        Last messages:
        \(messages)
        """
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let sanitizedText = formattedText.replacingOccurrences(of: "[\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}]", with: "", options: .regularExpression)
            self.overlayTextField?.stringValue = sanitizedText
            
            let mouseLocation = NSEvent.mouseLocation
            
            guard let mainDisplay = CGMainDisplayID() as CGDirectDisplayID? else {
                print("Error: couldn't get main display")
                return
            }
            let displayBounds = CGDisplayBounds(mainDisplay)
            
            let windowWidth: CGFloat = 600
            let windowHeight: CGFloat = 400
            let padding: CGFloat = 20
            
            var xPosition = mouseLocation.x + padding
            var yPosition = mouseLocation.y - windowHeight - padding
            
            if xPosition + windowWidth > displayBounds.width {
                xPosition = displayBounds.width - windowWidth - padding
            }
            
            if yPosition < 0 {
                yPosition = padding
            }
            
            self.overlayWindow?.setFrame(NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight), display: true)
            self.overlayTextField?.frame = NSRect(x: 10, y: 10, width: windowWidth - 20, height: windowHeight - 20)
            self.overlayWindow?.orderFront(nil)
        }
    }

    private func printElementInfo(_ element: AXUIElement) {
        if let (appName, windowName) = getAppAndWindowInfo(element) {
            print("_____________________________________________________________________")
            print("application: \(appName)")
            print("window: \(windowName)")
        }
        printAllAttributes(element)
    }

    private func getAppAndWindowInfo(_ element: AXUIElement) -> (String, String)? {
        var application: AXUIElement? = element
        while application != nil {
            var parent: AnyObject?
            AXUIElementCopyAttributeValue(application!, kAXParentAttribute as CFString, &parent)
            if parent == nil { break }
            application = (parent as! AXUIElement)
        }
        
        guard let app = application else { return nil }
        
        var processID: pid_t = 0
        AXUIElementGetPid(app, &processID)
        
        let appName = NSRunningApplication(processIdentifier: processID)?.localizedName ?? "unknown"
        
        var windowName: String = "unknown"
        var window: AXUIElement? = element
        while window != nil && windowName == "unknown" {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(window!, kAXRoleAttribute as CFString, &value) == .success,
               let role = value as? String, role == "AXWindow" {
                AXUIElementCopyAttributeValue(window!, kAXTitleAttribute as CFString, &value)
                windowName = value as? String ?? "unknown"
                break
            }
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(window!, kAXParentAttribute as CFString, &parentValue)
            window = parentValue as! AXUIElement?
        }
        
        return (appName, windowName)
    }

    private func printAllAttributes(_ element: AXUIElement) {
        var attributeNames: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributeNames) == .success,
              let attributes = attributeNames as? [String] else {
            print("error: failed to get attribute names")
            return
        }

        for attribute in attributes {
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
                continue
            }

            print("\(attribute): \(describeValue(value))")
        }
    }

    private func describeValue(_ value: AnyObject?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [AnyObject]:
            return "[\(array.map { describeValue($0) }.joined(separator: ", "))]"
        case is AXUIElement:
            return "AXUIElement"
        default:
            return String(describing: value)
        }
    }
}

func filterConversation(_ conversationName: String, lastMessages: Int? = nil) -> String {
    let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
    
    do {
        let content = try String(contentsOf: archiveFile)
        let lines = content.components(separatedBy: .newlines)
        
        print("total lines in file: \(lines.count)")
        
        var filteredMessages = lines.filter { line in
            line.contains(conversationName)
        }
        
        print("filtered messages count: \(filteredMessages.count)")
        
        if let lastN = lastMessages {
            filteredMessages = Array(filteredMessages.suffix(lastN))
        }
        
        let pattern = "^\\[.*?\\] \\[.*?\\] (.+)$"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        
        let result = filteredMessages.compactMap { line -> String? in
            if let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                let messageRange = match.range(at: 1)
                if let messageRange = Range(messageRange, in: line) {
                    let messageContent = String(line[messageRange])
                    print("processed message: \(messageContent)")
                    return messageContent
                }
            }
            print("unprocessed line: \(line)")
            return nil
        }.joined(separator: "\n")
        
        print("final result length: \(result.count)")
        return result
    } catch {
        print("error reading archive file: \(error.localizedDescription)")
        return "error: \(error.localizedDescription)"
    }
}

// Example usage of filterConversation
let conversationName = "Evan Teal"
let lastMessagesCount = 10
let filteredConversation = filterConversation(conversationName, lastMessages: lastMessagesCount)

// UI object identification
print("checking openai api key...")
checkOpenAIAPIKey()

let monitor = ElementMonitor()
monitor.startMonitoring()

print("monitoring started")

// Keep the program running
RunLoop.main.run()