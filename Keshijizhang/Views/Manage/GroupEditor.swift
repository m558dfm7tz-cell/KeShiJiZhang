import SwiftData
import SwiftUI

struct GroupEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Organization.name) private var organizations: [Organization]
    @Bindable var group: SmallGroup

    @State private var showSlot = false
    @State private var showMembers = false
    @State private var showOrg = false
    @State private var confirmDelete = false
    @State private var slotWeekday = 1
    @State private var slotStart = 17 * 60
    @State private var slotEnd = 18 * 60
    @State private var editingSlotID: UUID?
    @State private var baseText = ""
    @State private var deltaText = ""
    @State private var draftName = ""
    @State private var loadedPrice = false
    @State private var deleted = false

    var body: some View {
        let hintDelta = previewDelta
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "小班")
                    FormCard {
                        FieldRow(title: "班名", text: $group.name, placeholder: "例如周三数学班")
                        FormDivider()
                        Button { showOrg = true } label: {
                            ValueRow(title: "所属", value: group.organization?.name ?? "自己的")
                        }
                        .buttonStyle(.borderless)
                    }

                    SectionLabel(text: "每周上课时间")
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
                                    context.saveSoon()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.gray.opacity(0.45))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }

                    SectionLabel(text: "价格")
                    FormCard {
                        moneyRow(title: "基础价格（1 人）", text: $baseText, placeholder: "0")
                        FormDivider()
                        HStack {
                            Text("标准人数")
                            Spacer()
                            Button {
                                if group.standardCount > 0 { group.standardCount -= 1 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.blue)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            Text("\(group.standardCount)")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(minWidth: 28)
                            Button {
                                group.standardCount += 1
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.blue)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 54)
                        FormDivider()
                        moneyRow(title: "每人增减", text: $deltaText, placeholder: "不填")
                    }
                    Text("每多一人加 \(CN.money(hintDelta))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)

                    SectionLabel(text: "学生（选填）")
                    FormCard {
                        ToggleRow(title: "按名字点名", subtitle: "打开后，今天打卡会逐个点名；关掉就只选人数", isOn: $group.rollByName)
                        FormDivider()
                        HStack(spacing: 8) {
                            TextField("学生名字", text: $draftName)
                            Button("添加") { addDraftName() }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.secondary : Theme.blue)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        FormDivider()
                        let people = group.students.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                        if people.isEmpty {
                            Text("还没有学生。不填名字时，今天按人数记一整节。")
                                .foregroundStyle(Theme.secondary)
                                .font(.system(size: 14))
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
                                    context.saveSoon()
                                }
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.red)
                                .frame(minHeight: 44)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            FormDivider()
                        }
                        Button { showMembers = true } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("添加已有学生")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("一名学生只能在一个小班。小班归到机构后，班里的学生也算在这个机构下。按名字点名时，关掉的学生记请假、不收费。")
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
        .onAppear(perform: loadPrice)
        .onDisappear {
            guard !deleted else { return }
            commit()
            context.saveSoon()
        }
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
                context.saveSoon()
            }
        }
        .sheet(isPresented: $showMembers) {
            AssignGroupSheet(group: group)
        }
        .confirmationDialog("所属", isPresented: $showOrg, titleVisibility: .visible) {
            Button("自己的") { assignOrganization(nil) }
            ForEach(organizations, id: \.uuid) { org in
                Button(org.name) { assignOrganization(org) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("删除小班？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                deleted = true
                for student in Array(group.students) {
                    student.smallGroup = nil
                }
                context.delete(group)
                context.saveNow()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("学生和已经记下的课都会保留，只是以后不再有这个小班的固定课。")
        }
    }

    private var previewDelta: Double {
        CN.parseMoney(deltaText) ?? 0
    }

    private func moneyRow(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("¥")
                .foregroundStyle(Theme.secondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    private func loadPrice() {
        guard !loadedPrice else { return }
        loadedPrice = true
        baseText = group.basePrice == 0 ? "" : Self.plain(group.basePrice)
        deltaText = group.perPersonDelta == 0 ? "" : Self.plain(group.perPersonDelta)
    }

    private func commit() {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { group.name = trimmed }
        group.basePrice = CN.parseMoney(baseText) ?? 0
        let deltaTrimmed = deltaText.trimmingCharacters(in: .whitespacesAndNewlines)
        group.perPersonDelta = deltaTrimmed.isEmpty ? 0 : (CN.parseMoney(deltaTrimmed) ?? 0)
        group.syncMembersOrganization()
    }

    private func close() {
        commit()
        context.saveNow()
        dismiss()
    }

    private func assignOrganization(_ org: Organization?) {
        group.organization = org
        group.syncMembersOrganization()
        context.saveSoon()
    }

    private func addDraftName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let student = Student(name: trimmed)
        student.smallGroup = group
        student.organization = group.organization
        context.insert(student)
        draftName = ""
        context.saveSoon()
    }

    private static func plain(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
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
    @Environment(\.modelContext) private var context
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
                        student.organization = group.organization
                        context.saveSoon()
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
