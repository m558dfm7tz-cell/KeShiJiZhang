import SwiftData
import SwiftUI

private struct RollRequest: Identifiable {
    var id: String
    var group: SmallGroup
    var slot: WeeklySlot
    var existing: [Lesson]
}

private struct HeadcountRequest: Identifiable {
    var id: String
    var group: SmallGroup
    var slot: WeeklySlot
}

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \SmallGroup.createdAt) private var groups: [SmallGroup]

    @State private var query = ""
    @State private var addStudentID: UUID?
    @State private var roll: RollRequest?
    @State private var headcount: HeadcountRequest?
    @State private var doneExpanded = false
    @State private var toast: LessonTickUndo?
    @State private var editingLessonID: UUID?
    @State private var checkedKeys: Set<String> = []
    @State private var pinned: [String: TodayEntry] = [:]
    @State private var hiding: Set<String> = []
    @State private var heldLessonIDs: [String: Set<UUID>] = [:]
    @State private var followUps: [String: Task<Void, Never>] = [:]

    var body: some View {
        let day = CN.startOfDay(Date())
        let board = Agenda.board(students: students, groups: groups, on: day)
        let pending = visiblePending(board, day: day)
        let held = heldLessonUUIDs()
        let done = held.isEmpty ? board.doneLessons : board.doneLessons.filter { !held.contains($0.uuid) }
        let leave = held.isEmpty ? board.leaveLessons : board.leaveLessons.filter { !held.contains($0.uuid) }
        let fold = done + leave
        let adding = listedStudents(counts: board.engagementCounts)
        return ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeader(
                        title: "今天",
                        subtitle: "\(CN.fullDayTitle(day)) · 还剩 \(pending.count) 节"
                    )
                    if pending.isEmpty && fold.isEmpty {
                        Card {
                            EmptyHint(title: "今天没有固定课", message: "固定时间会按星期出现在这里。也可以在下面给学生加课或补记。")
                        }
                    }
                    VStack(spacing: 14) {
                        ForEach(pending) { entry in
                            pendingCard(entry, day: day)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.easeInOut(duration: 0.28), value: pending.map(\.id))
                    if !fold.isEmpty {
                        completedFold(done: done, leave: leave, fold: fold)
                    }
                    addSection(adding, counts: board.engagementCounts)
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
        .sheet(item: $headcount) { request in
            GroupHeadcountSheet(group: request.group, slot: request.slot, day: day) { lesson in
                let mark = key(request.id, day: day)
                withAnimation(.easeInOut(duration: 0.28)) {
                    hiding.insert(mark)
                }
                showToast(
                    LessonTickUndo(
                        message: "已记录：\(lesson.groupName) \(lesson.headcount) 人上完",
                        created: [lesson],
                        previous: [],
                        entryIDs: [mark]
                    )
                )
                context.saveSoon()
                scheduleHideClear(mark, after: 320_000_000)
            }
        }
        .sheet(item: $roll) { request in
            GroupRollSheet(group: request.group, slot: request.slot, day: day, existing: request.existing) { undo in
                var undo = undo
                let mark = key(request.id, day: day)
                undo.entryIDs = [mark]
                withAnimation(.easeInOut(duration: 0.28)) {
                    hiding.insert(mark)
                }
                showToast(undo)
                context.saveSoon()
                scheduleHideClear(mark, after: 320_000_000)
            }
        }
        .sheet(isPresented: editingPresented) {
            if let lesson = findLesson(editingLessonID) {
                LessonEditSheet(lesson: lesson)
            }
        }
    }

    private func visiblePending(_ board: AgendaBoard, day: Date) -> [TodayEntry] {
        var rows: [TodayEntry] = []
        var seen = Set<String>()
        for entry in board.entries {
            let mark = key(entry.id, day: day)
            if hiding.contains(mark) { continue }
            if let held = pinned[mark] {
                rows.append(held)
                seen.insert(mark)
            } else if !entry.isDone {
                rows.append(entry)
                seen.insert(mark)
            }
        }
        for (mark, entry) in pinned where !seen.contains(mark) && !hiding.contains(mark) {
            rows.append(entry)
        }
        guard !pinned.isEmpty else { return rows }
        rows.sort {
            if $0.sortMinutes != $1.sortMinutes { return $0.sortMinutes < $1.sortMinutes }
            return $0.id < $1.id
        }
        return rows
    }

    private func listedStudents(counts: [UUID: Int]) -> [Student] {
        let pool = students.filter { !$0.paused }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty ? pool : pool.filter { $0.name.localizedStandardContains(trimmed) }
        return filtered.sorted { lhs, rhs in
            let leftBusy = (counts[lhs.uuid] ?? 0) > 0
            let rightBusy = (counts[rhs.uuid] ?? 0) > 0
            if leftBusy != rightBusy { return !leftBusy && rightBusy }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func key(_ entryID: String, day: Date) -> String {
        "\(Int(day.timeIntervalSinceReferenceDate))|\(entryID)"
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

    private func completedFold(done: [Lesson], leave: [Lesson], fold: [Lesson]) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { doneExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    Text(foldTitle(done: done, leave: leave))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(foldSummary(done: done, leave: leave))
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if doneExpanded {
                ForEach(fold, id: \.uuid) { lesson in
                    Button {
                        editingLessonID = lesson.uuid
                    } label: {
                        LessonRecordRow(lesson: lesson, showsStudent: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
                let people = distinctStudents(in: fold)
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
                        .contentShape(Rectangle())
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func foldTitle(done: [Lesson], leave: [Lesson]) -> String {
        if done.isEmpty {
            return "今天请假 \(leave.count) 次"
        }
        return "今天已上完 \(done.count) 节"
    }

    private func foldSummary(done: [Lesson], leave: [Lesson]) -> String {
        let source = done.isEmpty ? leave : done
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

    private func addSection(_ addStudents: [Student], counts: [UUID: Int]) -> some View {
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
                        addRow(student, count: counts[student.uuid] ?? 0)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func addRow(_ student: Student, count: Int) -> some View {
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    @ViewBuilder
    private func pendingCard(_ entry: TodayEntry, day: Date) -> some View {
        let mark = key(entry.id, day: day)
        let checked = checkedKeys.contains(mark)
        switch entry {
        case .studentSlot(let slot, let student):
            TickCard(
                title: "\(CN.hm(slot.startMinutes)) \(student.name)",
                subtitle: CN.money(student.effectivePrice(on: day)),
                checked: checked,
                showsLeaveMenu: true,
                onTick: {
                    complete(entry, day: day) {
                        let lesson = LessonFactory.completeStudentSlot(slot, student: student, on: day, context: context, persists: false)
                        return LessonTickUndo(
                            message: taughtLine(student.name, minutes: lesson.timeMinutes),
                            created: [lesson],
                            previous: []
                        )
                    }
                },
                onLeave: {
                    leave(entry, day: day, student: student, slot: slot)
                }
            )
        case .groupSlot(let slot, let group):
            TickCard(
                title: "\(CN.hm(slot.startMinutes)) \(group.name)",
                subtitle: groupSubtitle(group),
                checked: false,
                showsLeaveMenu: false,
                onTick: {
                    if group.usesNameRoll {
                        roll = RollRequest(id: entry.id, group: group, slot: slot, existing: [])
                    } else {
                        headcount = HeadcountRequest(id: entry.id, group: group, slot: slot)
                    }
                },
                onLeave: nil
            )
        case .single(let lesson):
            TickCard(
                title: "\(lesson.hasTime ? CN.hm(lesson.timeMinutes) : "未填时间") \(lesson.student?.name ?? "学生")",
                subtitle: CN.money(lesson.amount),
                checked: checked,
                showsLeaveMenu: false,
                onTick: {
                    let priorStatus = lesson.statusRaw
                    let priorPaid = lesson.paid
                    complete(entry, day: day) {
                        lesson.status = .completed
                        return LessonTickUndo(
                            message: taughtLine(lesson.student?.name ?? "学生", minutes: lesson.timeMinutes),
                            created: [],
                            previous: [(lesson: lesson, statusRaw: priorStatus, paid: priorPaid)]
                        )
                    }
                },
                onLeave: nil
            )
        case .groupSession:
            EmptyView()
        }
    }

    private func complete(_ entry: TodayEntry, day: Date, make: () -> LessonTickUndo) {
        let mark = key(entry.id, day: day)
        guard !checkedKeys.contains(mark) else { return }
        checkedKeys.insert(mark)
        pinned[mark] = entry
        var undo = make()
        undo.entryIDs = [mark]
        var held = Set<UUID>()
        for lesson in undo.created {
            held.insert(lesson.uuid)
        }
        for prior in undo.previous {
            held.insert(prior.lesson.uuid)
        }
        heldLessonIDs[mark] = held
        showToast(undo)
        scheduleDeparture(mark)
        context.saveSoon(after: 420_000_000)
    }

    private func heldLessonUUIDs() -> Set<UUID> {
        var all = Set<UUID>()
        for ids in heldLessonIDs.values {
            all.formUnion(ids)
        }
        return all
    }

    private func leave(_ entry: TodayEntry, day: Date, student: Student, slot: WeeklySlot) {
        let mark = key(entry.id, day: day)
        guard !checkedKeys.contains(mark), !hiding.contains(mark) else { return }
        var lesson: Lesson?
        withAnimation(.easeInOut(duration: 0.28)) {
            hiding.insert(mark)
            lesson = LessonFactory.leaveStudentSlot(slot, student: student, on: day, context: context, persists: false)
        }
        guard let lesson else { return }
        showToast(
            LessonTickUndo(
                message: "已记录：\(student.name) \(CN.hm(slot.startMinutes)) 请假",
                created: [lesson],
                previous: [],
                entryIDs: [mark]
            )
        )
        context.saveSoon(after: 420_000_000)
        scheduleHideClear(mark, after: 320_000_000)
    }

    private func scheduleDeparture(_ mark: String) {
        followUps[mark]?.cancel()
        followUps[mark] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                hiding.insert(mark)
                pinned.removeValue(forKey: mark)
                heldLessonIDs.removeValue(forKey: mark)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            hiding.remove(mark)
            checkedKeys.remove(mark)
            followUps.removeValue(forKey: mark)
        }
    }

    private func scheduleHideClear(_ mark: String, after nanoseconds: UInt64) {
        followUps[mark]?.cancel()
        followUps[mark] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            hiding.remove(mark)
            checkedKeys.remove(mark)
            followUps.removeValue(forKey: mark)
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
        for mark in item.entryIDs {
            followUps[mark]?.cancel()
            followUps.removeValue(forKey: mark)
        }
        for lesson in item.created {
            context.delete(lesson)
        }
        for prior in item.previous {
            prior.lesson.statusRaw = prior.statusRaw
            prior.lesson.paid = prior.paid
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            for mark in item.entryIDs {
                checkedKeys.remove(mark)
                pinned.removeValue(forKey: mark)
                hiding.remove(mark)
                heldLessonIDs.removeValue(forKey: mark)
            }
        }
        context.saveNow()
        toast = nil
    }

    private func findLesson(_ id: UUID?) -> Lesson? {
        guard let id else { return nil }
        for student in students {
            if let lesson = student.lessons.first(where: { $0.uuid == id }) {
                return lesson
            }
        }
        for group in groups {
            if let lesson = group.classLessons.first(where: { $0.uuid == id }) {
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
        let who = group.organization?.name ?? "小班"
        let price = CN.money(group.basePrice)
        if group.standardCount > 0 {
            return "\(who) · 标准 \(group.standardCount) 人 · \(price)"
        }
        return "\(who) · \(price)"
    }

    private func student(_ id: UUID?) -> Student? {
        guard let id else { return nil }
        return students.first { $0.uuid == id }
    }
}

private struct TickCard: View {
    var title: String
    var subtitle: String
    var checked: Bool
    var showsLeaveMenu: Bool
    var onTick: () -> Void
    var onLeave: (() -> Void)?

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                if showsLeaveMenu, let onLeave {
                    Menu {
                        Button("记为请假（不计费）", action: onLeave)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(checked)
                    .accessibilityLabel("更多")
                }
                Button(action: onTick) {
                    CheckCircle(checked: checked)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(checked ? "已上完" : "记为上完")
            }
        }
    }
}
