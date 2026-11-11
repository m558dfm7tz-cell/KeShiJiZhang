import SwiftData
import SwiftUI

struct GroupEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var group: SmallGroup

    @State private var showSlot = false
    @State private var showMembers = false
    @State private var confirmDelete = false
    @State private var slotWeekday = 1
    @State private var slotStart = 17 * 60
    @State private var slotEnd = 18 * 60
    @State private var editingSlotID: UUID?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "小班")
                    FormCard {
                        FieldRow(title: "小班名字", text: $group.name, placeholder: "例如周三钢琴班")
                    }
                    SectionLabel(text: "每周固定时间")
                    FormCard {
                        let slots = group.sortedSlots
                        if slots.isEmpty {
                            Text("还没有固定时间，今天页就不会出现这门小班课")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                            FormDivider()
                        }
                        ForEach(slots, id: \.uuid) { slot in
                            HStack {
                                Text("每\(CN.weekdayShort(slot.weekday))")
                                Spacer()
                                Text("\(CN.hm(slot.startMinutes))–\(CN.hm(slot.endMinutes))")
                                    .foregroundStyle(Theme.secondary)
                                Button {
                                    context.delete(slot)
                                    try? context.save()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.gray.opacity(0.45))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingSlotID = slot.uuid
                                slotWeekday = slot.weekday
                                slotStart = slot.startMinutes
                                slotEnd = slot.endMinutes
                                showSlot = true
                            }
                            FormDivider()
                        }
                        Button {
                            editingSlotID = nil
                            slotWeekday = CN.mondayBasedWeekday(Date())
                            slotStart = 17 * 60
                            slotEnd = 18 * 60
                            showSlot = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("添加固定时间")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                        }
                        .buttonStyle(.plain)
                    }

                    SectionLabel(text: "成员")
                    FormCard {
                        let people = group.students.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        if people.isEmpty {
                            Text("还没有学生")
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                            FormDivider()
                        }
                        ForEach(people, id: \.uuid) { student in
                            HStack {
                                Avatar(text: student.name, color: avatarColor(for: student.name, muted: student.paused), size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.name)
                                    Text(student.paused ? "已停课，今天点名会跳过" : CN.money(student.currentPrice))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Button("移出") {
                                    student.smallGroup = nil
                                    try? context.save()
                                }
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.red)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            FormDivider()
                        }
                        Button { showMembers = true } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("添加学生到这个小班")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("一名学生只能在一个小班。上课打卡时，请假的学生可以单独关掉。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)

                    Button { confirmDelete = true } label: {
                        Text("删除小班（学生和记录保留）")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(group.name.isEmpty ? "小班" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { close() }
            }
        }
        .keyboardDone()
        .sheet(isPresented: $showSlot) {
            SlotEditorSheet(weekday: slotWeekday, startMinutes: slotStart, endMinutes: slotEnd) { weekday, start, end in
                if let editingSlotID, let slot = group.slots.first(where: { $0.uuid == editingSlotID }) {
                    slot.weekday = weekday
                    slot.startMinutes = start
                    slot.endMinutes = end
                } else {
                    let slot = WeeklySlot(weekday: weekday, startMinutes: start, endMinutes: end)
                    slot.group = group
                    context.insert(slot)
                }
                try? context.save()
            }
        }
        .sheet(isPresented: $showMembers) {
            AssignGroupSheet(group: group)
        }
        .alert("删除小班？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                for student in Array(group.students) {
                    student.smallGroup = nil
                }
                context.delete(group)
                try? context.save()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("学生和已经记下的课都会保留，只是以后不再有这个小班的固定课。")
        }
    }

    private func close() {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { group.name = trimmed }
        try? context.save()
        dismiss()
    }
}

struct NewGroupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var warning = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(alignment: .leading, spacing: 12) {
                    FormCard {
                        FieldRow(title: "小班名字", text: $name, placeholder: "例如周三钢琴班")
                    }
                    Text("建好后可以再加固定时间和学生。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("添加小班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .keyboardDone()
            .alert("请填写小班名字", isPresented: $warning) {
                Button("好", role: .cancel) {}
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            warning = true
            return
        }
        context.insert(SmallGroup(name: trimmed))
        try? context.save()
        dismiss()
    }
}

struct AssignGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Student.name) private var students: [Student]
    var group: SmallGroup

    private var candidates: [Student] {
        students.filter { $0.smallGroup?.uuid != group.uuid }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("没有可添加的学生")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates, id: \.uuid) { student in
                    Button {
                        student.smallGroup = group
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(student.name)
                                if let current = student.smallGroup {
                                    Text("当前在\(current.name)，点按会改到这里")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("添加学生")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
