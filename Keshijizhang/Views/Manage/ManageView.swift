import SwiftData
import SwiftUI

struct ManageView: View {
    @Query(sort: \Student.createdAt) private var students: [Student]
    @Query(sort: \Organization.createdAt) private var organizations: [Organization]
    @Query(sort: \SmallGroup.createdAt) private var groups: [SmallGroup]

    @State private var showNewStudent = false
    @State private var showNewOrg = false
    @State private var showNewGroup = false
    @State private var showPrice = false
    @State private var needStudent = false

    private var orderedStudents: [Student] {
        students.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var orderedOrgs: [Organization] {
        organizations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(students.count) 位学生 · \(organizations.count) 个机构 · \(groups.count) 个小班")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                    HStack(spacing: 10) {
                        actionButton(title: "添加学生", system: "plus", color: Theme.blue) {
                            showNewStudent = true
                        }
                        actionButton(title: "添加机构", system: "building.2.fill", color: Theme.orange) {
                            showNewOrg = true
                        }
                        actionButton(title: "调整价格", system: "yensign", color: Theme.green) {
                            if students.isEmpty {
                                needStudent = true
                            } else {
                                showPrice = true
                            }
                        }
                    }
                    orgSection
                    groupSection
                    studentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("管理")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showNewStudent) { NewStudentSheet() }
        .sheet(isPresented: $showNewOrg) { NewOrganizationSheet() }
        .sheet(isPresented: $showNewGroup) { NewGroupSheet() }
        .sheet(isPresented: $showPrice) { PriceAdjustView(presetStudentID: nil) }
        .alert("还没有学生", isPresented: $needStudent) {
            Button("好", role: .cancel) {}
        } message: {
            Text("先添加学生，再调整后续价格。")
        }
    }

    private var orgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "机构")
            if orderedOrgs.isEmpty {
                Card {
                    EmptyHint(title: "还没有机构", message: "一对一私教可以不建机构。培训机构建好后，把学生加进去。")
                }
            } else {
                ForEach(orderedOrgs, id: \.uuid) { org in
                    NavigationLink {
                        OrganizationEditorView(org: org)
                    } label: {
                        Card {
                            HStack(spacing: 12) {
                                Avatar(text: org.name, color: Theme.purple)
                                Text(org.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(org.students.count) 人")
                                    .foregroundStyle(Theme.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.gray.opacity(0.35))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "小班")
            if groups.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        EmptyHint(title: "还没有小班", message: "小班有固定时间。上课时到场的学生按各自单价各记一节。")
                        Button("添加小班") { showNewGroup = true }
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(groups, id: \.uuid) { group in
                    NavigationLink {
                        GroupEditorView(group: group)
                    } label: {
                        Card {
                            HStack(spacing: 12) {
                                Avatar(text: group.name, color: Theme.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(groupLine(group))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.gray.opacity(0.35))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("添加小班") { showNewGroup = true }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private var studentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "学生")
            if orderedStudents.isEmpty {
                Card {
                    EmptyHint(title: "还没有学生", message: "点上方「添加学生」。数据只存在这台手机上。")
                }
            } else {
                ForEach(orderedStudents, id: \.uuid) { student in
                    NavigationLink {
                        StudentEditorView(student: student)
                    } label: {
                        Card {
                            HStack(spacing: 12) {
                                Avatar(
                                    text: student.name,
                                    color: avatarColor(for: student.name, muted: student.paused)
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(student.name)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        if let org = student.organization {
                                            Pill(text: org.name, color: Theme.purple)
                                        }
                                        if student.paused {
                                            Pill(text: "停课", color: Theme.secondary)
                                        }
                                    }
                                    Text(studentSubtitle(student))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Text(CN.money(student.currentPrice))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func studentSubtitle(_ student: Student) -> String {
        if student.organization == nil {
            return student.paused ? "私教 · 已停课" : "私教"
        }
        if let group = student.smallGroup {
            return group.name
        }
        return student.weekdayListText
    }

    private func groupLine(_ group: SmallGroup) -> String {
        let schedule = group.scheduleSummary
        let named = group.students.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let count = named.isEmpty ? "标准 \(group.standardCount) 人" : "\(named.count) 人"
        if schedule.isEmpty { return count }
        return "\(schedule) · \(count)"
    }

    private func actionButton(title: String, system: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: system)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
