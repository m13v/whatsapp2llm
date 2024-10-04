import Foundation
import Dispatch
import CoreGraphics
import Security
import AVFoundation

struct SearchResult {
    let text: String
    let windowName: String
    let coordinates: (x: Double, y: Double, width: Double, height: Double)
}

class WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "WebSocketClient")
    private var isRunning = true
    private var latestData: [String: Any]?
    private var reconnectTimer: Timer?
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    
    func connect() {
        guard let url = URL(string: "ws://127.0.0.1:8080") else {
            print("invalid websocket url")
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        print("connecting to screenpipe...")
        receiveMessage()
    }
    
    private func receiveMessage() {
        guard isRunning else { return }
        
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isRunning else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.processMessage(text)
                case .data(let data):
                    if let jsonString = String(data: data, encoding: .utf8) {
                        self.processMessage(jsonString)
                    }
                @unknown default:
                    print("unknown message type received")
                }
                self.reconnectAttempts = 0 // Reset reconnect attempts on successful message
                self.receiveMessage()
            case .failure(let error):
                print("websocket error: \(error.localizedDescription)")
                self.handleDisconnection()
            }
        }
    }
    
    private func processMessage(_ jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            print("failed to parse message as json")
            return
        }
        self.latestData = json
    }
    
    private func handleDisconnection() {
        isRunning = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            print("attempting to reconnect (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.connect()
            }
        } else {
            print("max reconnection attempts reached. please check your websocket server and restart the script.")
        }
    }

    func search(query: String) -> [SearchResult] {
        guard let json = self.latestData,
              let windows = json["windows"] as? [[String: Any]] else {
            return []
        }
        
        return windows.flatMap { window -> [SearchResult] in
            guard let windowName = window["window_name"] as? String,
                  let textJson = window["text_json"] as? [[String: Any]] else {
                return []
            }
            
            return textJson.compactMap { item -> SearchResult? in
                guard let itemText = item["text"] as? String,
                      itemText.lowercased().contains(query.lowercased()),
                      let left = Double(item["left"] as? String ?? ""),
                      let top = Double(item["top"] as? String ?? ""),
                      let width = Double(item["width"] as? String ?? ""),
                      let height = Double(item["height"] as? String ?? "") else {
                    return nil
                }
                
                return SearchResult(
                    text: itemText,
                    windowName: windowName,
                    coordinates: (x: left, y: top, width: width, height: height)
                )
            }
        }
    }
    
    func checkIPhoneInUseAndHandle() {
        let iphoneInUseResults = self.search(query: "iPhone in Use")
        if !iphoneInUseResults.isEmpty {
            print("'iPhone in Use' message found. Looking for 'Try Again' button...")
            
            // Search for "Try Again" button
            let tryAgainResults = self.search(query: "Try Again")
            if let tryAgainResult = tryAgainResults.first {
                print("'Try Again' button found. Clicking it...")
                
                // Perform click on "Try Again" with a vertical offset
                // Adjust this value as needed to hit the correct spot
                let verticalOffset: CGFloat = 20 // Example value, adjust based on testing
                self.performClick(at: tryAgainResult.coordinates, windowName: tryAgainResult.windowName, verticalOffset: verticalOffset)
                
                // Wait for 5 seconds
                print("waiting 5 seconds...")
                Thread.sleep(forTimeInterval: 5)
            } else {
                print("'Try Again' button not found")
            }
        }
    }

    func getWindowPosition(windowName: String) -> CGRect? {
        guard let windowListInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as NSArray? as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowListInfo {
            if let name = windowInfo[kCGWindowName as String] as? String, name == windowName,
            let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
            let x = boundsDict["X"] as? CGFloat,
            let y = boundsDict["Y"] as? CGFloat,
            let width = boundsDict["Width"] as? CGFloat,
            let height = boundsDict["Height"] as? CGFloat {
                return CGRect(x: x, y: y, width: width, height: height)
            }
        }
        return nil
    }
    
    func isWindowInForeground(windowName: String) -> Bool {
        guard let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? as? [[String: Any]] else {
            return false
        }

        // The first window in the list is typically the frontmost window
        if let frontmostWindow = windowListInfo.first,
           let name = frontmostWindow[kCGWindowName as String] as? String {
            return name == windowName
        }

        return false
    }

    func performClick(at coordinates: (x: Double, y: Double, width: Double, height: Double), windowName: String, doubleClick: Bool = false, verticalOffset: CGFloat = 0) {
        guard let windowPosition = getWindowPosition(windowName: windowName) else {
            print("could not find window position for window: \(windowName)")
            return
        }

        // print("debug: window position: \(windowPosition)")

        // Convert percentage coordinates to actual window coordinates
        // Invert the y-coordinate and apply vertical offset
        let clickX = windowPosition.origin.x + (CGFloat(coordinates.x) * windowPosition.width)
        let clickY = windowPosition.origin.y + ((1 - CGFloat(coordinates.y)) * windowPosition.height) + verticalOffset

        // print("debug: percentage coordinates: x: \(coordinates.x * 100)%, y: \(coordinates.y * 100)%")
        // print("debug: window coordinates: x: \(clickX), y: \(clickY)")

        let mouseMoveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)
        let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)
        let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)

        mouseMoveEvent?.post(tap: .cghidEventTap)
        mouseDownEvent?.post(tap: .cghidEventTap)
        mouseUpEvent?.post(tap: .cghidEventTap)

        if doubleClick || !isWindowInForeground(windowName: windowName) {
            // Wait a short moment before the second click
            Thread.sleep(forTimeInterval: 0.1)
            mouseDownEvent?.post(tap: .cghidEventTap)
            mouseUpEvent?.post(tap: .cghidEventTap)
        }

        // print("performed \(doubleClick ? "double " : "")click at coordinates: x: \(clickX), y: \(clickY) for window: \(windowName)")
    }

    func printLatestText() {
        guard let json = self.latestData,
              let windows = json["windows"] as? [[String: Any]] else {
            print("no text data available")
            return
        }
        
        for window in windows {
            guard let windowName = window["window_name"] as? String,
                  let textJson = window["text_json"] as? [[String: Any]] else {
                continue
            }
            
            print("Window: \(windowName)")
            for textElement in textJson {
                if let text = textElement["text"] as? String {
                    print("  \(text)")
                }
            }
            print("---")
        }
    }

    func stop() {
        isRunning = false
        reconnectTimer?.invalidate()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    // Add this new public method
    func getLatestData() -> [String: Any]? {
        return latestData
    }

    // Add this helper function to extract text from the latest data
    func extractText(from data: [String: Any]?) -> String? {
        guard let windows = data?["windows"] as? [[String: Any]],
              let firstWindow = windows.first,
              let text = firstWindow["text"] as? String else {
            return nil
        }
        return text
    }
}

