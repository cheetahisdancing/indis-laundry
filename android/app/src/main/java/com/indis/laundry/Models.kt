package com.indis.laundry

import androidx.annotation.DrawableRes
import androidx.compose.ui.graphics.Color
import java.util.Locale
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.max

/** 세탁기 / 건조기 구분 */
enum class MachineKind(
    val label: String,
    /** 멈춰 있을 때 아이콘 */
    @DrawableRes val icon: Int,
    /** 문 안에서 회전시킬 내용물 아이콘 */
    @DrawableRes val drumIcon: Int,
) {
    WASHER("세탁기", R.drawable.ic_washer, R.drawable.ic_washer_drum),
    DRYER("건조기", R.drawable.ic_dryer, R.drawable.ic_dryer_drum);

    /** 문 안쪽이 비어 있는 몸체 아이콘 (돌아갈 때 바탕) */
    @get:DrawableRes
    val bodyIcon: Int get() = R.drawable.ic_machine_body

    /** 정렬용: 세탁기 먼저 */
    val order: Int get() = if (this == WASHER) 0 else 1
}

/** 세탁 코스 */
data class WashCourse(val id: String, val name: String, val minutes: Int) {
    val millis: Long get() = minutes * 60_000L

    /** 버튼에 쓰는 문구: "표준 · 40분" */
    val buttonLabel: String
        get() = if (id == "demo") "데모 · 1분 (시연용)" else "$name · ${minutes}분"

    companion object {
        val STRONG = WashCourse("strong", "강력", 45)
        val STANDARD = WashCourse("standard", "표준", 40)
        val SYNTHETIC = WashCourse("synthetic", "합성", 42)
        val WOOL = WashCourse("wool", "울", 43)
        val DRY_STANDARD = WashCourse("dry", "표준 건조", 50)
        val DEMO = WashCourse("demo", "데모", 1)

        /** 세탁기 코스 4가지 */
        val washerCourses = listOf(STRONG, STANDARD, SYNTHETIC, WOOL)

        fun coursesFor(kind: MachineKind): List<WashCourse> = when (kind) {
            MachineKind.WASHER -> washerCourses + DEMO
            MachineKind.DRYER -> listOf(DRY_STANDARD, DEMO)
        }
    }
}

/** 서버(또는 센서)가 알려주는 기기의 실제 상태. 시각은 모두 epoch 밀리초 */
sealed interface MachineStatus {
    data object Available : MachineStatus
    data class Running(val startedAt: Long, val endsAt: Long, val course: WashCourse) : MachineStatus
    data class Pickup(val since: Long, val course: WashCourse?) : MachineStatus
    data object Broken : MachineStatus
}

/** 화면에 보여줄 상태 (남은 시간에 따라 '곧 끝남'이 추가됨) */
enum class DisplayState(val label: String, val color: Color, @DrawableRes val icon: Int) {
    AVAILABLE("사용 가능", Color(0xFF1D4ED8), R.drawable.ic_available),
    RUNNING("사용 중", Color(0xFFC2410C), R.drawable.ic_running),
    SOON("곧 끝남", Color(0xFFA16207), R.drawable.ic_soon),
    PICKUP("수거 대기", Color(0xFF0F766E), R.drawable.ic_pickup),
    BROKEN("고장", Color(0xFF4B5563), R.drawable.ic_broken);

    val isSpinning: Boolean get() = this == RUNNING || this == SOON
}

