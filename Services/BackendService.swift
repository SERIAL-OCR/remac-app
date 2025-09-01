import Foundation

// MARK: - Models are defined in Models/ folder

// MARK: - Backend Service
class BackendService: ObservableObject {
    @Published var baseURL: String = "http://localhost:8000"
    @Published var apiKey: String = ""
    @Published var isConnected: Bool = false
    
    private let session = URLSession.shared
    
    // MARK: - Submit Serial
    func submitSerial(_ submission: SerialSubmission) async throws -> SerialResponse {
        guard let url = URL(string: "\(baseURL)/serials") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(submission)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(SerialResponse.self, from: data)
        } else {
            throw BackendError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Fetch History
    func fetchHistory(limit: Int = 50, offset: Int = 0) async throws -> [ScanHistory] {
        var components = URLComponents(string: "\(baseURL)/history")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        guard let url = components.url else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ScanHistory].self, from: data)
        } else {
            throw BackendError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Export History
    func exportHistory(format: String) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)/export")!
        components.queryItems = [
            URLQueryItem(name: "format", value: format)
        ]
        
        guard let url = components.url else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            return data
        } else {
            throw BackendError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Fetch System Stats
    func fetchSystemStats() async throws -> SystemStats {
        guard let url = URL(string: "\(baseURL)/stats") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(SystemStats.self, from: data)
        } else {
            throw BackendError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Get Client Config
    func getClientConfig() async throws -> ClientConfig {
        guard let url = URL(string: "\(baseURL)/config") else {
            throw BackendError.invalidURL
        }
        
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(ClientConfig.self, from: data)
        } else {
            throw BackendError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Test Connection
    func testConnection() async -> Bool {
        do {
            _ = try await getClientConfig()
            await MainActor.run {
                self.isConnected = true
            }
            return true
        } catch {
            await MainActor.run {
                self.isConnected = false
            }
            return false
        }
    }
}

// MARK: - Errors
enum BackendError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}
