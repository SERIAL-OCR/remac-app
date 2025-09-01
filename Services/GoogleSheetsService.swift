import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Google Sheets Service
@MainActor
class GoogleSheetsService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUserEmail: String?
    @Published var isAuthenticating = false

    private var accessToken: String?
    private var refreshToken: String?
    private let clientId = "YOUR_GOOGLE_CLIENT_ID" // Replace with actual client ID
    private let clientSecret = "YOUR_GOOGLE_CLIENT_SECRET" // Replace with actual client secret
    private let redirectURI = "com.googleusercontent.apps.YOUR_APP_BUNDLE_ID:/oauth2redirect"

    // Google Sheets API endpoints
    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"

    // MARK: - Authentication
    func authenticate() {
        isAuthenticating = true

        let authURL = buildAuthURL()

        // For iOS, use ASWebAuthenticationSession
        #if os(iOS)
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "com.googleusercontent.apps.YOUR_APP_BUNDLE_ID") { [weak self] callbackURL, error in
            self?.handleAuthCallback(callbackURL: callbackURL, error: error)
        }

        session.presentationContextProvider = self
        session.start()
        #else
        // For macOS, you might need a different approach
        // This could involve opening the URL in the default browser
        NSWorkspace.shared.open(authURL)
        #endif
    }

    private func buildAuthURL() -> URL {
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/userinfo.email"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }

    private func handleAuthCallback(callbackURL: URL?, error: Error?) {
        isAuthenticating = false

        if let error = error {
            print("Authentication error: \(error)")
            return
        }

        guard let callbackURL = callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("No authorization code received")
            return
        }

        // Exchange authorization code for access token
        exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]

        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Token exchange error: \(error)")
                return
            }

            if let data = data,
               let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data) {
                DispatchQueue.main.async {
                    self?.accessToken = tokenResponse.accessToken
                    self?.refreshToken = tokenResponse.refreshToken
                    self?.isAuthenticated = true
                    self?.getUserInfo()
                }
            }
        }.resume()
    }

    private func getUserInfo() {
        guard let accessToken = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let data = data,
               let userInfo = try? JSONDecoder().decode(UserInfo.self, from: data) {
                DispatchQueue.main.async {
                    self?.currentUserEmail = userInfo.email
                }
            }
        }.resume()
    }

    // MARK: - Google Sheets API Methods

    func createSpreadsheet(title: String) async throws -> GoogleSpreadsheet {
        guard let accessToken = accessToken else {
            throw GoogleSheetsError.notAuthenticated
        }

        let createRequest = CreateSpreadsheetRequest(
            properties: SpreadsheetProperties(title: title)
        )

        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONEncoder().encode(createRequest)
        request.httpBody = jsonData

        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(CreateSpreadsheetResponse.self, from: data)
        return response.spreadsheet
    }

    func updateSpreadsheet(spreadsheetId: String, values: [[String]], range: String = "A1") async throws {
        guard let accessToken = accessToken else {
            throw GoogleSheetsError.notAuthenticated
        }

        let updateRequest = UpdateValuesRequest(
            range: range,
            majorDimension: "ROWS",
            values: values
        )

        let url = URL(string: "\(baseURL)/\(spreadsheetId)/values/\(range)?valueInputOption=RAW")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONEncoder().encode(updateRequest)
        request.httpBody = jsonData

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    func getSpreadsheet(spreadsheetId: String) async throws -> GoogleSpreadsheet {
        guard let accessToken = accessToken else {
            throw GoogleSheetsError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/\(spreadsheetId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        let response = try JSONDecoder().decode(GetSpreadsheetResponse.self, from: data)
        return response.spreadsheet
    }

    func shareSpreadsheet(spreadsheetId: String, email: String, role: String = "writer") async throws {
        guard let accessToken = accessToken else {
            throw GoogleSheetsError.notAuthenticated
        }

        let shareRequest = ShareRequest(
            role: role,
            type: "user",
            emailAddress: email
        )

        let url = URL(string: "\(baseURL)/\(spreadsheetId)/permissions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONEncoder().encode(shareRequest)
        request.httpBody = jsonData

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    // MARK: - Batch Operations
    func exportBatchData(spreadsheetId: String, batchData: BatchExportData) async throws {
        // Create headers
        let headers = [["Session Name", "Created", "Completed", "Total Items", "Completed", "Failed"]]
        let sessionInfo = [[
            batchData.sessionName,
            batchData.createdAt.formatted(),
            batchData.completedAt?.formatted() ?? "",
            String(batchData.totalItems),
            String(batchData.completedItems),
            String(batchData.failedItems)
        ]]

        // Create item data
        let itemHeaders = [["Device Type", "Serial Number", "Confidence", "Status", "Timestamp", "Error"]]
        let itemData = batchData.items.map { item in
            [
                item.deviceType,
                item.serialNumber ?? "",
                item.confidence.map { String(format: "%.1f%%", $0 * 100) } ?? "",
                item.status,
                item.timestamp?.formatted() ?? "",
                item.errorMessage ?? ""
            ]
        }

        // Update spreadsheet with all data
        try await updateSpreadsheet(spreadsheetId: spreadsheetId, values: headers, range: "A1")
        try await updateSpreadsheet(spreadsheetId: spreadsheetId, values: sessionInfo, range: "A2")
        try await updateSpreadsheet(spreadsheetId: spreadsheetId, values: itemHeaders, range: "A4")
        try await updateSpreadsheet(spreadsheetId: spreadsheetId, values: itemData, range: "A5")
    }

    // MARK: - Utility Methods
    func signOut() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        currentUserEmail = nil
    }

    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw GoogleSheetsError.noRefreshToken
        }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
    }
}

// MARK: - Authentication Session Presentation (iOS)
#if os(iOS)
extension GoogleSheetsService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first!
    }
}
#endif

