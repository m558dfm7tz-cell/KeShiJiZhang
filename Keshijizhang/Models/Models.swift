import Foundation
import SwiftData

enum LessonKind: String, CaseIterable, Identifiable {
    case fixed
    case extra
    case makeup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "固定课"
        case .extra: return "加课"
        case .makeup: return "补课"
        }
    }
}

enum LessonStatus: String {
    case pending
    case completed
    case leave
}

enum OriginKind {
    static let studentSlot = "studentSlot"
    static let groupSlot = "groupSlot"
    static let groupHeadcount = "groupHeadcount"
    static let manual = "manual"
}

@Model
final class Organization {
    var uuid: UUID = UUID()
    var name: String = ""
    var contact: String = ""
    var phone: String = ""
    var settlement: String = "每月月底"
    var note: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Student.organization)
    var students: [Student] = []

    @Relationship(deleteRule: .nullify, inverse: \SmallGroup.organization)
    var groups: [SmallGroup] = []

    @Relationship(deleteRule: .nullify, inverse: \Lesson.organization)
    var billedLessons: [Lesson] = []

    init(
        name: String,
        contact: String = "",
        phone: String = "",
        settlement: String = "每月月底",
        note: String = ""
    ) {
        self.uuid = UUID()
        self.name = name
        self.contact = contact
        self.phone = phone
        self.settlement = settlement
        self.note = note
        self.createdAt = Date()
    }
}

@Model
final class SmallGroup {
    var uuid: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var basePrice: Double = 0
    var standardCount: Int = 0
    var perPersonDelta: Double = 0
    /// 已有小班默认仍按名字点名，避免升级后改掉原来的打卡方式。
    var rollByName: Bool = true
    var organization: Organization? = nil

    @Relationship(deleteRule: .nullify, inverse: \Student.smallGroup)
    var students: [Student] = []

    @Relationship(deleteRule: .cascade, inverse: \WeeklySlot.group)
    var slots: [WeeklySlot] = []

    @Relationship(deleteRule: .nullify, inverse: \Lesson.group)
    var classLessons: [Lesson] = []

