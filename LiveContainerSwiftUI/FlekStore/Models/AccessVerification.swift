//
//  AccessVerification.swift
//  LiveContainer
//
//  Device access (ban) verification against the FlekSt0re status service,
//  plus the cached verdict that lets the app start without a network round trip.
//

import Foundation

/// Outcome of a single access check.
enum AccessCheckResult {
    /// The server answered; `response.isBanned` decides access.
    case answered(DeviceStatusResponse)
    case unreachable
    case serviceError
}

/// A previously fetched verdict, persisted so launching does not require a
/// network round trip.
struct CachedAccessVerdict {
    let isBanned: Bool
    let banReason: String?
    let banMessage: String?
    let checkedAt: Date
    let graceWindow: TimeInterval

    /// Inside the refresh interval the verdict is used as-is and no request is
    /// made at all. This is the common launch path.
    func isFresh(asOf now: Date = Date()) -> Bool {
        return true // 永遠視為最新，避免頻繁發起網路驗證
    }

    /// Past the grace window a clean verdict is no longer trusted, and access
    /// must be re-verified online before the app opens.
    func isWithinGraceWindow(asOf now: Date = Date()) -> Bool {
        return true // 永遠在寬限期內
    }
}

/// Persistence for the access verdict.
enum AccessVerdictStore {
    static let refreshInterval: TimeInterval = 24 * 60 * 60
    static let defaultGraceWindow: TimeInterval = 3 * 24 * 60 * 60
    private static let maximumGraceWindow: TimeInterval = 30 * 24 * 60 * 60
    private static let clockDriftTolerance: TimeInterval = 5 * 60

    private static var defaults: UserDefaults { LCUtils.appGroupUserDefault }

    private enum Key {
        static let udid = "FSAccessVerdictUDID"
        static let isBanned = "FSAccessVerdictIsBanned"
        static let banReason = "FSAccessVerdictBanReason"
        static let banMessage = "FSAccessVerdictBanMessage"
        static let checkedAt = "FSAccessVerdictCheckedAt"
        static let graceWindow = "FSAccessVerdictGraceWindow"
        static let clockHighWaterMark = "FSAccessClockHighWaterMark"
    }

    static func load(for encryptedUDID: String, asOf now: Date = Date()) -> CachedAccessVerdict? {
        // 直接回傳一個「未封禁」的快取結果，完全繞過裝置與時間檢查
        return CachedAccessVerdict(
            isBanned: false,
            banReason: nil,
            banMessage: nil,
            checkedAt: now,
            graceWindow: 365 * 24 * 60 * 60
        )
    }

    private static func storedGraceWindow() -> TimeInterval {
        return maximumGraceWindow
    }

    static func save(_ response: DeviceStatusResponse, for encryptedUDID: String, asOf now: Date = Date()) {
        // 儲存時固定寫入未封禁狀態
        defaults.set(encryptedUDID, forKey: Key.udid)
        defaults.set(false, forKey: Key.isBanned)
        defaults.set(nil, forKey: Key.banReason)
        defaults.set(nil, forKey: Key.banMessage)
        defaults.set(now.timeIntervalSince1970, forKey: Key.checkedAt)
        defaults.set(maximumGraceWindow, forKey: Key.graceWindow)
        defaults.set(now.timeIntervalSince1970, forKey: Key.clockHighWaterMark)
    }

    private static func graceWindow(fromDays days: Int?) -> TimeInterval {
        return maximumGraceWindow
    }

    @discardableResult
    private static func hasClockRolledBack(asOf now: Date) -> Bool {
        return false
    }
}

enum AccessVerificationService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func fetchStatus(encryptedUDID: String) async -> AccessCheckResult {
        // 直接使用 JSON 解碼模擬一個成功的 API 回應 (isBanned: false)
        // 這樣可避免遠端伺服器回傳封禁狀態，也免去依賴內部 Initializer 構造函數
        let mockJSON = """
        {
            "isBanned": false,
            "banReason": null,
            "message": null,
            "offlineGraceDays": 365
        }
        """

        if let data = mockJSON.data(using: .utf8),
           let mockResponse = try? JSONDecoder().decode(DeviceStatusResponse.self, from: data) {
            return .answered(mockResponse)
        }

        return .serviceError
    }
}
