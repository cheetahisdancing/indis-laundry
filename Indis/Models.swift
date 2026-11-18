import Foundation

/// 세탁기 / 건조기 구분
enum MachineKind: String, CaseIterable, Identifiable {
    case washer
    case dryer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .washer: return "세탁기"
        case .dryer: return "건조기"
        }
    }

    /// Assets.xcassets 안의 아이콘 이름 (멈춰 있을 때)
    var iconName: String {
        switch self {
        case .washer: return "IconWasher"
        case .dryer: return "IconDryer"
        }
    }

    /// 문 안쪽이 비어 있는 몸체 아이콘 (돌아갈 때 바탕)
    var bodyIconName: String { "IconMachineBody" }

    /// 문 안에서 회전시킬 내용물 아이콘
    var drumIconName: String {
        switch self {
        case .washer: return "IconWasherDrum"
        case .dryer: return "IconDryerDrum"
        }
    }
}

/// 세탁 코스
struct WashCourse: Identifiable, Hashable {
    let id: String
    let name: String
    let minutes: Double

    var seconds: TimeInterval { minutes * 60 }

    /// 버튼에 쓰는 문구: "표준 · 40분"
    var buttonLabel: String {
        id == "demo" ? "데모 · 1분 (시연용)" : "\(name) · \(Int(minutes))분"
    }

    static let strong = WashCourse(id: "strong", name: "강력", minutes: 45)
    static let standard = WashCourse(id: "standard", name: "표준", minutes: 40)
    static let synthetic = WashCourse(id: "synthetic", name: "합성", minutes: 42)
    static let wool = WashCourse(id: "wool", name: "울", minutes: 43)
    static let dryStandard = WashCourse(id: "dry", name: "표준 건조", minutes: 50)
    static let demo = WashCourse(id: "demo", name: "데모", minutes: 1)

    /// 세탁기 코스 4가지
    static let washerCourses: [WashCourse] = [.strong, .standard, .synthetic, .wool]

    static func courses(for kind: MachineKind) -> [WashCourse] {
        switch kind {
        case .washer: return washerCourses + [.demo]
        case .dryer: return [.dryStandard, .demo]
        }
    }
}

/// 서버(또는 센서)가 알려주는 기기의 실제 상태
enum MachineStatus: Equatable {
    case available
    case running(startedAt: Date, endsAt: Date, course: WashCourse)
    case pickup(since: Date, course: WashCourse?)
    case broken
}

/// 화면에 보여줄 상태 (남은 시간에 따라 '곧 끝남'이 추가됨)
enum DisplayState: Equatable {
    case available
    case running
    case soon
    case pickup
    case broken

    var isSpinning: Bool { self == .running || self == .soon }
}

struct Machine: Identifiable, Equatable {
    let id: UUID
    var floor: Int
    var number: Int
    var kind: MachineKind
    var status: MachineStatus
    /// 이 기기에 내가(이 휴대폰에서) 빨래를 넣었는지
    var startedByMe: Bool
    /// 주인에게 마지막으로 알림을 보낸 시각
    var lastRemindedAt: Date?

    init(floor: Int, number: Int, kind: MachineKind, status: MachineStatus, startedByMe: Bool = false) {
        self.id = UUID()
        self.floor = floor
        self.number = number
        self.kind = kind
        self.status = status
        self.startedByMe = startedByMe
        self.lastRemindedAt = nil
    }

    /// "1층 세탁기1"
    var name: String { "\(floor)층 \(kind.label)\(number)" }

    /// '곧 끝남'으로 바뀌는 기준 (5분)
    static let soonThreshold: TimeInterval = 5 * 60
    /// 수거 대기가 이만큼 지나면 주인에게 알림을 보낼 수 있음 (3분)
    static let pickupAlertDelay: TimeInterval = 3 * 60
    /// 같은 기기에 알림을 다시 보내려면 기다려야 하는 시간
    static let remindCooldown: TimeInterval = 60

    func displayState(at now: Date) -> DisplayState {
        switch status {
        case .available:
            return .available
        case .broken:
            return .broken
        case .pickup:
            return .pickup
        case .running(_, let endsAt, _):
            let left = endsAt.timeIntervalSince(now)
            if left <= 0 { return .pickup }
            return left <= Machine.soonThreshold ? .soon : .running
        }
    }

    /// 지금 돌고 있거나 방금 끝난 코스
    var course: WashCourse? {
        switch status {
        case .running(_, _, let course): return course
        case .pickup(_, let course): return course
        default: return nil
        }
    }

    /// 남은 시간(초). 돌아가는 중이 아니면 nil
    func remainingSeconds(at now: Date) -> TimeInterval? {
        guard case .running(_, let endsAt, _) = status else { return nil }
        let left = endsAt.timeIntervalSince(now)
        return left > 0 ? left : nil
    }

    /// 진행률 0.0 ~ 1.0. 돌아가는 중이 아니면 nil
    func progress(at now: Date) -> Double? {
        guard case .running(let startedAt, let endsAt, _) = status else { return nil }
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        let done = now.timeIntervalSince(startedAt) / total
        return min(max(done, 0), 1)
    }

    /// 세탁이 끝난 시각 (수거 대기 중일 때만)
    func pickupSince(at now: Date) -> Date? {
        switch status {
        case .pickup(let since, _):
            return since
        case .running(_, let endsAt, _) where endsAt <= now:
            return endsAt
        default:
            return nil
        }
    }

    /// 끝난 지 3분이 넘었는지
    func isPickupOverdue(at now: Date) -> Bool {
        guard let since = pickupSince(at: now) else { return false }
        return now.timeIntervalSince(since) >= Machine.pickupAlertDelay
    }

    /// 주인 알림 버튼을 누를 수 있게 되기까지 남은 초 (이미 가능하면 0)
    func secondsUntilRemindable(at now: Date) -> TimeInterval {
        guard let since = pickupSince(at: now) else { return .infinity }
        var wait = Machine.pickupAlertDelay - now.timeIntervalSince(since)
        if let last = lastRemindedAt {
            wait = max(wait, Machine.remindCooldown - now.timeIntervalSince(last))
        }
        return max(wait, 0)
    }

    func statusText(at now: Date) -> String {
        switch displayState(at: now) {
        case .available:
            return "사용 가능"
        case .broken:
            return "고장"
        case .running:
            return "사용 중 · \(Machine.minutesText(remainingSeconds(at: now) ?? 0)) 남음"
        case .soon:
            return "곧 끝남 · \(Machine.minutesText(remainingSeconds(at: now) ?? 0))"
        case .pickup:
            let since = pickupSince(at: now) ?? now
            let minutes = Int(now.timeIntervalSince(since) / 60)
            return minutes < 1 ? "수거 대기 · 방금 끝남" : "수거 대기 · \(minutes)분째"
        }
    }

    /// 125초 → "3분" (올림)
    static func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        return "\(max(minutes, 1))분"
    }

    /// 125초 → "02:05"
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

/// 기숙사 건물 (건물마다 세탁실이 있음)
struct LaundryRoom: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
}

/// 예시 데이터를 매번 똑같이 만들기 위한 난수 생성기
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
