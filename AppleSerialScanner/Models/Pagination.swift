import Foundation

struct Pagination: Codable {
    let currentPage: Int
    let totalPages: Int
    let itemsPerPage: Int
}
