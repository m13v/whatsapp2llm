import Cocoa
import Foundation
import Security

// Simple OpenAI API Client
class OpenAIClient {
    let apiKey: String
    let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func sendCompletion(prompt: String, model: String = "gpt-4o", maxTokens: Int = 4000, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else {
                    throw NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var scrollView: NSScrollView!
    var progressBar: NSProgressIndicator!
    var statsLabel: NSTextField!
    var statusLabel: NSTextField!
    var conversationsDropdown: NSPopUpButton!
    var contactsDropdown: NSPopUpButton!
    var addToAIChatButton: NSButton!
    var openAI: OpenAIClient?
    var loadingSpinner: NSProgressIndicator!

    let keychainService = "com.yourcompany.whatsapp-autoresponder"
    let keychainAccount = "OPENAI_API_KEY"

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

        // Load button (adjusted position)
        let loadButton = NSButton(frame: NSRect(x: 20, y: window.contentView!.frame.height - 160, width: 150, height: 30))
        loadButton.title = "load chat history"
        loadButton.bezelStyle = .rounded
        loadButton.target = self
        loadButton.action = #selector(loadChatHistory)
        loadButton.wantsLayer = true
        loadButton.layer?.backgroundColor = NSColor.systemBlue.cgColor
        loadButton.layer?.cornerRadius = 5

        // Conversations dropdown (adjusted position and width)
        conversationsDropdown = NSPopUpButton(frame: NSRect(x: 20, y: window.contentView!.frame.height - 200, width: 240, height: 30))
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

        // Add target for conversationsDropdown
        conversationsDropdown.target = self
        conversationsDropdown.action = #selector(conversationSelected)

        // Contacts dropdown (adjusted position)
        contactsDropdown = NSPopUpButton(frame: NSRect(x: 280, y: window.contentView!.frame.height - 200, width: 240, height: 30))
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

        // Add target for contactsDropdown
        contactsDropdown.target = self
        contactsDropdown.action = #selector(contactSelected)

        // Add to AI chat button
        addToAIChatButton = NSButton(frame: NSRect(x: 540, y: window.contentView!.frame.height - 200, width: 120, height: 30))
        addToAIChatButton.title = "add to AI chat"
        addToAIChatButton.bezelStyle = .rounded
        addToAIChatButton.target = self
        addToAIChatButton.action = #selector(addToAIChat)
        addToAIChatButton.wantsLayer = true
        addToAIChatButton.layer?.backgroundColor = NSColor.systemGreen.cgColor
        addToAIChatButton.layer?.cornerRadius = 5

        // Progress bar (adjusted position)
        progressBar = NSProgressIndicator(frame: NSRect(x: 180, y: window.contentView!.frame.height - 155, width: 400, height: 20))
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

        // Add loading spinner
        loadingSpinner = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 32, height: 32))
        loadingSpinner.style = .spinning
        loadingSpinner.isDisplayedWhenStopped = false

        contentView.addSubview(statsColumn)
        contentView.addSubview(statusColumn)
        contentView.addSubview(loadButton)
        contentView.addSubview(conversationsDropdown)
        contentView.addSubview(contactsDropdown)
        contentView.addSubview(addToAIChatButton)  // Add the new button
        contentView.addSubview(progressBar)
        contentView.addSubview(scrollView)
        contentView.addSubview(loadingSpinner)

        window.contentView = contentView

        // Set up autoresizing masks
        statsColumn.autoresizingMask = [.minYMargin] // Stick to left side when resizing
        statusColumn.autoresizingMask = [.minXMargin, .minYMargin]
        loadButton.autoresizingMask = [.minYMargin] // Stick to left side when resizing
        conversationsDropdown.autoresizingMask = [.minYMargin] // Stick to left side when resizing
        contactsDropdown.autoresizingMask = [.minYMargin]
        addToAIChatButton.autoresizingMask = [.minYMargin]
        progressBar.autoresizingMask = [.width, .minYMargin]
        scrollView.autoresizingMask = [.width, .height]
        loadingSpinner.autoresizingMask = [.minXMargin, .minYMargin]

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
                
