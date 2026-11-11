import SwiftData
import SwiftUI

struct StudentRecordsView: View {
    @Environment(\.dismiss) private var dismiss
    var student: Student
    var backTitle: String = "管理"

    @State private var month = CN.startOfMonth(Date())
    @State private var editingID: UUID?

    private func lessons(in month: Date) -> [Lesson] {
        var seen = Set<UUID>()
        return student.lessons
            .filter { CN.isSameMonth($0.date, month) }
            .filter { seen.insert($0.uuid).inserted }
            .sorted { lhs, rhs in
                if !CN.isSameDay(lhs.date, rhs.date) { return lhs.date > rhs.date }
                return lhs.timeMinutes > rhs.timeMinutes
            }
    }

    var body: some View {
        let monthLessons = lessons(in: month)
        let taughtCount = monthLessons.reduce(into: 0) { count, lesson in
            if lesson.status == .completed { count += 1 }
        }
        let leaveCount = monthLessons.reduce(into: 0) { count, lesson in
            if lesson.status == .leave { count += 1 }
        }
        let taughtAmount = Money.sum(monthLessons.compactMap { $0.status == .completed ? $0.amount : nil })
        return ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(student.name) · 上课记录")
                        .font(.system(size: 28, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    monthSwitcher

                    Text("\(CN.monthShort(month)) 已上 \(taughtCount) 节 · 请假 \(leaveCount) 次 · \(CN.money(taughtAmount))")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)

                    if monthLessons.isEmpty {
                        Card {
                            EmptyHint(title: "这个月还没有记录", message: "在「今天」打卡或补记之后，会出现在这里。")
                        }
                    } else {
                        ForEach(monthLessons, id: \.uuid) { lesson in
                            Button {
                                editingID = lesson.uuid
                            } label: {
                                LessonRecordRow(lesson: lesson)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Text("点任意一条可修改；在「管理」点学生进入，或在「今天」展开已上完的课点进来")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.horizontal, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavBackButton(title: backTitle) { dismiss() }
            }
        }
        .sheet(isPresented: editingPresented) {
            if let lesson = lessons(in: month).first(where: { $0.uuid == editingID }) ?? student.lessons.first(where: { $0.uuid == editingID }) {
                LessonEditSheet(lesson: lesson)
            }
        }
    }

    private var editingPresented: Binding<Bool> {
        Binding(
            get: { editingID != nil },
            set: { if !$0 { editingID = nil } }
        )
    }

    private var monthSwitcher: some View {
        HStack(spacing: 0) {
            monthChip(CN.shiftMonth(month, by: -1), selected: false)
            monthChip(month, selected: true)
            monthChip(CN.shiftMonth(month, by: 1), selected: false)
        }
        .padding(3)
        .background(Color(red: 0.91, green: 0.91, blue: 0.93), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func monthChip(_ date: Date, selected: Bool) -> some View {
        Button {
            month = CN.startOfMonth(date)
        } label: {
            Text(CN.monthShort(date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? Color.primary : Theme.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.card : Color.clear)
                )
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
    }
}

struct LessonRecordRow: View {
    var lesson: Lesson
    var showsStudent: Bool = false

    var body: some View {
        let chip = lessonChip(lesson)
        Card {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(CN.money(lesson.amount))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Pill(text: chip.0, color: chip.1)
                if lesson.status == .completed {
                    Pill(text: lesson.paid ? "已收" : "未收", color: lesson.paid ? Theme.green : Theme.red)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gray.opacity(0.35))
            }
        }
    }

    private var title: String {
        if lesson.isClassHeadcount {
            let name = lesson.groupName.isEmpty ? (lesson.group?.name ?? "小班") : lesson.groupName
            return "\(CN.listDay(lesson.date)) \(name) · \(lesson.headcount) 人"
        }
        let time = lesson.hasTime ? " \(CN.hm(lesson.timeMinutes))" : ""
        let who = showsStudent ? " \(lesson.student?.name ?? "")" : ""
        return CN.listDay(lesson.date) + time + who
    }
}
