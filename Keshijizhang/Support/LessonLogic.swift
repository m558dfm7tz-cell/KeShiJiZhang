import Foundation
import SwiftData

enum TodayEntry: Identifiable {
    case studentSlot(WeeklySlot, Student)
    case groupSlot(WeeklySlot, SmallGroup)
    case single(Lesson)
    case groupSession(slotKey: String, lessons: [Lesson], groupName: String, timeMinutes: Int)

    var id: String {
        switch self {
        case .studentSlot(let slot, _):
            return "slot-\(slot.uuid.uuidString)"
        case .groupSlot(let slot, _):
            return "group-\(slot.uuid.uuidString)"
        case .single(let lesson):
            return "lesson-\(lesson.uuid.uuidString)"
        case .groupSession(let key, _, _, _):
            return "session-\(key)"
        }
    }

    var sortMinutes: Int {
        switch self {
        case .studentSlot(let slot, _):
            return slot.startMinutes
        case .groupSlot(let slot, _):
            return slot.startMinutes
        case .single(let lesson):
            return lesson.hasTime ? lesson.timeMinutes : 24 * 60 + 1
        case .groupSession(_, _, _, let time):
            return time >= 0 ? time : 24 * 60 + 1
        }
    }

    var isDone: Bool {
        switch self {
        case .studentSlot, .groupSlot:
            return false
        case .single(let lesson):
            return lesson.status != .pending
        case .groupSession:
            return true
        }
    }
}

enum Agenda {
    static func entries(students: [Student], groups: [SmallGroup], on date: Date) -> [TodayEntry] {
        let day = CN.startOfDay(date)
        let weekday = CN.mondayBasedWeekday(day)
        var result: [TodayEntry] = []

        var grouped: [String: [Lesson]] = [:]
        for student in students {
            for lesson in student.lessons where CN.isSameDay(lesson.date, day) {
                if lesson.originKind == OriginKind.groupSlot, !lesson.originSlotKey.isEmpty {
                    grouped[lesson.originSlotKey, default: []].append(lesson)
                } else {
                    result.append(.single(lesson))
                }
            }
        }
        for (key, lessons) in grouped {
            let name = lessons.first?.groupName ?? "小班"
            let time = lessons.compactMap { $0.hasTime ? $0.timeMinutes : nil }.min() ?? -1
            result.append(.groupSession(slotKey: key, lessons: lessons, groupName: name, timeMinutes: time))
        }

        for student in students where !student.paused {
            for slot in student.slots where slot.weekday == weekday {
                let exists = student.lessons.contains {
                    CN.isSameDay($0.date, day)
                        && $0.originKind == OriginKind.studentSlot
                        && $0.originSlotKey == slot.uuid.uuidString
                }
                if !exists {
                    result.append(.studentSlot(slot, student))
                }
            }
        }

        for group in groups {
            let active = group.activeStudents
            guard !active.isEmpty else { continue }
            for slot in group.slots where slot.weekday == weekday {
                let key = slot.uuid.uuidString
                let exists = grouped[key] != nil || group.students.contains { student in
                    student.lessons.contains {
                        CN.isSameDay($0.date, day)
                            && $0.originKind == OriginKind.groupSlot
                            && $0.originSlotKey == key
                    }
                }
                if !exists {
                    result.append(.groupSlot(slot, group))
                }
            }
        }

        return result.sorted {
            if $0.sortMinutes != $1.sortMinutes { return $0.sortMinutes < $1.sortMinutes }
            return $0.id < $1.id
        }
    }
}

enum Billing {
    static func completed(_ lessons: [Lesson], inMonth month: Date) -> [Lesson] {
        lessons.filter { $0.countsTowardBill && CN.isSameMonth($0.date, month) }
    }

    static func receivable(_ lessons: [Lesson]) -> Double {
        Money.sum(lessons.filter(\.countsTowardBill).map(\.amount))
    }

    static func received(_ lessons: [Lesson]) -> Double {
        Money.sum(lessons.filter { $0.countsTowardBill && $0.paid }.map(\.amount))
    }

    static func unpaid(_ lessons: [Lesson]) -> Double {
        let due = receivable(lessons)
        let got = received(lessons)
        return max(0, round2(due - got))
    }

    static func priceText(_ lessons: [Lesson]) -> String {
        let done = lessons.filter(\.countsTowardBill)
        guard !done.isEmpty else { return "0 节" }
        let grouped = Dictionary(grouping: done) { round2($0.amount) }
        if grouped.count == 1, let price = grouped.keys.first {
            return "\(done.count) 节 · \(CN.money(price))/节"
        }
        let parts = grouped.keys.sorted().map { price in
            "\(grouped[price]?.count ?? 0) 节 × \(CN.money(price))"
        }
        return parts.joined(separator: " + ")
    }
}

