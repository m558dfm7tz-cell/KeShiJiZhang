import SwiftData
import SwiftUI

struct OrganizationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var org: Organization

    @State private var showAssign = false
    @State private var showNewStudent = false
    @State private var showAssignGroup = false
    @State private var showNewGroup = false
    @State private var confirmDelete = false
    @State private var settlementOptions = ["每月月底", "每月月初", "上完即结", "按学期结算", "其他"]

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "机构信息")
                    FormCard {
                        FieldRow(title: "机构名字", text: $org.name, placeholder: "机构名字")
                        FormDivider()
                        FieldRow(title: "联系人", text: $org.contact, placeholder: "选填")
                        FormDivider()
                        FieldRow(title: "电话", text: $org.phone, placeholder: "选填", keyboard: .phone)
                        FormDivider()
                        Picker("结算方式", selection: $org.settlement) {
                            ForEach(settlementChoices, id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        FormDivider()
                        FieldRow(title: "备注", text: $org.note, placeholder: "例如转账到工行卡")
                    }

                    SectionLabel(text: "名下学生（单价各自算）")
                    FormCard {
                        let people = org.sortedStudents
                        if people.isEmpty {
                            Text("还没有学生")
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            FormDivider()
                        }
                        ForEach(people, id: \.uuid) { student in
                            NavigationLink {
                                StudentEditorView(student: student)
                            } label: {
                                HStack(spacing: 10) {
                                    Avatar(text: student.name, color: Theme.blue, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(student.name)
                                            .foregroundStyle(.primary)
                                        Text(studentPriceLine(student))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.gray.opacity(0.35))
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 54)
                            }
                            .buttonStyle(.plain)
                            FormDivider()
                        }
                        Button { showAssign = true } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("添加学生到这个机构")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                        }
                        .buttonStyle(.plain)
                    }

                    SectionLabel(text: "小班")
                    FormCard {
                        let classes = org.sortedGroups
                        if classes.isEmpty {
                            Text("还没有小班")
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            FormDivider()
                        }
                        ForEach(classes, id: \.uuid) { group in
                            HStack(spacing: 8) {
                                NavigationLink {
                                    GroupEditorView(group: group)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name)
                                            .foregroundStyle(.primary)
                                        Text(groupLine(group))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button("移出") {
                                    group.organization = nil
                                    group.syncMembersOrganization()
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
                        Button { showAssignGroup = true } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("添加已有小班")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        FormDivider()
                        Button { showNewGroup = true } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("新建小班")
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
                    Text("这里和小班资料里的「所属」是同一项。班归到这个机构后，班里有名字的学生也归这里。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)

                    Button { confirmDelete = true } label: {
                        Text("删除机构（学生和记录保留）")
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
        .navigationTitle(org.name.isEmpty ? "机构" : org.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { close() }
            }
        }
        .keyboardDone()
        .sheet(isPresented: $showAssign) {
            AssignOrganizationSheet(org: org) { showNewStudent = true }
        }
        .sheet(isPresented: $showNewStudent) {
            NewStudentSheet(presetOrganizationID: org.uuid)
        }
        .sheet(isPresented: $showAssignGroup) {
            AssignGroupOrganizationSheet(org: org)
        }
        .sheet(isPresented: $showNewGroup) {
            NewOrgGroupSheet(org: org)
        }
        .alert("删除机构？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                for student in Array(org.students) {
                    student.organization = nil
                }
                context.delete(org)
                try? context.save()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("学生和上课记录都会保留，这些学生会变成私教。")
        }
    }

    private var settlementChoices: [String] {
        var items = settlementOptions
        if !org.settlement.isEmpty, !items.contains(org.settlement) {
            items.insert(org.settlement, at: 0)
        }
        return items
    }

    private func groupLine(_ group: SmallGroup) -> String {
        let named = group.students.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let people = named.isEmpty ? "标准 \(group.standardCount) 人" : "\(named.count) 人"
        if group.scheduleSummary.isEmpty { return people }
        return "\(group.scheduleSummary) · \(people)"
    }

    private func studentPriceLine(_ student: Student) -> String {
        let days = student.weekdayListText
        if days.isEmpty { return CN.money(student.currentPrice) }
        return "\(CN.money(student.currentPrice)) · \(days)"
    }

    private func close() {
        let trimmed = org.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { org.name = trimmed }
        try? context.save()
        dismiss()
    }
}

struct NewOrganizationSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var contact = ""
    @State private var phone = ""
    @State private var settlement = "每月月底"
    @State private var note = ""
    @State private var warning = false

    private let settlements = ["每月月底", "每月月初", "上完即结", "按学期结算", "其他"]

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    FormCard {
                        FieldRow(title: "机构名字", text: $name, placeholder: "机构名字")
                        FormDivider()
                        FieldRow(title: "联系人", text: $contact, placeholder: "选填")
                        FormDivider()
                        FieldRow(title: "电话", text: $phone, placeholder: "选填", keyboard: .phone)
                        FormDivider()
                        Picker("结算方式", selection: $settlement) {
                            ForEach(settlements, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        FormDivider()
                        FieldRow(title: "备注", text: $note, placeholder: "选填")
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("添加机构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .keyboardDone()
            .alert("请填写机构名字", isPresented: $warning) {
                Button("好", role: .cancel) {}
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            warning = true
            return
        }
        let org = Organization(
            name: trimmed,
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            settlement: settlement,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(org)
        try? context.save()
        dismiss()
    }
}

struct AssignOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Student.name) private var students: [Student]
    var org: Organization
    var onCreate: () -> Void

    private var candidates: [Student] {
        students.filter { $0.organization?.uuid != org.uuid }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            onCreate()
                        }
                    } label: {
                        Label("新建学生并加入", systemImage: "plus")
                    }
                }
                Section("已有学生") {
                    if candidates.isEmpty {
                        Text("其他学生都已经在这个机构里")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates, id: \.uuid) { student in
                        Button {
                            student.organization = org
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.name)
                                    if let current = student.organization {
                                        Text("当前在\(current.name)，点按会改到这里")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("私教")
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
            }
            .navigationTitle("添加到机构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct AssignGroupOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SmallGroup.name) private var groups: [SmallGroup]
    var org: Organization

    private var candidates: [SmallGroup] {
        groups.filter { $0.organization?.uuid != org.uuid }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("其他小班都已经在这个机构里")
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates, id: \.uuid) { group in
                    Button {
                        group.organization = org
                        group.syncMembersOrganization()
                        context.saveSoon()
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                if let current = group.organization {
                                    Text("当前在\(current.name)，点按会改到这里")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("自己的")
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
            .navigationTitle("添加小班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct NewOrgGroupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var org: Organization
    @State private var name = ""
    @State private var warning = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(alignment: .leading, spacing: 12) {
                    FormCard {
                        FieldRow(title: "小班名字", text: $name, placeholder: "例如周三数学班")
                    }
                    Text("建好后算在\(org.name)名下，可以再去小班资料里加时间和价格。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("新建小班")
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
        let group = SmallGroup(name: trimmed)
        group.organization = org
        context.insert(group)
        context.saveSoon()
        dismiss()
    }
}
