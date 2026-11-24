package com.indis.laundry

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 앱 전체 상태. 지금은 예시 데이터로 동작하고,
 * 나중에 실제 서버/센서와 연결할 때 이 클래스만 바꾸면 됩니다. (iOS LaundryStore.swift와 동일)
 */
class LaundryStore(app: Application) : AndroidViewModel(app) {

    private val notifier = Notifier(app)
    private val prefs = app.getSharedPreferences("indis", Context.MODE_PRIVATE)

    // ---------- 상태 ----------

    var now by mutableLongStateOf(System.currentTimeMillis())
        private set

    val rooms: List<LaundryRoom> = buildList {
        for (n in 1..10) add(LaundryRoom("dorm$n", "생활관 ${n}동", "생활관"))
        for (n in 1..3) add(LaundryRoom("female$n", "여사 ${n}동", "여사"))
    }

    var selectedRoomId by mutableStateOf(rooms[0].id)

    var machinesByRoom by mutableStateOf(createSampleData())
        private set

    /** 즐겨찾는 기기 (건물·층·종류·번호로 만든 고정 키, 앱을 껐다 켜도 유지) */
    var favoriteKeys by mutableStateOf(prefs.getStringSet(FAVORITES_KEY, emptySet())!!.toSet())
        private set

    /** '빈 세탁기 생기면 알림' 켜짐 여부 */
    var notifyWhenFree by mutableStateOf(false)
        private set

    /** 끝나면 알림 받기로 한 기기들 */
    var notifyMachineIds by mutableStateOf(emptySet<String>())
        private set

    /** 다른 사람 빨래가 수거 대기로 이만큼 지나면 꺼내 간 것으로 시뮬레이션 */
    private val simulatedPickupDelay = 8 * 60_000L

    init {
        viewModelScope.launch {
            while (isActive) {
                delay(1000)
                tick()
            }
        }
    }

    // ---------- 읽기용 값 ----------

    val currentRoom: LaundryRoom get() = rooms.firstOrNull { it.id == selectedRoomId } ?: rooms[0]

    val roomGroups = listOf("생활관", "여사")

    fun roomsIn(group: String) = rooms.filter { it.group == group }

    val machines: List<Machine> get() = machinesByRoom[selectedRoomId].orEmpty()

    val floors: List<Int> get() = machines.map { it.floor }.distinct().sorted()

    fun machinesOnFloor(floor: Int): List<Machine> =
        machines.filter { it.floor == floor }.sortedWith(compareBy({ it.kind.order }, { it.number }))

    fun machine(id: String): Machine? = machinesByRoom.values.firstNotNullOfOrNull { list -> list.firstOrNull { it.id == id } }

    fun roomName(machineId: String): String {
        val roomId = roomIdOf(machineId) ?: return "세탁실"
        return rooms.firstOrNull { it.id == roomId }?.name ?: "세탁실"
    }

    fun availableCount(kind: MachineKind): Int =
        machines.count { it.kind == kind && it.displayState(now) == DisplayState.AVAILABLE }

    /** 가장 빨리 비는 기기까지 남은 시간 문구 */
    fun soonestWaitText(kind: MachineKind): String {
        if (availableCount(kind) > 0) return "지금 바로"
        val soonest = machines.filter { it.kind == kind }.mapNotNull { it.remainingMillis(now) }.minOrNull()
            ?: return "정보 없음"
        return Machine.minutesText(soonest)
    }

    fun isNotifying(machine: Machine) = machine.id in notifyMachineIds

    // ---------- 즐겨찾기 ----------

    private fun favoriteKey(machine: Machine): String? {
        val roomId = roomIdOf(machine.id) ?: return null
        return keyOf(roomId, machine)
    }

    private fun keyOf(roomId: String, m: Machine) = "$roomId|${m.floor}|${m.kind.name.lowercase()}|${m.number}"

    fun isFavorite(machine: Machine): Boolean = favoriteKey(machine)?.let { it in favoriteKeys } ?: false

