import Foundation
import Security
import Dispatch

// Define a Message struct to represent individual messages in a conversation
struct Message: Hashable {
    let timestamp: Date
    let sender: String
    var text: String
    let rawLine: String
    
    // Custom hash function to ensure unique identification of messages
    func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
        hasher.combine(sender)
        hasher.combine(text)
    }
    
    // Custom equality function to compare messages
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
               lhs.sender == rhs.sender &&
               lhs.text == rhs.text
    }
}

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
                completion(.failure(NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "no data received"])))
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
                    throw NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "invalid response format"])
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// Function to extract messages from a specific conversation in the chat archive
func getMessagesFromConversation(conversationName: String) -> [Message] {
    let fileManager = FileManager.default
    let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let archiveFile = downloadsURL.appendingPathComponent("do_not_delete_chat_archive.txt")
    
    do {
        let content = try String(contentsOf: archiveFile, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var messages: [Message] = []
        var foundMessagesSection = false
        var inTargetConversation = false
        var lastTimestamp: Date?
        var seenMessages = Set<String>()
        
        // Regular expression to parse message lines
        let pattern = "^\\[(.*?)\\] \\[(.*?)\\] (.*?): (.*)$"
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        
        // Date formatter to parse timestamps in the messages
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yy, h:mm:ss a"
        
        // Iterate through each line in the archive file
        for line in lines {
            // Check if we've reached the messages section
            if line.starts(with: "<<<messages>>>") {
                foundMessagesSection = true
                continue
            }
            
            if foundMessagesSection && !line.isEmpty {
                if line.starts(with: "[") {
                    // Try to match the line against the regular expression
                    let nsLine = line as NSString
                    let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
                    
                    if let match = matches.first {
                        // Extract conversation name, date, sender, and message text
                        let conversation = nsLine.substring(with: match.range(at: 1))
                        let dateString = nsLine.substring(with: match.range(at: 2))
                        let sender = nsLine.substring(with: match.range(at: 3))
                        let messageText = nsLine.substring(with: match.range(at: 4))
                        
                        // Check if the conversation matches the target conversation
                        if conversation == conversationName {
                            inTargetConversation = true

                            if let timestamp = dateFormatter.date(from: dateString) {
                                lastTimestamp = timestamp
                                // Extract only the message content for deduplication
                                let messageContent = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                if !seenMessages.contains(messageContent) {
                                    let message = Message(timestamp: timestamp, sender: sender, text: messageText, rawLine: line)
                                    messages.append(message)
                                    seenMessages.insert(messageContent)
                                }
                            } else {
                                print("failed to parse date from '\(dateString)'")
                            }
                        } else {
                            inTargetConversation = false
                        }
                    } else if inTargetConversation, let timestamp = lastTimestamp {
                        // Handle continuation of previous message in the target conversation
                        let messageContent = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !seenMessages.contains(messageContent) {
                            let message = Message(timestamp: timestamp, sender: "", text: line, rawLine: line)
                            messages.append(message)
                            seenMessages.insert(messageContent)
                        }
                    }
                } else if inTargetConversation, let timestamp = lastTimestamp {
                    // Handle continuation of previous message in the target conversation
                    let messageContent = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !seenMessages.contains(messageContent) {
                        let message = Message(timestamp: timestamp, sender: "", text: line, rawLine: line)
                        messages.append(message)
                        seenMessages.insert(messageContent)
                    }
                }
            }
        }
        
        // Sort messages from latest to oldest
        messages.sort { $0.timestamp > $1.timestamp }
        
        // Deduplicate messages
        let uniqueMessages = Array(Set(messages))
        
        return uniqueMessages
    } catch {
        print("error reading archive file: \(error.localizedDescription)")
        return []
    }
}

// Function to analyze the conversation and find unanswered messages
func sendEmail(subject: String, body: String, logId: String, conversationName: String) {
    let apiKey = ProcessInfo.processInfo.environment["SMTP2GO_API_KEY"] ?? ""
    let apiUrl = URL(string: "https://api.smtp2go.com/v3/email/send")!

    let markdownBody = """
    # \(conversationName)
    \(body)
    """
    
    let htmlBody = convertMarkdownToHTML(markdownBody)
    let bodyWithTracker = """
    \(htmlBody)
    <script>
    document.addEventListener('DOMContentLoaded', function() {
        var sendLink = document.querySelector('a[href^="http://localhost:8080/log/"]');
        sendLink.addEventListener('click', function(e) {
            e.preventDefault();
            this.textContent = 'SENT';
            this.style.pointerEvents = 'none';
            this.style.color = 'gray';
            fetch(this.href).then(() => {
                setTimeout(() => window.close(), 1000);
            });
        });
    });
    </script>
    """

    let payload: [String: Any] = [
        "sender": "whatsapp ai assistant <i@m13v.com>",
        "to": ["myself <i@m13v.com>"],
        "subject": subject,
        "html_body": bodyWithTracker
    ]

    let jsonData = try! JSONSerialization.data(withJSONObject: payload)

    var request = URLRequest(url: apiUrl)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(apiKey, forHTTPHeaderField: "X-Smtp2go-Api-Key")
    request.httpBody = jsonData

    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
        if let error = error {
            print("failed to send email: \(error)")
            return
        }
        
        guard let data = data else {
            print("no data received")
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode) {
            print("email sent successfully!")
            if let responseString = String(data: data, encoding: .utf8) {
                print("response: \(responseString)")
            }
        } else {
            print("failed to send email")
            if let responseString = String(data: data, encoding: .utf8) {
                print("error response: \(responseString)")
            }
        }
    }

    task.resume()
}

