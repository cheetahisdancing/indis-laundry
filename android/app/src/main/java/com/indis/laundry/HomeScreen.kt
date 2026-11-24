package com.indis.laundry

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** 첫 화면: 세탁실 현황 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(store: LaundryStore, withNotificationPermission: (() -> Unit) -> Unit) {
    var selectedMachineId by rememberSaveable { mutableStateOf<String?>(null) }
    val now = store.now

    Scaffold(
        containerColor = Palette.background,
        topBar = {
            TopAppBar(
                title = { Text("세탁실 현황", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Palette.ink) },
                actions = {
                    IconButton(onClick = store::refresh) {
                        SvgIcon(R.drawable.ic_refresh, 22.dp, Palette.ink, contentDescription = "새로고침")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Palette.background),
            )
        },
        bottomBar = {
            BottomBar(
                on = store.notifyWhenFree,
                onClick = {
                    if (store.notifyWhenFree) store.setNotifyWhenFree(false)
                    else withNotificationPermission { store.setNotifyWhenFree(true) }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            FavoritesSection(store, now) { selectedMachineId = it }
            RoomPicker(store)
            Summary(store)

            store.floors.forEach { floor ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "${floor}층",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = Palette.subtle,
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .semantics { heading() },
                    )
                    TwoColumnGrid(store.machinesOnFloor(floor)) { machine, mod ->
                        MachineCard(
                            machine = machine,
                            now = now,
                            onClick = { selectedMachineId = machine.id },
                            modifier = mod,
                            isNotifying = store.isNotifying(machine),
                            isFavorite = store.isFavorite(machine),
                        )
                    }
                }
            }
        }
    }

    selectedMachineId?.let { id ->
        MachineDetailSheet(
            store = store,
            machineId = id,
            withNotificationPermission = withNotificationPermission,
            onDismiss = { selectedMachineId = null },
        )
    }
}

/** 2열 격자 (같은 줄의 카드는 높이를 맞춤) */
@Composable
fun <T> TwoColumnGrid(items: List<T>, content: @Composable (T, Modifier) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        items.chunked(2).forEach { row ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                row.forEach { item ->
                    Box(Modifier.weight(1f)) { content(item, Modifier.fillMaxHeight()) }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

// ---------- 세탁실 선택 ----------

@Composable
private fun RoomPicker(store: LaundryStore) {
    var expanded by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(12.dp)
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(shape)
                .background(Palette.card)
                .border(1.dp, Palette.border, shape)
                .clickable { expanded = true }
                .semantics(mergeDescendants = true) {
                    contentDescription = "기숙사 선택, 현재 ${store.currentRoom.name}"
                }
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SvgIcon(R.drawable.ic_room, 20.dp)
            Text(
                "${store.currentRoom.name} 세탁실",
                color = Palette.ink,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Text("변경", color = Palette.subtle, fontSize = 13.sp)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            store.roomGroups.forEachIndexed { index, group ->
                if (index > 0) HorizontalDivider()
                Text(
                    group,
                    color = Palette.subtle,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                store.roomsIn(group).forEach { room ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                room.name,
                                fontWeight = if (room.id == store.selectedRoomId) FontWeight.Bold else FontWeight.Normal,
                                color = if (room.id == store.selectedRoomId) Palette.primary else Palette.ink,
                            )
                        },
                        onClick = {
                            store.selectRoom(room.id)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

// ---------- 요약 카드 ----------

@Composable
private fun Summary(store: LaundryStore) {
    val free = store.availableCount(MachineKind.WASHER)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        SummaryTile("비어 있는 세탁기", "${free}대", highlight = free > 0, modifier = Modifier.weight(1f))
        SummaryTile("세탁기 가장 빠른 대기", store.soonestWaitText(MachineKind.WASHER), highlight = false, modifier = Modifier.weight(1f))
    }
}

/** 요약 숫자 타일 */
@Composable
private fun SummaryTile(title: String, value: String, highlight: Boolean, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(if (highlight) Palette.primarySoft else Palette.card)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, fontSize = 12.sp, color = if (highlight) Palette.primaryDeep else Palette.subtle)
        Text(
            value,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = if (highlight) Palette.primary else Palette.ink,
        )
    }
}

// ---------- 즐겨찾는 기기 ----------

@Composable
private fun FavoritesSection(store: LaundryStore, now: Long, onSelect: (String) -> Unit) {
    val favorites = store.favoriteMachines
    Column(
        modifier = Modifier.padding(bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            SvgIcon(R.drawable.ic_star_fill, 16.dp, Palette.star)
            Text(
                "즐겨찾는 기기",
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = Palette.ink,
                modifier = Modifier.semantics { heading() },
            )
        }

        if (favorites.isEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Palette.card)
                    .drawBehind {
                        val w = 1.dp.toPx()
                        drawRoundRect(
                            color = Palette.border,
                            topLeft = androidx.compose.ui.geometry.Offset(w / 2, w / 2),
                            size = androidx.compose.ui.geometry.Size(size.width - w, size.height - w),
                            cornerRadius = CornerRadius(14.dp.toPx()),
                            style = Stroke(
                                width = w,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())),
                            ),
                        )
                    }
                    .padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SvgIcon(R.drawable.ic_star, 22.dp, Palette.subtle)
                Text(
                    "자주 쓰는 세탁기를 눌러 상세 화면 위쪽의 별을 누르면 여기에서 바로 상태를 볼 수 있어요.",
                    fontSize = 13.sp,
                    color = Palette.subtle,
                )
            }
        } else {
            TwoColumnGrid(favorites) { item, mod ->
                MachineCard(
                    machine = item.machine,
                    now = now,
                    onClick = { onSelect(item.machine.id) },
                    modifier = mod,
                    isNotifying = store.isNotifying(item.machine),
                    roomName = item.room.name,
                    isFavorite = true,
                )
            }
        }
    }
}

// ---------- 하단 버튼 ----------

@Composable
private fun BottomBar(on: Boolean, onClick: () -> Unit) {
    Surface(color = Color.White, shadowElevation = 6.dp) {
        Box(
            Modifier
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 8.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (on) Palette.primarySoft else Palette.primary)
                    .clickable(onClick = onClick),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SvgIcon(R.drawable.ic_bell, 22.dp, if (on) Palette.primary else Color.White)
                Spacer(Modifier.padding(start = 8.dp))
                Text(
                    if (on) "빈 세탁기 알림 켜짐 · 끄기" else "빈 세탁기 생기면 알림 받기",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (on) Palette.primary else Color.White,
                )
            }
        }
    }
}
