import SwiftUI

/// Card style shared with MGUpd's ControlPanel: material fill, continuous
/// rounded corners, hairline border.
struct FishPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

/// Weekday circle picker, Monday-first. Days use Calendar numbering
/// (1 = Sunday … 7 = Saturday).
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    private let order = [2, 3, 4, 5, 6, 7, 1]
    private let names = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                Button {
                    if days.contains(day) { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(names[day - 1])
                        .font(.callout)
                        .frame(width: 30, height: 30)
                        .background(days.contains(day) ? Color.accentColor.opacity(0.25) : .clear,
                                    in: Circle())
                        .overlay(Circle().strokeBorder(days.contains(day) ? Color.accentColor : .secondary.opacity(0.4)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("周\(names[day - 1])")
                .accessibilityAddTraits(days.contains(day) ? .isSelected : [])
            }
        }
    }
}