// Add this function to convert basic Markdown to HTML
func convertMarkdownToHTML(_ markdown: String) -> String {
    var html = markdown
    
    // Convert headers
    html = html.replacingOccurrences(of: #"^# (.+)$"#, with: "<h1>$1</h1>", options: .regularExpression, range: nil)
    html = html.replacingOccurrences(of: #"^## (.+)$"#, with: "<h2>$1</h2>", options: .regularExpression, range: nil)
    html = html.replacingOccurrences(of: #"^### (.+)$"#, with: "<h3>$1</h3>", options: .regularExpression, range: nil)
    
    // Convert bold and italic
    html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression, range: nil)
    html = html.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression, range: nil)
    
    // Convert links
    html = html.replacingOccurrences(of: #"\[(.+?)\]\((.+?)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression, range: nil)
    
    // Convert newlines to <br> tags
    html = html.replacingOccurrences(of: "\n", with: "<br>")
    
    return html
}

// Add this struct to represent the HTTP request
struct HTTPRequest {
    let params: [String: String]
    let rawRequest: String
    
    init(rawRequest: String) {
        self.rawRequest = rawRequest
        self.params = [:]  // We'll parse params later if needed
    }
}

// Add this struct to represent the HTTP response headers
struct HTTPResponseHeaders {}

// Add this enum to represent the HTTP response
enum HTTPResponse {
    case ok(String)
    case notFound
}

// Simplified HTTPServer struct
struct HTTPServer {
    let port: Int
    var routes: [String: (HTTPRequest) -> String] = [:]
    private var listener: FileHandle?
    private var shouldKeepRunning = true
    private var modifiedContent: String = ""

    init(port: Int) {
        self.port = port
    }

    mutating func addRoute(path: String, handler: @escaping (HTTPRequest) -> String) {
        routes[path] = handler
    }

    mutating func start() throws {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw NSError(domain: "HTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        var value: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = in_addr_t(0)
        
        guard bind(socket, sockaddr_cast(&addr), socklen_t(MemoryLayout<sockaddr_in>.size)) >= 0 else {
            throw NSError(domain: "HTTPServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind to port \(port)"])
        }

        guard listen(socket, 5) >= 0 else {
            throw NSError(domain: "HTTPServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"])
        }

        print("Server started on port \(port)")

        listener = FileHandle(fileDescriptor: socket)
        
        while shouldKeepRunning {
            autoreleasepool {
                let clientSocket = accept(socket, nil, nil)
                if clientSocket >= 0 {
                    let clientFileHandle = FileHandle(fileDescriptor: clientSocket)
                    handleClient(clientSocket: clientFileHandle)
                } else {
                    print("failed to accept client connection")
                }
            }
        }

        print("server stopped")
    }
    
    private func handleClient(clientSocket: FileHandle) {
        let data = clientSocket.availableData
        let request = HTTPRequest(rawRequest: String(data: data, encoding: .utf8) ?? "")
        
        var response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
        
        if request.rawRequest.contains("/log/"),
        let handler = routes["/log/:id"] {
            let body = handler(request)
            response = body
            
            // Extract the ID from the request
            if let id = request.rawRequest.components(separatedBy: "/log/").last?.components(separatedBy: " ").first,
            let itemNumber = id.components(separatedBy: "/").last {
                print("log: whatsapp message with id \(id) was sent successfully")
                
                // Find and print the associated content
                if let content = findAssociatedContent(for: itemNumber, in: self.modifiedContent) {
                    print("Associated content for item \(itemNumber):")
                    print(content)
                    
                    // Call find_and_click.swift and type_and_send.swift
                    DispatchQueue.global(qos: .background).async {
                        self.runFindAndClickScript(associatedContent: content)
                    }
                } else {
                    print("No associated content found for item \(itemNumber)")
                }
            }
        }
        
        clientSocket.write(response.data(using: .utf8)!)
        clientSocket.closeFile()
    }
    
    mutating func stop() {
        shouldKeepRunning = false
        listener?.closeFile()
    }
    
    private func sockaddr_cast(_ addr: UnsafeMutablePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutableRawPointer(addr).assumingMemoryBound(to: sockaddr.self)
    }

    // Add this new function to run find_and_click.swift
    private func runFindAndClickScript(associatedContent: String) {
        let scriptPath = "find_and_click.swift"
        let typeAndSendPath = "type_and_send.swift"
        
        // First call
        let process1 = Process()
        process1.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process1.arguments = [scriptPath, "WhatsApp", "Chats"]
        
        do {
            try process1.run()
            process1.waitUntilExit()
            
            if process1.terminationStatus == 0 {
                print("first find_and_click.swift executed successfully")
            } else {
                print("first find_and_click.swift failed with status: \(process1.terminationStatus)")
            }
        } catch {
            print("error running first find_and_click.swift: \(error)")
        }
        
        // Wait for 200ms
        Thread.sleep(forTimeInterval: 0.2)
        
        // Second call
        let process2 = Process()
        process2.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process2.arguments = [scriptPath, "WhatsApp", "George"]
        
        do {
            try process2.run()
            process2.waitUntilExit()
            
            if process2.terminationStatus == 0 {
                print("second find_and_click.swift executed successfully")
            } else {
                print("second find_and_click.swift failed with status: \(process2.terminationStatus)")
            }
        } catch {
            print("error running second find_and_click.swift: \(error)")
        }
        
        // Wait for 200ms
        Thread.sleep(forTimeInterval: 0.2)
        
        // Execute type_and_send.swift
        let process3 = Process()
        process3.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process3.arguments = [typeAndSendPath, associatedContent]
        
        do {
            try process3.run()
            process3.waitUntilExit()
            
            if process3.terminationStatus == 0 {
                print("type_and_send.swift executed successfully")
            } else {
                print("type_and_send.swift failed with status: \(process3.terminationStatus)")
            }
        } catch {
            print("error running type_and_send.swift: \(error)")
        }
    }

    // Add this new function to find the associated content
    private func findAssociatedContent(for itemNumber: String, in content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var result = ""
        var foundItem = false
        var itemNumberInBrackets = "[" + itemNumber + "]"

        for line in lines {
            if line.contains(itemNumberInBrackets) {
                foundItem = true
                continue  // Skip the line with the item number
            } else if foundItem {
                if line.lowercased().contains("[send]") {
                    // Remove [SEND] and everything after it
                    if let range = line.range(of: "[SEND]", options: .caseInsensitive) {
                        result += line[..<range.lowerBound]
                    }
                    break
                }
                result += line + "\n"
            }
        }

        return result.isEmpty ? nil : result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setModifiedContent(_ content: String) {
        self.modifiedContent = content
    }

    func getModifiedContent() -> String {
        return self.modifiedContent
    }
}

// Add this at the global scope
var shouldKeepRunning = true

// Add this function to handle the termination signal
func setupSignalHandler() {
    signal(SIGINT) { _ in
        print("\nreceived interrupt signal. shutting down...")
        shouldKeepRunning = false
        exit(0)
    }
}

// Modify the analyzeConversation function to return a closure that takes a pointer to HTTPServer
func analyzeConversation(messages: [Message], openAI: OpenAIClient, conversationName: String) -> (UnsafeMutablePointer<HTTPServer>) -> Void {
    let conversationText = messages.map { "[\($0.timestamp)] \($0.sender): \($0.text)" }.joined(separator: "\n")
    
    let prompt = """
    which message did i (Matt) forget to reply to? just show the message con't, don't mention sender. limit it to 1 or 2 most important messages, always enumerated, draft a reply under each message. add special text '[SEND]' after each reply 
    don't add extra empty lines.
    \(conversationText)
    unanswered messages:
    [1]. (<short timestamp>)...
    -> (sorry, i forgot to reply):
    [2]. (<short timestamp>)...
    -> (sorry, i forgot to reply):
    """
    
    return { serverPtr in
        openAI.sendCompletion(prompt: prompt) { result in
            switch result {
            case .success(let content):
                print("ai analysis:")
                print(content)
                let logId = UUID().uuidString // Generate a unique logId
                let logLink = "http://localhost:8080/log/\(logId)"
                
                // Process the content
                let processedContent = content
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                    .replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
                
                // Replace [SEND] with the SEND link, including the item number
                var modifiedContent = processedContent
                var lines = modifiedContent.components(separatedBy: .newlines)
                var currentItemNumber = 0
                
                for (index, line) in lines.enumerated() {
                    if let range = line.range(of: "^\\d+\\.", options: .regularExpression) {
                        currentItemNumber = Int(line[range].dropLast()) ?? 0
                    } else if line.contains("[SEND]") && currentItemNumber > 0 {
                        lines[index] = line.replacingOccurrences(of: "[SEND]", with: "[SEND](\(logLink)/\(currentItemNumber))")
                    }
                }
                
                modifiedContent = lines.joined(separator: "\n")
                
                // Set the modified content in the server
                serverPtr.pointee.setModifiedContent(modifiedContent)

                sendEmail(subject: "WhatsApp missed messages summary", body: modifiedContent, logId: logId, conversationName: conversationName)
            case .failure(let error):
                print("error during ai analysis: \(error.localizedDescription)")
            }
        }
    }
}

// In the main function, modify the server setup and analyzeConversation call:
func main() {
    setupSignalHandler()

    let targetConversation = "GZ George The Commons"
    let conversationMessages = getMessagesFromConversation(conversationName: targetConversation)

    // Print cleaned messages (without conversation name prefix)
    for message in conversationMessages {
        let cleanedLine = message.rawLine.replacingOccurrences(of: "[\(targetConversation)] ", with: "")
        print(cleanedLine)
    }

    // Print the total number of unique messages
    print("total unique messages: \(conversationMessages.count)")

    // Initialize OpenAI client
    var openAI: OpenAIClient?

    if let apiKey = loadAPIKeyFromKeychain() {
        openAI = OpenAIClient(apiKey: apiKey)
    } else {
        print("no api key found in keychain. please set it using the saveAPIKeyToKeychain function.")
        // You might want to add a way to input the API key here if it's not found
    }

    // Set up the server
    var server = HTTPServer(port: 8080)
    server.addRoute(path: "/log/:id") { request in
        // For simplicity, we're just checking if the raw request contains the ID
        // In a real implementation, you'd want to properly parse the URL
        if let id = request.rawRequest.components(separatedBy: "/log/").last?.components(separatedBy: " ").first {
            print("log: whatsapp message with id \(id) was sent successfully")
            let responseBody = """
            <html>
            <body>
            <h1>Message successfully sent on whatsapp</h1>
            <p>You can close this window now.</p>
            <script>setTimeout(function(){window.close()},1000);</script>
            </body>
            </html>
            """
            return "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(responseBody.utf8.count)\r\n\r\n\(responseBody)"
        }
        return "HTTP/1.1 404 Not Found\r\n\r\n"
    }

    let serverQueue = DispatchQueue(label: "com.yourcompany.server", attributes: .concurrent)
    serverQueue.async {
        do {
            try server.start()
        } catch {
            print("failed to start server: \(error)")
        }
    }

    // Analyze the conversation
    if let openAI = openAI {
        let analyzeAction = analyzeConversation(messages: conversationMessages, openAI: openAI, conversationName: targetConversation)
        withUnsafeMutablePointer(to: &server) { serverPtr in
            analyzeAction(serverPtr)
        }
    } else {
        print("unable to initialize openai client due to missing api key")
    }

    // Run the server


    print("press ctrl+c to stop the script")

    // Keep the main thread running
    while shouldKeepRunning {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
    }
}

// Call the main function
main()

// Move these functions before they are used
func saveAPIKeyToKeychain(_ apiKey: String) {
    let keyData = apiKey.data(using: .utf8)!
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.yourcompany.whatsapp-autoresponder",
        kSecAttrAccount as String: "OPENAI_API_KEY",
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
        kSecAttrService as String: "com.yourcompany.whatsapp-autoresponder",
        kSecAttrAccount as String: "OPENAI_API_KEY",
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


// Main execution
let targetConversation = "GZ George The Commons"
let conversationMessages = getMessagesFromConversation(conversationName: targetConversation)

// Print cleaned messages (without conversation name prefix)
for message in conversationMessages {
    let cleanedLine = message.rawLine.replacingOccurrences(of: "[\(targetConversation)] ", with: "")
    print(cleanedLine)
}

// Print the total number of unique messages
print("total unique messages: \(conversationMessages.count)")

// Initialize OpenAI client
var openAI: OpenAIClient?

if let apiKey = loadAPIKeyFromKeychain() {
    openAI = OpenAIClient(apiKey: apiKey)
} else {
    print("no api key found in keychain. please set it using the saveAPIKeyToKeychain function.")
    // You might want to add a way to input the API key here if it's not found
}


// Keep the main thread running
RunLoop.main.run()

