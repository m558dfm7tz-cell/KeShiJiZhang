import SwiftData
import SwiftUI

struct PriceAdjustView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Student.name) private var students: [Student]

    var presetStudentID: UUID?

    @State private var studentID: UUID?
    @State private var priceText = ""
    @State private var fromDate = CN.startOfDay(Date())
    @State private var showStudents = false
    @State private var warning = false

    private var student: Student? {
        students.first { $0.uuid == studentID }
    }

    private var parsed: Double? { CN.parseMoney(priceText) }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FormCard {
                            Button { showStudents = true } label: {
                                ValueRow(title: "学生", value: student?.name ?? "请选择")
                            }
                            .buttonStyle(.plain)
                            FormDivider()
                            HStack {
                                Text("现在单价")
                                Spacer()
                                Text(student.map { "\(CN.money($0.currentPrice))/节" } ?? "—")
                                    .foregroundStyle(Theme.secondary)
                            }
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            FormDivider()
                            HStack {
                                Text("新单价")
                                Spacer()
                                Text("¥")
                                    .foregroundStyle(Theme.secondary)
                                TextField("0", text: $priceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                Text("/节")
                                    .foregroundStyle(Theme.secondary)
                            }
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            FormDivider()
                            DatePicker("从哪天起", selection: $fromDate, displayedComponents: .date)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 50)
                        }

                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)

                        SectionLabel(text: "价格变动记录")
                        if let student {
                            let records = student.prices.sorted {
                                if $0.effectiveFrom != $1.effectiveFrom { return $0.effectiveFrom > $1.effectiveFrom }
                                return $0.createdAt > $1.createdAt
                            }
                            if records.isEmpty {
                                Card {
                                    Text("还没有单价")
                                        .foregroundStyle(Theme.secondary)
                                }
                            } else {
                                FormCard {
                                    ForEach(Array(records.enumerated()), id: \.element.uuid) { index, record in
                                        if index > 0 { FormDivider() }
                                        HStack {
                                            Text("\(CN.priceDay(record.effectiveFrom))起")
                                            Spacer()
                                            Text(CN.money(record.unitPrice))
                                                .fontWeight(.semibold)
                                        }
                                        .font(.system(size: 16))
                                        .padding(.horizontal, 16)
                                        .frame(minHeight: 50)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("调整后续价格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(student == nil || parsed == nil)
                }
            }
            .keyboardDone()
            .onAppear {
                if studentID == nil {
                    studentID = presetStudentID ?? students.first?.uuid
                }
            }
            .sheet(isPresented: $showStudents) {
                NavigationStack {
                    List {
                        ForEach(students, id: \.uuid) { item in
                            Button {
                                studentID = item.uuid
                                showStudents = false
                            } label: {
                                HStack {
                                    Text(item.name)
                                    Spacer()
                                    Text(CN.money(item.currentPrice))
                                        .foregroundStyle(Theme.secondary)
                                    if item.uuid == studentID {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .navigationTitle("选择学生")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showStudents = false }
                        }
                    }
                }
            }
            .alert("请选择学生并填写单价", isPresented: $warning) {
                Button("好", role: .cancel) {}
            }
        }
    }

    private var note: String {
        guard let student else { return "选择学生后，可以从某一天起使用新单价。已经记下的课不会改。" }
        let day = CN.startOfDay(fromDate)
        let previous = CN.calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let old = student.effectivePrice(on: previous)
        let newText = parsed.map(CN.money) ?? "新单价"
        return "\(CN.monthDay(day))以后的课按\(newText)计；之前已上的课还是\(CN.money(old))，不会变。"
    }

    private func save() {
        guard let student, let value = parsed else {
            warning = true
            return
        }
        let day = CN.startOfDay(fromDate)
        if let existing = student.prices.first(where: { CN.isSameDay($0.effectiveFrom, day) }) {
            existing.unitPrice = value
        } else {
            let record = PriceRecord(unitPrice: value, effectiveFrom: day)
            record.student = student
            context.insert(record)
        }
        try? context.save()
        dismiss()
    }
}
