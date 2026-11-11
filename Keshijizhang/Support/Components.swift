import SwiftUI
import UIKit

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct CheckCircle: View {
    var checked: Bool
    var color: Color = Theme.green

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(checked ? color : Color.gray.opacity(0.35), lineWidth: 1.6)
                .background(Circle().fill(checked ? color : Color.clear))
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }
}

struct Pill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct Avatar: View {
    var text: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Text(String(text.prefix(1)))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

func avatarColor(for name: String, muted: Bool = false) -> Color {
    if muted { return Color.gray.opacity(0.45) }
    let palette: [Color] = [
        Theme.blue,
        Theme.purple,
        Color(red: 0.20, green: 0.62, blue: 0.86),
        Color(red: 0.96, green: 0.48, blue: 0.36),
    ]
    let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
}

struct MonthSwitcher: View {
    var title: String
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.blue)
        .buttonStyle(.plain)
    }
}

struct FillButton: View {
    var title: String
    var color: Color = Theme.blue
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    disabled ? Color.gray.opacity(0.35) : color,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct ScreenBackground: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

struct FormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

struct FormDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.6)
            .padding(.leading, 16)
    }
}

struct FieldRow: View {
    var title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: Kind = .text

    enum Kind { case text, phone, decimal }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }

    private var keyboardType: UIKeyboardType {
        switch keyboard {
        case .text: return .default
        case .phone: return .phonePad
        case .decimal: return .decimalPad
        }
    }
}

struct ValueRow: View {
    var title: String
    var value: String
    var valueColor: Color = Theme.blue
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.gray.opacity(0.35))
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.green)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }
}

struct PageHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DayFace {
    case plain
    case today
    case selected
    case rangeStart
    case rangeMiddle
    case rangeEnd
    case rangeSingle
}

struct MonthGrid: View {
    @Binding var visibleMonth: Date
    var face: (Date) -> DayFace
    var onTap: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let symbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    visibleMonth = CN.shiftMonth(visibleMonth, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                Text(CN.monthTitle(visibleMonth))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    visibleMonth = CN.shiftMonth(visibleMonth, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.primary)
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .frame(height: 18)
                }
                ForEach(Array(CN.daysInMonth(visibleMonth).enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let style = face(date)
        return Button {
            onTap(CN.startOfDay(date))
        } label: {
            ZStack {
                bar(style)
                if isCircle(style) {
                    Circle()
                        .fill(Theme.blue)
                        .frame(width: 32, height: 32)
                }
                Text("\(CN.dayNumber(date))")
                    .font(.system(size: 16, weight: isCircle(style) ? .semibold : .regular))
                    .foregroundStyle(textColor(style))
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bar(_ style: DayFace) -> some View {
        switch style {
        case .rangeStart:
            HStack(spacing: 0) {
                Color.clear
                Color(red: 0.80, green: 0.90, blue: 1.0)
            }
        case .rangeEnd:
            HStack(spacing: 0) {
                Color(red: 0.80, green: 0.90, blue: 1.0)
                Color.clear
            }
        case .rangeMiddle:
            Color(red: 0.80, green: 0.90, blue: 1.0)
        default:
            Color.clear
        }
    }

    private func isCircle(_ style: DayFace) -> Bool {
        switch style {
        case .selected, .rangeStart, .rangeEnd, .rangeSingle:
            return true
        default:
            return false
        }
    }

    private func textColor(_ style: DayFace) -> Color {
        switch style {
        case .selected, .rangeStart, .rangeEnd, .rangeSingle:
            return .white
        case .today, .rangeMiddle:
            return Theme.blue
        case .plain:
            return .primary
        }
    }
}

struct ChipScroll<Item: Identifiable, Label: View>: View {
    var items: [Item]
    var isSelected: (Item) -> Bool
    var action: (Item) -> Void
    @ViewBuilder var label: (Item) -> Label

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        action(item)
                    } label: {
                        label(item)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected(item) ? Color.white : Color.primary.opacity(0.8))
                            .background(
                                isSelected(item) ? Theme.blue : Theme.chipIdle,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct SegmentTabs<Item: Hashable>: View {
    var items: [Item]
    var title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == item ? Color.primary : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == item ? Theme.card : Color.clear)
                        )
                        .shadow(color: selection == item ? Color.black.opacity(0.06) : .clear, radius: 1, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(red: 0.91, green: 0.91, blue: 0.93), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MetricColumn: View {
    var label: String
    var value: String
    var color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct NavBackButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 17))
            }
        }
    }
}

extension View {
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
        }
    }
}

struct EmptyHint: View {
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
