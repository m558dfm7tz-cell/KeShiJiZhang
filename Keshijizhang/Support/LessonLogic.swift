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

enum LessonDay {
    struct Index {
        var lessons: [Lesson] = []
        var studentSlotKeys: Set<String> = []
        var groupSlotKeys: Set<String> = []
    }

    static func index(_ lessons: [Lesson], on date: Date) -> Index {
        let day = CN.startOfDay(date)
        var indexed = Index()
        indexed.lessons.reserveCapacity(4)
        for lesson in lessons where CN.isSameDay(lesson.date, day) {
            indexed.lessons.append(lesson)
            if lesson.originKind == OriginKind.studentSlot {
                indexed.studentSlotKeys.insert(lesson.originSlotKey)
            } else if lesson.originKind == OriginKind.groupSlot {
                indexed.groupSlotKeys.insert(lesson.originSlotKey)
            }
        }
        return indexed
    }
}

struct AgendaBoard {
    var entries: [TodayEntry]
    var doneLessons: [Lesson]
    var leaveLessons: [Lesson]
    var engagementCounts: [UUID: Int]
}

enum Agenda {
    static func board(students: [Student], groups: [SmallGroup], on date: Date) -> AgendaBoard {
        let day = CN.startOfDay(date)
        let weekday = CN.mondayBasedWeekday(day)
        var entries: [TodayEntry] = []
        var grouped: [String: [Lesson]] = [:]
        var groupKeysByStudent: [UUID: Set<String>] = [:]
        var seenLessons = Set<UUID>()
        var done: [Lesson] = []
        var leave: [Lesson] = []
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(students.count)

        for student in students {
            let indexed = LessonDay.index(student.lessons, on: day)
            groupKeysByStudent[student.uuid] = indexed.groupSlotKeys
            counts[student.uuid] = student.engagementCount(
                lessonCount: indexed.lessons.count,
                studentSlotKeys: indexed.studentSlotKeys,
                groupSlotKeys: indexed.groupSlotKeys,
                weekday: weekday
            )
            for lesson in indexed.lessons where seenLessons.insert(lesson.uuid).inserted {
                if lesson.status == .completed {
                    done.append(lesson)
                } else if lesson.status == .leave {
                    leave.append(lesson)
                }
                if lesson.originKind == OriginKind.groupSlot,
                   !lesson.originSlotKey.isEmpty,
                   lesson.status != .pending {
                    grouped[lesson.originSlotKey, default: []].append(lesson)
                } else {
                    entries.append(.single(lesson))
                }
            }
            if !student.paused {
                for slot in student.slots where slot.weekday == weekday && !indexed.studentSlotKeys.contains(slot.uuid.uuidString) {
                    entries.append(.studentSlot(slot, student))
                }
            }
        }

        done.sort { $0.timeMinutes < $1.timeMinutes }
        leave.sort { $0.timeMinutes < $1.timeMinutes }

        for (key, lessons) in grouped {
            let name = lessons.first?.groupName ?? "小班"
            let time = lessons.compactMap { $0.hasTime ? $0.timeMinutes : nil }.min() ?? -1
            entries.append(.groupSession(slotKey: key, lessons: lessons, groupName: name, timeMinutes: time))
        }

        for group in groups {
            guard !group.activeStudents.isEmpty else { continue }
            for slot in group.slots where slot.weekday == weekday {
                let key = slot.uuid.uuidString
                let exists = grouped[key] != nil || group.students.contains { student in
                    groupKeysByStudent[student.uuid]?.contains(key) == true
                }
                if !exists {
                    entries.append(.groupSlot(slot, group))
                }
            }
        }

        entries.sort {
            if $0.sortMinutes != $1.sortMinutes { return $0.sortMinutes < $1.sortMinutes }
            return $0.id < $1.id
        }
        return AgendaBoard(
            entries: entries,
            doneLessons: done,
            leaveLessons: leave,
            engagementCounts: counts
        )
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

    @discardableResult
    static func completeStudentSlot(
        _ slot: WeeklySlot,
        student: Student,
        on day: Date,
        context: ModelContext,
        persists: Bool = true
    ) -> Lesson {
        let amount = student.effectivePrice(on: day)
        let lesson = make(
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
        if persists { try? context.save() }
        return lesson
    }

    @discardableResult
    static func leaveStudentSlot(
        _ slot: WeeklySlot,
        student: Student,
        on day: Date,
        context: ModelContext,
        persists: Bool = true
    ) -> Lesson {
        let lesson = make(
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
        if persists { try? context.save() }
        return lesson
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

    static func setLeave(_ lesson: Lesson, context: ModelContext, persists: Bool = true) {
        lesson.status = .leave
        lesson.paid = false
        if persists { try? context.save() }
    }

    static func restoreCompleted(_ lesson: Lesson, context: ModelContext, persists: Bool = true) {
        lesson.status = .completed
        if persists { try? context.save() }
    }

    static func togglePaid(_ lesson: Lesson, context: ModelContext, persists: Bool = true) {
        guard lesson.countsTowardBill else { return }
        lesson.paid.toggle()
        if persists { try? context.save() }
    }

    static func markPaid(_ lessons: [Lesson], paid: Bool, context: ModelContext, persists: Bool = true) {
        for lesson in lessons where lesson.countsTowardBill {
            lesson.paid = paid
        }
        if persists { try? context.save() }
    }

    static func updateAmount(_ lesson: Lesson, amount: Double, context: ModelContext, persists: Bool = true) {
        lesson.amount = round2(amount)
        lesson.priceOverridden = true
        if persists { try? context.save() }
    }

    static func delete(_ lesson: Lesson, context: ModelContext, persists: Bool = true) {
        context.delete(lesson)
        if persists { try? context.save() }
    }

    @discardableResult
    static func applyGroupRoll(
        context: ModelContext,
        group: SmallGroup,
        slot: WeeklySlot,
        day: Date,
        attending: Set<UUID>,
        paid: Set<UUID>,
        persists: Bool = true
    ) -> GroupRollApply {
        var created: [Lesson] = []
        var previous: [(lesson: Lesson, statusRaw: String, paid: Bool)] = []
        let members = group.activeStudents
        let key = slot.uuid.uuidString
        for student in members {
            let indexed = LessonDay.index(student.lessons, on: day)
            let existing = indexed.lessons.first {
                $0.originKind == OriginKind.groupSlot && $0.originSlotKey == key
            }
            let isAttending = attending.contains(student.uuid)
            if let existing {
                previous.append((lesson: existing, statusRaw: existing.statusRaw, paid: existing.paid))
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
                created.append(lesson)
            } else {
                let lesson = make(
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
                created.append(lesson)
            }
        }
        if persists { try? context.save() }
        return GroupRollApply(created: created, previous: previous)
    }

    static func undoGroup(slotKey: String, lessons: [Lesson], context: ModelContext) {
        for lesson in lessons {
            context.delete(lesson)
        }
        try? context.save()
    }
}

struct GroupRollApply {
    var created: [Lesson]
    var previous: [(lesson: Lesson, statusRaw: String, paid: Bool)]
}

struct LessonTickUndo: Identifiable {
    var id = UUID()
    var message: String
    var created: [Lesson]
    var previous: [(lesson: Lesson, statusRaw: String, paid: Bool)]
    var entryIDs: [String] = []
}

@MainActor
enum Persistence {
    private static var tokens: [ObjectIdentifier: Int] = [:]

    static func saveSoon(_ context: ModelContext, after nanoseconds: UInt64 = 80_000_000) {
        let key = ObjectIdentifier(context)
        tokens[key, default: 0] += 1
        let token = tokens[key] ?? 0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard tokens[key] == token else { return }
            try? context.save()
        }
    }

    static func saveNow(_ context: ModelContext) {
        let key = ObjectIdentifier(context)
        tokens[key, default: 0] += 1
        try? context.save()
    }
}

extension ModelContext {
    func saveSoon(after nanoseconds: UInt64 = 80_000_000) {
        Persistence.saveSoon(self, after: nanoseconds)
    }

    func saveNow() {
        Persistence.saveNow(self)
    }
}
