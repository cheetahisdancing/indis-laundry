import Foundation
import Observation

/// 앱 전체 상태. 지금은 예시 데이터로 동작하고,
/// 나중에 실제 서버/센서와 연결할 때 이 클래스만 바꾸면 됩니다.
@Observable
final class LaundryStore {
    // MARK: - 상태

    var now = Date()
    let rooms: [LaundryRoom]
    var selectedRoomID: String
    private(set) var machinesByRoom: [String: [Machine]]

    /// 방마다 대기 줄에 선 인원 (예시)
    private(set) var queueCountByRoom: [String: Int]
    /// 내 대기 순서 (줄 안 섰으면 nil)
    private(set) var myQueuePosition: Int? = nil
    private(set) var myQueueRoomID: String? = nil

    /// '빈 세탁기 생기면 알림' 켜짐 여부
    var notifyWhenFree = false
    /// 끝나면 알림 받기로 한 기기들
    private(set) var notifyMachineIDs: Set<UUID> = []

    /// 수거 대기 상태가 이만큼 지나면 누군가 꺼내 간 것으로 시뮬레이션
    private let simulatedPickupDelay: TimeInterval = 3 * 60

    @ObservationIgnored private var timer: Timer? = nil

    // MARK: - 초기화

    init() {
        let rooms = [
            LaundryRoom(id: "a", name: "A동 세탁실"),
            LaundryRoom(id: "b", name: "B동 세탁실"),
            LaundryRoom(id: "c", name: "C동 세탁실")
        ]
        self.rooms = rooms
        self.selectedRoomID = rooms[0].id
        self.machinesByRoom = LaundryStore.sampleMachines(now: Date())
        self.queueCountByRoom = ["a": 2, "b": 0, "c": 1]

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - 읽기용 값

    var currentRoom: LaundryRoom {
        rooms.first { $0.id == selectedRoomID } ?? rooms[0]
    }

    var machines: [Machine] {
        machinesByRoom[selectedRoomID] ?? []
    }

    var queueCount: Int {
        queueCountByRoom[selectedRoomID] ?? 0
    }

    var isInQueueHere: Bool {
        myQueuePosition != nil && myQueueRoomID == selectedRoomID
    }

    func machine(id: UUID) -> Machine? {
        for list in machinesByRoom.values {
            if let m = list.first(where: { $0.id == id }) { return m }
        }
        return nil
    }

    func availableCount(_ kind: MachineKind) -> Int {
        machines.filter { $0.kind == kind && $0.displayState(at: now) == .available }.count
    }

    /// 가장 빨리 비는 기기까지 남은 시간 문구
    func soonestWaitText(_ kind: MachineKind) -> String {
        if availableCount(kind) > 0 { return "지금 바로" }
        let lefts = machines
            .filter { $0.kind == kind }
            .compactMap { $0.remainingSeconds(at: now) }
        guard let soonest = lefts.min() else { return "정보 없음" }
        return Machine.minutesText(soonest)
    }

    func isNotifying(_ machine: Machine) -> Bool {
        notifyMachineIDs.contains(machine.id)
    }

    // MARK: - 동작

    func refresh() {
        now = Date()
    }

    func start(_ id: UUID, course: WashCourse) {
        let startedAt = Date()
        update(id) { $0.status = .running(startedAt: startedAt, endsAt: startedAt.addingTimeInterval(course.seconds)) }
    }

    func markCollected(_ id: UUID) {
        update(id) { $0.status = .available }
        if let m = machine(id: id) { machineBecameFree(m) }
    }

    func reportBroken(_ id: UUID) {
        cancelNotify(id)
        update(id) { $0.status = .broken }
    }

    func markFixed(_ id: UUID) {
        update(id) { $0.status = .available }
        if let m = machine(id: id) { machineBecameFree(m) }
    }

    func toggleNotify(_ machine: Machine) {
        if notifyMachineIDs.contains(machine.id) {
            cancelNotify(machine.id)
            return
        }
        guard case .running(_, let endsAt) = machine.status else { return }
        notifyMachineIDs.insert(machine.id)
        NotificationManager.shared.schedule(
            id: machine.id.uuidString,
            title: "\(machine.name) 세탁이 끝났어요",
            body: "\(currentRoom.name)에서 빨래를 꺼내 주세요.",
            at: endsAt
        )
    }

    func joinQueue() {
        guard myQueuePosition == nil else { return }
        let count = (queueCountByRoom[selectedRoomID] ?? 0) + 1
        queueCountByRoom[selectedRoomID] = count
        myQueuePosition = count
        myQueueRoomID = selectedRoomID
    }

    func leaveQueue() {
        guard let roomID = myQueueRoomID else { return }
        queueCountByRoom[roomID] = max((queueCountByRoom[roomID] ?? 1) - 1, 0)
        myQueuePosition = nil
        myQueueRoomID = nil
    }

    func setNotifyWhenFree(_ on: Bool) {
        notifyWhenFree = on
        if on { NotificationManager.shared.requestPermission() }
    }

    // MARK: - 내부 로직

    private func cancelNotify(_ id: UUID) {
        notifyMachineIDs.remove(id)
        NotificationManager.shared.cancel(id: id.uuidString)
    }

    private func update(_ id: UUID, _ change: (inout Machine) -> Void) {
        for (roomID, list) in machinesByRoom {
            if let index = list.firstIndex(where: { $0.id == id }) {
                var newList = list
                change(&newList[index])
                machinesByRoom[roomID] = newList
                return
            }
        }
    }

    /// 1초마다 호출: 시간 갱신 + 상태 변화 시뮬레이션
    private func tick() {
        now = Date()
        var freed: [Machine] = []

        for (roomID, list) in machinesByRoom {
            var newList = list
            var changed = false
            for i in newList.indices {
                switch newList[i].status {
                case .running(_, let endsAt) where endsAt <= now:
                    newList[i].status = .pickup(since: endsAt)
                    notifyMachineIDs.remove(newList[i].id)
                    changed = true
                case .pickup(let since) where now.timeIntervalSince(since) >= simulatedPickupDelay:
                    newList[i].status = .available
                    freed.append(newList[i])
                    changed = true
                default:
                    break
                }
            }
            if changed { machinesByRoom[roomID] = newList }
        }

        for m in freed { machineBecameFree(m) }
    }

    /// 기기가 비었을 때: 대기 줄 당기기 + 알림
    private func machineBecameFree(_ machine: Machine) {
        guard machine.kind == .washer,
              let roomID = roomID(of: machine.id) else { return }
        let roomName = rooms.first { $0.id == roomID }?.name ?? "세탁실"

        if myQueueRoomID == roomID, let position = myQueuePosition {
            if position <= 1 {
                myQueuePosition = nil
                myQueueRoomID = nil
                NotificationManager.shared.sendNow(
                    title: "내 차례예요!",
                    body: "\(roomName) \(machine.name)이 비었어요."
                )
            } else {
                myQueuePosition = position - 1
            }
        }
        queueCountByRoom[roomID] = max((queueCountByRoom[roomID] ?? 0) - 1, 0)

        if notifyWhenFree && roomID == selectedRoomID {
            NotificationManager.shared.sendNow(
                title: "빈 세탁기가 생겼어요",
                body: "\(roomName) \(machine.name)을 지금 쓸 수 있어요."
            )
        }
    }

    private func roomID(of machineID: UUID) -> String? {
        machinesByRoom.first { $0.value.contains { $0.id == machineID } }?.key
    }

    // MARK: - 예시 데이터

    private static func sampleMachines(now: Date) -> [String: [Machine]] {
        func running(startedMinutesAgo: Double, minutesLeft: Double) -> MachineStatus {
            .running(startedAt: now.addingTimeInterval(-startedMinutesAgo * 60),
                     endsAt: now.addingTimeInterval(minutesLeft * 60))
        }
        func pickup(minutesAgo: Double) -> MachineStatus {
            .pickup(since: now.addingTimeInterval(-minutesAgo * 60))
        }

        return [
            "a": [
                Machine(number: 1, kind: .washer, status: .available),
                Machine(number: 2, kind: .washer, status: running(startedMinutesAgo: 8, minutesLeft: 32)),
                Machine(number: 3, kind: .washer, status: running(startedMinutesAgo: 36, minutesLeft: 4)),
                Machine(number: 4, kind: .washer, status: pickup(minutesAgo: 1)),
                Machine(number: 1, kind: .dryer, status: running(startedMinutesAgo: 32, minutesLeft: 18)),
                Machine(number: 2, kind: .dryer, status: .broken)
            ],
            "b": [
                Machine(number: 1, kind: .washer, status: running(startedMinutesAgo: 20, minutesLeft: 20)),
                Machine(number: 2, kind: .washer, status: running(startedMinutesAgo: 38, minutesLeft: 2)),
                Machine(number: 3, kind: .washer, status: pickup(minutesAgo: 2)),
                Machine(number: 1, kind: .dryer, status: .available)
            ],
            "c": [
                Machine(number: 1, kind: .washer, status: .available),
                Machine(number: 2, kind: .washer, status: .available),
                Machine(number: 1, kind: .dryer, status: running(startedMinutesAgo: 10, minutesLeft: 40)),
                Machine(number: 2, kind: .dryer, status: running(startedMinutesAgo: 45, minutesLeft: 5))
            ]
        ]
    }
}
