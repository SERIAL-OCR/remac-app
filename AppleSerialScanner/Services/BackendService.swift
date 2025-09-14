import Foundation
import Network

// MARK: - Models are defined in Models/ folder

// MARK: - Backend Service
class BackendService: ObservableObject {
    @Published var baseURL: String = "http://192.168.1.34:8000"  // Updated to correct IP address
    @Published var apiKey: String = "phase2-pilot-key-2024"
    @Published var isConnected: Bool = false
    @Published var networkAvailable: Bool = true
    @Published var connectionError: String? = nil
    
    private let session: URLSession
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Retry configuration
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let requestTimeout: TimeInterval = 10.0
    
    init() {
        // Configure URLSession with shorter timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        
        setupNetworkMonitoring()
        
        // Test connection on startup
        Task { [weak self] in
            _ = await self?.testConnection()
        }
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] (path: NWPath) -> Void in
            DispatchQueue.main.async {
                self?.networkAvailable = path.status == .satisfied
                if path.status != .satisfied {
                    self?.connectionError = "Network connection unavailable"
                    self?.isConnected = false
                } else {
                    self?.connectionError = nil
                    Task { [weak self] in
                        _ = await self?.testConnection()
                    }
                }
                // Simplified logging to avoid ambiguous expression with custom logger
                let available = self?.networkAvailable ?? false
                print("[Network] status=\(path.status) available=\(available)")
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
        return request
    }

    // MARK: - Retry Logic with Exponential Backoff
    private func makeRequestWithRetry<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                guard let url = URL(string: "\(baseURL)\(endpoint)") else {
                    throw BackendError.invalidURL
                }
                
                var request = authorizedRequest(url: url, method: method)
                
                if let body = body {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                }
                
                print("API Request attempt \(attempt)/\(maxRetries): \(method) \(url)")
                
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BackendError.invalidResponse
                }
                
                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    
                    await updateConnectionStatus(true)
                    let result = try decoder.decode(responseType, from: data)
                    
                    print("API Request successful after \(attempt) attempt(s)")
                    return result
                } else {
                    throw BackendError.serverError(httpResponse.statusCode)
                }
                
            } catch {
                lastError = error
                print("API Request attempt \(attempt) failed: \(error.localizedDescription)")
                
                // Don't retry on certain errors
                if let backendError = error as? BackendError {
                    switch backendError {
                    case .invalidURL, .decodingError:
                        throw error // Don't retry these
                    case .serverError(let code) where code >= 400 && code < 500:
                        throw error // Don't retry client errors
                    default:
                        break // Retry for other errors
                    }
                }
                
                // If this is the last attempt, throw the error
                if attempt == maxRetries {
                    await handleURLError(error as? URLError ?? URLError(.unknown))
                    break
                }
                
                // Exponential backoff: wait longer between retries
                let delay = baseRetryDelay * pow(2.0, Double(attempt - 1))
                print("Waiting \(String(format: "%.1f", delay))s before retry...")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? BackendError.networkError(URLError(.unknown))
    }

    // MARK: - Updated Submit Serial with Retry Logic
    func submitSerial(_ submission: SerialSubmission) async throws -> SerialResponse {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(submission)
        
        return try await makeRequestWithRetry(
            endpoint: "/serials",
            method: "POST",
            body: body,
            responseType: SerialResponse.self
        )
    }

    // MARK: - Updated Fetch History with Retry Logic
    func fetchHistory(limit: Int = 50, offset: Int = 0, dateFrom: Date? = nil, dateTo: Date? = nil, source: String? = nil, deviceType: String? = nil) async throws -> [ScanHistory] {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        var components = URLComponents(string: "/history")!
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

        let endpoint = components.url?.absoluteString ?? "/history"
        
        return try await makeRequestWithRetry(
            endpoint: endpoint,
            responseType: [ScanHistory].self
        )
    }

    // MARK: - Updated Get Client Config with Retry Logic
    func getClientConfig() async throws -> ClientConfig {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        return try await makeRequestWithRetry(
            endpoint: "/config",
            responseType: ClientConfig.self
        )
    }

    // MARK: - Updated Fetch System Stats with Retry Logic
    func fetchSystemStats() async throws -> SystemStats {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        return try await makeRequestWithRetry(
            endpoint: "/stats",
            responseType: SystemStats.self
        )
    }

    // MARK: - Updated Health Check with Retry Logic
    func healthCheck() async throws -> Bool {
        guard networkAvailable else {
            throw BackendError.networkOffline
        }
        
        do {
            _ = try await makeRequestWithRetry(
                endpoint: "/health",
                responseType: HealthStatus.self
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Test Connection with Enhanced Logging
    func testConnection() async -> Bool {
        print("Testing connection to \(baseURL)...")
        
        do {
            _ = try await getClientConfig()
            await updateConnectionStatus(true)
            print("Connection test successful")
            return true
        } catch {
            await updateConnectionStatus(false, error: error)
            print("Connection test failed: \(error.localizedDescription)")
            return false
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
