import SwiftData
import SwiftUI

private struct RollRequest: Identifiable {
    var id: String
    var group: SmallGroup
    var slot: WeeklySlot
    var existing: [Lesson]
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \SmallGroup.createdAt) private var groups: [SmallGroup]

    @State private var query = ""
    @State private var addStudentID: UUID?
    @State private var roll: RollRequest?
    @State private var doneExpanded = false
    @State private var toast: LessonTickUndo?
    @State private var editingLessonID: UUID?

    private var today: Date { CN.startOfDay(Date()) }

    private var todayLessons: [Lesson] {
        var seen = Set<UUID>()
        var list: [Lesson] = []
        for student in students {
            for lesson in student.lessons where CN.isSameDay(lesson.date, today) {
                if seen.insert(lesson.uuid).inserted {
                    list.append(lesson)
                }
            }
        }
        return list.sorted { $0.timeMinutes < $1.timeMinutes }
    }

    private var doneLessons: [Lesson] { todayLessons.filter { $0.status == .completed } }
    private var leaveLessons: [Lesson] { todayLessons.filter { $0.status == .leave } }
    private var foldLessons: [Lesson] { doneLessons + leaveLessons }

    private var entries: [TodayEntry] {
        Agenda.entries(students: students, groups: groups, on: today)
    }

    private var pending: [TodayEntry] { entries.filter { !$0.isDone } }

    private var addStudents: [Student] {
        let pool = students.filter { !$0.paused }
        let filtered = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? pool
            : pool.filter { $0.name.localizedStandardContains(query) }
        return filtered.sorted { lhs, rhs in
            let leftBusy = !lhs.engagements(on: today).isEmpty
            let rightBusy = !rhs.engagements(on: today).isEmpty
            if leftBusy != rightBusy { return !leftBusy && rightBusy }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(
                        title: "今天",
                        subtitle: "\(CN.fullDayTitle(today)) · 还剩 \(pending.count) 节"
                    )
                    if pending.isEmpty && foldLessons.isEmpty {
                        Card {
                            EmptyHint(title: "今天没有固定课", message: "固定时间会按星期出现在这里。也可以在下面给学生加课或补记。")
                        }
                    }
                    ForEach(pending) { entry in
                        pendingCard(entry)
                    }
                    if !foldLessons.isEmpty {
                        completedFold
                    }
                    addSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) { toastBar }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: addSheetPresented) {
            if let student = student(addStudentID) {
                AddLessonSheet(student: student)
            }
        }
        .sheet(item: $roll) { request in
            GroupRollSheet(group: request.group, slot: request.slot, day: today, existing: request.existing) { undo in
                showToast(undo)
            }
        }
        .sheet(isPresented: editingPresented) {
            if let lesson = findLesson(editingLessonID) {
                LessonEditSheet(lesson: lesson)
            }
        }
    }

    private var editingPresented: Binding<Bool> {
        Binding(
            get: { editingLessonID != nil },
            set: { if !$0 { editingLessonID = nil } }
        )
    }

    @ViewBuilder
    private var toastBar: some View {
        if let toast {
            HStack(spacing: 12) {
                Text(toast.message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("撤销") { undo(toast) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .task(id: toast.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if self.toast?.id == toast.id {
                    self.toast = nil
                }
            }
        }
    }

    private var completedFold: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { doneExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    Text(foldTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(foldSummary)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(doneExpanded ? "收起" : "展开")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.blue)
                    Image(systemName: doneExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if doneExpanded {
                ForEach(foldLessons, id: \.uuid) { lesson in
                    Button {
                        editingLessonID = lesson.uuid
                    } label: {
                        LessonRecordRow(lesson: lesson, showsStudent: true)
                    }
                    .buttonStyle(.plain)
                }
                let people = distinctStudents(in: foldLessons)
                ForEach(people, id: \.uuid) { person in
                    NavigationLink {
                        StudentRecordsView(student: person, backTitle: "今天")
                    } label: {
                        HStack {
                            Text("\(person.name) 的上课记录")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var foldTitle: String {
        if doneLessons.isEmpty {
            return "今天请假 \(leaveLessons.count) 次"
        }
        return "今天已上完 \(doneLessons.count) 节"
    }

    private var foldSummary: String {
        let source = doneLessons.isEmpty ? leaveLessons : doneLessons
        let parts = source.prefix(3).map { lesson in
            let name = lesson.student?.name ?? ""
            if lesson.hasTime { return "\(name) \(CN.hm(lesson.timeMinutes))" }
            return name
        }
        let suffix = source.count > 3 ? "等" : ""
        return parts.joined(separator: "、") + suffix
    }

    private var addSheetPresented: Binding<Bool> {
        Binding(
            get: { addStudentID != nil },
            set: { if !$0 { addStudentID = nil } }
        )
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "加课 / 补记（点学生右边的 +）")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondary)
                TextField("搜索学生", text: $query)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(red: 0.93, green: 0.93, blue: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if students.isEmpty {
                Card {
                    EmptyHint(title: "还没有学生", message: "到「管理」页点「添加学生」，记下姓名和每节单价。")
                }
            } else if addStudents.isEmpty {
                Card {
                    EmptyHint(title: "没有匹配的学生", message: "换个名字试试。停课的学生不会出现在这里。")
                }
            } else {
                FormCard {
                    ForEach(Array(addStudents.enumerated()), id: \.element.uuid) { index, student in
                        if index > 0 { FormDivider() }
                        addRow(student)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func addRow(_ student: Student) -> some View {
        let count = student.engagements(on: today).count
        let busy = count > 0
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(busy ? Theme.secondary : Color.primary)
                Text(busy ? "今天已有 \(count) 节" : CN.money(student.currentPrice))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button {
                addStudentID = student.uuid
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(busy ? Color.gray.opacity(0.45) : Theme.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    @ViewBuilder
    private func pendingCard(_ entry: TodayEntry) -> some View {
        switch entry {
        case .studentSlot(let slot, let student):
            tickCard(
                title: "\(CN.hm(slot.startMinutes)) \(student.name)",
                subtitle: CN.money(student.effectivePrice(on: today))
            ) {
                let lesson = LessonFactory.completeStudentSlot(slot, student: student, on: today, context: context)
                showToast(
                    LessonTickUndo(
                        message: taughtLine(student.name, minutes: lesson.timeMinutes),
                        created: [lesson],
                        previous: []
                    )
                )
            }
            .contextMenu {
                Button("记为请假（不计费）") {
                    let lesson = LessonFactory.leaveStudentSlot(slot, student: student, on: today, context: context)
                    showToast(
                        LessonTickUndo(
                            message: "已记录：\(student.name) \(CN.hm(slot.startMinutes)) 请假",
                            created: [lesson],
                            previous: []
                        )
                    )
                }
            }
        case .groupSlot(let slot, let group):
            tickCard(title: "\(CN.hm(slot.startMinutes)) \(group.name)", subtitle: groupSubtitle(group)) {
                roll = RollRequest(id: slot.uuid.uuidString, group: group, slot: slot, existing: [])
            }
        case .single(let lesson):
            if lesson.status == .pending {
                tickCard(
                    title: "\(lesson.hasTime ? CN.hm(lesson.timeMinutes) : "未填时间") \(lesson.student?.name ?? "学生")",
                    subtitle: CN.money(lesson.amount)
                ) {
                    let priorStatus = lesson.statusRaw
                    let priorPaid = lesson.paid
                    lesson.status = .completed
                    try? context.save()
                    showToast(
                        LessonTickUndo(
                            message: taughtLine(lesson.student?.name ?? "学生", minutes: lesson.timeMinutes),
                            created: [],
                            previous: [(lesson: lesson, statusRaw: priorStatus, paid: priorPaid)]
                        )
                    )
                }
            }
        case .groupSession:
            EmptyView()
        }
    }

    private func tickCard(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Button(action: action) {
                    CheckCircle(checked: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func taughtLine(_ name: String, minutes: Int) -> String {
        if minutes >= 0 {
            return "已记录：\(name) \(CN.hm(minutes)) 上完"
        }
        return "已记录：\(name) 上完"
    }

    private func showToast(_ undo: LessonTickUndo) {
        toast = undo
    }

    private func undo(_ item: LessonTickUndo) {
        for lesson in item.created {
            context.delete(lesson)
        }
        for prior in item.previous {
            prior.lesson.statusRaw = prior.statusRaw
            prior.lesson.paid = prior.paid
        }
        try? context.save()
        toast = nil
    }

    private func findLesson(_ id: UUID?) -> Lesson? {
        guard let id else { return nil }
        for student in students {
            if let lesson = student.lessons.first(where: { $0.uuid == id }) {
                return lesson
            }
        }
        return nil
    }

    private func distinctStudents(in lessons: [Lesson]) -> [Student] {
        var seen = Set<UUID>()
        var people: [Student] = []
        for lesson in lessons {
            guard let student = lesson.student, seen.insert(student.uuid).inserted else { continue }
            people.append(student)
        }
        return people
    }

    private func groupSubtitle(_ group: SmallGroup) -> String {
        let names = group.activeStudents.map(\.name)
        let shown = names.prefix(4).joined(separator: "、")
        let suffix = names.count > 4 ? "等 \(names.count) 人" : ""
        if names.isEmpty { return "小班" }
        return "小班 \(names.count) 人 · \(shown)\(suffix)"
    }

    private func student(_ id: UUID?) -> Student? {
        guard let id else { return nil }
        return students.first { $0.uuid == id }
    }

}