// MARK: - Error Types
enum GoogleSheetsError: Error {
    case notAuthenticated
    case noRefreshToken
    case invalidResponse
    case apiError(String)
}

// MARK: - Data Models

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct UserInfo: Codable {
    let id: String
    let email: String
    let verifiedEmail: Bool
    let name: String
    let givenName: String
    let familyName: String
    let picture: String
}

struct CreateSpreadsheetRequest: Codable {
    let properties: SpreadsheetProperties
}

struct SpreadsheetProperties: Codable {
    let title: String
}

struct CreateSpreadsheetResponse: Codable {
    let spreadsheetId: String
    let spreadsheetUrl: String
    let spreadsheet: GoogleSpreadsheet
}

struct GoogleSpreadsheet: Codable {
    let spreadsheetId: String
    let properties: SpreadsheetProperties
    let sheets: [Sheet]?
    let spreadsheetUrl: String
}

struct Sheet: Codable {
    let properties: SheetProperties
}

struct SheetProperties: Codable {
    let sheetId: Int
    let title: String
    let index: Int
    let sheetType: String
}

struct UpdateValuesRequest: Codable {
    let range: String
    let majorDimension: String
    let values: [[String]]
}

struct GetSpreadsheetResponse: Codable {
    let spreadsheet: GoogleSpreadsheet
}

struct ShareRequest: Codable {
    let role: String
    let type: String
    let emailAddress: String
}

// MARK: - Convenience Extensions
extension GoogleSheetsService {
    func createAndPopulateSpreadsheet(title: String, values: [[String]]) async throws -> String {
        let spreadsheet = try await createSpreadsheet(title: title)
        try await updateSpreadsheet(spreadsheetId: spreadsheet.spreadsheetId, values: values)
        return spreadsheet.spreadsheetUrl
    }

    func exportScanHistory(title: String, scanHistory: [ScanHistory]) async throws -> String {
        let headers = [["Device Type", "Serial Number", "Confidence", "Source", "Timestamp", "Validation"]]
        let data = scanHistory.map { scan in
            [
                scan.deviceType,
                scan.serial,
                String(format: "%.1f%%", scan.confidence * 100),
                scan.source,
                scan.timestamp.formatted(),
                scan.validationPassed ? "Valid" : "Invalid"
            ]
        }

        let values = headers + data
        return try await createAndPopulateSpreadsheet(title: title, values: values)
    }
}
