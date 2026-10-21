import Foundation

enum CheckInDay {
    static func number(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Int {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        // Map the local calendar date onto a UTC date so DST's 23/25-hour days are still one day apart.
        let components = local.dateComponents([.year, .month, .day], from: date)
        return Int(utc.date(from: components)!.timeIntervalSince1970 / 86400)
    }
}

struct CollectionProgress: Codable, Equatable {
    static let milestones = [5, 10, 25, 50, 100, 150, 200, 250, 300, 350, 365, 400, 450, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950, 1000, 1100, 1250, 1400, 1500]
    var owned: [CompanionKind] = []
    var names: [String: String] = [:]
    var lastCheckInDay: Int?
    var streak = 0
    var bestStreak = 0
    var totalDays = 0
    var earnedMilestones: Set<Int> = []
    var eggs: [Int] = []
    var restoresUsed = 0
    var pendingCheckInDay: Int?
    static let lifetimeRestores = 3
    var restoresRemaining: Int { max(0, Self.lifetimeRestores - restoresUsed) }

    func canOfferRestore(on day: Int) -> Bool {
        guard let last = lastCheckInDay else { return false }
        return day > last + 1 && streak > 0 && restoresRemaining > 0
    }

    func currentStreak(on day: Int) -> Int {
        guard let last = lastCheckInDay, day <= last + 1 else { return 0 }
        return streak
    }
    var nextMilestone: Int? { Self.milestones.first { !earnedMilestones.contains($0) } }

    @discardableResult mutating func checkIn(on day: Int, restore: Bool = false) -> Int? {
        // Repeated taps, relaunches, or turning the clock back cannot award another check-in.
        if let last = lastCheckInDay, day <= last { return nil }
        let restoreGap = restore && canOfferRestore(on: day)
        if restoreGap { restoresUsed += 1 }
        streak = lastCheckInDay.map { day == $0 + 1 || restoreGap ? streak + 1 : 1 } ?? 1
        pendingCheckInDay = nil
        lastCheckInDay = day
        totalDays += 1
        bestStreak = max(bestStreak, streak)
        if Self.milestones.contains(streak), !earnedMilestones.contains(streak), owned.count + eggs.count < CompanionKind.allCases.count {
            earnedMilestones.insert(streak)
            eggs.append(streak)
            return streak
        }
        return nil
    }
    var displayOrder: [CompanionKind] { owned + unowned }
    var unowned: [CompanionKind] { CompanionKind.allCases.filter { !owned.contains($0) } }
    mutating func hatch(_ kind: CompanionKind, free: Bool) -> Bool {
        guard !owned.contains(kind), free ? owned.isEmpty : !eggs.isEmpty else { return false }
        if !free { eggs.removeFirst() }
        owned.append(kind)
        names[kind.rawValue] = kind.defaultName
        return true
    }
}