    init(name: String) {
        self.uuid = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

@Model
final class Student {
    var uuid: UUID = UUID()
    var name: String = ""
    var parentPhone: String = ""
    var note: String = ""
    var paused: Bool = false
    var createdAt: Date = Date()

    var organization: Organization? = nil
    var smallGroup: SmallGroup? = nil

    @Relationship(deleteRule: .cascade, inverse: \WeeklySlot.student)
    var slots: [WeeklySlot] = []

    @Relationship(deleteRule: .cascade, inverse: \PriceRecord.student)
    var prices: [PriceRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \Lesson.student)
    var lessons: [Lesson] = []

    init(name: String, parentPhone: String = "", note: String = "", paused: Bool = false) {
        self.uuid = UUID()
        self.name = name
        self.parentPhone = parentPhone
        self.note = note
        self.paused = paused
        self.createdAt = Date()
    }
}

@Model
final class WeeklySlot {
    var uuid: UUID = UUID()
    var weekday: Int = 1
    var startMinutes: Int = 600
    var endMinutes: Int = 660
    var student: Student? = nil
    var group: SmallGroup? = nil

    init(weekday: Int, startMinutes: Int, endMinutes: Int) {
        self.uuid = UUID()
        self.weekday = weekday
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }
}

@Model
final class PriceRecord {
    var uuid: UUID = UUID()
    var unitPrice: Double = 0
    var effectiveFrom: Date = Date()
    var createdAt: Date = Date()
    var student: Student? = nil

    init(unitPrice: Double, effectiveFrom: Date) {
        self.uuid = UUID()
        self.unitPrice = unitPrice
        self.effectiveFrom = effectiveFrom
        self.createdAt = Date()
    }
}

@Model
final class Lesson {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var timeMinutes: Int = -1
    var amount: Double = 0
    var priceOverridden: Bool = false
    var kindRaw: String = LessonKind.fixed.rawValue
    var statusRaw: String = LessonStatus.completed.rawValue
    var paid: Bool = false
    var originKind: String = OriginKind.manual
    var originSlotKey: String = ""
    var groupName: String = ""
    var headcount: Int = 0
    var createdAt: Date = Date()
    var student: Student? = nil
    var group: SmallGroup? = nil
    var organization: Organization? = nil

    init() {
        self.uuid = UUID()
        self.createdAt = Date()
    }

    var kind: LessonKind {
        get { LessonKind(rawValue: kindRaw) ?? .fixed }
        set { kindRaw = newValue.rawValue }
    }

    var status: LessonStatus {
        get { LessonStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var hasTime: Bool { timeMinutes >= 0 }

    var countsTowardBill: Bool { status == .completed }

    var isClassHeadcount: Bool { originKind == OriginKind.groupHeadcount }

    var classHeadline: String {
        let name = groupName.isEmpty ? (group?.name ?? "小班") : groupName
        return "\(name) · \(max(headcount, 0)) 人 · \(CN.money(amount))"
    }
}

struct Engagement {
    var timeMinutes: Int?
    var title: String
}

extension Student {
    func effectivePrice(on date: Date) -> Double {
        let day = CN.startOfDay(date)
        var best: PriceRecord?
        for price in prices where price.effectiveFrom <= day {
            guard let current = best else {
                best = price
                continue
            }
            if price.effectiveFrom > current.effectiveFrom
                || (price.effectiveFrom == current.effectiveFrom && price.createdAt > current.createdAt) {
                best = price
            }
        }
        return best?.unitPrice ?? 0
    }

    var currentPrice: Double { effectivePrice(on: Date()) }

    var sortedSlots: [WeeklySlot] {
        slots.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            return $0.startMinutes < $1.startMinutes
        }
    }

    /// Compact schedule, e.g. 每周一 10:00、周三 10:00.
    var scheduleSummary: String {
        let list = sortedSlots
        guard !list.isEmpty else { return "" }
        return list.enumerated().map { index, slot in
            let prefix = index == 0 ? "每" : ""
            return "\(prefix)\(CN.weekdayShort(slot.weekday)) \(CN.hm(slot.startMinutes))"
        }.joined(separator: "、")
    }

    var weekdayListText: String {
        let names = sortedSlots.map { CN.weekdayShort($0.weekday) }
        var seen: [String] = []
        for name in names where !seen.contains(name) {
            seen.append(name)
        }
        return seen.joined(separator: "、")
    }

    func engagements(on date: Date) -> [Engagement] {
        let indexed = LessonDay.index(lessons, on: date)
        var items: [Engagement] = []
        items.reserveCapacity(indexed.lessons.count + slots.count)
        for lesson in indexed.lessons {
            items.append(
                Engagement(
                    timeMinutes: lesson.hasTime ? lesson.timeMinutes : nil,
                    title: "已有记录"
                )
            )
        }
        guard !paused else { return items }
        let weekday = CN.mondayBasedWeekday(date)
        for slot in slots where slot.weekday == weekday && !indexed.studentSlotKeys.contains(slot.uuid.uuidString) {
            items.append(Engagement(timeMinutes: slot.startMinutes, title: "固定课"))
        }
        if let group = smallGroup {
            for slot in group.slots where slot.weekday == weekday && !indexed.groupSlotKeys.contains(slot.uuid.uuidString) {
                items.append(Engagement(timeMinutes: slot.startMinutes, title: group.name))
            }
        }
        return items
    }

    func engagementCount(
        lessonCount: Int,
        studentSlotKeys: Set<String>,
        groupSlotKeys: Set<String>,
        weekday: Int
    ) -> Int {
        var count = lessonCount
        guard !paused else { return count }
        for slot in slots where slot.weekday == weekday && !studentSlotKeys.contains(slot.uuid.uuidString) {
            count += 1
        }
        if let group = smallGroup {
            for slot in group.slots where slot.weekday == weekday && !groupSlotKeys.contains(slot.uuid.uuidString) {
                count += 1
            }
        }
        return count
    }
}

extension SmallGroup {
    var sortedSlots: [WeeklySlot] {
        slots.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            return $0.startMinutes < $1.startMinutes
        }
    }

    var activeStudents: [Student] {
        students.filter { !$0.paused }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var scheduleSummary: String {
        sortedSlots.map {
            "每\(CN.weekdayShort($0.weekday)) \(CN.hm($0.startMinutes))"
        }.joined(separator: "、")
    }

    var usesConfiguredClassPrice: Bool {
        basePrice != 0 || perPersonDelta != 0
    }

    var usesNameRoll: Bool {
        rollByName && !activeStudents.isEmpty
    }

    /// 基础价格是 1 个人的价格。标准人数不参与计算。
    func classCharge(for count: Int) -> Double {
        let people = max(count, 1)
        let raw = basePrice + Double(people - 1) * perPersonDelta
        return max(0, round2(raw))
    }

    func syncMembersOrganization() {
        for student in students where student.organization?.uuid != organization?.uuid {
            student.organization = organization
        }
    }
}

extension Organization {
    var sortedStudents: [Student] {
        students.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
