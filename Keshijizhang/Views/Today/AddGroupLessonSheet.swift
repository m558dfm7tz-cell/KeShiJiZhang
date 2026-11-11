import SwiftData
import SwiftUI

struct AddGroupLessonSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var group: SmallGroup
    var onSaved: (LessonTickUndo) -> Void

    @State private var step = 0
    @State private var visibleMonth = CN.startOfMonth(Date())
    @State private var day = CN.startOfDay(Date())
    @State private var hasTime = true
    @State private var timeDate = CN.date(minutes: 19 * 60)
    @State private var showTime = false
    @State private var kind: LessonKind = .extra

    @State private var count: Int
    @State private var amountText: String
    @State private var customText = ""
    @State private var showCustom = false

    @State private var attending: Set<UUID> = []

    init(group: SmallGroup, onSaved: @escaping (LessonTickUndo) -> Void) {
        self.group = group
        self.onSaved = onSaved
        let initial = group.standardCount > 0 ? group.standardCount : 1
        _count = State(initialValue: initial)
        _amountText = State(initialValue: Self.plain(group.classCharge(for: initial)))
    }

    private var members: [Student] { group.activeStudents }
    private var minutes: Int { hasTime ? CN.minutes(from: timeDate) : -1 }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                if step == 0 {
                    setup
                } else if !members.isEmpty {
                    roll
                } else {
                    headcount
                }
            }
            .navigationTitle(step == 0 ? "给\(group.name)加课" : group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "取消" : "上一步") {
                        if step == 0 {
                            dismiss()
                        } else {
                            step = 0
                        }
                    }
                }
            }
            .keyboardDone()
            .sheet(isPresented: $showTime) { timeSheet }
            .alert("其他人数", isPresented: $showCustom) {
                TextField("人数", text: $customText)
                    .keyboardType(.numberPad)
                Button("确定") { applyCustom() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("填这次实际来了几个人。")
            }
            .onAppear {
                if attending.isEmpty {
                    attending = Set(members.map(\.uuid))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    MonthGrid(visibleMonth: $visibleMonth, face: face) { picked in
                        day = picked
                    }
                }
                Text("选一天。默认今天，也可以补记以前或排到以后。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                FormCard {
                    Button { showTime = true } label: {
                        ValueRow(title: "时间", value: hasTime ? CN.hm(minutes) : "不填")
                    }
                    .buttonStyle(.borderless)
                    FormDivider()
                    HStack {
                        Text("类型")
                        Spacer()
                        kindButton(.extra)
                        kindButton(.makeup)
                    }
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Button {
                    step = 1
                } label: {
                    Text("下一步")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.bg)
        }
    }

    private var headcount: some View {
        let charge = currentAmount
        let extra = max(count - 1, 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(CN.listDay(day)) · \(hasTime ? CN.hm(minutes) : "不填时间") · \(kind.title)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(1...6, id: \.self) { number in
                        countButton(number)
                    }
                }
                otherButton
                Text("\(count) 人 · 基础 \(CN.money(group.basePrice)) + (\(extra))×\(CN.money(group.perPersonDelta))")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 4)
                FormCard {
                    HStack {
                        Text("金额")
                        Spacer()
                        Text("¥")
                            .foregroundStyle(Theme.secondary)
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    .font(.system(size: 16))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                }
                Text("应收 \(CN.money(charge))。改金额只影响这一节。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar(title: group.standardCount > 0 ? "标准 \(group.standardCount) 人" : "标准人数", confirm: "确认 \(count) 人") {
                if group.standardCount > 0 {
                    setCount(group.standardCount)
                    saveHeadcount(group.standardCount)
                }
            } confirmAction: {
                saveHeadcount(count)
            }
        }
    }

    private var roll: some View {
        let present = members.filter { attending.contains($0.uuid) }.count
        let absent = max(members.count - present, 0)
        let total = rollTotal(present: present)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(CN.listDay(day)) · \(hasTime ? CN.hm(minutes) : "不填时间") · \(kind.title)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                Text("到场的学生各记一节。关掉的学生记为请假，不计费。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                if members.isEmpty {
                    Card {
                        EmptyHint(title: "这个小班没有在上课的学生", message: "停课的学生不会出现在点名里。")
                    }
                } else {
                    FormCard {
                        ForEach(Array(members.enumerated()), id: \.element.uuid) { index, student in
                            if index > 0 { FormDivider() }
                            memberRow(student)
                        }
                    }
                }
                Text("\(present) 人上课 · \(absent) 人请假")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 4)
                Text("应收 \(CN.money(total))")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(present == 0 ? Theme.secondary : Theme.red)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar(title: "全到", confirm: "确认", confirmDisabled: members.isEmpty) {
                attending = Set(members.map(\.uuid))
            } confirmAction: {
                saveRoll()
            }
        }
    }

    private func bottomBar(
        title: String,
        confirm: String,
        confirmDisabled: Bool = false,
        secondary: @escaping () -> Void,
        confirmAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Button(action: secondary) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(title.hasPrefix("标准") && group.standardCount <= 0)
            Button(action: confirmAction) {
                Text(confirm)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(confirmDisabled ? Color.gray.opacity(0.35) : Theme.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(confirmDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var currentAmount: Double {
        CN.parseMoney(amountText) ?? group.classCharge(for: count)
    }

    private func rollTotal(present: Int) -> Double {
        if group.usesConfiguredClassPrice {
            guard present > 0 else { return 0 }
            return group.classCharge(for: present)
        }
        return Money.sum(members.filter { attending.contains($0.uuid) }.map { $0.effectivePrice(on: day) })
    }

    private func countButton(_ number: Int) -> some View {
        let selected = count == number
        let isStandard = number == group.standardCount && group.standardCount > 0
        return Button {
            setCount(number)
        } label: {
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.system(size: 22, weight: .semibold))
                Text(isStandard ? "标准" : " ")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(selected ? Theme.blue : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var otherButton: some View {
        let selected = count > 6
        return Button {
            customText = count > 6 ? "\(count)" : ""
            showCustom = true
        } label: {
            Text(selected ? "其他人数 · \(count)" : "其他人数…")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Theme.blue)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? Theme.blue : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func memberRow(_ student: Student) -> some View {
        let on = attending.contains(student.uuid)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.system(size: 16, weight: .semibold))
                Text(on ? (group.usesConfiguredClassPrice ? "上课" : CN.money(student.effectivePrice(on: day))) : "请假 · 不计费")
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
                    }
                }
            ))
            .labelsHidden()
            .tint(Theme.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func kindButton(_ value: LessonKind) -> some View {
        let on = kind == value
        return Button {
            kind = value
        } label: {
            Text(value.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(on ? Theme.blue : Color(red: 0.93, green: 0.93, blue: 0.95), in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func face(_ date: Date) -> DayFace {
        if CN.isSameDay(date, day) { return .selected }
        if CN.isSameDay(date, Date()) { return .today }
        return .plain
    }

    private var timeSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("时间", selection: $timeDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Button("不填时间") {
                    hasTime = false
                    showTime = false
                }
                .foregroundStyle(Theme.red)
                Spacer()
            }
            .padding()
            .navigationTitle("时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTime = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        hasTime = true
                        showTime = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func setCount(_ number: Int) {
        guard number > 0 else { return }
        let previous = group.classCharge(for: count)
        let typed = CN.parseMoney(amountText)
        let followsFormula = typed == nil || abs((typed ?? 0) - previous) < 0.001
        count = number
        if followsFormula {
            let next = Self.plain(group.classCharge(for: number))
            if amountText != next {
                amountText = next
            }
        }
    }

    private func applyCustom() {
        guard let number = Int(customText.trimmingCharacters(in: .whitespaces)), number > 0 else { return }
        setCount(number)
    }

    private func saveHeadcount(_ number: Int) {
        guard number > 0 else { return }
        let typed = CN.parseMoney(amountText)
        let formula = group.classCharge(for: number)
        let override = typed.flatMap { abs($0 - formula) > 0.001 ? $0 : nil }
        let lesson = LessonFactory.recordGroupHeadcount(
            group: group,
            on: day,
            timeMinutes: minutes,
            count: number,
            amountOverride: override,
            kind: kind,
            slotKey: "",
            context: context,
            persists: false
        )
        onSaved(
            LessonTickUndo(
                message: "已记录：\(group.name) \(lesson.headcount) 人\(kind.title)",
                created: [lesson],
                previous: []
            )
        )
        dismiss()
    }

    private func saveRoll() {
        let applied = LessonFactory.applyAdHocGroupRoll(
            context: context,
            group: group,
            day: day,
            timeMinutes: minutes,
            kind: kind,
            attending: attending,
            persists: false
        )
        onSaved(
            LessonTickUndo(
                message: "已记录：\(group.name) \(kind.title)",
                created: applied.created,
                previous: []
            )
        )
        dismiss()
    }

    private static func plain(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}
