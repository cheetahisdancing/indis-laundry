import SwiftUI

/// 홈 화면 그리드의 기기 카드 하나
struct MachineCard: View {
    let machine: Machine
    let now: Date
    var isNotifying: Bool = false

    var body: some View {
        let state = machine.displayState(at: now)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                MachineIcon(kind: machine.kind, state: state, size: 44)
                Spacer()
                if isNotifying {
                    SVGIcon(name: "IconBell", size: 18, color: Theme.subtle)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(machine.statusText(at: now))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(state.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if let progress = machine.progress(at: now) {
                ProgressView(value: progress)
                    .tint(state.color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
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
        .accessibilityLabel("\(machine.name), \(machine.statusText(at: now))")
    }
}
