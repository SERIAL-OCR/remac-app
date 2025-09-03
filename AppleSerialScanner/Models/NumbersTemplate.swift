import Foundation

// MARK: - Numbers Template
struct NumbersTemplate: Codable, Equatable {
    let name: String
    let includeCharts: Bool
    let includeStatistics: Bool
    let colorScheme: ColorScheme
    
    enum ColorScheme: String, Codable {
        case light
        case dark
        case auto
    }
    
    static let standard = NumbersTemplate(
        name: "Standard",
        includeCharts: true,
        includeStatistics: true,
        colorScheme: .auto
    )
    
    static let minimal = NumbersTemplate(
        name: "Minimal",
        includeCharts: false,
        includeStatistics: false,
        colorScheme: .light
    )
    
    static let analytics = NumbersTemplate(
        name: "Analytics",
        includeCharts: true,
        includeStatistics: true,
        colorScheme: .light
    )
}
