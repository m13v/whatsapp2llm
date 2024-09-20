import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var scrollView: NSScrollView!
    var progressBar: NSProgressIndicator!
    var statsLabel: NSTextField!
    var statusLabel: NSTextField!
    var conversationsDropdown: NSPopUpButton!
    var contactsDropdown: NSPopUpButton!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let frame = NSRect(x: 100, y: 100, width: 1200, height: 800) // 4 times larger
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "whatsapp autoresponder"
        window.makeKeyAndOrderFront(nil)

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1.0).cgColor

        // Stats column (adjusted position)
        let statsColumn = NSView(frame: NSRect(x: 20, y: window.contentView!.frame.height - 120, width: 280, height: 100))
        
        let statsHeading = createLabel(frame: NSRect(x: 0, y: 80, width: 280, height: 20))
        statsHeading.stringValue = "stats:"
        statsHeading.font = NSFont.boldSystemFont(ofSize: 16)
        statsHeading.textColor = .white
        
        statsLabel = createLabel(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        statsLabel.font = NSFont.systemFont(ofSize: 14)
        statsLabel.textColor = .white
        
        statsColumn.addSubview(statsHeading)
        statsColumn.addSubview(statsLabel)

        // Status log column (adjusted position)
        let statusColumn = NSView(frame: NSRect(x: 320, y: window.contentView!.frame.height - 120, width: 280, height: 100))
        
        let statusHeading = createLabel(frame: NSRect(x: 0, y: 80, width: 280, height: 20))
        statusHeading.stringValue = "status log:"
        statusHeading.font = NSFont.boldSystemFont(ofSize: 16)
        statusHeading.textColor = .white
        
        statusLabel = createLabel(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor(calibratedWhite: 0.7, alpha: 1.0)
        
        statusColumn.addSubview(statusHeading)
        statusColumn.addSubview(statusLabel)

        // Conversations dropdown (adjusted position and width)
        conversationsDropdown = NSPopUpButton(frame: NSRect(x: 20, y: window.contentView!.frame.height - 160, width: 240, height: 30))
        conversationsDropdown.addItem(withTitle: "select a conversation")
        conversationsDropdown.wantsLayer = true
        conversationsDropdown.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1.0).cgColor
        conversationsDropdown.layer?.cornerRadius = 5

        // Set text color for the dropdown
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14)
        ]
        conversationsDropdown.attributedTitle = NSAttributedString(string: "select a conversation", attributes: attributes)

        // Contacts dropdown (new)
        contactsDropdown = NSPopUpButton(frame: NSRect(x: 280, y: window.contentView!.frame.height - 160, width: 240, height: 30))
        contactsDropdown.addItem(withTitle: "select a contact")
        contactsDropdown.wantsLayer = true
        contactsDropdown.layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1.0).cgColor
        contactsDropdown.layer?.cornerRadius = 5

        // Set text color for the contacts dropdown
        let contactAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14)
        ]
        contactsDropdown.attributedTitle = NSAttributedString(string: "select a contact", attributes: contactAttributes)

        // Load button (adjusted position)
        let loadButton = NSButton(frame: NSRect(x: 20, y: window.contentView!.frame.height - 200, width: 150, height: 30))
        loadButton.title = "load chat history"
        loadButton.bezelStyle = .rounded
        loadButton.target = self
        loadButton.action = #selector(loadChatHistory)
        loadButton.wantsLayer = true
        loadButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        loadButton.layer?.cornerRadius = 5

        // Progress bar (adjusted position)
        progressBar = NSProgressIndicator(frame: NSRect(x: 180, y: window.contentView!.frame.height - 195, width: 400, height: 20))
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        progressBar.isHidden = true

        // Text view (adjusted size)
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 1160, height: window.contentView!.frame.height - 240))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.autoresizingMask = [.width, .height]
        textView.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
        textView.textColor = .white

        scrollView.documentView = textView

        contentView.addSubview(statsColumn)
        contentView.addSubview(statusColumn)
        contentView.addSubview(conversationsDropdown)
        contentView.addSubview(contactsDropdown)
        contentView.addSubview(loadButton)
        contentView.addSubview(progressBar)
        contentView.addSubview(scrollView)

        window.contentView = contentView

        // Set up autoresizing masks
        statsColumn.autoresizingMask = [.minYMargin] // Stick to left side when resizing
        statusColumn.autoresizingMask = [.minXMargin, .minYMargin]
        conversationsDropdown.autoresizingMask = [.minYMargin] // Stick to left side when resizing
        contactsDropdown.autoresizingMask = [.minYMargin]
        loadButton.autoresizingMask = [.minYMargin] // Stick to left side when resizing
        progressBar.autoresizingMask = [.width, .minYMargin]
        scrollView.autoresizingMask = [.width, .height]

        window.setContentSize(NSSize(width: 1200, height: 800)) // 4 times larger
        window.minSize = NSSize(width: 800, height: 600) // Adjusted minimum size

        checkArchiveFile()
    }

    func createLabel(frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.cell?.wraps = false
        label.cell?.isScrollable = true
        return label
    }

    func checkArchiveFile() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
        
        if FileManager.default.fileExists(atPath: archiveFile.path) {
            do {
                let content = try String(contentsOf: archiveFile)
                let lines = content.components(separatedBy: .newlines)
                
                // Update stats label
                if let statsIndex = lines.firstIndex(of: "stats:"),
                   statsIndex + 3 < lines.count {
                    let statsText = lines[(statsIndex + 1)...(statsIndex + 3)]
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .joined(separator: "\n")
                    DispatchQueue.main.async {
                        self.statsLabel.stringValue = statsText
                    }
                }
                
                // Update status label
                if let statusIndex = lines.firstIndex(of: "status_log:"),
                   statusIndex + 4 < lines.count {
                    let statusText = lines[(statusIndex + 1)...(statusIndex + 4)]
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .joined(separator: "\n")
                    DispatchQueue.main.async {
                        self.statusLabel.stringValue = statusText
                    }
                }
                
                // Update conversations dropdown
                if let conversationsIndex = lines.firstIndex(of: "conversations:"),
                   conversationsIndex + 1 < lines.count {
                    let conversationsLines = lines[(conversationsIndex + 1)...]
                        .prefix(while: { !$0.isEmpty && $0.hasPrefix("  ") })
                    
                    DispatchQueue.main.async {
                        self.conversationsDropdown.removeAllItems()
                        self.conversationsDropdown.addItem(withTitle: "Select a conversation")
                        for line in conversationsLines {
                            let conversation = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")[0]
                            self.conversationsDropdown.addItem(withTitle: conversation)
                        }
                    }
                }
                
                // Update contacts dropdown
                if let contactsIndex = lines.firstIndex(of: "contacts:"),
                   contactsIndex + 1 < lines.count {
                    let contactsLines = lines[(contactsIndex + 1)...]
                        .prefix(while: { !$0.isEmpty && $0.hasPrefix("  ") })
                    
                    DispatchQueue.main.async {
                        self.contactsDropdown.removeAllItems()
                        self.contactsDropdown.addItem(withTitle: "Select a contact")
                        for line in contactsLines {
                            let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: ": ")
                            if components.count >= 3 {
                                let contact = components[0]
                                let messageCount = components[2]
                                self.contactsDropdown.addItem(withTitle: "\(contact) (\(messageCount))")
                            }
                        }
                    }
                }
            } catch {
                print("error reading archive file: \(error.localizedDescription)")
            }
        }
    }

    @objc func loadChatHistory() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            var existingContent = ""
            var lastProcessedZip = ""
            var conversations: [String: String] = [:] // chatName: lastTimestamp
            var contacts: [String: (lastTimestamp: String, messageCount: Int)] = [:]
            var existingMessages = Set<String>()

            let archiveExists = FileManager.default.fileExists(atPath: archiveFile.path)
            if !archiveExists {
                FileManager.default.createFile(atPath: archiveFile.path, contents: nil, attributes: nil)
            } else {
                existingContent = try String(contentsOf: archiveFile)
                let lines = existingContent.components(separatedBy: .newlines)
                if lines.count > 1 && lines[1].starts(with: "conversations:") {
                    let conversationsLine = lines[1].replacingOccurrences(of: "conversations: ", with: "")
                    conversations = Dictionary(uniqueKeysWithValues: 
                        conversationsLine.components(separatedBy: ", ")
                            .map { $0.components(separatedBy: ": ") }
                            .map { ($0[0], $0[1]) }
                    )
                }
                if lines.count > 2 && lines[2].starts(with: "contacts:") {
                    let contactsLine = lines[2].replacingOccurrences(of: "contacts: ", with: "")
                    contacts = Dictionary(uniqueKeysWithValues: 
                        contactsLine.components(separatedBy: ", ")
                            .map { $0.components(separatedBy: ": ") }
                            .map { ($0[0], ($0[1], Int($0[2])!)) }
                    )
                }
                if let firstLogLine = existingContent.components(separatedBy: .newlines).first,
                   firstLogLine.starts(with: "status_log:") {
                    let logParts = firstLogLine.components(separatedBy:",")
                    if logParts.count >= 4 {
                        lastProcessedZip = logParts[3].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            existingMessages = archiveExists ? Set(existingContent.components(separatedBy: .newlines)) : Set<String>()
            
            // Find all WhatsApp chat zip files
            let zipFiles = try FileManager.default.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.starts(with: "WhatsApp Chat -") && $0.pathExtension == "zip" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent } // sort in descending order
            
            var newMessages = [String]()
            var processedZipCount = 0
            
            DispatchQueue.main.async {
                self.progressBar.isHidden = false
                self.progressBar.doubleValue = 0
            }
            
            for (index, zipFile) in zipFiles.enumerated() {
                if archiveExists && !lastProcessedZip.isEmpty && zipFile.lastPathComponent <= lastProcessedZip {
                    break // stop processing if we've reached the last processed zip
                }
                
                processedZipCount += 1
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-j", zipFile.path, "*_chat*.txt", "-d", tempDir.path]
                try process.run()
                process.waitUntilExit()
                
                let chatName = zipFile.lastPathComponent
                    .replacingOccurrences(of: "WhatsApp Chat - ", with: "")
                    .replacingOccurrences(of: ".zip", with: "")
                    .replacingOccurrences(of: #" \(\d+\)"#, with: "", options: .regularExpression)
                
                let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.pathExtension == "txt" {
                        let content = try String(contentsOf: fileURL)
                        let messages = content.components(separatedBy: .newlines)
                        for message in messages {
                            if !message.isEmpty {
                                let formattedMessage = "[\(chatName)] \(message)"
                                if !existingMessages.contains(formattedMessage) {
                                    newMessages.append(formattedMessage)
                                    
                                    // Update last timestamp for the conversation
                                    if let timestamp = message.components(separatedBy: "] ").first?
                                        .trimmingCharacters(in: CharacterSet(charactersIn: "[]")) {
                                        conversations[chatName] = timestamp
                                        
                                        // Update contact information
                                        if let contactPart = message.components(separatedBy: "] ").last {
                                            let contactComponents = contactPart.components(separatedBy: ": ")
                                            if contactComponents.count > 1 {
                                                let contactName = contactComponents[0].trimmingCharacters(in: .whitespaces)
                                                // Check if it's not a system message
                                                if !contactName.contains("‎") && !contactName.contains("‪") {
                                                    let currentCount = contacts[contactName]?.messageCount ?? 0
                                                    contacts[contactName] = (timestamp, currentCount + 1)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }
                
                // Get the "date added" attribute of the zip file
                let attributes = try FileManager.default.attributesOfItem(atPath: zipFile.path)
                let creationDate = attributes[.creationDate] as? Date ?? Date()
                let zipTimestamp = ISO8601DateFormatter().string(from: creationDate)

                // Update the status log to include the zipTimestamp
                let statusLog = "status_log: timestamp: \(ISO8601DateFormatter().string(from: Date())), new messages: \(newMessages.count), processed zips: \(processedZipCount), last zip: \(zipFile.lastPathComponent), last zip timestamp: \(zipTimestamp)\n"
                try statusLog.write(to: archiveFile, atomically: false, encoding: .utf8)

                DispatchQueue.main.async {
                    let progress = Double(index + 1) / Double(zipFiles.count) * 100
                    self.progressBar.doubleValue = progress
                }
            }
            
            // Move statusLog definition here, after the loop
            let statusLog = "status_log:\n  timestamp: \(ISO8601DateFormatter().string(from: Date()))\n  new messages: \(newMessages.count)\n  processed zips: \(processedZipCount)\n  last zip: \(zipFiles.first?.lastPathComponent ?? "N/A")\n"

            if !newMessages.isEmpty || processedZipCount > 0 || !archiveExists {
                var totalMessages = 0
                var totalConversations = 0
                var totalContacts = 0

                totalMessages = existingMessages.count + newMessages.count
                totalConversations = conversations.count
                totalContacts = contacts.count

                let statsLog = "stats:\n  total messages: \(totalMessages)\n  total conversations: \(totalConversations)\n  total contacts: \(totalContacts)\n"
                let conversationsLog = "conversations:\n" + conversations.map { "  \($0.key): \($0.value)" }.joined(separator: "\n") + "\n"

                // Sort contacts
                let sortedContacts = contacts.sorted { (contact1, contact2) -> Bool in
                    let name1 = contact1.key
                    let name2 = contact2.key
                    let count1 = contact1.value.messageCount
                    let count2 = contact2.value.messageCount

                    if name1.hasPrefix("~") && !name2.hasPrefix("~") {
                        return false
                    } else if !name1.hasPrefix("~") && name2.hasPrefix("~") {
                        return true
                    } else {
                        return count1 > count2
                    }
                }

                let contactsLog = "contacts:\n" + sortedContacts.map { "  \($0.key): \($0.value.lastTimestamp): \($0.value.messageCount)" }.joined(separator: "\n") + "\n"
                let updatedContent = statsLog + statusLog + conversationsLog + contactsLog + existingContent + (existingContent.isEmpty ? "" : "\n") + newMessages.joined(separator: "\n")
                try updatedContent.write(to: archiveFile, atomically: true, encoding: String.Encoding.utf8)
                
                DispatchQueue.main.async {
                    // Only display new messages in the text view
                    self.textView.string = newMessages.joined(separator: "\n")
                }
            } else {
                DispatchQueue.main.async {
                    self.textView.string = "no new messages found in zip files"
                }
            }
            
            try FileManager.default.removeItem(at: tempDir)

            DispatchQueue.main.async {
                self.progressBar.isHidden = true
                self.checkArchiveFile() // Update the stats and status labels
            }
        } catch {
            print("error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.textView.string = "error: \(error.localizedDescription)"
                self.progressBar.isHidden = true
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

NSApp.activate(ignoringOtherApps: true)
NSApp.setActivationPolicy(.regular)

app.run()