    fun toggleFavorite(machine: Machine) {
        val key = favoriteKey(machine) ?: return
        favoriteKeys = if (key in favoriteKeys) favoriteKeys - key else favoriteKeys + key
        prefs.edit().putStringSet(FAVORITES_KEY, favoriteKeys).apply()
    }

    /** 즐겨찾는 기기 전체 (건물 순서 → 층 → 세탁기/건조기 → 번호) */
    val favoriteMachines: List<FavoriteItem>
        get() = rooms.flatMap { room ->
            machinesByRoom[room.id].orEmpty()
                .filter { keyOf(room.id, it) in favoriteKeys }
                .sortedWith(compareBy({ it.floor }, { it.kind.order }, { it.number }))
                .map { FavoriteItem(room, it) }
        }

    // ---------- 동작 ----------

    fun refresh() {
        now = System.currentTimeMillis()
    }

    fun selectRoom(id: String) {
        selectedRoomId = id
    }

    fun start(id: String, course: WashCourse) {
        val startedAt = System.currentTimeMillis()
        update(id) {
            it.copy(
                status = MachineStatus.Running(startedAt, startedAt + course.millis, course),
                startedByMe = true,
                lastRemindedAt = null,
            )
        }
        now = startedAt
    }

    fun markCollected(id: String) {
        update(id) { it.copy(status = MachineStatus.Available, startedByMe = false, lastRemindedAt = null) }
        machine(id)?.let { machineBecameFree(it) }
    }

    fun reportBroken(id: String) {
        cancelNotify(id)
        update(id) { it.copy(status = MachineStatus.Broken, startedByMe = false) }
    }

    fun markFixed(id: String) {
        update(id) { it.copy(status = MachineStatus.Available) }
        machine(id)?.let { machineBecameFree(it) }
    }

    fun toggleNotify(machine: Machine) {
        if (machine.id in notifyMachineIds) {
            cancelNotify(machine.id)
            return
        }
        val running = machine.status as? MachineStatus.Running ?: return
        notifyMachineIds = notifyMachineIds + machine.id
        val (title, body) = finishedMessage(machine, running.course)
        notifier.schedule(machine.id, title, body, running.endsAt)
    }

    /**
     * 수거 대기 3분이 지난 기기의 주인에게 알림 보내기.
     * 프로토타입에서는 '주인이 받게 될 알림'을 이 기기에 띄워서 보여줍니다.
     */
    fun remindOwner(id: String): Boolean {
        val m = machine(id) ?: return false
        val since = m.pickupSince(now) ?: return false
        if (!m.isPickupOverdue(now) || m.millisUntilRemindable(now) > 0) return false

        val minutes = ((now - since) / 60_000L).toInt()
        update(id) { it.copy(lastRemindedAt = System.currentTimeMillis()) }
        notifier.showNow(
            "빨래를 꺼내 주세요",
            "${roomName(id)} ${m.name} 세탁이 끝난 지 ${minutes}분이 지났어요. 다음 사람이 기다리고 있어요.",
        )
        return true
    }

    fun setNotifyWhenFree(on: Boolean) {
        notifyWhenFree = on
    }

    // ---------- 내부 로직 ----------

    private fun finishedMessage(machine: Machine, course: WashCourse) =
        "${machine.name} 세탁이 끝났어요" to
            "${roomName(machine.id)} ${machine.name} · ${course.name} 코스가 끝났어요. 빨래를 꺼내 주세요."

    private fun cancelNotify(id: String) {
        notifyMachineIds = notifyMachineIds - id
        notifier.cancel(id)
    }

    private fun update(id: String, change: (Machine) -> Machine) {
        val roomId = roomIdOf(id) ?: return
        machinesByRoom = machinesByRoom + (roomId to machinesByRoom[roomId]!!.map { if (it.id == id) change(it) else it })
    }