enum LessonFactory {
    @discardableResult
    static func make(
        context: ModelContext,
        student: Student,
        date: Date,
        timeMinutes: Int?,
        amount: Double,
        overridden: Bool,
        kind: LessonKind,
        status: LessonStatus,
        originKind: String,
        originSlotKey: String = "",
        groupName: String = ""
    ) -> Lesson {
        let lesson = Lesson()
        lesson.date = CN.startOfDay(date)
        lesson.timeMinutes = timeMinutes ?? -1
        lesson.amount = round2(amount)
        lesson.priceOverridden = overridden
        lesson.kind = kind
        lesson.status = status
        lesson.paid = false
        lesson.originKind = originKind
        lesson.originSlotKey = originSlotKey
        lesson.groupName = groupName
        lesson.student = student
        context.insert(lesson)
        return lesson
    }

    static func completeStudentSlot(_ slot: WeeklySlot, student: Student, on day: Date, context: ModelContext) {
        let amount = student.effectivePrice(on: day)
        make(
            context: context,
            student: student,
            date: day,
            timeMinutes: slot.startMinutes,
            amount: amount,
            overridden: false,
            kind: .fixed,
            status: .completed,
            originKind: OriginKind.studentSlot,
            originSlotKey: slot.uuid.uuidString
        )
        try? context.save()
    }

    static func leaveStudentSlot(_ slot: WeeklySlot, student: Student, on day: Date, context: ModelContext) {
        make(
            context: context,
            student: student,
            date: day,
            timeMinutes: slot.startMinutes,
            amount: student.effectivePrice(on: day),
            overridden: false,
            kind: .fixed,
            status: .leave,
            originKind: OriginKind.studentSlot,
            originSlotKey: slot.uuid.uuidString
        )
        try? context.save()
    }

    static func undo(_ lesson: Lesson, context: ModelContext) {
        if lesson.originKind == OriginKind.manual {
            lesson.status = .pending
            lesson.paid = false
        } else {
            context.delete(lesson)
        }
        try? context.save()
    }

    static func setLeave(_ lesson: Lesson, context: ModelContext) {
        lesson.status = .leave
        lesson.paid = false
        try? context.save()
    }

    static func restoreCompleted(_ lesson: Lesson, context: ModelContext) {
        lesson.status = .completed
        try? context.save()
    }

    static func togglePaid(_ lesson: Lesson, context: ModelContext) {
        guard lesson.countsTowardBill else { return }
        lesson.paid.toggle()
        try? context.save()
    }

    static func markPaid(_ lessons: [Lesson], paid: Bool, context: ModelContext) {
        for lesson in lessons where lesson.countsTowardBill {
            lesson.paid = paid
        }
        try? context.save()
    }

    static func updateAmount(_ lesson: Lesson, amount: Double, context: ModelContext) {
        lesson.amount = round2(amount)
        lesson.priceOverridden = true
        try? context.save()
    }

    static func delete(_ lesson: Lesson, context: ModelContext) {
        context.delete(lesson)
        try? context.save()
    }

    static func applyGroupRoll(
        context: ModelContext,
        group: SmallGroup,
        slot: WeeklySlot,
        day: Date,
        attending: Set<UUID>,
        paid: Set<UUID>
    ) {
        let members = group.activeStudents
        let key = slot.uuid.uuidString
        for student in members {
            let existing = student.lessons.first {
                CN.isSameDay($0.date, day)
                    && $0.originKind == OriginKind.groupSlot
                    && $0.originSlotKey == key
            }
            let isAttending = attending.contains(student.uuid)
            if let existing {
                existing.groupName = group.name
                existing.timeMinutes = slot.startMinutes
                existing.kind = .fixed
                if isAttending {
                    if existing.status == .leave && !existing.priceOverridden {
                        existing.amount = student.effectivePrice(on: day)
                    }
                    existing.status = .completed
                    existing.paid = paid.contains(student.uuid)
                } else {
                    existing.status = .leave
                    existing.paid = false
                }
            } else if isAttending {
                let lesson = make(
                    context: context,
                    student: student,
                    date: day,
                    timeMinutes: slot.startMinutes,
                    amount: student.effectivePrice(on: day),
                    overridden: false,
                    kind: .fixed,
                    status: .completed,
                    originKind: OriginKind.groupSlot,
                    originSlotKey: key,
                    groupName: group.name
                )
                lesson.paid = paid.contains(student.uuid)
            } else {
                make(
                    context: context,
                    student: student,
                    date: day,
                    timeMinutes: slot.startMinutes,
                    amount: student.effectivePrice(on: day),
                    overridden: false,
                    kind: .fixed,
                    status: .leave,
                    originKind: OriginKind.groupSlot,
                    originSlotKey: key,
                    groupName: group.name
                )
            }
        }
        try? context.save()
    }

    static func undoGroup(slotKey: String, lessons: [Lesson], context: ModelContext) {
        for lesson in lessons {
            context.delete(lesson)
        }
        try? context.save()
    }
}