data class Machine(
    val floor: Int,
    val number: Int,
    val kind: MachineKind,
    val status: MachineStatus,
    /** 이 기기에 내가(이 휴대폰에서) 빨래를 넣었는지 */
    val startedByMe: Boolean = false,
    /** 주인에게 마지막으로 알림을 보낸 시각 */
    val lastRemindedAt: Long? = null,
    val id: String = UUID.randomUUID().toString(),
) {
    /** "1층 세탁기1" */
    val name: String get() = "${floor}층 ${kind.label}$number"

    fun displayState(now: Long): DisplayState = when (val s = status) {
        MachineStatus.Available -> DisplayState.AVAILABLE
        MachineStatus.Broken -> DisplayState.BROKEN
        is MachineStatus.Pickup -> DisplayState.PICKUP
        is MachineStatus.Running -> {
            val left = s.endsAt - now
            when {
                left <= 0 -> DisplayState.PICKUP
                left <= SOON_THRESHOLD -> DisplayState.SOON
                else -> DisplayState.RUNNING
            }
        }
    }

    /** 지금 돌고 있거나 방금 끝난 코스 */
    val course: WashCourse?
        get() = when (val s = status) {
            is MachineStatus.Running -> s.course
            is MachineStatus.Pickup -> s.course
            else -> null
        }

    /** 남은 시간(ms). 돌아가는 중이 아니면 null */
    fun remainingMillis(now: Long): Long? {
        val s = status as? MachineStatus.Running ?: return null
        val left = s.endsAt - now
        return if (left > 0) left else null
    }

    /** 진행률 0.0 ~ 1.0. 돌아가는 중이 아니면 null */
    fun progress(now: Long): Float? {
        val s = status as? MachineStatus.Running ?: return null
        val total = s.endsAt - s.startedAt
        if (total <= 0) return 1f
        return ((now - s.startedAt).toFloat() / total).coerceIn(0f, 1f)
    }

    /** 세탁이 끝난 시각 (수거 대기 중일 때만) */
    fun pickupSince(now: Long): Long? = when (val s = status) {
        is MachineStatus.Pickup -> s.since
        is MachineStatus.Running -> if (s.endsAt <= now) s.endsAt else null
        else -> null
    }

    /** 끝난 지 3분이 넘었는지 */
    fun isPickupOverdue(now: Long): Boolean {
        val since = pickupSince(now) ?: return false
        return now - since >= PICKUP_ALERT_DELAY
    }

    /** 주인 알림 버튼을 누를 수 있게 되기까지 남은 ms (이미 가능하면 0) */
    fun millisUntilRemindable(now: Long): Long {
        val since = pickupSince(now) ?: return Long.MAX_VALUE
        var wait = PICKUP_ALERT_DELAY - (now - since)
        lastRemindedAt?.let { wait = max(wait, REMIND_COOLDOWN - (now - it)) }
        return max(wait, 0L)
    }

    fun statusText(now: Long): String = when (displayState(now)) {
        DisplayState.AVAILABLE -> "사용 가능"
        DisplayState.BROKEN -> "고장"
        DisplayState.RUNNING -> "사용 중 · ${minutesText(remainingMillis(now) ?: 0)} 남음"
        DisplayState.SOON -> "곧 끝남 · ${minutesText(remainingMillis(now) ?: 0)}"
        DisplayState.PICKUP -> {
            val since = pickupSince(now) ?: now
            val minutes = ((now - since) / 60_000L).toInt()
            if (minutes < 1) "수거 대기 · 방금 끝남" else "수거 대기 · ${minutes}분째"
        }
    }

    companion object {
        /** '곧 끝남'으로 바뀌는 기준 (5분) */
        const val SOON_THRESHOLD = 5 * 60_000L
        /** 수거 대기가 이만큼 지나면 주인에게 알림을 보낼 수 있음 (3분) */
        const val PICKUP_ALERT_DELAY = 3 * 60_000L
        /** 같은 기기에 알림을 다시 보내려면 기다려야 하는 시간 */
        const val REMIND_COOLDOWN = 60_000L

        /** 125초 → "3분" (올림) */
        fun minutesText(millis: Long): String {
            val minutes = ceil(millis / 60_000.0).toInt()
            return "${max(minutes, 1)}분"
        }

        /** 125초 → "02:05" */
        fun clockText(millis: Long): String {
            val total = ceil(millis / 1000.0).toInt()
            val h = total / 3600
            val m = (total % 3600) / 60
            val s = total % 60
            return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
            else String.format(Locale.US, "%02d:%02d", m, s)
        }
    }
}

/** 기숙사 건물 (건물마다 세탁실이 있음) */
data class LaundryRoom(val id: String, val name: String, val group: String)

/** 즐겨찾기 목록의 한 줄 (어느 건물의 어떤 기기인지) */
data class FavoriteItem(val room: LaundryRoom, val machine: Machine)

/** 예시 데이터를 매번 똑같이 만들기 위한 난수 생성기 (SplitMix64) */
class SeededGenerator(seed: Long) {
    private var state = seed

    fun next(): Long {
        state += 0x9E3779B97F4A7C15uL.toLong()
        var z = state
        z = (z xor (z ushr 30)) * 0xBF58476D1CE4E5B9uL.toLong()
        z = (z xor (z ushr 27)) * 0x94D049BB133111EBuL.toLong()
        return z xor (z ushr 31)
    }

    fun nextInt(range: IntRange): Int {
        val span = (range.last - range.first + 1).toLong()
        return range.first + java.lang.Long.remainderUnsigned(next(), span).toInt()
    }

    fun <T> pick(list: List<T>): T = list[nextInt(list.indices)]
}
