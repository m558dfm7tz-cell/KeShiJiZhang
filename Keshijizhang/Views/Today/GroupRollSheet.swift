import SwiftData
import SwiftUI

struct GroupRollSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var group: SmallGroup
    var slot: WeeklySlot
    var day: Date
    var existing: [Lesson]
    var onSaved: (LessonTickUndo) -> Void = { _ in }

    @State private var attending: Set<UUID> = []
    @State private var paid: Set<UUID> = []
    @State private var ready = false

    private var members: [Student] { group.activeStudents }
    private var isReview: Bool { !existing.isEmpty }

    private var total: Double {
        Money.sum(members.filter { attending.contains($0.uuid) }.map { amount(for: $0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(CN.listDay(day)) · \(CN.hm(slot.startMinutes))–\(CN.hm(slot.endMinutes))")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)
                        Text("到场的学生按自己的单价各记一节。关掉的学生记为请假，不计费。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)

                        if members.isEmpty {
                            Card {
                                EmptyHint(title: "这个小班没有在上课的学生", message: "停课的学生不会出现在点名里。可以先到学生资料里取消停课。")
                            }
                        } else {
                            FormCard {
                                ForEach(Array(members.enumerated()), id: \.element.uuid) { index, student in
                                    if index > 0 { FormDivider() }
                                    memberRow(student)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        FillButton(title: buttonTitle, color: Theme.blue, disabled: members.isEmpty, action: save)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.bg)
                }
            }
            .navigationTitle(isReview ? group.name : "给\(group.name)上课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDragIndicator(.visible)
    }

    private var buttonTitle: String {
        let count = attending.count
        if count == 0 { return "全部记为请假" }
        let verb = isReview ? "保存" : "确认上完"
        return "\(verb) · \(count) 人 · \(CN.money(total))"
    }

    private func memberRow(_ student: Student) -> some View {
        let on = attending.contains(student.uuid)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Avatar(text: student.name, color: avatarColor(for: student.name, muted: !on), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(on ? CN.money(amount(for: student)) : "请假 · 不计费")
                        .font(.system(size: 13))
                        .foregroundStyle(on ? Theme.secondary : Theme.orange)
                }
                Spacer()
                Toggle("到场", isOn: Binding(
                    get: { attending.contains(student.uuid) },
                    set: { value in
                        if value {
                            attending.insert(student.uuid)
                        } else {
                            attending.remove(student.uuid)
                            paid.remove(student.uuid)
                        }
                    }
                ))
                .labelsHidden()
                .tint(Theme.green)
            }
            if isReview && on {
                Button {
                    if paid.contains(student.uuid) {
                        paid.remove(student.uuid)
                    } else {
                        paid.insert(student.uuid)
                    }
                } label: {
                    Pill(text: paid.contains(student.uuid) ? "已收" : "未收", color: paid.contains(student.uuid) ? Theme.green : Theme.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func amount(for student: Student) -> Double {
        if let lesson = existing.first(where: { $0.student?.uuid == student.uuid }), lesson.status != .leave {
            return lesson.amount
        }
        return student.effectivePrice(on: day)
    }

    private func load() {
        guard !ready else { return }
        ready = true
        if existing.isEmpty {
            attending = Set(members.map(\.uuid))
        } else {
            attending = Set(existing.filter { $0.status != .leave }.compactMap { $0.student?.uuid })
            paid = Set(existing.filter(\.paid).compactMap { $0.student?.uuid })
        }
    }

    private func save() {
        let key = slot.uuid.uuidString
        var previous: [(lesson: Lesson, statusRaw: String, paid: Bool)] = []
        for student in members {
            if let lesson = student.lessons.first(where: {
                CN.isSameDay($0.date, day)
                    && $0.originKind == OriginKind.groupSlot
                    && $0.originSlotKey == key
            }) {
                previous.append((lesson: lesson, statusRaw: lesson.statusRaw, paid: lesson.paid))
            }
        }
        let created = LessonFactory.applyGroupRoll(
            context: context,
            group: group,
            slot: slot,
            day: day,
            attending: attending,
            paid: paid
        )
        onSaved(
            LessonTickUndo(
                message: "已记录：\(group.name) \(CN.hm(slot.startMinutes)) 上完",
                created: created,
                previous: previous
            )
        )
        dismiss()
    }
}
