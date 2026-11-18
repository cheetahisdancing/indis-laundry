import SwiftUI

/// 기기를 눌렀을 때 뜨는 상세 화면
struct MachineDetailView: View {
    @Environment(LaundryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let machineID: UUID

    @State private var confirmBroken = false

    var body: some View {
        NavigationStack {
            Group {
                if let machine = store.machine(id: machineID) {
                    content(machine)
                } else {
                    Text("기기 정보를 찾을 수 없어요")
                        .foregroundStyle(Theme.subtle)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func content(_ machine: Machine) -> some View {
        let state = machine.displayState(at: store.now)
        let ringValue = CGFloat(machine.progress(at: store.now) ?? (state == .available ? 0 : 1))

        return ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(state.color.opacity(0.15), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: ringValue)
                        .stroke(state.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: store.now)
                    MachineIcon(kind: machine.kind, state: state, size: 72)
                }
                .frame(width: 168, height: 168)
                .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(machine.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(state.label)
                        .font(.headline)
                        .foregroundStyle(state.color)
                    if let left = machine.remainingSeconds(at: store.now) {
                        Text(Machine.clockText(left))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .accessibilityLabel("남은 시간 \(Machine.minutesText(left))")
                        Text("남은 시간")
                            .font(.footnote)
                            .foregroundStyle(Theme.subtle)
                    } else if state == .pickup {
                        Text(machine.statusText(at: store.now))
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtle)
                    }
                }

                actions(machine, state)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .confirmationDialog("\(machine.name)을 고장으로 신고할까요?",
                            isPresented: $confirmBroken,
                            titleVisibility: .visible) {
            Button("고장 신고", role: .destructive) {
                store.reportBroken(machine.id)
            }
            Button("취소", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func actions(_ machine: Machine, _ state: DisplayState) -> some View {
        VStack(spacing: 10) {
            switch state {
            case .available:
                Text("코스를 골라 사용을 시작하세요")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
                ForEach(WashCourse.courses(for: machine.kind)) { course in
                    PrimaryButton(title: course.name, icon: "IconTimer") {
                        store.start(machine.id, course: course)
                    }
                }

            case .running, .soon:
                PrimaryButton(
                    title: store.isNotifying(machine) ? "알림 취소" : "끝나면 알림 받기",
                    icon: "IconBell",
                    filled: !store.isNotifying(machine)
                ) {
                    store.toggleNotify(machine)
                }

            case .pickup:
                PrimaryButton(title: "빨래 꺼냈어요", icon: "IconMyLaundry") {
                    store.markCollected(machine.id)
                }

            case .broken:
                PrimaryButton(title: "수리 완료로 표시", icon: "IconAvailable", filled: false) {
                    store.markFixed(machine.id)
                }
            }

            if state != .broken {
                Button {
                    confirmBroken = true
                } label: {
                    HStack(spacing: 6) {
                        SVGIcon(name: "IconBroken", size: 18, color: Theme.subtle)
                        Text("고장 신고")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.subtle)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 큰 버튼
struct PrimaryButton: View {
    let title: String
    let icon: String
    var filled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SVGIcon(name: icon, size: 20, color: filled ? .white : Theme.primary)
                Text(title)
                    .font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(filled ? .white : Theme.primary)
            .background(
                filled ? Theme.primary : Theme.primarySoft,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let store = LaundryStore()
    return MachineDetailView(machineID: store.machines[1].id)
        .environment(store)
}