// Function to check if iPhone Mirroring app is running
func isIPhoneMirroringRunning() -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/pgrep"
    task.arguments = ["-if", "iPhone Mirroring"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)
    
    return !(output?.isEmpty ?? true)
}

// Function to start iPhone Mirroring app
func startIPhoneMirroring() {
    let task = Process()
    task.launchPath = "/usr/bin/open"
    task.arguments = ["-a", "iPhone Mirroring"]
    task.launch()
    task.waitUntilExit()
    
    print("waiting 10 seconds for iphone mirroring to fully load...")
    Thread.sleep(forTimeInterval: 10)
}

// Function to bring iPhone Mirroring to foreground
func bringIPhoneMirroringToForeground() {
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", "tell application \"iPhone Mirroring\" to activate"]
    task.launch()
    task.waitUntilExit()
    
    print("brought iphone mirroring to foreground")
    Thread.sleep(forTimeInterval: 2) // Wait for 2 seconds to ensure the app is in focus
}

// Check and start iPhone Mirroring if not running, or bring it to foreground if it is
if isIPhoneMirroringRunning() {
    print("iphone mirroring is already running, bringing it to foreground...")
    bringIPhoneMirroringToForeground()
} else {
    print("iphone mirroring is not running. starting it now...")
    startIPhoneMirroring()
    print("iphone mirroring has been started and loaded")
}

