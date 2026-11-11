import SwiftData
import SwiftUI

struct OrganizationEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var org: Organization

    @State private var showAssign = false
    @State private var showNewStudent = false
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
