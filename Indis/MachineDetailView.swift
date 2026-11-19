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
                ToolbarItem(placement: .topBarLeading) {
                    if let machine = store.machine(id: machineID) {
                        let favorite = store.isFavorite(machine)
                        Button {
                            store.toggleFavorite(machine)
                        } label: {
                            SVGIcon(name: favorite ? "IconStarFill" : "IconStar",
                                    size: 24,
                                    color: favorite ? Color(hex: 0xA16207) : Theme.ink)
                        }
                        .accessibilityLabel(favorite ? "즐겨찾기에서 빼기" : "즐겨찾기에 추가")
                    }
                }
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
                    if let course = machine.course, state != .available, state != .broken {
                        Text("\(course.name) 코스 · \(Int(course.minutes))분")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.mutedFill, in: Capsule())
                    }
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
                    PrimaryButton(title: course.buttonLabel, icon: "IconTimer",
                                  filled: course.id != "demo") {
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
                if !machine.startedByMe {
                    ownerReminder(machine)
                }
                PrimaryButton(title: "빨래 꺼냈어요", icon: "IconMyLaundry",
                              filled: machine.startedByMe) {
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

extension MachineDetailView {
    /// 수거 대기 3분이 지나면 세탁물 주인에게 알림 보내기
    @ViewBuilder
    func ownerReminder(_ machine: Machine) -> some View {
        let now = store.now
        let wait = machine.secondsUntilRemindable(at: now)

        VStack(spacing: 8) {
            if !machine.isPickupOverdue(at: now) {
                Text("끝난 지 3분이 지나면 세탁물 주인에게 알림을 보낼 수 있어요 · \(Machine.clockText(wait)) 남음")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.center)
            } else if wait > 0 {
                HStack(spacing: 8) {
                    SVGIcon(name: "IconAvailable", size: 20, color: Theme.primary)
                    Text("주인에게 알림을 보냈어요")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("\(Int(wait.rounded(.up)))초 뒤에 다시 보낼 수 있어요")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
            } else {
                PrimaryButton(title: "세탁물 주인에게 알림 보내기", icon: "IconBell") {
                    store.remindOwner(machine.id)
                }
                Text("프로토타입에서는 주인이 받을 알림이 이 기기에 표시돼요.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtle)
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