// MAIN LOGIC - MAIN LOGIC - MAIN LOGIC - MAIN LOGIC - MAIN LOGIC - MAIN LOGIC - MAIN LOGIC
let client = WebSocketClient()
client.connect()

// Wait for the WebSocket connection to be established
Thread.sleep(forTimeInterval: 2)

enum State {
    case lookingForSearch
    case waitingForSearchResults
    // Add more states as needed
}

signal(SIGINT) { _ in
    print("\nreceived interrupt signal, shutting down...")
    client.stop()
    exit(0)
}

var currentState = State.lookingForSearch
var lastActionTime = Date()
let cooldownPeriod: TimeInterval = 2 // 2 seconds cooldown between actions

// Search for and click the "Search" button
while true {
    // Check for "iPhone in Use" message and handle it if present
    client.checkIPhoneInUseAndHandle()
    
    // Perform your regular search
    let searchResults = client.search(query: "Search")
    if let result = searchResults.first {
        print("found 'search' button:")
        print("""
            window: \(result.windowName)
            coordinates: x: \(result.coordinates.x * 100)%, y: \(result.coordinates.y * 100)% (from bottom)
            width: \(result.coordinates.width * 100)%, height: \(result.coordinates.height * 100)%
        """)
        client.performClick(at: result.coordinates, windowName: result.windowName)
        client.printLatestText()
        break // Exit the loop after clicking the "Search" button
    }
    
    // Wait before next iteration
    Thread.sleep(forTimeInterval: 1)
}

print("search button clicked, now typing 'Hinge'")

// Function to simulate key press
func simulateKeyPress(key: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

// Wait for 1 second after clicking the search button
Thread.sleep(forTimeInterval: 1)

// Type "Hinge" with 0.1-second intervals
let hingeCharacters: [(Character, CGKeyCode)] = [
    ("H", 0x04),
    ("i", 0x22),
    ("n", 0x2D),
    ("g", 0x05),
    ("e", 0x0E)
]

for (_, keyCode) in hingeCharacters {
    simulateKeyPress(key: keyCode)
    Thread.sleep(forTimeInterval: 0.1)
}

// Press Enter key
print("pressing enter key")
simulateKeyPress(key: 0x24) // 0x24 is the CGKeyCode for the Enter key

print("typing and pressing enter")

// Function to simulate mouse wheel scrolling
func simulateMouseWheelScroll(scrollAmount: Int32) {
    let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: scrollAmount, wheel2: 0, wheel3: 0)
    scrollEvent?.post(tap: .cghidEventTap)
}

// Search for "Age" in a loop
var ageResult: SearchResult?
while ageResult == nil {
    let ageResults = client.search(query: "Age")
    ageResult = ageResults.first
    
    if ageResult == nil {
        // print("'age' not found, retrying in 1 second...")
        Thread.sleep(forTimeInterval: 1)
    }
}

// print("found 'age':")

// Store text data before and after scrolling
var scrollData: [String: String] = [:]
if let text = client.extractText(from: client.getLatestData()) {
    scrollData["before_scroll"] = text
    // print("text data before scrolling:")
    print(scrollData["before_scroll"] ?? "no data available")
} else {
    print("no text data available before scrolling")
}

