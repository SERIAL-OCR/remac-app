import Foundation

struct ClientConfig: Codable {
    let apiKey: String
    let baseURL: URL
    let timeout: TimeInterval
    
    static let `default`: ClientConfig = {
        let url = URL(string: "https://api.example.com") ?? URL(string: "https://localhost")!
        return ClientConfig(apiKey: "", baseURL: url, timeout: 30.0)
    }()
}
