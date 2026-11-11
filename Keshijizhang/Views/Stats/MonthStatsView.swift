import SwiftData
import SwiftUI

private enum StatsMode: String, CaseIterable, Identifiable {
    case student
    case org
    var id: String { rawValue }
    var title: String { self == .student ? "按学生" : "按机构" }
}

private struct StudentStat: Identifiable {
    var id: UUID
    var student: Student
    var lessons: [Lesson]
    var receivable: Double
    var unpaid: Double
}

private struct OrgStat: Identifiable {
    var id: String
    var title: String
    var color: Color
    var mark: String
    var rows: [StudentStat]
    var isPersonal: Bool
    var organization: Organization?

    var receivable: Double { Money.sum(rows.map(\.receivable)) }
    var unpaid: Double { Money.sum(rows.map(\.unpaid)) }
    var lessons: [Lesson] { rows.flatMap(\.lessons) }
}

struct MonthStatsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \Organization.createdAt) private var organizations: [Organization]

    @State private var month = CN.startOfMonth(Date())
    @State private var mode: StatsMode = .student

    private var studentStats: [StudentStat] {
        students.map { student in
            let lessons = student.lessons.filter { $0.countsTowardBill && CN.isSameMonth($0.date, month) }
            let unique = dedupe(lessons)
            return StudentStat(
                id: student.uuid,
                student: student,
                lessons: unique,
                receivable: Billing.receivable(unique),
                unpaid: Billing.unpaid(unique)
            )
        }
        .filter { !$0.lessons.isEmpty }
        .sorted { lhs, rhs in
            if lhs.unpaid != rhs.unpaid { return lhs.unpaid > rhs.unpaid }
            return lhs.student.name.localizedStandardCompare(rhs.student.name) == .orderedAscending
        }
    }

    private var allLessons: [Lesson] { studentStats.flatMap(\.lessons) }

    private var orgStats: [OrgStat] {
        var result: [OrgStat] = []
        let named = organizations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for org in named {
            let rows = studentStats.filter { $0.student.organization?.uuid == org.uuid }
            result.append(
                OrgStat(
                    id: org.uuid.uuidString,
                    title: org.name,
                    color: Theme.purple,
                    mark: String(org.name.prefix(1)),
                    rows: rows,
                    isPersonal: false,
                    organization: org
                )
            )
        }
        let personal = studentStats.filter { $0.student.organization == nil }
        if !personal.isEmpty || organizations.isEmpty {
            result.append(
                OrgStat(
                    id: "personal",
                    title: "私教学生",
                    color: Theme.blue,
                    mark: "私",
                    rows: personal,
                    isPersonal: true,
                    organization: nil
                )
            )
        }
        return result.filter { !$0.rows.isEmpty || $0.organization != nil }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        MonthSwitcher(title: CN.monthTitle(month)) {
                            month = CN.shiftMonth(month, by: -1)
                        } onNext: {
                            month = CN.shiftMonth(month, by: 1)
                        }
                    }
                    Card(padding: 16) {
                        HStack(spacing: 0) {
                            MetricColumn(label: "应收", value: CN.money(Billing.receivable(allLessons)), color: .primary)
                            MetricColumn(label: "已收", value: CN.money(Billing.received(allLessons)), color: Theme.green)
                            MetricColumn(label: "未收", value: CN.money(Billing.unpaid(allLessons)), color: Theme.red)
                        }
                    }
                    SegmentTabs(items: StatsMode.allCases, title: \.title, selection: $mode)
                    if mode == .student {
                        Text("共 \(allLessons.count) 节")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)
                        studentList
                    } else {
                        orgList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("月统计")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private var studentList: some View {
        if studentStats.isEmpty {
            Card {
                EmptyHint(title: "本月还没有已上完的课", message: "在「今天」打卡，或补记以前的课之后，这里会按学生汇总。")
            }
        } else {
            ForEach(studentStats) { stat in
                NavigationLink {
                    StudentMonthDetailView(student: stat.student, month: month)
                } label: {
                    studentCard(stat, showsPrice: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var orgList: some View {
        let visible = orgStats.filter { !$0.rows.isEmpty }
        if visible.isEmpty {
            Card {
                EmptyHint(title: "本月还没有已上完的课", message: "机构分组会在有上课记录后出现。没有机构的学生算在私教里。")
            }
        } else {
            ForEach(visible) { stat in
                orgCard(stat)
            }
        }
    }

    private func studentCard(_ stat: StudentStat, showsPrice: Bool) -> some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.student.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(showsPrice ? Billing.priceText(stat.lessons) : "\(stat.lessons.count) 节")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(CN.money(stat.receivable))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    if stat.unpaid > 0 {
                        Text("未收 \(CN.money(stat.unpaid))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.red)
                    } else {
                        Text("已收清")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.green)
                    }
                }
            }
        }
    }

    private func orgCard(_ stat: OrgStat) -> some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Avatar(text: stat.mark, color: stat.color, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.title)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CN.money(stat.receivable))
                            .font(.system(size: 18, weight: .bold))
                        if stat.unpaid > 0 {
                            Text("未收 \(CN.money(stat.unpaid))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.red)
                        } else if stat.receivable > 0 {
                            Text("已收清")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.green)
                        }
                    }
                }
                .padding(14)

                ForEach(stat.rows) { row in
                    NavigationLink {
                        StudentMonthDetailView(student: row.student, month: month)
                    } label: {
                        HStack {
                            Text("\(row.student.name) · \(Billing.priceText(row.lessons))")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            Text(CN.money(row.receivable))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                if stat.unpaid > 0 {
                    Button {
                        LessonFactory.markPaid(stat.lessons, paid: true, context: context)
                    } label: {
                        Text("\(shortName(stat.title)) 本月全部标为已收 · \(CN.money(stat.unpaid))")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
            }
        }
    }

    private func shortName(_ name: String) -> String {
        if name.count <= 8 { return name }
        return String(name.prefix(8))
    }

    private func dedupe(_ lessons: [Lesson]) -> [Lesson] {
        var seen = Set<UUID>()
        var list: [Lesson] = []
        for lesson in lessons where seen.insert(lesson.uuid).inserted {
            list.append(lesson)
        }
        return list
    }
}
