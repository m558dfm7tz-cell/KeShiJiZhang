import SwiftData
import SwiftUI

private enum BatchMode: String, CaseIterable, Identifiable {
    case student
    case org
    var id: String { rawValue }
    var title: String { self == .student ? "学生" : "机构" }
}

private enum OrgPick: Hashable {
    case org(UUID)
    case personal
}

struct BatchPaySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Student.name) private var students: [Student]
    @Query(sort: \Organization.name) private var orgs: [Organization]
    @Query(filter: #Predicate<Lesson> { $0.originKind == "groupHeadcount" }, sort: \Lesson.date)
    private var classLessonSource: [Lesson]

    var month: Date

    @State private var mode: BatchMode = .student
    @State private var studentID: UUID?
    @State private var orgPick: OrgPick?
    @State private var showPicker = false
    @State private var visibleMonth: Date
    @State private var rangeStart: Date
    @State private var rangeEnd: Date
    @State private var anchor: Date?

    init(month: Date) {
        self.month = month
        let start = CN.startOfMonth(month)
        let today = CN.startOfDay(Date())
        let end = CN.isSameMonth(today, month) ? today : start
        _visibleMonth = State(initialValue: start)
        _rangeStart = State(initialValue: start)
        _rangeEnd = State(initialValue: end)
    }

    private var targetName: String {
        switch mode {
        case .student:
            return students.first { $0.uuid == studentID }?.name ?? "未选学生"
        case .org:
            switch orgPick {
            case .org(let id):
                return orgs.first { $0.uuid == id }?.name ?? "未选机构"
            case .personal:
                return "私教学生"
            case nil:
                return "未选机构"
            }
        }
    }

    private func rangedLessons() -> [Lesson] {
        let start = CN.startOfDay(min(rangeStart, rangeEnd))
        let end = CN.startOfDay(max(rangeStart, rangeEnd))
        var seen = Set<UUID>()
        var list: [Lesson] = []
        for student in students where includes(student) {
            for lesson in student.lessons {
                let day = CN.startOfDay(lesson.date)
                guard day >= start, day <= end, seen.insert(lesson.uuid).inserted else { continue }
                if lesson.countsTowardBill || lesson.status == .pending {
                    list.append(lesson)
                }
            }
        }
        for lesson in classLessonSource where lesson.countsTowardBill && includesClass(lesson) {
            let day = CN.startOfDay(lesson.date)
            guard day >= start, day <= end, seen.insert(lesson.uuid).inserted else { continue }
            list.append(lesson)
        }
        return list
    }

    private func includesClass(_ lesson: Lesson) -> Bool {
        let orgID = lesson.organization?.uuid ?? lesson.group?.organization?.uuid
        switch mode {
        case .student:
            return false
        case .org:
            switch orgPick {
            case .org(let id):
                return orgID == id
            case .personal:
                return orgID == nil
            case nil:
                return false
            }
        }
    }

    var body: some View {
        let ranged = rangedLessons()
        let taught = ranged.filter(\.countsTowardBill)
        let pendingCount = ranged.reduce(into: 0) { count, lesson in
            if lesson.status == .pending { count += 1 }
        }
        let unpaidLessons = taught.filter { !$0.paid }
        return NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        FormCard {
                            HStack {
                                Text("对象")
                                Spacer()
                                Picker("对象", selection: $mode) {
                                    ForEach(BatchMode.allCases) { item in
                                        Text(item.title).tag(item)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            FormDivider()
                            Button {
                                showPicker = true
                            } label: {
                                ValueRow(title: mode.title, value: targetName)
                            }
                            .buttonStyle(.plain)
                        }

                        FormCard {
                            HStack {
                                Text("从")
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(CN.monthDay(min(rangeStart, rangeEnd)))
                                    .foregroundStyle(Theme.blue)
                                    .fontWeight(.semibold)
                                Text("到")
                                    .foregroundStyle(Theme.secondary)
                                    .padding(.leading, 12)
                                Spacer()
                                Text(CN.monthDay(max(rangeStart, rangeEnd)))
                                    .foregroundStyle(Theme.blue)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                        }

                        Card {
                            MonthGrid(visibleMonth: $visibleMonth, face: face, onTap: tap)
                        }

                        Card {
                            VStack(spacing: 8) {
                                Text("这段时间\(targetName)共上 \(taught.count) 节，其中未收")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.secondary)
                                    .multilineTextAlignment(.center)
                                Text("\(unpaidLessons.count) 节 · \(CN.money(Billing.receivable(unpaidLessons)))")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(unpaidLessons.isEmpty ? Theme.secondary : Theme.red)
                                if pendingCount > 0 {
                                    Text("另有 \(pendingCount) 节已排期但还没打卡，不计入收款")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        FillButton(
                            title: "全部标为已收",
                            color: Theme.green,
                            disabled: unpaidLessons.isEmpty,
                            action: markAll
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("按日期收款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if studentID == nil {
                    studentID = students.first?.uuid
                }
                if orgPick == nil {
                    if let org = orgs.first {
                        orgPick = .org(org.uuid)
                    } else if students.contains(where: { $0.organization == nil }) {
                        orgPick = .personal
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                picker
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var picker: some View {
        NavigationStack {
            List {
                if mode == .student {
                    Section("学生") {
                        if students.isEmpty {
                            Text("还没有学生")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(students, id: \.uuid) { student in
                            Button {
                                studentID = student.uuid
                                showPicker = false
                            } label: {
                                HStack {
                                    Text(student.name)
                                    Spacer()
                                    if student.uuid == studentID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Section("机构") {
                        ForEach(orgs, id: \.uuid) { org in
                            Button {
                                orgPick = .org(org.uuid)
                                showPicker = false
                            } label: {
                                HStack {
                                    Text(org.name)
                                    Spacer()
                                    if orgPick == .org(org.uuid) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        if students.contains(where: { $0.organization == nil }) {
                            Button {
                                orgPick = .personal
                                showPicker = false
                            } label: {
                                HStack {
                                    Text("私教学生")
                                    Spacer()
                                    if orgPick == .personal {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(mode == .student ? "选择学生" : "选择机构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showPicker = false }
                }
            }
        }
    }

    private func includes(_ student: Student) -> Bool {
        switch mode {
        case .student:
            return student.uuid == studentID
        case .org:
            switch orgPick {
            case .org(let id):
                return student.organization?.uuid == id
            case .personal:
                return student.organization == nil
            case nil:
                return false
            }
        }
    }

    private func face(_ date: Date) -> DayFace {
        let day = CN.startOfDay(date)
        let start = CN.startOfDay(min(rangeStart, rangeEnd))
        let end = CN.startOfDay(max(rangeStart, rangeEnd))
        if day == start && day == end { return .rangeSingle }
        if day == start { return .rangeStart }
        if day == end { return .rangeEnd }
        if day > start && day < end { return .rangeMiddle }
        if CN.isSameDay(day, Date()) { return .today }
        return .plain
    }

    private func tap(_ day: Date) {
        if let anchor {
            rangeStart = min(anchor, day)
            rangeEnd = max(anchor, day)
            self.anchor = nil
        } else {
            anchor = day
            rangeStart = day
            rangeEnd = day
        }
    }

    private func markAll() {
        let unpaid = rangedLessons().filter { $0.countsTowardBill && !$0.paid }
        LessonFactory.markPaid(unpaid, paid: true, context: context, persists: false)
        context.saveSoon()
        dismiss()
    }
}
