import SwiftUI

/// 홈 화면 그리드의 기기 카드 하나
struct MachineCard: View {
    let machine: Machine
    let now: Date
    var isNotifying: Bool = false

    var body: some View {
        let state = machine.displayState(at: now)
        let overdue = machine.isPickupOverdue(at: now)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                MachineIcon(kind: machine.kind, state: state, size: 44)
                Spacer()
                if overdue {
                    Text("3분 초과")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(state.color, in: Capsule())
                } else if isNotifying {
                    SVGIcon(name: "IconBell", size: 18, color: Theme.subtle)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(machine.statusText(at: now))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(state.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let course = machine.course, state != .available, state != .broken {
                    Text(machine.startedByMe ? "\(course.name) 코스 · 내 빨래" : "\(course.name) 코스")
                        .font(.caption)
                        .foregroundStyle(Theme.subtle)
                        .lineLimit(1)
                }
            }

            if let progress = machine.progress(at: now) {
                ProgressView(value: progress)
                    .tint(state.color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            state == .broken ? Theme.mutedFill : Theme.card,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(state == .available ? state.color : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(state: state))
    }

    private func accessibilityText(state: DisplayState) -> String {
        var text = "\(machine.name), \(machine.statusText(at: now))"
        if let course = machine.course, state != .available, state != .broken {
            text += ", \(course.name) 코스"
        }
        return text
    }
}
