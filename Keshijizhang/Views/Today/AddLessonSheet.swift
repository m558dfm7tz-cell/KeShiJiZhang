import SwiftData
import SwiftUI

struct AddLessonSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var student: Student

    @State private var visibleMonth = CN.startOfMonth(Date())
    @State private var selected: Set<Date> = [CN.startOfDay(Date())]
    @State private var priceText = ""
    @State private var priceTouched = false
    @State private var ignorePriceEdit = false
    @State private var hasTime = false
    @State private var timeDate = CN.date(minutes: 19 * 60)
    @State private var showTime = false
    @State private var kind: LessonKind = .extra

    private var dates: [Date] { selected.map(CN.startOfDay).sorted() }

    private var uniformDefault: Double? {
        let prices = Set(dates.map { round2(student.effectivePrice(on: $0)) })
        return prices.count == 1 ? prices.first : nil
    }

    private var usingEachDayPrice: Bool {
        !priceTouched && uniformDefault == nil && !dates.isEmpty
    }

    private var perDate: [(Date, Double)] {
        if priceTouched, let typed = CN.parseMoney(priceText) {
            return dates.map { ($0, typed) }
        }
        return dates.map { ($0, student.effectivePrice(on: $0)) }
    }

    private var total: Double { Money.sum(perDate.map(\.1)) }

    private var priceIsValid: Bool {
        if dates.isEmpty { return false }
        if priceTouched { return CN.parseMoney(priceText) != nil }
        return true
    }

    private var conflictLines: [String] {
        dates.compactMap { date in
            let items = student.engagements(on: date)
            guard !items.isEmpty else { return nil }
            let time: String
            if items.count == 1, let minutes = items[0].timeMinutes {
                time = "（\(CN.hm(minutes))）"
            } else {
                time = ""
            }
            let countText = items.count == 1 ? "1 节课" : "\(items.count) 节课"
            return "\(CN.monthDay(date)) \(student.name)已经有 \(countText)\(time)，确定要再加一节吗？"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !conflictLines.isEmpty {
                            warning
                        }
                        Card {
                            MonthGrid(visibleMonth: $visibleMonth, face: face) { day in
                                toggle(day)
                            }
                        }
                        Text("可多选 · 默认今天 · 往前补记、往后排课都可以")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)

                        FormCard {
                            HStack {
                                Text("已选")
                                Spacer()
                                Text(selectionText)
                                    .foregroundStyle(Theme.blue)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            FormDivider()
                            HStack {
                                Text(usingEachDayPrice ? "每节价格" : "每节价格")
                                Spacer()
                                Text("¥")
                                    .foregroundStyle(Theme.secondary)
                                TextField(usingEachDayPrice ? "按当天单价" : "0", text: $priceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
                                    .onChange(of: priceText) { _, _ in
                                        if ignorePriceEdit {
                                            ignorePriceEdit = false
                                            return
                                        }
                                        priceTouched = true
                                    }
                            }
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            FormDivider()
                            Button {
                                showTime = true
                            } label: {
                                ValueRow(
                                    title: "时间（选填）",
                                    value: hasTime ? CN.hm(CN.minutes(from: timeDate)) : "不填"
                                )
                            }
                            .buttonStyle(.plain)
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

                        if usingEachDayPrice {
                            Text("所选日期的单价不一样，未改价格时按各天生效的单价分别记入。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        FillButton(
                            title: buttonTitle,
                            color: Theme.blue,
                            disabled: !priceIsValid,
                            action: save
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Theme.bg)
                }
            }
            .navigationTitle("给\(student.name)加课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .keyboardDone()
            .onAppear(perform: refreshDefaultPrice)
            .sheet(isPresented: $showTime) {
                timeSheet
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.orange)
            Text(conflictLines.joined(separator: "\n"))
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.05))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var selectionText: String {
        if dates.isEmpty { return "还没选" }
        if dates.count == 1, let date = dates.first {
            return CN.selectionDay(date)
        }
        let pieces = dates.prefix(8).map { "\(CN.dayNumber($0))日" }.joined(separator: "、")
        let more = dates.count > 8 ? "…" : ""
        return "\(dates.count) 天 \(pieces)\(more)"
    }

    private var buttonTitle: String {
        let verb = conflictLines.isEmpty ? "确认添加" : "仍然添加"
        return "\(verb) \(dates.count) 节 · \(CN.money(total))"
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
                .background(on ? Theme.blue : Color(red: 0.93, green: 0.93, blue: 0.95), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func face(_ date: Date) -> DayFace {
        if selected.contains(CN.startOfDay(date)) { return .selected }
        if CN.isSameDay(date, Date()) { return .today }
        return .plain
    }

    private func toggle(_ day: Date) {
        if selected.contains(day) {
            selected.remove(day)
        } else {
            selected.insert(day)
        }
        if !priceTouched {
            refreshDefaultPrice()
        }
    }

    private func refreshDefaultPrice() {
        let next = uniformDefault.map { plain($0) } ?? ""
        guard priceText != next else { return }
        ignorePriceEdit = true
        priceText = next
    }

    private func plain(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }

    private var timeSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("时间", selection: $timeDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                if hasTime {
                    Button("清除时间") {
                        hasTime = false
                        showTime = false
                    }
                    .foregroundStyle(Theme.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("上课时间")
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

    private func save() {
        guard priceIsValid else { return }
        let now = CN.startOfDay(Date())
        let minutes = hasTime ? CN.minutes(from: timeDate) : nil
        for (date, amount) in perDate {
            let standard = student.effectivePrice(on: date)
            let overridden = abs(round2(amount) - round2(standard)) > 0.001
            let status: LessonStatus = CN.startOfDay(date) > now ? .pending : .completed
            LessonFactory.make(
                context: context,
                student: student,
                date: date,
                timeMinutes: minutes,
                amount: amount,
                overridden: overridden,
                kind: kind,
                status: status,
                originKind: OriginKind.manual
            )
        }
        try? context.save()
        dismiss()
    }
}
