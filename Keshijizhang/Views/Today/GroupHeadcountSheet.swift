import SwiftData
import SwiftUI

struct GroupHeadcountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var group: SmallGroup
    var slot: WeeklySlot
    var day: Date
    var onSaved: (Lesson) -> Void

    @Environment(\.modelContext) private var context
    @State private var count: Int
    @State private var customText = ""
    @State private var showCustom = false

    init(group: SmallGroup, slot: WeeklySlot, day: Date, onSaved: @escaping (Lesson) -> Void) {
        self.group = group
        self.slot = slot
        self.day = day
        self.onSaved = onSaved
        let initial = group.standardCount > 0 ? group.standardCount : 1
        _count = State(initialValue: initial)
    }

    private var charge: Double { group.classCharge(for: count) }

    var body: some View {
        let summary = summaryLine
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(CN.listDay(day)) · \(CN.hm(slot.startMinutes))–\(CN.hm(slot.endMinutes))")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)
                        Text(intro)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(1...6, id: \.self) { number in
                                countButton(number)
                            }
                        }
                        otherButton

                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(summary)
                                    .font(.system(size: 16, weight: .medium))
                                Text("应收 \(CN.money(charge))")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Theme.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        Button {
                            confirm(group.standardCount)
                        } label: {
                            Text("标准 \(group.standardCount) 人")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(group.standardCount > 0 ? Theme.blue : Theme.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(group.standardCount <= 0)

                        Button {
                            confirm(count)
                        } label: {
                            Text("确认 \(count) 人")
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
            .navigationTitle("给\(group.name)上课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("其他人数", isPresented: $showCustom) {
                TextField("人数", text: $customText)
                    .keyboardType(.numberPad)
                Button("确定") { applyCustom() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("填这次实际来了几个人。")
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var intro: String {
        "基础价格按 1 人算。标准人数只是这里的默认选中，不改变单价。"
    }

    private var summaryLine: String {
        let extra = max(count - 1, 0)
        return "\(count) 人 · 基础 \(CN.money(group.basePrice)) + (\(extra))×\(CN.money(group.perPersonDelta))"
    }

    private func countButton(_ number: Int) -> some View {
        let selected = count == number
        let isStandard = number == group.standardCount && group.standardCount > 0
        return Button {
            count = number
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

    private func applyCustom() {
        guard let number = Int(customText.trimmingCharacters(in: .whitespaces)), number > 0 else { return }
        count = number
    }

    private func confirm(_ number: Int) {
        guard number > 0 else { return }
        count = number
        let lesson = LessonFactory.completeGroupHeadcount(
            slot,
            group: group,
            on: day,
            count: number,
            context: context,
            persists: false
        )
        onSaved(lesson)
        dismiss()
    }
}