// Function to perform scroll and capture data
func performScrollAndCaptureData(scrollCount: Int, scrollData: inout [String: String]) {
    if let windowRect = client.getWindowPosition(windowName: ageResult!.windowName) {
        let centerX = windowRect.origin.x + windowRect.width / 2
        let centerY = windowRect.origin.y + windowRect.height / 2
        
        let mouseMoveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: centerX, y: centerY), mouseButton: .left)
        mouseMoveEvent?.post(tap: .cghidEventTap)
        
        // Scroll mouse wheel up with larger steps and more iterations
        for _ in 1...5 {
            simulateMouseWheelScroll(scrollAmount: -100) // Increased scroll amount
            Thread.sleep(forTimeInterval: 0.05) // Slightly increased delay between scrolls
        }
        
        print("scrolling")
    } else {
        print("could not find window position")
    }

    // Wait for 8 seconds
    // print("waiting for 8 seconds...")
    Thread.sleep(forTimeInterval: 6)

    // Store text data after scrolling
    if let text = client.extractText(from: client.getLatestData()) {
        scrollData["after_scroll_\(scrollCount)"] = text
        // print("text data after scroll \(scrollCount):")
        print(scrollData["after_scroll_\(scrollCount)"] ?? "no data available")
    } else {
        print("no text data available after scroll \(scrollCount)")
    }
}

// Perform multiple scrolls
for i in 1...6 {
    performScrollAndCaptureData(scrollCount: i, scrollData: &scrollData)
}

// print("complete scroll data:")
// print(scrollData)

class OpenAIClient {
    let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func sendCompletion(prompt: String, model: String = "gpt-4o", maxTokens: Int = 4000, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "be very concise, funny, romantic"],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                    completion(.failure(NSError(domain: "OpenAIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "failed to parse api response"])))
                }
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }
}

class HingeAgent {
    let keychainService = "com.yourcompany.whatsapp-autoresponder"
    let keychainAccountOpenAI = "OPENAI_API_KEY"
    let keychainAccountElevenLabs = "ELEVENLABS_API_KEY"
    var openAI: OpenAIClient?

    func loadAPIKeyFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
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

    func saveAPIKeyToKeychain(_ apiKey: String, account: String) {
        let keyData = apiKey.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("error saving api key to keychain: \(status)")
        }
    }

    func decideToLikeOrPass(scrollData: [String: String]) {
        guard let apiKey = loadAPIKeyFromKeychain(account: keychainAccountOpenAI) else {
            print("error: api key not found in keychain")
            print("please enter your openai api key:")
            if let inputApiKey = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !inputApiKey.isEmpty {
                saveAPIKeyToKeychain(inputApiKey, account: keychainAccountOpenAI)
                decideToLikeOrPass(scrollData: scrollData)
            } else {
                print("invalid api key. exiting.")
            }
            return
        }

        self.openAI = OpenAIClient(apiKey: apiKey)

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        decide whether to like or pass. be skeptical, by default pass, we can only like 10% of profiles overall, so be selective. Provide a brief explanation for your decision.
        Be very concise, funny, sarcastic, like a bro friend giving advice.
        Profile data:
        \(scrollData)

        End your response with "[like]" or "[pass]"
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "be very concise, funny, sarcastic, like a bro friend giving advice."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4000
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error: Failed to serialize request body: \(error.localizedDescription)")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                print("Error: API request failed: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("Error: No data received from API")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("\n\(content)\n")
                    self.handleDecision(content)
                } else {
                    print("Error: Failed to parse API response")
                }
            } catch {
                print("Error: Failed to parse API response: \(error.localizedDescription)")
            }
        }

        task.resume()
        semaphore.wait()
    }

