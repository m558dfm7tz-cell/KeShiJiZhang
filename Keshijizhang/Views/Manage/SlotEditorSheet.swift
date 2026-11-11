import SwiftUI

struct SlotDraft: Identifiable, Equatable {
    var id = UUID()
    var weekday: Int
    var startMinutes: Int
    var endMinutes: Int
}

struct SlotEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    var initialWeekday: Int
    var initialStart: Int
    var initialEnd: Int
    var onSave: (Int, Int, Int) -> Void

    @State private var weekday: Int
    @State private var start: Date
    @State private var end: Date

    init(weekday: Int = 1, startMinutes: Int = 600, endMinutes: Int = 660, onSave: @escaping (Int, Int, Int) -> Void) {
        initialWeekday = weekday
        initialStart = startMinutes
        initialEnd = endMinutes
        self.onSave = onSave
        _weekday = State(initialValue: weekday)
        _start = State(initialValue: CN.date(minutes: startMinutes))
        _end = State(initialValue: CN.date(minutes: endMinutes))
    }

    private var startMinutes: Int { CN.minutes(from: start) }
    private var endMinutes: Int { CN.minutes(from: end) }
    private var valid: Bool { endMinutes > startMinutes }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(alignment: .leading, spacing: 16) {
                    Text("星期")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                weekday = day
                            } label: {
                                Text(CN.weekdayShort(day))
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(weekday == day ? Color.white : Color.primary)
                                    .background(weekday == day ? Theme.blue : Color.white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    FormCard {
                        DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                        FormDivider()
                        DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                    }
                    if !valid {
                        Text("结束时间要晚于开始时间")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.red)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("固定上课时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard valid else { return }
        onSave(weekday, startMinutes, endMinutes)
        dismiss()
    }
}
