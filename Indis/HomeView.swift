import SwiftUI

/// 첫 화면: 세탁실 현황
struct HomeView: View {
    @Environment(LaundryStore.self) private var store
    @State private var selectedMachineID: UUID?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    roomPicker
                    summary
                    queueBanner

                    Text("세탁기 · 건조기")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.subtle)
                        .padding(.top, 4)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.machines) { machine in
                            Button {
                                selectedMachineID = machine.id
                            } label: {
                                MachineCard(
                                    machine: machine,
                                    now: store.now,
                                    isNotifying: store.isNotifying(machine)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("세탁실 현황")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.refresh()
                    } label: {
                        SVGIcon(name: "IconRefresh", size: 22)
                    }
                    .accessibilityLabel("새로고침")
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .sheet(isPresented: Binding(
                get: { selectedMachineID != nil },
                set: { if !$0 { selectedMachineID = nil } }
            )) {
                if let id = selectedMachineID {
                    MachineDetailView(machineID: id)
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: - 세탁실 선택

    private var roomPicker: some View {
        Menu {
            ForEach(store.rooms) { room in
                Button(room.name) {
                    store.selectedRoomID = room.id
                }
            }
        } label: {
            HStack(spacing: 10) {
                SVGIcon(name: "IconRoom", size: 20)
                Text(store.currentRoom.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("변경")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
        }
        .accessibilityLabel("세탁실 선택, 현재 \(store.currentRoom.name)")
    }

    // MARK: - 요약 카드

    private var summary: some View {
        HStack(spacing: 10) {
            SummaryTile(
                title: "비어 있는 세탁기",
                value: "\(store.availableCount(.washer))대",
                highlight: store.availableCount(.washer) > 0
            )
            SummaryTile(
                title: "세탁기 가장 빠른 대기",
                value: store.soonestWaitText(.washer),
                highlight: false
            )
        }
    }

    // MARK: - 대기 줄 안내

    @ViewBuilder
    private var queueBanner: some View {
        if store.isInQueueHere, let position = store.myQueuePosition {
            HStack(spacing: 12) {
                SVGIcon(name: "IconQueue", size: 24, color: Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("대기 \(position)번째")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                    Text("세탁기가 비면 알림으로 알려드릴게요.")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtle)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 하단 버튼

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                if store.isInQueueHere {
                    store.leaveQueue()
                } else {
                    NotificationManager.shared.requestPermission()
                    store.joinQueue()
                }
            } label: {
                HStack(spacing: 8) {
                    SVGIcon(name: "IconQueue", size: 22, color: store.isInQueueHere ? Theme.primary : .white)
                    Text(store.isInQueueHere ? "대기 취소" : "대기 줄 서기 · \(store.queueCount)명")
                        .font(.body.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(store.isInQueueHere ? Theme.primary : .white)
                .background(
                    store.isInQueueHere ? Theme.primarySoft : Theme.primary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(store.myQueuePosition != nil && !store.isInQueueHere)

            Button {
                store.setNotifyWhenFree(!store.notifyWhenFree)
            } label: {
                SVGIcon(name: "IconBell", size: 22, color: store.notifyWhenFree ? .white : Theme.ink)
                    .frame(width: 52, height: 52)
                    .background(
                        store.notifyWhenFree ? Theme.primary : Theme.card,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(store.notifyWhenFree ? Color.clear : Theme.border, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.notifyWhenFree ? "빈 세탁기 알림 끄기" : "빈 세탁기 생기면 알림 받기")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

/// 요약 숫자 타일
struct SummaryTile: View {
    let title: String
    let value: String
    let highlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(highlight ? Color(hex: 0x1E3A8A) : Theme.subtle)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(highlight ? Theme.primary : Theme.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlight ? Theme.primarySoft : Theme.card,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

#Preview {
    HomeView()
        .environment(LaundryStore())
}
