import Foundation

struct ClientConfig: Codable {
    let apiKey: String
    let baseURL: URL
    let timeout: TimeInterval
    
    static let `default`: ClientConfig = {
        guard let url = URL(string: "https://api.example.com") else {
            fatalError("Invalid base URL in ClientConfig")
        }
        return ClientConfig(apiKey: "YOUR_API_KEY", baseURL: url, timeout: 30.0)
    }()
}