private func handleDecision(_ response: String) {
    // Trigger async call to Eleven Labs and play the content
    Task {
        do {
            print("fetching audio data...")
            let audioData = try await fetchAudioFromElevenLabs(content: response)
            print("audio data received, size: \(audioData.count) bytes")
            playAudio(data: audioData)
        } catch {
            print("Error fetching or playing audio: \(error)")
        }
    }

    if response.contains("[like]") {
    // if true { //TESTING HARDCODED [like]
        print("decision: [like]")
        // perform click on the like button
        performClickOnLikeButton(scrollData: scrollData)
    } else {
        print("decision: [pass]")
        // perform click on the cross button
        performClickOnCrossButton()
    }
}

    private func performClickOnCrossButton() {
        let windowName = "iPhone Mirroring"

        guard let windowPosition = client.getWindowPosition(windowName: windowName) else {
            print("could not find window position for window: \(windowName)")
            return
        }

        var clickYPercentage: CGFloat = 0.93

        while true {
            let clickX = windowPosition.origin.x + (windowPosition.width * 0.10)
            let clickY = windowPosition.origin.y + (windowPosition.height * clickYPercentage)

            let mouseMoveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)
            let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)
            let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)

            mouseMoveEvent?.post(tap: .cghidEventTap)
            mouseDownEvent?.post(tap: .cghidEventTap)
            mouseUpEvent?.post(tap: .cghidEventTap)

            print("clicking on cross button")

            // wait for 5 seconds
            Thread.sleep(forTimeInterval: 7)

            // search for "age" text
            let ageResults = client.search(query: "age")
            if !ageResults.isEmpty {
                print("'age' found, cross button click successful")
                break
            } else {
                print("'age' not found, adjusting click position")
                clickYPercentage -= 0.05
            }
        }
    }

    private func performClickOnLikeButton(scrollData: [String: String]) {
        let windowName = "iPhone Mirroring" // Updated to the correct window name

        guard let windowPosition = client.getWindowPosition(windowName: windowName) else {
            print("could not find window position for window: \(windowName)")
            return
        }

        var clickYPercentage: CGFloat = 0.83

        while true {
            let clickX = windowPosition.origin.x + (windowPosition.width * 0.90)
            let clickY = windowPosition.origin.y + (windowPosition.height * clickYPercentage)
            // print("performing click at 95% x \(clickYPercentage * 100)% of the window: x: \(clickX), y: \(clickY)")

            let mouseMoveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)
            let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)
            let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: clickX, y: clickY), mouseButton: .left)

            mouseMoveEvent?.post(tap: .cghidEventTap)
            mouseDownEvent?.post(tap: .cghidEventTap)
            mouseUpEvent?.post(tap: .cghidEventTap)

            print("clicking on like button")


            // Wait for 5 seconds
            // print("waiting 8 seconds...")
            Thread.sleep(forTimeInterval: 5)

            // Search for "Send like" text
            let sendLikeResults = client.search(query: "comment")
            if let commentResult = sendLikeResults.first {
                print("adding comment")
                client.performClick(at: commentResult.coordinates, windowName: commentResult.windowName)
                print("clicked on comment field")
                let commentPrompt = """
                write a 10 word max funny viby comment based on the scroll data:
                \(scrollData)
                -
                you should sound like a very confident successful middle aged man, and not like a ai bot
                be the opposite of needy
                you can use emojiy but only consisting of keyboard characters
                """
                self.openAI?.sendCompletion(prompt: commentPrompt, completion: { result in
                    switch result {
                    case .success(let comment):
                        print("\n\(comment)\n")
                        // Here you can add the logic to type the comment into the app
                        // Ensure `comment` is defined before calling `self.typeComment(comment)`
                        self.typeComment(comment)
                    case .failure(let error):
                        print("error generating comment: \(error)")
                    }
                })
                break
            } else {
                print("didn't work, keep searching the like button")
                clickYPercentage -= 0.04
            }
        }
    }

    private func sanitizeComment(_ comment: String) -> String {
        let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?'\"()-@#$%^&*()_+=[]{}\\|;:<>/`~")
        return String(comment.filter { allowedCharacters.contains($0) })
    }

    private func typeComment(_ comment: String) {
        let sanitizedComment = sanitizeComment(comment)
        print("sanitized comment: \(sanitizedComment)")
        
        for char in sanitizedComment {
            if let keyCode = keyCodeForCharacter(char) {
                simulateKeyPress(key: keyCode)
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        
        // Press Enter key after typing the comment
        simulateKeyPress(key: 0x24) // 0x24 is the CGKeyCode for the Enter key
        print("comment typed and enter key pressed")
        
        // Wait for a moment after pressing Enter
        Thread.sleep(forTimeInterval: 1)
        
    }

    private func keyCodeForCharacter(_ char: Character) -> CGKeyCode? {
        // Map characters to their respective key codes
        let keyMap: [Character: CGKeyCode] = [
            "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
            "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
            "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
            "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
            "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
            "z": 0x06, 
            "A": 0x00, "B": 0x0B, "C": 0x08, "D": 0x02,
            "E": 0x0E, "F": 0x03, "G": 0x05, "H": 0x04, "I": 0x22,
            "J": 0x26, "K": 0x28, "L": 0x25, "M": 0x2E, "N": 0x2D,
            "O": 0x1F, "P": 0x23, "Q": 0x0C, "R": 0x0F, "S": 0x01,
            "T": 0x11, "U": 0x20, "V": 0x09, "W": 0x0D, "X": 0x07,
            "Y": 0x10, "Z": 0x06, 
            "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C,
            "9": 0x19, "0": 0x1D, " ": 0x31, ".": 0x2F, ",": 0x2B,
            "!": 0x1E, "@": 0x1F, "#": 0x20, "$": 0x21,
            "%": 0x22, "^": 0x23, "&": 0x24, "*": 0x25, "(": 0x26,
            ")": 0x27, "-": 0x1B, "_": 0x1B, "=": 0x18, "+": 0x18,
            "[": 0x21, "]": 0x1E, "{": 0x21, "}": 0x1E, "\\": 0x2A,
            "|": 0x2A, ";": 0x29, ":": 0x29, "'": 0x27, "\"": 0x27,
            "/": 0x2C, "<": 0x2B, ">": 0x2F, "`": 0x32,
            "~": 0x32
        ]
        return keyMap[char]
    }

    func repeatDecisionLoop() {
        for _ in 1...100 {
            // Search for "Age" in a loop
            var ageResult: SearchResult?
            while ageResult == nil {
                let ageResults = client.search(query: "Age")
                ageResult = ageResults.first
                
                if ageResult == nil {
                    // print("'age' not found, retrying in 1 second...")
                    Thread.sleep(forTimeInterval: 1)
                }
            }

            // Store text data before and after scrolling
            var scrollData: [String: String] = [:]
            if let text = client.extractText(from: client.getLatestData()) {
                scrollData["before_scroll"] = text
            } else {
                print("no text data available before scrolling")
            }

            // Perform multiple scrolls
            for i in 1...6 {
                performScrollAndCaptureData(scrollCount: i, scrollData: &scrollData)
            }

            // print("complete scroll data:")
            // print(scrollData)

            // Decide to like or pass based on scroll data
            decideToLikeOrPass(scrollData: scrollData)
        }
    }

    func fetchAudioFromElevenLabs(content: String) async throws -> Data {
        guard let apiKey = loadAPIKeyFromKeychain(account: keychainAccountElevenLabs) else {
            print("error: elevenlabs api key not found in keychain")
            print("please enter your elevenlabs api key:")
            if let inputApiKey = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !inputApiKey.isEmpty {
                saveAPIKeyToKeychain(inputApiKey, account: keychainAccountElevenLabs)
                return try await fetchAudioFromElevenLabs(content: content)
            } else {
                print("invalid api key. exiting.")
                throw URLError(.userAuthenticationRequired)
            }
        }

        let voiceId = "jBpfuIE2acCO8z3wKNLl"
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let body: [String: Any] = ["text": content]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }

    func playAudio(data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            player.play()
            print("audio playback started")
            
            // Wait for the audio to finish playing
            while player.isPlaying {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            }
            print("audio playback finished")
        } catch {
            print("error playing audio: \(error)")
        }
    }
}

// Create an instance of HingeAgent and call the function
let hingeAgent = HingeAgent()
print("analyzing hinge profile...")
hingeAgent.decideToLikeOrPass(scrollData: scrollData)

// Start the decision loop
hingeAgent.repeatDecisionLoop()

print("now continuously printing latest text")

// New loop to continuously print the latest text
// while true {
//     Thread.sleep(forTimeInterval: 1) // Print every 1 second
//     client.printLatestText()
// }