                // Display message history
                let messageHistory = lines.drop(while: { !$0.starts(with: "[") })
                DispatchQueue.main.async {
                    self.textView.string = messageHistory.joined(separator: "\n")
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
            
            if !newMessages.isEmpty || processedZipCount > 0 || !archiveExists {
                var totalMessages = existingMessages.count + newMessages.count
                var totalConversations = conversations.count
                var totalContacts = contacts.count

                let statsLog = "stats:\n  total messages: \(totalMessages)\n  total conversations: \(totalConversations)\n  total contacts: \(totalContacts)\n"
                let statusLog = "status_log:\n  timestamp: \(ISO8601DateFormatter().string(from: Date()))\n  new messages: \(newMessages.count)\n  processed zips: \(processedZipCount)\n  last zip: \(zipFiles.first?.lastPathComponent ?? "N/A")\n"
                
                let conversationsLog = conversations.isEmpty ? "" : "conversations:\n" + conversations.map { "  \($0.key): \($0.value)" }.joined(separator: "\n") + "\n"

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

                let contactsLog = contacts.isEmpty ? "" : "contacts:\n" + sortedContacts.map { "  \($0.key): \($0.value.lastTimestamp): \($0.value.messageCount)" }.joined(separator: "\n") + "\n"
                
                // Remove old stats, status_log, conversations, and contacts from existing content
                let contentLines = existingContent.components(separatedBy: .newlines)
                let updatedExistingContent = contentLines.drop(while: { line in
                    line.starts(with: "stats:") || 
                    line.starts(with: "status_log:") || 
                    line.starts(with: "conversations:") || 
                    line.starts(with: "contacts:") ||
                    line.trimmingCharacters(in: .whitespaces).isEmpty
                }).joined(separator: "\n")
                
                let updatedContent = statsLog + statusLog + conversationsLog + contactsLog + newMessages.joined(separator: "\n") + (newMessages.isEmpty ? "" : "\n") + updatedExistingContent
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

    @objc func conversationSelected() {
        guard let selectedConversation = conversationsDropdown.titleOfSelectedItem,
              selectedConversation != "Select a conversation" else {
            return
        }
        
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
        
        do {
            let content = try String(contentsOf: archiveFile)
            let lines = content.components(separatedBy: .newlines)
            
            let filteredMessages = lines.filter { line in
                line.starts(with: "[\(selectedConversation)]")
            }
            
            DispatchQueue.main.async {
                self.textView.string = filteredMessages.joined(separator: "\n")
            }
        } catch {
            print("error reading archive file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.textView.string = "error: \(error.localizedDescription)"
            }
        }
    }

    @objc func contactSelected() {
        guard let selectedItem = contactsDropdown.titleOfSelectedItem,
              selectedItem != "Select a contact" else {
            print("No contact selected or default option chosen")
            return
        }

        let selectedContact = selectedItem.components(separatedBy: " (")[0]
        print("Selected contact: \(selectedContact)")
        
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
        
        do {
            let content = try String(contentsOf: archiveFile)
            let lines = content.components(separatedBy: .newlines)
            
            print("Total lines in archive: \(lines.count)")
            
            let filteredMessages = lines.filter { line in
                line.contains(": \(selectedContact): ") || line.contains("[\(selectedContact)]")
            }
            
            print("Filtered messages count: \(filteredMessages.count)")
            
            DispatchQueue.main.async {
                if filteredMessages.isEmpty {
                    self.textView.string = "No messages found for contact: \(selectedContact)"
                } else {
                    self.textView.string = filteredMessages.joined(separator: "\n")
                }
            }
        } catch {
            print("Error reading archive file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.textView.string = "Error: \(error.localizedDescription)"
            }
        }
    }

    @objc func addToAIChat() {
        guard let selectedItem = contactsDropdown.titleOfSelectedItem,
              selectedItem != "Select a contact" else {
            print("No contact selected or default option chosen")
            return
        }

        let selectedContact = selectedItem.components(separatedBy: " (")[0]
        print("Adding contact to AI chat: \(selectedContact)")

        // Try to load the API key from Keychain
        if let apiKey = loadAPIKeyFromKeychain() {
            self.openAI = OpenAIClient(apiKey: apiKey)
            self.performAIAnalysis(for: selectedContact)
        } else {
            // Show modal to input API key if not found in Keychain
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Enter OpenAI API Key"
                alert.informativeText = "Please enter your OpenAI API key to proceed with the analysis."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")

                let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                inputTextField.placeholderString = "sk-..."
                alert.accessoryView = inputTextField

                let response = alert.runModal()
                
                guard response == .alertFirstButtonReturn else {
                    print("API key input cancelled")
                    return
                }

                let apiKey = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else {
                    print("API key is empty")
                    return
                }

                // Save the API key to Keychain
                self.saveAPIKeyToKeychain(apiKey)

                // Initialize OpenAI client with the provided API key
                self.openAI = OpenAIClient(apiKey: apiKey)

                self.performAIAnalysis(for: selectedContact)
            }
        }
    }

    func performAIAnalysis(for contact: String) {
        // Get the chat history for the selected contact
        let chatHistory = self.getChatHistoryForContact(contact)

        // Prepare the prompt for GPT-4
        let prompt = """
        The following is a chat history with \(contact). Please analyze this conversation and provide a summary of the key points, topics discussed, and any notable patterns or insights:

        \(chatHistory)

        Summary:
        """

        // Show loading spinner
        DispatchQueue.main.async {
            self.loadingSpinner.startAnimation(nil)
            self.textView.string = "Analyzing chat history for \(contact)..."
        }

        // Make the API call to OpenAI
        self.openAI?.sendCompletion(prompt: prompt) { result in
            DispatchQueue.main.async {
                self.loadingSpinner.stopAnimation(nil)
                
                switch result {
                case .success(let content):
                    self.textView.string = "AI Analysis for \(contact):\n\n\(content)"
                case .failure(let error):
                    print("OpenAI API Error: \(error.localizedDescription)")
                    self.textView.string = "Error: Unable to generate AI analysis. Please try again."
                }
            }
        }
    }

    func getChatHistoryForContact(_ contact: String) -> String {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
        
        do {
            let content = try String(contentsOf: archiveFile)
            let lines = content.components(separatedBy: .newlines)
            
            let filteredMessages = lines.filter { line in
                line.contains(": \(contact): ") || line.contains("[\(contact)]")
            }
            
            return filteredMessages.joined(separator: "\n")
        } catch {
            print("Error reading archive file: \(error.localizedDescription)")
            return "Error: Unable to retrieve chat history."
        }
    }

    func saveAPIKeyToKeychain(_ apiKey: String) {
        let keyData = apiKey.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("error saving api key to keychain: \(status)")
        }
    }

    func loadAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            if let data = result as? Data,
               let apiKey = String(data: data, encoding: .utf8) {
                return apiKey
            }
        }
        return nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

NSApp.activate(ignoringOtherApps: true)
NSApp.setActivationPolicy(.regular)

app.run()