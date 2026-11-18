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

    /// 건물마다 대기 줄에 선 인원 (예시)
    private(set) var queueCountByRoom: [String: Int]
    /// 내 대기 순서 (줄 안 섰으면 nil)
    private(set) var myQueuePosition: Int? = nil
    private(set) var myQueueRoomID: String? = nil

    /// '빈 세탁기 생기면 알림' 켜짐 여부
    var notifyWhenFree = false
    /// 끝나면 알림 받기로 한 기기들
    private(set) var notifyMachineIDs: Set<UUID> = []

    /// 다른 사람 빨래가 수거 대기로 이만큼 지나면 꺼내 간 것으로 시뮬레이션
    private let simulatedPickupDelay: TimeInterval = 8 * 60

    @ObservationIgnored private var timer: Timer? = nil

    // MARK: - 초기화

    init() {
        var rooms: [LaundryRoom] = []
        for n in 1...10 {
            rooms.append(LaundryRoom(id: "dorm\(n)", name: "생활관 \(n)동", group: "생활관"))
        }
        for n in 1...3 {
            rooms.append(LaundryRoom(id: "female\(n)", name: "여사 \(n)동", group: "여사"))
        }
        self.rooms = rooms
        self.selectedRoomID = rooms[0].id

        var rng = SeededGenerator(seed: 2026)
        let start = Date()
        var machines: [String: [Machine]] = [:]
        var queues: [String: Int] = [:]
        for (index, room) in rooms.enumerated() {
            machines[room.id] = LaundryStore.sampleMachines(roomIndex: index, now: start, rng: &rng)
            queues[room.id] = Int.random(in: 0...3, using: &rng)
        }
        self.machinesByRoom = machines
        self.queueCountByRoom = queues

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

    var roomGroups: [String] { ["생활관", "여사"] }

    func rooms(in group: String) -> [LaundryRoom] {
        rooms.filter { $0.group == group }
    }

    var machines: [Machine] {
        machinesByRoom[selectedRoomID] ?? []
    }

    var floors: [Int] {
        Array(Set(machines.map { $0.floor })).sorted()
    }

    func machines(onFloor floor: Int) -> [Machine] {
        machines
            .filter { $0.floor == floor }
            .sorted { ($0.kind == .washer ? 0 : 1, $0.number) < ($1.kind == .washer ? 0 : 1, $1.number) }
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

    func roomName(of machineID: UUID) -> String {
        guard let roomID = roomID(of: machineID) else { return "세탁실" }
        return rooms.first { $0.id == roomID }?.name ?? "세탁실"
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
        update(id) {
            $0.status = .running(startedAt: startedAt,
                                 endsAt: startedAt.addingTimeInterval(course.seconds),
                                 course: course)
            $0.startedByMe = true
            $0.lastRemindedAt = nil
        }
    }

    func markCollected(_ id: UUID) {
        update(id) {
            $0.status = .available
            $0.startedByMe = false
            $0.lastRemindedAt = nil
        }
        if let m = machine(id: id) { machineBecameFree(m) }
    }

    func reportBroken(_ id: UUID) {
        cancelNotify(id)
        update(id) {
            $0.status = .broken
            $0.startedByMe = false
        }
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
        guard case .running(_, let endsAt, let course) = machine.status else { return }
        notifyMachineIDs.insert(machine.id)
        NotificationManager.shared.schedule(
            id: machine.id.uuidString,
            title: "\(machine.name) 세탁이 끝났어요",
            body: "\(roomName(of: machine.id)) \(machine.name) · \(course.name) 코스가 끝났어요. 빨래를 꺼내 주세요.",
            at: endsAt
        )
    }

    /// 수거 대기 3분이 지난 기기의 주인에게 알림 보내기.
    /// 프로토타입에서는 '주인이 받게 될 알림'을 이 기기에 띄워서 보여줍니다.
    @discardableResult
    func remindOwner(_ id: UUID) -> Bool {
        guard let m = machine(id: id),
              m.isPickupOverdue(at: now),
              m.secondsUntilRemindable(at: now) <= 0,
              let since = m.pickupSince(at: now) else { return false }

        let minutes = Int(now.timeIntervalSince(since) / 60)
        update(id) { $0.lastRemindedAt = Date() }
        NotificationManager.shared.sendNow(
            title: "빨래를 꺼내 주세요",
            body: "\(roomName(of: id)) \(m.name) 세탁이 끝난 지 \(minutes)분이 지났어요. 다음 사람이 기다리고 있어요."
        )
        return true
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
                case .running(_, let endsAt, let course) where endsAt <= now:
                    newList[i].status = .pickup(since: endsAt, course: course)
                    notifyMachineIDs.remove(newList[i].id)
                    changed = true
                case .pickup(let since, _) where !newList[i].startedByMe
                    && now.timeIntervalSince(since) >= simulatedPickupDelay:
                    newList[i].status = .available
                    newList[i].lastRemindedAt = nil
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

    // MARK: - 예시 데이터 (건물마다 3개 층 × 세탁기 2대 + 건조기 1대)

    private static func sampleMachines(roomIndex: Int, now: Date, rng: inout SeededGenerator) -> [Machine] {
        var list: [Machine] = []
        for floor in 1...3 {
            for number in 1...2 {
                list.append(Machine(floor: floor, number: number, kind: .washer,
                                    status: washerStatus(now: now, rng: &rng)))
            }
            list.append(Machine(floor: floor, number: 1, kind: .dryer,
                                status: dryerStatus(now: now, rng: &rng)))
        }
        // 시연용: 모든 건물의 2층 세탁기2는 끝난 지 3분이 넘은 수거 대기 상태
        let overdueMinutes = Double(4 + roomIndex % 4)
        list[4].status = .pickup(since: now.addingTimeInterval(-overdueMinutes * 60),
                                 course: WashCourse.washerCourses[roomIndex % 4])
        return list
    }

    private static func running(_ course: WashCourse, minutesLeft: Double, now: Date) -> MachineStatus {
        let endsAt = now.addingTimeInterval(minutesLeft * 60)
        return .running(startedAt: endsAt.addingTimeInterval(-course.seconds), endsAt: endsAt, course: course)
    }

    private static func washerStatus(now: Date, rng: inout SeededGenerator) -> MachineStatus {
        let course = WashCourse.washerCourses.randomElement(using: &rng) ?? .standard
        switch Int.random(in: 0..<10, using: &rng) {
        case 0, 1, 2:
            return .available
        case 3, 4, 5, 6:
            return running(course, minutesLeft: Double(Int.random(in: 8...Int(course.minutes) - 2, using: &rng)), now: now)
        case 7, 8:
            return running(course, minutesLeft: Double(Int.random(in: 1...4, using: &rng)), now: now)
        default:
            return .pickup(since: now.addingTimeInterval(-Double(Int.random(in: 0...1, using: &rng)) * 60), course: course)
        }
    }

    private static func dryerStatus(now: Date, rng: inout SeededGenerator) -> MachineStatus {
        switch Int.random(in: 0..<10, using: &rng) {
        case 0, 1, 2, 3:
            return running(.dryStandard, minutesLeft: Double(Int.random(in: 3...45, using: &rng)), now: now)
        case 4, 5, 6, 7:
            return .available
        case 8:
            return .broken
        default:
            return .pickup(since: now.addingTimeInterval(-60), course: .dryStandard)
        }
    }
}
