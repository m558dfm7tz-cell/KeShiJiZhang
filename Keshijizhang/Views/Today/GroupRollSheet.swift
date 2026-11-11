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

    private var isReview: Bool { !existing.isEmpty }

    var body: some View {
        let members = group.activeStudents
        let amounts = amountsByStudent(members)
        let total = Money.sum(members.compactMap { attending.contains($0.uuid) ? amounts[$0.uuid] : nil })
        let title = buttonTitle(count: attending.count, total: total)
        return NavigationStack {
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
                                    memberRow(student, amount: amounts[student.uuid] ?? 0)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        FillButton(title: title, color: Theme.blue, disabled: members.isEmpty, action: save)
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

    private func buttonTitle(count: Int, total: Double) -> String {
        if count == 0 { return "全部记为请假" }
        let verb = isReview ? "保存" : "确认上完"
        return "\(verb) · \(count) 人 · \(CN.money(total))"
    }

    private func amountsByStudent(_ members: [Student]) -> [UUID: Double] {
        var amounts: [UUID: Double] = [:]
        amounts.reserveCapacity(members.count)
        for student in members {
            amounts[student.uuid] = amount(for: student)
        }
        return amounts
    }

    private func memberRow(_ student: Student, amount: Double) -> some View {
        let on = attending.contains(student.uuid)
        let hasPaid = paid.contains(student.uuid)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Avatar(text: student.name, color: avatarColor(for: student.name, muted: !on), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(on ? CN.money(amount) : "请假 · 不计费")
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
                    if hasPaid {
                        paid.remove(student.uuid)
                    } else {
                        paid.insert(student.uuid)
                    }
                } label: {
                    Pill(text: hasPaid ? "已收" : "未收", color: hasPaid ? Theme.green : Theme.red)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
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
            attending = Set(group.activeStudents.map(\.uuid))
        } else {
            attending = Set(existing.filter { $0.status != .leave }.compactMap { $0.student?.uuid })
            paid = Set(existing.filter(\.paid).compactMap { $0.student?.uuid })
        }
    }

    private func save() {
        let applied = LessonFactory.applyGroupRoll(
            context: context,
            group: group,
            slot: slot,
            day: day,
            attending: attending,
            paid: paid,
            persists: false
        )
        onSaved(
            LessonTickUndo(
                message: "已记录：\(group.name) \(CN.hm(slot.startMinutes)) 上完",
                created: applied.created,
                previous: applied.previous
            )
        )
        dismiss()
    }
}
