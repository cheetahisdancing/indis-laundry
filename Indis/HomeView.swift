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
                    favoritesSection
                    roomPicker
                    summary

                    ForEach(store.floors, id: \.self) { floor in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(floor)층")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.subtle)
                                .padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(store.machines(onFloor: floor)) { machine in
                                    Button {
                                        selectedMachineID = machine.id
                                    } label: {
                                        MachineCard(
                                            machine: machine,
                                            now: store.now,
                                            isNotifying: store.isNotifying(machine),
                                            isFavorite: store.isFavorite(machine)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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
            ForEach(store.roomGroups, id: \.self) { group in
                Section(group) {
                    ForEach(store.rooms(in: group)) { room in
                        Button(room.name) {
                            store.selectedRoomID = room.id
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                SVGIcon(name: "IconRoom", size: 20)
                Text("\(store.currentRoom.name) 세탁실")
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
        .accessibilityLabel("기숙사 선택, 현재 \(store.currentRoom.name)")
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

    // MARK: - 즐겨찾는 기기

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SVGIcon(name: "IconStarFill", size: 16, color: Color(hex: 0xA16207))
                Text("즐겨찾는 기기")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }

            if store.favoriteMachines.isEmpty {
                HStack(spacing: 10) {
                    SVGIcon(name: "IconStar", size: 22, color: Theme.subtle)
                    Text("자주 쓰는 세탁기를 눌러 상세 화면 위쪽의 별을 누르면 여기에서 바로 상태를 볼 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.favoriteMachines) { item in
                        Button {
                            selectedMachineID = item.machine.id
                        } label: {
                            MachineCard(
                                machine: item.machine,
                                now: store.now,
                                isNotifying: store.isNotifying(item.machine),
                                roomName: item.room.name,
                                isFavorite: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 하단 버튼

    private var bottomBar: some View {
        Button {
            store.setNotifyWhenFree(!store.notifyWhenFree)
        } label: {
            HStack(spacing: 8) {
                SVGIcon(name: "IconBell", size: 22, color: store.notifyWhenFree ? Theme.primary : .white)
                Text(store.notifyWhenFree ? "빈 세탁기 알림 켜짐 · 끄기" : "빈 세탁기 생기면 알림 받기")
                    .font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(store.notifyWhenFree ? Theme.primary : .white)
            .background(
                store.notifyWhenFree ? Theme.primarySoft : Theme.primary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
