import Foundation

struct KimiUsageData: Codable, Equatable {
    let cashBalance: Double      // available cash balance (CNY)
    let voucherBalance: Double   // available voucher/credits balance
    let totalBalance: Double     // cash + voucher
    let fetchedAt: Date

    static let empty = KimiUsageData(
        cashBalance: 0,
        voucherBalance: 0,
        totalBalance: 0,
        fetchedAt: .distantPast
    )
}