    /** 1초마다 호출: 시간 갱신 + 상태 변화 시뮬레이션 */
    private fun tick() {
        val t = System.currentTimeMillis()
        now = t
        val freed = mutableListOf<Machine>()
        var notify = notifyMachineIds
        var changedAny = false

        val updated = machinesByRoom.mapValues { (_, list) ->
            list.map { m ->
                val s = m.status
                when {
                    s is MachineStatus.Running && s.endsAt <= t -> {
                        changedAny = true
                        if (m.id in notify) {
                            // 앱이 살아 있으면 바로 알림 (예약 알림은 취소해서 중복 방지)
                            notify = notify - m.id
                            notifier.cancel(m.id)
                            val (title, body) = finishedMessage(m, s.course)
                            notifier.showNow(title, body, Notifier.idFor(m.id))
                        }
                        m.copy(status = MachineStatus.Pickup(s.endsAt, s.course))
                    }
                    s is MachineStatus.Pickup && !m.startedByMe && t - s.since >= simulatedPickupDelay -> {
                        changedAny = true
                        m.copy(status = MachineStatus.Available, lastRemindedAt = null).also { freed += it }
                    }
                    else -> m
                }
            }
        }
        if (changedAny) machinesByRoom = updated
        notifyMachineIds = notify
        freed.forEach { machineBecameFree(it) }
    }

    /** 기기가 비었을 때: 빈 세탁기 알림 */
    private fun machineBecameFree(machine: Machine) {
        if (machine.kind != MachineKind.WASHER) return
        val roomId = roomIdOf(machine.id) ?: return
        if (notifyWhenFree && roomId == selectedRoomId) {
            val roomName = rooms.firstOrNull { it.id == roomId }?.name ?: "세탁실"
            notifier.showNow("빈 세탁기가 생겼어요", "$roomName ${machine.name}을 지금 쓸 수 있어요.")
        }
    }

    private fun roomIdOf(machineId: String): String? =
        machinesByRoom.entries.firstOrNull { (_, list) -> list.any { it.id == machineId } }?.key

    // ---------- 예시 데이터 (건물마다 3개 층 × 세탁기 2대 + 건조기 1대) ----------

    private fun createSampleData(): Map<String, List<Machine>> {
        val rng = SeededGenerator(2026)
        val start = System.currentTimeMillis()
        return rooms.mapIndexed { index, room -> room.id to sampleMachines(index, start, rng) }.toMap()
    }

    private fun sampleMachines(roomIndex: Int, now: Long, rng: SeededGenerator): List<Machine> {
        val list = mutableListOf<Machine>()
        for (floor in 1..3) {
            for (number in 1..2) {
                list += Machine(floor, number, MachineKind.WASHER, washerStatus(now, rng))
            }
            list += Machine(floor, 1, MachineKind.DRYER, dryerStatus(now, rng))
        }
        // 시연용: 모든 건물의 2층 세탁기2는 끝난 지 3분이 넘은 수거 대기 상태
        val overdueMinutes = 4 + roomIndex % 4
        list[4] = list[4].copy(
            status = MachineStatus.Pickup(now - overdueMinutes * 60_000L, WashCourse.washerCourses[roomIndex % 4]),
        )
        return list
    }

    private fun running(course: WashCourse, minutesLeft: Int, now: Long): MachineStatus {
        val endsAt = now + minutesLeft * 60_000L
        return MachineStatus.Running(endsAt - course.millis, endsAt, course)
    }

    private fun washerStatus(now: Long, rng: SeededGenerator): MachineStatus {
        val course = rng.pick(WashCourse.washerCourses)
        return when (rng.nextInt(0..9)) {
            0, 1, 2 -> MachineStatus.Available
            3, 4, 5, 6 -> running(course, rng.nextInt(8..(course.minutes - 2)), now)
            7, 8 -> running(course, rng.nextInt(1..4), now)
            else -> MachineStatus.Pickup(now - rng.nextInt(0..1) * 60_000L, course)
        }
    }

    private fun dryerStatus(now: Long, rng: SeededGenerator): MachineStatus =
        when (rng.nextInt(0..9)) {
            0, 1, 2, 3 -> running(WashCourse.DRY_STANDARD, rng.nextInt(3..45), now)
            4, 5, 6, 7 -> MachineStatus.Available
            8 -> MachineStatus.Broken
            else -> MachineStatus.Pickup(now - 60_000L, WashCourse.DRY_STANDARD)
        }

    private companion object {
        const val FAVORITES_KEY = "favoriteMachines"
    }
}
