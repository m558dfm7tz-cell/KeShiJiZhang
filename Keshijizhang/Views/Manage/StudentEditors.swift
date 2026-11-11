import SwiftData
import SwiftUI

struct StudentEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var student: Student

    @Query(sort: \Organization.name) private var organizations: [Organization]
    @Query(sort: \SmallGroup.name) private var groups: [SmallGroup]

    @State private var showOrg = false
    @State private var showGroup = false
    @State private var showPrice = false
    @State private var showSlot = false
    @State private var slotWeekday = 1
    @State private var slotStart = 600
    @State private var slotEnd = 660
    @State private var editingSlotID: UUID?
    @State private var confirmDelete = false
    @State private var nameWarning = false

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink {
                        StudentRecordsView(student: student, backTitle: "管理")
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("上课记录")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("查看和修改每一节课")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.gray.opacity(0.35))
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    SectionLabel(text: "基础信息")
                    FormCard {
                        FieldRow(title: "姓名", text: $student.name, placeholder: "学生姓名")
                        FormDivider()
                        FieldRow(title: "家长电话", text: $student.parentPhone, placeholder: "选填", keyboard: .phone)
                        FormDivider()
                        Button { showPrice = true } label: {
                            ValueRow(title: "每节单价", value: CN.money(student.currentPrice))
                        }
                        .buttonStyle(.plain)
                        FormDivider()
                        Button { showOrg = true } label: {
                            ValueRow(title: "所属机构", value: student.organization?.name ?? "私教")
                        }
                        .buttonStyle(.plain)
                    }

                    SectionLabel(text: "每周固定课")
                    FormCard {
                        let slots = student.sortedSlots
                        if slots.isEmpty {
                            Text("还没有固定时间")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(.system(size: 16))
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
                            slotStart = 600
                            slotEnd = 660
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

                    SectionLabel(text: "其他")
                    FormCard {
                        Button { showGroup = true } label: {
                            ValueRow(title: "所在小班", value: student.smallGroup?.name ?? "无")
                        }
                        .buttonStyle(.plain)
                        FormDivider()
                        FieldRow(title: "备注", text: $student.note, placeholder: "选填，例如初二数学")
                        FormDivider()
                        ToggleRow(title: "停课", subtitle: "打开后不再出现在今天的固定课里，历史记录保留", isOn: $student.paused)
                    }

                    Button {
                        confirmDelete = true
                    } label: {
                        Text("删除学生")
                            .font(.system(size: 17, weight: .semibold))
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
        .navigationTitle(student.name.isEmpty ? "学生" : student.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { saveAndClose() }
            }
        }
        .keyboardDone()
        .sheet(isPresented: $showPrice) {
            PriceAdjustView(presetStudentID: student.uuid)
        }
        .sheet(isPresented: $showSlot) {
            SlotEditorSheet(weekday: slotWeekday, startMinutes: slotStart, endMinutes: slotEnd) { weekday, start, end in
                if let editingSlotID, let slot = student.slots.first(where: { $0.uuid == editingSlotID }) {
                    slot.weekday = weekday
                    slot.startMinutes = start
                    slot.endMinutes = end
                } else {
                    let slot = WeeklySlot(weekday: weekday, startMinutes: start, endMinutes: end)
                    slot.student = student
                    context.insert(slot)
                }
                try? context.save()
            }
        }
        .confirmationDialog("所属机构", isPresented: $showOrg, titleVisibility: .visible) {
            Button("私教") { student.organization = nil }
            ForEach(organizations, id: \.uuid) { org in
                Button(org.name) { student.organization = org }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("所在小班", isPresented: $showGroup, titleVisibility: .visible) {
            Button("不在小班") { student.smallGroup = nil }
            ForEach(groups, id: \.uuid) { group in
                Button(group.name) {
                    student.smallGroup = group
                    student.organization = group.organization
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("一名学生只能在一个小班。")
        }
        .alert("请填写姓名", isPresented: $nameWarning) {
            Button("好", role: .cancel) {}
        }
        .alert("删除学生？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                student.organization = nil
                student.smallGroup = nil
                context.delete(student)
                try? context.save()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将同时删除该学生的上课记录、固定时间和价格记录，且无法恢复。")
        }
    }

    private func saveAndClose() {
        let trimmed = student.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameWarning = true
            return
        }
        student.name = trimmed
        try? context.save()
        dismiss()
    }
}

struct NewStudentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Organization.name) private var organizations: [Organization]
    @Query(sort: \SmallGroup.name) private var groups: [SmallGroup]

    var presetOrganizationID: UUID?
    var presetGroupID: UUID?

    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var priceText = ""
    @State private var paused = false
    @State private var orgID: UUID?
    @State private var groupID: UUID?
    @State private var slots: [SlotDraft] = []
    @State private var showOrg = false
    @State private var showGroup = false
    @State private var showSlot = false
    @State private var nameWarning = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "基础信息")
                        FormCard {
                            FieldRow(title: "姓名", text: $name, placeholder: "学生姓名")
                            FormDivider()
                            FieldRow(title: "家长电话", text: $phone, placeholder: "选填", keyboard: .phone)
                            FormDivider()
                            FieldRow(title: "每节单价", text: $priceText, placeholder: "例如 150", keyboard: .decimal)
                            FormDivider()
                            Button { showOrg = true } label: {
                                ValueRow(title: "所属机构", value: orgName)
                            }
                            .buttonStyle(.plain)
                        }
                        SectionLabel(text: "每周固定课")
                        FormCard {
                            if slots.isEmpty {
                                Text("可以稍后再加")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.secondary)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 48)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                FormDivider()
                            }
                            ForEach(slots) { slot in
                                HStack {
                                    Text("每\(CN.weekdayShort(slot.weekday))  \(CN.hm(slot.startMinutes))–\(CN.hm(slot.endMinutes))")
                                    Spacer()
                                    Button {
                                        slots.removeAll { $0.id == slot.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(Color.gray.opacity(0.45))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 50)
                                FormDivider()
                            }
                            Button { showSlot = true } label: {
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
                        SectionLabel(text: "其他")
                        FormCard {
                            Button { showGroup = true } label: {
                                ValueRow(title: "所在小班", value: groupName)
                            }
                            .buttonStyle(.plain)
                            FormDivider()
                            FieldRow(title: "备注", text: $note, placeholder: "选填")
                            FormDivider()
                            ToggleRow(title: "停课", subtitle: "打开后不出现在今天的固定课里", isOn: $paused)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("添加学生")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .keyboardDone()
            .onAppear {
                if orgID == nil { orgID = presetOrganizationID }
                if groupID == nil { groupID = presetGroupID }
            }
            .sheet(isPresented: $showSlot) {
                SlotEditorSheet { weekday, start, end in
                    slots.append(SlotDraft(weekday: weekday, startMinutes: start, endMinutes: end))
                }
            }
            .confirmationDialog("所属机构", isPresented: $showOrg, titleVisibility: .visible) {
                Button("私教") { orgID = nil }
                ForEach(organizations, id: \.uuid) { org in
                    Button(org.name) { orgID = org.uuid }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("所在小班", isPresented: $showGroup, titleVisibility: .visible) {
                Button("不在小班") { groupID = nil }
                ForEach(groups, id: \.uuid) { group in
                    Button(group.name) { groupID = group.uuid }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("请填写姓名和单价", isPresented: $nameWarning) {
                Button("好", role: .cancel) {}
            } message: {
                Text("单价可以填 0。留空无法保存。")
            }
        }
    }

    private var orgName: String {
        organizations.first { $0.uuid == orgID }?.name ?? "私教"
    }

    private var groupName: String {
        groups.first { $0.uuid == groupID }?.name ?? "无"
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let price = CN.parseMoney(priceText) else {
            nameWarning = true
            return
        }
        let student = Student(name: trimmed, parentPhone: phone.trimmingCharacters(in: .whitespaces), note: note.trimmingCharacters(in: .whitespaces), paused: paused)
        context.insert(student)
        if let groupID, let chosen = groups.first(where: { $0.uuid == groupID }) {
            student.smallGroup = chosen
            student.organization = chosen.organization
        } else if let orgID {
            student.organization = organizations.first { $0.uuid == orgID }
        }
        let record = PriceRecord(unitPrice: price, effectiveFrom: CN.startOfDay(Date()))
        record.student = student
        context.insert(record)
        for draft in slots {
            let slot = WeeklySlot(weekday: draft.weekday, startMinutes: draft.startMinutes, endMinutes: draft.endMinutes)
            slot.student = student
            context.insert(slot)
        }
        try? context.save()
        dismiss()
    }
}
