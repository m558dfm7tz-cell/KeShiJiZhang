import SwiftData
import SwiftUI

struct LessonEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var lesson: Lesson

    @State private var day: Date
    @State private var hasTime: Bool
    @State private var timeDate: Date
    @State private var priceText: String
    @State private var status: LessonStatus
    @State private var kind: LessonKind
    @State private var paid: Bool
    @State private var showDate = false
    @State private var showTime = false
    @State private var showPrice = false
    @State private var confirmDelete = false
    @State private var priceWarning = false

    init(lesson: Lesson) {
        self.lesson = lesson
        _day = State(initialValue: CN.startOfDay(lesson.date))
        _hasTime = State(initialValue: lesson.hasTime)
        _timeDate = State(initialValue: CN.date(minutes: lesson.hasTime ? lesson.timeMinutes : 10 * 60))
        _priceText = State(initialValue: Self.plain(lesson.amount))
        _status = State(initialValue: lesson.status)
        _kind = State(initialValue: lesson.kind)
        _paid = State(initialValue: lesson.paid)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FormCard {
                            Button { showDate = true } label: {
                                ValueRow(title: "日期", value: CN.listDay(day))
                            }
                            .buttonStyle(.plain)
                            FormDivider()
                            Button { showTime = true } label: {
                                ValueRow(title: "时间", value: hasTime ? CN.hm(CN.minutes(from: timeDate)) : "不填")
                            }
                            .buttonStyle(.plain)
                            FormDivider()
                            Button { showPrice = true } label: {
                                ValueRow(title: "价格", value: priceLabel)
                            }
                            .buttonStyle(.plain)
                            FormDivider()
                            choiceRow(title: "状态") {
                                statusChip("已上", on: status == .completed) { status = .completed }
                                statusChip("未上", on: status == .pending) { status = .pending }
                                statusChip("请假", on: status == .leave) { status = .leave }
                            }
                            FormDivider()
                            choiceRow(title: "类型") {
                                statusChip("正常", on: kind == .fixed) { kind = .fixed }
                                statusChip("加课", on: kind == .extra) { kind = .extra }
                                statusChip("补课", on: kind == .makeup) { kind = .makeup }
                            }
                            FormDivider()
                            choiceRow(title: "收款") {
                                payChip("已收", on: paid && status == .completed, color: Theme.green) {
                                    status = .completed
                                    paid = true
                                }
                                payChip("未收", on: !paid || status != .completed, color: Theme.red) {
                                    paid = false
                                }
                            }
                        }

                        Text("改成「未上」：这节课回到当天的「今天」页待打勾，不计入应收。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)

                        Button { confirmDelete = true } label: {
                            Text("删除这条记录")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        FillButton(title: "保存修改", color: Theme.blue, action: save)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("修改这节课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .sheet(isPresented: $showDate) { dateSheet }
            .sheet(isPresented: $showTime) { timeSheet }
            .sheet(isPresented: $showPrice) { priceSheet }
            .alert("删除这条记录？", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) {
                    context.delete(lesson)
                    context.saveSoon()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后，这节课不再计入收款和月统计。固定课会回到那一天的待打卡。")
            }
            .alert("请填写价格", isPresented: $priceWarning) {
                Button("好", role: .cancel) {}
            } message: {
                Text("价格可以是 0，不能空着。")
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var priceLabel: String {
        if let value = CN.parseMoney(priceText) {
            return CN.money(value)
        }
        return "¥\(priceText)"
    }

    private func choiceRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16))
            Spacer(minLength: 8)
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    private func statusChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(on ? Theme.blue : Color(red: 0.93, green: 0.93, blue: 0.95), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func payChip(_ title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? color : Theme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(on ? color.opacity(0.14) : Color(red: 0.93, green: 0.93, blue: 0.95), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var dateSheet: some View {
        NavigationStack {
            DatePicker("日期", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            day = CN.startOfDay(day)
                            showDate = false
                        }
                    }
                }
        }
        .presentationDetents([.large])
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

    private var priceSheet: some View {
        NavigationStack {
            FormCard {
                HStack {
                    Text("价格")
                    Spacer()
                    Text("¥")
                        .foregroundStyle(Theme.secondary)
                    TextField("0", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
            }
            .padding()
            .navigationTitle("价格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showPrice = false }
                }
            }
            .keyboardDone()
        }
        .presentationDetents([.height(220)])
    }

    private func save() {
        guard let amount = CN.parseMoney(priceText) else {
            priceWarning = true
            return
        }
        let student = lesson.student
        let standard = student?.effectivePrice(on: day) ?? amount
        lesson.date = CN.startOfDay(day)
        lesson.timeMinutes = hasTime ? CN.minutes(from: timeDate) : -1
        lesson.amount = amount
        lesson.priceOverridden = abs(round2(amount) - round2(standard)) > 0.001
        lesson.kind = kind
        lesson.status = status
        if status != .completed {
            lesson.paid = false
        } else {
            lesson.paid = paid
        }
        context.saveSoon()
        dismiss()
    }

    private static func plain(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}

func lessonChip(_ lesson: Lesson) -> (String, Color) {
    if lesson.status == .leave { return ("请假", Theme.secondary) }
    if lesson.status == .pending { return ("未上", Theme.secondary) }
    switch lesson.kind {
    case .extra: return ("加课", Theme.orange)
    case .makeup: return ("补课", Theme.blue)
    case .fixed: return ("已上", Theme.green)
    }
}
