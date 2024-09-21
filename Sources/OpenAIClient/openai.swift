import Foundation
import Cocoa

public class OpenAIClient {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    public init() {
        self.apiKey = OpenAIClient.getAPIKey()
    }

    public func sendCompletion(prompt: String, chatHistory: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": "You are a helpful assistant analyzing chat history."],
            ["role": "user", "content": "Here's the chat history:\n\(chatHistory)\n\nAnalyze this conversation and provide a summary based on the following prompt:\n\(prompt)"]
        ]
        
        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": messages,
            "max_tokens": 1000
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

    private static func getAPIKey() -> String {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let configFile = homeDirectory.appendingPathComponent(".whatsapp2llm_config.json")
        
        if fileManager.fileExists(atPath: configFile.path) {
            do {
                let data = try Data(contentsOf: configFile)
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String]
                if let apiKey = json?["api_key"], !apiKey.isEmpty {
                    return apiKey
                }
            } catch {
                print("error reading config file: \(error.localizedDescription)")
            }
        }
        
        return askUserForAPIKey()
    }

    private static func askUserForAPIKey() -> String {
        print("openai api key required")
        print("please enter your openai api key:")
        
        guard let apiKey = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            fatalError("failed to get api key. please provide a valid api key when prompted.")
        }
        
        saveAPIKey(apiKey)
        return apiKey
    }

    private static func saveAPIKey(_ apiKey: String) {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let configFile = homeDirectory.appendingPathComponent(".whatsapp2llm_config.json")
        
        let config = ["api_key": apiKey]
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: configFile)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        } catch {
            print("error saving api key: \(error.localizedDescription)")
        }
    }
}