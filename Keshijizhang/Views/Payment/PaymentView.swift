import SwiftData
import SwiftUI

private enum PaySegment: String, CaseIterable, Identifiable {
    case unpaid
    case paid
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unpaid: return "未收"
        case .paid: return "已收"
        case .all: return "全部"
        }
    }
}

private struct PayChip: Identifiable, Hashable {
    enum Kind: Hashable {
        case all
        case org(UUID)
        case personal
        case student(UUID)
    }

    var id: String
    var kind: Kind
    var title: String
}

struct PaymentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \Organization.createdAt) private var orgs: [Organization]

    @State private var month = CN.startOfMonth(Date())
    @State private var chip = PayChip(id: "all", kind: .all, title: "全部")
    @State private var segment: PaySegment = .unpaid
    @State private var selection: Set<UUID> = []
    @State private var showBatch = false

    private var chips: [PayChip] {
        var items = [PayChip(id: "all", kind: .all, title: "全部")]
        for org in orgs.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            items.append(PayChip(id: "org-\(org.uuid.uuidString)", kind: .org(org.uuid), title: org.name))
        }
        if students.contains(where: { $0.organization == nil }) {
            items.append(PayChip(id: "personal", kind: .personal, title: "私教"))
        }
        for student in students.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            items.append(PayChip(id: "stu-\(student.uuid.uuidString)", kind: .student(student.uuid), title: student.name))
        }
        return items
    }

    private var monthLessons: [Lesson] {
        var seen = Set<UUID>()
        var list: [Lesson] = []
        for student in students {
            guard matches(student) else { continue }
            for lesson in student.lessons where lesson.countsTowardBill && CN.isSameMonth(lesson.date, month) {
                if seen.insert(lesson.uuid).inserted {
                    list.append(lesson)
                }
            }
        }
        return list.sorted { lhs, rhs in
            if !CN.isSameDay(lhs.date, rhs.date) { return lhs.date > rhs.date }
            return lhs.timeMinutes > rhs.timeMinutes
        }
    }

    private var visibleLessons: [Lesson] {
        switch segment {
        case .unpaid: return monthLessons.filter { !$0.paid }
        case .paid: return monthLessons.filter(\.paid)
        case .all: return monthLessons
        }
    }

    private var unpaidTotal: Double {
        Billing.unpaid(monthLessons)
    }

    private var selectedLessons: [Lesson] {
        monthLessons.filter { selection.contains($0.uuid) && !$0.paid }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("收款")
                            .font(.system(size: 34, weight: .bold))
                        HStack(spacing: 8) {
                            MonthSwitcher(title: CN.monthTitle(month)) {
                                changeMonth(-1)
                            } onNext: {
                                changeMonth(1)
                            }
                            Text("·")
                                .foregroundStyle(Theme.secondary)
                            Text("未收合计")
                                .foregroundStyle(Theme.secondary)
                            Text(CN.money(unpaidTotal))
                                .foregroundStyle(Theme.red)
                        }
                        .font(.system(size: 15, weight: .medium))
                    }

                    ChipScroll(items: chips, isSelected: { $0.kind == chip.kind }, action: { item in
                        chip = item
                        selection.removeAll()
                    }) { item in
                        Text(item.title)
                    }

                    SegmentTabs(items: PaySegment.allCases, title: { $0.title }, selection: $segment)
                        .onChange(of: segment) { _, _ in
                            selection.removeAll()
                        }

                    Button {
                        showBatch = true
                    } label: {
                        Card {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Theme.blue)
                                Text("按日期批量收款")
                                    .font(.system(size: 16, weight: .medium))
                                Spacer()
                                Text("选择日期")
                                    .foregroundStyle(Theme.blue)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.blue.opacity(0.7))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if visibleLessons.isEmpty {
                        Card {
                            EmptyHint(
                                title: emptyTitle,
                                message: students.isEmpty ? "先到「管理」添加学生并记下上课，这里才会出现要收的钱。" : "换个月份、学生，或切到「全部」看看。"
                            )
                        }
                    } else {
                        ForEach(visibleLessons, id: \.uuid) { lesson in
                            lessonRow(lesson)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !selectedLessons.isEmpty {
                HStack(spacing: 12) {
                    Text("已勾选 \(selectedLessons.count) 节 · \(CN.money(Billing.receivable(selectedLessons)))")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button {
                        LessonFactory.markPaid(selectedLessons, paid: true, context: context)
                        selection.removeAll()
                    } label: {
                        Text("确认收款")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.green, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.white)
            }
        }
        .sheet(isPresented: $showBatch) {
            BatchPaySheet(month: month)
        }
    }

    private var emptyTitle: String {
        switch segment {
        case .unpaid: return "这个范围没有未收的课"
        case .paid: return "这个范围还没有已收的课"
        case .all: return "这个范围没有已上完的课"
        }
    }

    private func matches(_ student: Student) -> Bool {
        switch chip.kind {
        case .all:
            return true
        case .org(let id):
            return student.organization?.uuid == id
        case .personal:
            return student.organization == nil
        case .student(let id):
            return student.uuid == id
        }
    }

    private func changeMonth(_ delta: Int) {
        month = CN.shiftMonth(month, by: delta)
        selection.removeAll()
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        let chosen = selection.contains(lesson.uuid)
        let emphasized = lesson.paid || chosen
        return Card {
            HStack(spacing: 12) {
                Button {
                    toggle(lesson)
                } label: {
                    CheckCircle(checked: lesson.paid || chosen)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(CN.listDay(lesson.date)) · \(lesson.student?.name ?? "")")
                        .font(.system(size: 16, weight: .semibold))
                    Text(detail(lesson))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(CN.money(lesson.amount))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(emphasized ? Theme.green : Color.primary)
            }
        }
    }

    private func detail(_ lesson: Lesson) -> String {
        var parts: [String] = []
        if lesson.hasTime { parts.append(CN.hm(lesson.timeMinutes)) }
        if lesson.originKind == OriginKind.groupSlot, !lesson.groupName.isEmpty {
            parts.append(lesson.groupName)
        } else if lesson.kind == .fixed {
            parts.append("一对一")
        } else {
            parts.append(lesson.kind.title)
        }
        if lesson.priceOverridden { parts.append("改价") }
        return parts.joined(separator: " ")
    }

    private func toggle(_ lesson: Lesson) {
        if lesson.paid {
            lesson.paid = false
            selection.remove(lesson.uuid)
            try? context.save()
        } else if selection.contains(lesson.uuid) {
            selection.remove(lesson.uuid)
        } else {
            selection.insert(lesson.uuid)
        }
    }
}
