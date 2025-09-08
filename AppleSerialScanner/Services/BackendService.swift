import Foundation
import Network
import OSLog

// MARK: - Models are defined in Models/ folder

// MARK: - Backend Service
class BackendService: ObservableObject {
    @Published var baseURL: String {
        didSet {
            userDefaults.set(baseURL, forKey: "backend_base_url")
        }
    }
    @Published var apiKey: String {
        didSet {
            do { try SecureStore.set(apiKey, forKey: "backend_api_key") } catch {
                userDefaults.set(apiKey, forKey: "backend_api_key")
                AppLogger.storage.error("Failed to persist API key: \(error.localizedDescription)")
            }
        }
    }
    @Published var isConnected: Bool = false
    @Published var networkAvailable: Bool = true
    @Published var connectionError: String? = nil
    
    private let session: URLSession
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private let userDefaults = UserDefaults.standard
    
    init() {
        // Load persisted settings
        let storedBaseURL = userDefaults.string(forKey: "backend_base_url")
        let defaultBaseURL = "https://api.example.com"
        let initialBaseURL = (storedBaseURL?.isEmpty == false ? storedBaseURL! : defaultBaseURL)
        self.baseURL = initialBaseURL

        let storedApiKey = (try? SecureStore.get(forKey: "backend_api_key")) ?? userDefaults.string(forKey: "backend_api_key")
        self.apiKey = storedApiKey ?? ""

        // Configure dedicated URLSession with timeouts
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)

        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.networkAvailable = path.status == .satisfied
                if path.status != .satisfied {
                    self?.connectionError = "Network connection unavailable"
                    self?.isConnected = false
                } else {
                    self?.connectionError = nil
                    // Don't set isConnected to true here - only after a successful connection test
                    Task {
                        _ = await self?.testConnection()
                    }
                }
                
                AppLogger.network.debug("Network status: \(String(describing: path.status.rawValue)), available=\(self?.networkAvailable ?? false)")
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // Utility: Always set Authorization header
    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - Submit Serial
    func submitSerial(_ submission: SerialSubmission) async throws -> SerialResponse {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let url = URL(string: baseURL)?.appendingPathComponent("serials") else {
            throw BackendError.invalidURL
        }
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(submission)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                await updateConnectionStatus(true)
                return try decoder.decode(SerialResponse.self, from: data)
            } else {
                throw BackendError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }
    
    // MARK: - Fetch History
    func fetchHistory(limit: Int = 50, offset: Int = 0, dateFrom: Date? = nil, dateTo: Date? = nil, source: String? = nil, deviceType: String? = nil) async throws -> [ScanHistory] {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let base = URL(string: baseURL) else { throw BackendError.invalidURL }
        var components = URLComponents(url: base.appendingPathComponent("history"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        if let dateFrom = dateFrom {
            components.queryItems?.append(URLQueryItem(name: "dateFrom", value: dateFrom.ISO8601Format()))
        }
        if let dateTo = dateTo {
            components.queryItems?.append(URLQueryItem(name: "dateTo", value: dateTo.ISO8601Format()))
        }
        if let source = source {
            components.queryItems?.append(URLQueryItem(name: "source", value: source))
        }
        if let deviceType = deviceType {
            components.queryItems?.append(URLQueryItem(name: "deviceType", value: deviceType))
        }

        guard let url = components.url else {
            throw BackendError.invalidURL
        }

        var request = authorizedRequest(url: url)

        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                await updateConnectionStatus(true)
                return try decoder.decode([ScanHistory].self, from: data)
            } else {
                throw BackendError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }
    
    // MARK: - Export History
    func exportHistory(format: String) async throws -> Data {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let base = URL(string: baseURL) else { throw BackendError.invalidURL }
        var components = URLComponents(url: base.appendingPathComponent("export"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: format)
        ]
        
        guard let url = components.url else {
            throw BackendError.invalidURL
        }
        
        var request = authorizedRequest(url: url)

        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                await updateConnectionStatus(true)
                return data
            } else {
                throw BackendError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }
    
    // MARK: - Fetch System Stats
    func fetchSystemStats() async throws -> SystemStats {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let url = URL(string: baseURL)?.appendingPathComponent("stats") else {
            throw BackendError.invalidURL
        }
        
        var request = authorizedRequest(url: url)

        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                await updateConnectionStatus(true)
                return try decoder.decode(SystemStats.self, from: data)
            } else {
                throw BackendError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }
    
    // MARK: - Get Client Config
    func getClientConfig() async throws -> ClientConfig {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let url = URL(string: baseURL)?.appendingPathComponent("config") else {
            throw BackendError.invalidURL
        }
        
        var request = authorizedRequest(url: url)

        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                await updateConnectionStatus(true)
                return try decoder.decode(ClientConfig.self, from: data)
            } else {
                throw BackendError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }
    
    // MARK: - Test Connection
    func testConnection() async -> Bool {
        do {
            _ = try await getClientConfig()
            await updateConnectionStatus(true)
            return true
        } catch {
            await updateConnectionStatus(false, error: error)
            return false
        }
    }

    // MARK: - Fetch Health Status
    func fetchHealthStatus() async throws -> HealthStatus {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let url = URL(string: baseURL)?.appendingPathComponent("health") else {
            throw BackendError.invalidURL
        }
        var request = authorizedRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                await updateConnectionStatus(true)
                return try decoder.decode(HealthStatus.self, from: data)
            } else {
                throw BackendError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }

    // Update healthCheck to use /health
    func healthCheck() async throws -> Bool {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        guard let url = URL(string: "\(baseURL)/health") else {
            throw BackendError.invalidURL
        }
        var request = authorizedRequest(url: url)
        
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BackendError.invalidResponse
            }
            await updateConnectionStatus(true)
            return httpResponse.statusCode == 200
        } catch let error as URLError {
            await handleURLError(error)
            throw BackendError.networkError(error)
        } catch {
            throw error
        }
    }
    
    // Helper method to update connection status
    @MainActor
    private func updateConnectionStatus(_ connected: Bool, error: Error? = nil) {
        self.isConnected = connected
        if !connected {
            if let urlError = error as? URLError {
                self.connectionError = self.formatURLError(urlError)
            } else if let error = error {
                self.connectionError = error.localizedDescription
            } else {
                self.connectionError = "Could not connect to server"
            }
        } else {
            self.connectionError = nil
        }
    }
    
    // Helper method to handle URL errors
    private func handleURLError(_ error: URLError) async {
        await updateConnectionStatus(false, error: error)
    }
    
    // Format user-friendly error messages for common URL errors
    private func formatURLError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "Not connected to the internet"
        case .timedOut:
            return "Connection timed out"
        case .cannotFindHost:
            return "Cannot find server \(baseURL)"
        case .cannotConnectToHost:
            return "Cannot connect to server \(baseURL)"
        case .networkConnectionLost:
            return "Network connection was lost"
        default:
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Errors
enum BackendError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case networkOffline
    case networkError(Error)
    
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
        case .networkOffline:
            return "Network connection is offline"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
