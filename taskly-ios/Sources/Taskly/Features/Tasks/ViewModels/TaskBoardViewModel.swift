import SwiftUI

@MainActor
final class TaskBoardViewModel: ObservableObject {
    enum BoardMode { case tasks, services }
    enum SortOption: String, CaseIterable {
        case newest = "newest"
        case priceLow = "price_low"
        case priceHigh = "price_high"

        var displayName: String {
            switch self {
            case .newest: return "Newest"
            case .priceLow: return "Price ↑"
            case .priceHigh: return "Price ↓"
            }
        }
    }

    @Published var boardMode: BoardMode = .tasks
    @Published var tasks: [TaskItem] = []
    @Published var services: [ServiceCard] = []
    @Published var isLoading = false
    @Published var selectedCategory: TaskCategory? = nil
    @Published var sortBy: SortOption = .newest

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var params: [String: Any] = ["sort": sortBy.rawValue]
            if let cat = selectedCategory { params["category"] = cat.rawValue }

            if boardMode == .tasks {
                let r: PageResponse<TaskItem> = try await NetworkManager.shared.request("/tasks", parameters: params)
                tasks = r.list
            } else {
                let r: PageResponse<ServiceCard> = try await NetworkManager.shared.request("/services", parameters: params)
                services = r.list
            }
        } catch {
            print("Board load error: \(error)")
        }
    }

    func applyFilter(category: TaskCategory?) {
        selectedCategory = category
        Task { await load() }
    }

    func applySort(_ sort: SortOption) {
        sortBy = sort
        Task { await load() }
    }
}
