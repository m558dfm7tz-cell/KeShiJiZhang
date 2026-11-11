import SwiftData
import SwiftUI

struct StudentMonthDetailView: View {
    @Environment(\.modelContext) private var context
    var student: Student
    var month: Date

    @State private var amountLessonID: UUID?
    @State private var amountText = ""

    private func lessons(in month: Date) -> [Lesson] {
        var seen = Set<UUID>()
        var list: [Lesson] = []
        for lesson in student.lessons where CN.isSameMonth(lesson.date, month) && seen.insert(lesson.uuid).inserted {
            list.append(lesson)
        }
        return list.sorted { lhs, rhs in
            if !CN.isSameDay(lhs.date, rhs.date) { return lhs.date > rhs.date }
            return lhs.timeMinutes > rhs.timeMinutes
        }
    }

    var body: some View {
        let monthLessons = lessons(in: month)
        let billed = monthLessons.filter(\.countsTowardBill)
        let unpaidLessons = billed.filter { !$0.paid }
        return ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(student.name)
                            .font(.system(size: 34, weight: .bold))
                        Text(headline)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondary)
                    }
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CN.monthShort(month))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondary)
                                Text("\(billed.count) 节")
                                    .font(.system(size: 22, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            MetricColumn(label: "应收", value: CN.money(Billing.receivable(billed)), color: .primary)
                            MetricColumn(
                                label: "未收",
                                value: unpaidLessons.isEmpty && !billed.isEmpty ? "已收清" : CN.money(Billing.unpaid(billed)),
                                color: unpaidLessons.isEmpty ? Theme.green : Theme.red
                            )
                        }
                    }
                    Button {
                        LessonFactory.markPaid(unpaidLessons, paid: true, context: context, persists: false)
                        context.saveSoon()
                    } label: {
                        Text("本月未收全部标为已收")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(unpaidLessons.isEmpty ? Theme.secondary : Theme.blue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(unpaidLessons.isEmpty)

                    SectionLabel(text: "上课记录（点标签切换已收/未收）")
                    if monthLessons.isEmpty {
                        Card {
                            EmptyHint(title: "本月还没有记录", message: "打卡、补记或请假之后会出现在这里。")
                        }
                    } else {
                        ForEach(monthLessons, id: \.uuid) { lesson in
                            recordRow(lesson)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(student.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("编辑") {
                    StudentEditorView(student: student)
                }
            }
        }
        .alert("修改这节金额", isPresented: amountPresented) {
            TextField("金额", text: $amountText)
                .keyboardType(.decimalPad)
            Button("保存") { saveAmount() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只改这一节，并记为改价。")
        }
    }

    private var headline: String {
        let price = "\(CN.money(student.currentPrice))/节"
        let schedule = student.scheduleSummary
        if schedule.isEmpty { return price }
        return "\(price) · \(schedule)"
    }

    private var amountPresented: Binding<Bool> {
        Binding(
            get: { amountLessonID != nil },
            set: { if !$0 { amountLessonID = nil } }
        )
    }

    private func recordRow(_ lesson: Lesson) -> some View {
        Card {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(CN.listDay(lesson.date))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(lesson.status == .leave ? Theme.secondary : Color.primary)
                        if lesson.status == .pending {
                            Pill(text: "待上", color: Theme.secondary)
                        } else if lesson.status == .leave {
                            Text("· 请假")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                        } else {
                            if lesson.kind == .extra { Pill(text: "加课", color: Theme.orange) }
                            if lesson.kind == .makeup { Pill(text: "补课", color: Theme.blue) }
                            if lesson.priceOverridden { Pill(text: "改价", color: Theme.orange) }
                        }
                    }
                    if lesson.hasTime && lesson.status != .leave {
                        Text(CN.hm(lesson.timeMinutes))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                if lesson.status == .leave {
                    Text("不计费")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                } else if lesson.status == .pending {
                    Text(CN.money(lesson.amount))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                } else {
                    Text(CN.money(lesson.amount))
                        .font(.system(size: 16, weight: .semibold))
                    Button {
                        LessonFactory.togglePaid(lesson, context: context, persists: false)
                        context.saveSoon()
                    } label: {
                        Pill(text: lesson.paid ? "已收" : "未收", color: lesson.paid ? Theme.green : Theme.red)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
                lessonMenu(lesson)
            }
        }
    }

    private func lessonMenu(_ lesson: Lesson) -> some View {
        Menu {
            if lesson.countsTowardBill {
                Button(lesson.paid ? "标为未收" : "标为已收") {
                    LessonFactory.togglePaid(lesson, context: context, persists: false)
                    context.saveSoon()
                }
                Button("修改金额") {
                    amountText = amountString(lesson.amount)
                    amountLessonID = lesson.uuid
                }
                Button("改为请假") {
                    LessonFactory.setLeave(lesson, context: context, persists: false)
                    context.saveSoon()
                }
            } else if lesson.status == .leave {
                Button("取消请假，记为已上") {
                    LessonFactory.restoreCompleted(lesson, context: context, persists: false)
                    context.saveSoon()
                }
            } else if lesson.status == .pending {
                Button("记为已上完") {
                    lesson.status = .completed
                    context.saveSoon()
                }
            }
            Button("删除这节课", role: .destructive) {
                LessonFactory.delete(lesson, context: context, persists: false)
                context.saveSoon()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("更多")
    }

    private func amountString(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 { return String(Int(value.rounded())) }
        return String(format: "%.2f", value)
    }

    private func saveAmount() {
        guard let id = amountLessonID,
              let lesson = lessons(in: month).first(where: { $0.uuid == id }),
              let amount = CN.parseMoney(amountText) else { return }
        LessonFactory.updateAmount(lesson, amount: amount, context: context, persists: false)
        context.saveSoon()
        amountLessonID = nil
    }
}
