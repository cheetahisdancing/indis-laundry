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

    /// Assets.xcassets 안의 아이콘 이름
    var iconName: String {
        switch self {
        case .washer: return "IconWasher"
        case .dryer: return "IconDryer"
        }
    }
}

/// 서버(또는 센서)가 알려주는 기기의 실제 상태
enum MachineStatus: Equatable {
    case available
    case running(startedAt: Date, endsAt: Date)
    case pickup(since: Date)
    case broken
}

/// 화면에 보여줄 상태 (남은 시간에 따라 '곧 끝남'이 추가됨)
enum DisplayState: Equatable {
    case available
    case running
    case soon
    case pickup
    case broken
}

struct Machine: Identifiable, Equatable {
    let id: UUID
    var number: Int
    var kind: MachineKind
    var status: MachineStatus

    init(number: Int, kind: MachineKind, status: MachineStatus) {
        self.id = UUID()
        self.number = number
        self.kind = kind
        self.status = status
    }

    var name: String { "\(kind.label) \(number)" }

    /// '곧 끝남'으로 바뀌는 기준 (5분)
    static let soonThreshold: TimeInterval = 5 * 60

    func displayState(at now: Date) -> DisplayState {
        switch status {
        case .available:
            return .available
        case .broken:
            return .broken
        case .pickup:
            return .pickup
        case .running(_, let endsAt):
            let left = endsAt.timeIntervalSince(now)
            if left <= 0 { return .pickup }
            return left <= Machine.soonThreshold ? .soon : .running
        }
    }

    /// 남은 시간(초). 돌아가는 중이 아니면 nil
    func remainingSeconds(at now: Date) -> TimeInterval? {
        guard case .running(_, let endsAt) = status else { return nil }
        let left = endsAt.timeIntervalSince(now)
        return left > 0 ? left : nil
    }

    /// 진행률 0.0 ~ 1.0. 돌아가는 중이 아니면 nil
    func progress(at now: Date) -> Double? {
        guard case .running(let startedAt, let endsAt) = status else { return nil }
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        let done = now.timeIntervalSince(startedAt) / total
        return min(max(done, 0), 1)
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
            let since: Date
            switch status {
            case .pickup(let s): since = s
            case .running(_, let endsAt): since = endsAt
            default: since = now
            }
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

struct LaundryRoom: Identifiable, Hashable {
    let id: String
    let name: String
}

/// 세탁 코스 (프로토타입용)
struct WashCourse: Identifiable, Hashable {
    let id: String
    let name: String
    let seconds: TimeInterval

    static func courses(for kind: MachineKind) -> [WashCourse] {
        switch kind {
        case .washer:
            return [
                WashCourse(id: "standard", name: "표준 세탁 · 40분", seconds: 40 * 60),
                WashCourse(id: "quick", name: "쾌속 세탁 · 25분", seconds: 25 * 60),
                WashCourse(id: "demo", name: "데모 · 1분", seconds: 60)
            ]
        case .dryer:
            return [
                WashCourse(id: "standard", name: "표준 건조 · 50분", seconds: 50 * 60),
                WashCourse(id: "demo", name: "데모 · 1분", seconds: 60)
            ]
        }
    }
}
