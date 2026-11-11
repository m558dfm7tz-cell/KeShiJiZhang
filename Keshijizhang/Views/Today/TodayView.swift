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
    @State private var amountLessonID: UUID?
    @State private var amountText = ""

    private var today: Date { CN.startOfDay(Date()) }

    private var entries: [TodayEntry] {
        Agenda.entries(students: students, groups: groups, on: today)
    }

    private var pending: [TodayEntry] { entries.filter { !$0.isDone } }
    private var done: [TodayEntry] { entries.filter(\.isDone) }

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
                        subtitle: "\(CN.fullDayTitle(today)) · \(entries.count) 节课"
                    )
                    if pending.isEmpty && done.isEmpty {
                        Card {
                            EmptyHint(title: "今天没有固定课", message: "固定时间会按星期出现在这里。也可以在下面给学生加课或补记。")
                        }
                    }
                    if !pending.isEmpty {
                        SectionLabel(text: "待上课")
                        ForEach(pending) { entry in
                            entryCard(entry)
                        }
                    }
                    if !done.isEmpty {
                        SectionLabel(text: "已上完")
                        ForEach(done) { entry in
                            entryCard(entry)
                        }
                    }
                    addSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: addSheetPresented) {
            if let student = student(addStudentID) {
                AddLessonSheet(student: student)
            }
        }
        .sheet(item: $roll) { request in
            GroupRollSheet(group: request.group, slot: request.slot, day: today, existing: request.existing)
        }
        .alert("修改这节金额", isPresented: amountAlertPresented) {
            TextField("金额", text: $amountText)
                .keyboardType(.decimalPad)
            Button("保存") { saveAmount() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只改这一节，不会影响单价。")
        }
    }

    private var addSheetPresented: Binding<Bool> {
        Binding(
            get: { addStudentID != nil },
            set: { if !$0 { addStudentID = nil } }
        )
    }

    private var amountAlertPresented: Binding<Bool> {
        Binding(
            get: { amountLessonID != nil },
            set: { if !$0 { amountLessonID = nil } }
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
                ForEach(addStudents, id: \.uuid) { student in
                    addRow(student)
                }
            }
        }
        .padding(.top, 8)
    }

    private func addRow(_ student: Student) -> some View {
        let count = student.engagements(on: today).count
        let busy = count > 0
        return Card {
            HStack(spacing: 12) {
                Avatar(text: student.name, color: avatarColor(for: student.name, muted: busy))
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
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: TodayEntry) -> some View {
        switch entry {
        case .studentSlot(let slot, let student):
            lessonCard(
                time: CN.hm(slot.startMinutes),
                title: student.name,
                subtitle: "一对一 · \(CN.money(student.effectivePrice(on: today)))",
                badges: [],
                checked: false,
                muted: false
            ) {
                LessonFactory.completeStudentSlot(slot, student: student, on: today, context: context)
            }
            .contextMenu {
                Button("记为请假（不计费）") {
                    LessonFactory.leaveStudentSlot(slot, student: student, on: today, context: context)
                }
            }
        case .groupSlot(let slot, let group):
            lessonCard(
                time: CN.hm(slot.startMinutes),
                title: group.name,
                subtitle: groupSubtitle(group),
                badges: [],
                checked: false,
                muted: false
            ) {
                roll = RollRequest(
                    id: slot.uuid.uuidString,
                    group: group,
                    slot: slot,
                    existing: []
                )
            }
        case .single(let lesson):
            singleCard(lesson)
        case .groupSession(let key, let lessons, let name, let time):
            groupDoneCard(key: key, lessons: lessons, name: name, time: time)
        }
    }

    private func singleCard(_ lesson: Lesson) -> some View {
        let leave = lesson.status == .leave
        let pending = lesson.status == .pending
        var badges: [(String, Color)] = []
        if lesson.kind == .extra { badges.append(("加课", Theme.orange)) }
        if lesson.kind == .makeup { badges.append(("补课", Theme.blue)) }
        if lesson.priceOverridden && lesson.countsTowardBill { badges.append(("改价", Theme.orange)) }
        if lesson.countsTowardBill {
            badges.append((lesson.paid ? "已收" : "未收", lesson.paid ? Theme.green : Theme.red))
        }
        let subtitle: String = {
            if leave { return "请假 · 不计费" }
            if pending { return "待打卡 · \(CN.money(lesson.amount))" }
            let who = lesson.kind == .fixed ? "一对一" : lesson.kind.title
            return "\(who) · \(CN.money(lesson.amount))"
        }()
        return lessonCard(
            time: lesson.hasTime ? CN.hm(lesson.timeMinutes) : "未填时间",
            title: lesson.student?.name ?? "学生",
            subtitle: subtitle,
            badges: badges,
            checked: !pending,
            muted: leave,
            onBadge: { badge in
                if badge == "已收" || badge == "未收" {
                    LessonFactory.togglePaid(lesson, context: context)
                }
            }
        ) {
            if pending {
                lesson.status = .completed
                try? context.save()
            } else {
                LessonFactory.undo(lesson, context: context)
            }
        }
        .contextMenu {
            if lesson.countsTowardBill {
                Button(lesson.paid ? "标为未收" : "标为已收") {
                    LessonFactory.togglePaid(lesson, context: context)
                }
                Button("修改金额") {
                    amountText = String(format: "%g", lesson.amount)
                    amountLessonID = lesson.uuid
                }
                Button("改为请假") {
                    LessonFactory.setLeave(lesson, context: context)
                }
            } else if leave {
                Button("取消请假，记为已上") {
                    LessonFactory.restoreCompleted(lesson, context: context)
                }
            }
            Button("删除这节课", role: .destructive) {
                LessonFactory.delete(lesson, context: context)
            }
        }
    }

    private func groupDoneCard(key: String, lessons: [Lesson], name: String, time: Int) -> some View {
        let attended = lessons.filter { $0.status == .completed }
        let leaves = lessons.filter { $0.status == .leave }
        let unpaid = Billing.unpaid(attended)
        var subtitle = "到场 \(attended.count) 人"
        if !leaves.isEmpty { subtitle += " · 请假 \(leaves.count) 人" }
        if attended.isEmpty {
            subtitle = "全部请假 · 不计费"
        } else {
            subtitle += " · \(CN.money(Billing.receivable(attended)))"
        }
        var badges: [(String, Color)] = []
        if !attended.isEmpty {
            badges.append((unpaid > 0 ? "未收 \(CN.money(unpaid))" : "已收清", unpaid > 0 ? Theme.red : Theme.green))
        }
        return lessonCard(
            time: time >= 0 ? CN.hm(time) : "小班",
            title: name,
            subtitle: subtitle,
            badges: badges,
            checked: true,
            muted: attended.isEmpty,
            onCard: {
                guard let located = locate(slotKey: key) else { return }
                roll = RollRequest(id: "edit-\(key)", group: located.0, slot: located.1, existing: lessons)
            }
        ) {
            LessonFactory.undoGroup(slotKey: key, lessons: lessons, context: context)
        }
    }

    private func lessonCard(
        time: String,
        title: String,
        subtitle: String,
        badges: [(String, Color)],
        checked: Bool,
        muted: Bool,
        onBadge: ((String) -> Void)? = nil,
        onCard: (() -> Void)? = nil,
        onCheck: @escaping () -> Void
    ) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(time) \(title)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(muted ? Theme.secondary : Color.primary)
                    }
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            Button {
                                onBadge?(badge.0)
                            } label: {
                                Pill(text: badge.0, color: badge.1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onCard?() }
                Button(action: onCheck) {
                    CheckCircle(checked: checked)
                }
                .buttonStyle(.plain)
            }
        }
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

    private func lesson(_ id: UUID?) -> Lesson? {
        guard let id else { return nil }
        for student in students {
            if let lesson = student.lessons.first(where: { $0.uuid == id }) {
                return lesson
            }
        }
        return nil
    }

    private func saveAmount() {
        guard let lesson = lesson(amountLessonID), let amount = CN.parseMoney(amountText) else { return }
        LessonFactory.updateAmount(lesson, amount: amount, context: context)
        amountLessonID = nil
    }

    private func locate(slotKey: String) -> (SmallGroup, WeeklySlot)? {
        for group in groups {
            if let slot = group.slots.first(where: { $0.uuid.uuidString == slotKey }) {
                return (group, slot)
            }
        }
        return nil
    }
}
