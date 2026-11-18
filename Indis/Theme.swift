import SwiftUI

extension Color {
    /// 0x1D4ED8 같은 16진수 색
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    static let background = Color(hex: 0xF6F7F9)
    static let card = Color.white
    static let mutedFill = Color(hex: 0xEEF0F3)
    static let ink = Color(hex: 0x16181D)
    static let subtle = Color(hex: 0x4B5563)
    static let border = Color(hex: 0xD5D9E0)
    static let primary = Color(hex: 0x1D4ED8)
    static let primarySoft = Color(hex: 0xE6EEFF)
}

extension DisplayState {
    var color: Color {
        switch self {
        case .available: return Color(hex: 0x1D4ED8)
        case .running: return Color(hex: 0xC2410C)
        case .soon: return Color(hex: 0xA16207)
        case .pickup: return Color(hex: 0x0F766E)
        case .broken: return Color(hex: 0x4B5563)
        }
    }

    var label: String {
        switch self {
        case .available: return "사용 가능"
        case .running: return "사용 중"
        case .soon: return "곧 끝남"
        case .pickup: return "수거 대기"
        case .broken: return "고장"
        }
    }

    /// 상태 배지 아이콘 (Assets.xcassets)
    var iconName: String {
        switch self {
        case .available: return "IconAvailable"
        case .running: return "IconRunning"
        case .soon: return "IconSoon"
        case .pickup: return "IconPickup"
        case .broken: return "IconBroken"
        }
    }
}

/// 디자인한 SVG 아이콘을 색을 입혀 쓰는 뷰
struct SVGIcon: View {
    let name: String
    var size: CGFloat = 24
    var color: Color = Theme.ink

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// 기기 아이콘 + 오른쪽 아래 상태 배지.
/// 사용 중일 때는 문 안의 드럼이 빙글빙글 돌아갑니다.
struct MachineIcon: View {
    let kind: MachineKind
    let state: DisplayState
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                if state.isSpinning {
                    SVGIcon(name: kind.bodyIconName, size: size, color: state.color)
                    SpinningDrum(kind: kind, color: state.color, size: size)
                } else {
                    SVGIcon(name: kind.iconName, size: size, color: state.color)
                }
            }
            .frame(width: size, height: size)

            Circle()
                .fill(state.color)
                .frame(width: size * 0.48, height: size * 0.48)
                .overlay {
                    SVGIcon(name: state.iconName, size: size * 0.32, color: .white)
                }
                .overlay {
                    Circle().strokeBorder(Color.white, lineWidth: 2)
                }
                .offset(x: size * 0.16, y: size * 0.1)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 세탁기 문(원) 안에서 회전하는 드럼
struct SpinningDrum: View {
    let kind: MachineKind
    let color: Color
    let size: CGFloat
    /// 한 바퀴 도는 데 걸리는 시간(초)
    var period: Double = 1.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 아이콘은 24×24 격자. 문 중심은 (12, 14.2), 반지름 4.6
        let unit = size / 24
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = reduceMotion ? 0 : (t.truncatingRemainder(dividingBy: period) / period) * 360
            ZStack {
                // 문 안쪽 내용물(물결/바람)이 회전
                SVGIcon(name: kind.drumIconName, size: 9.2 * unit, color: color)
                // 문 테두리를 따라 도는 굵은 호
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
                    .frame(width: 9.2 * unit, height: 9.2 * unit)
            }
            .rotationEffect(.degrees(angle))
            .position(x: 12 * unit, y: 14.2 * unit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
