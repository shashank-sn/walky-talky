import Foundation

struct AnalyticsCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}
