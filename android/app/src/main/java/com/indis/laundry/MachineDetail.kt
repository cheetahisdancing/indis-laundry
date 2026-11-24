package com.indis.laundry

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import kotlin.math.ceil

/** 기기를 눌렀을 때 뜨는 상세 화면 (아래에서 올라오는 시트) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MachineDetailSheet(
    store: LaundryStore,
    machineId: String,
    withNotificationPermission: (() -> Unit) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val close: () -> Unit = {
        scope.launch { sheetState.hide() }.invokeOnCompletion { onDismiss() }
    }
    val machine = store.machine(machineId)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.White,
    ) {
        Column(Modifier.navigationBarsPadding()) {
            // 위쪽 줄: 즐겨찾기 별 · 닫기
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (machine != null) {
                    val favorite = store.isFavorite(machine)
                    IconButton(onClick = { store.toggleFavorite(machine) }) {
                        SvgIcon(
                            if (favorite) R.drawable.ic_star_fill else R.drawable.ic_star,
                            24.dp,
                            if (favorite) Palette.star else Palette.ink,
                            contentDescription = if (favorite) "즐겨찾기에서 빼기" else "즐겨찾기에 추가",
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = close) { Text("닫기", fontSize = 16.sp) }
            }

            if (machine == null) {
                Text(
                    "기기 정보를 찾을 수 없어요",
                    color = Palette.subtle,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(48.dp),
                    textAlign = TextAlign.Center,
                )
            } else {
                DetailContent(store, machine, withNotificationPermission)
            }
        }
    }
}

@Composable
private fun DetailContent(
    store: LaundryStore,
    machine: Machine,
    withNotificationPermission: (() -> Unit) -> Unit,
) {
    val now = store.now
    val state = machine.displayState(now)
    val target = machine.progress(now) ?: if (state == DisplayState.AVAILABLE) 0f else 1f
    val ring by animateFloatAsState(target, tween(1000, easing = LinearEasing), label = "ring")
    var confirmBroken by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // 남은 시간 링
        Box(Modifier.size(168.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 12.dp.toPx()
                val topLeft = Offset(stroke / 2, stroke / 2)
                val arcSize = Size(size.width - stroke, size.height - stroke)
                drawArc(state.color.copy(alpha = 0.15f), 0f, 360f, false, topLeft, arcSize, style = Stroke(stroke))
                if (ring > 0f) {
                    drawArc(
                        state.color, -90f, 360f * ring, false, topLeft, arcSize,
                        style = Stroke(stroke, cap = StrokeCap.Round),
                    )
                }
            }
            MachineIcon(machine.kind, state, 72.dp)
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(machine.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Palette.ink)
            Text(state.label, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = state.color)
            val course = machine.course
            if (course != null && state != DisplayState.AVAILABLE && state != DisplayState.BROKEN) {
                Text(
                    "${course.name} 코스 · ${course.minutes}분",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Palette.ink,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Palette.mutedFill)
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
            val left = machine.remainingMillis(now)
            if (left != null) {
                Text(
                    Machine.clockText(left),
                    style = TextStyle(
                        fontSize = 44.sp,
                        fontWeight = FontWeight.Bold,
                        color = Palette.ink,
                        fontFeatureSettings = "tnum",
                    ),
                    modifier = Modifier.semantics { contentDescription = "남은 시간 ${Machine.minutesText(left)}" },
                )
                Text("남은 시간", fontSize = 13.sp, color = Palette.subtle)
            } else if (state == DisplayState.PICKUP) {
                Text(machine.statusText(now), fontSize = 15.sp, color = Palette.subtle)
            }
        }

        Actions(store, machine, state, withNotificationPermission) { confirmBroken = true }
    }

    if (confirmBroken) {
        AlertDialog(
            onDismissRequest = { confirmBroken = false },
            title = { Text("${machine.name}을 고장으로 신고할까요?", fontSize = 18.sp) },
            confirmButton = {
                TextButton(onClick = {
                    store.reportBroken(machine.id)
                    confirmBroken = false
                }) { Text("고장 신고", color = Palette.danger, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { confirmBroken = false }) { Text("취소") }
            },
            containerColor = Color.White,
        )
    }
}

@Composable
private fun Actions(
    store: LaundryStore,
    machine: Machine,
    state: DisplayState,
    withNotificationPermission: (() -> Unit) -> Unit,
    onReportBroken: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        when (state) {
            DisplayState.AVAILABLE -> {
                Text("코스를 골라 사용을 시작하세요", fontSize = 13.sp, color = Palette.subtle)
                WashCourse.coursesFor(machine.kind).forEach { course ->
                    PrimaryButton(course.buttonLabel, R.drawable.ic_timer, filled = course.id != "demo") {
                        store.start(machine.id, course)
                    }
                }
            }

            DisplayState.RUNNING, DisplayState.SOON -> {
                val notifying = store.isNotifying(machine)
                PrimaryButton(
                    if (notifying) "알림 취소" else "끝나면 알림 받기",
                    R.drawable.ic_bell,
                    filled = !notifying,
                ) {
                    if (notifying) store.toggleNotify(machine)
                    else withNotificationPermission { store.toggleNotify(machine) }
                }
            }

            DisplayState.PICKUP -> {
                if (!machine.startedByMe) OwnerReminder(store, machine, withNotificationPermission)
                PrimaryButton("빨래 꺼냈어요", R.drawable.ic_my_laundry, filled = machine.startedByMe) {
                    store.markCollected(machine.id)
                }
            }

            DisplayState.BROKEN -> {
                PrimaryButton("수리 완료로 표시", R.drawable.ic_available, filled = false) {
                    store.markFixed(machine.id)
                }
            }
        }

        if (state != DisplayState.BROKEN) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(onClick = onReportBroken),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SvgIcon(R.drawable.ic_broken, 18.dp, Palette.subtle)
                Spacer(Modifier.width(6.dp))
                Text("고장 신고", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Palette.subtle)
            }
        }
    }
}

/** 수거 대기 3분이 지나면 세탁물 주인에게 알림 보내기 */
@Composable
private fun OwnerReminder(
    store: LaundryStore,
    machine: Machine,
    withNotificationPermission: (() -> Unit) -> Unit,
) {
    val now = store.now
    val wait = machine.millisUntilRemindable(now)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        when {
            !machine.isPickupOverdue(now) -> Text(
                "끝난 지 3분이 지나면 세탁물 주인에게 알림을 보낼 수 있어요 · ${Machine.clockText(wait)} 남음",
                fontSize = 13.sp,
                color = Palette.subtle,
                textAlign = TextAlign.Center,
            )

            wait > 0 -> {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Palette.primarySoft),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SvgIcon(R.drawable.ic_available, 20.dp, Palette.primary)
                    Spacer(Modifier.width(8.dp))
                    Text("주인에게 알림을 보냈어요", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Palette.primary)
                }
                Text("${ceil(wait / 1000.0).toInt()}초 뒤에 다시 보낼 수 있어요", fontSize = 13.sp, color = Palette.subtle)
            }

            else -> {
                PrimaryButton("세탁물 주인에게 알림 보내기", R.drawable.ic_bell) {
                    withNotificationPermission { store.remindOwner(machine.id) }
                }
                Text("프로토타입에서는 주인이 받을 알림이 이 기기에 표시돼요.", fontSize = 12.sp, color = Palette.subtle)
            }
        }
    }
}

/** 큰 버튼 */
@Composable
fun PrimaryButton(title: String, icon: Int, filled: Boolean = true, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (filled) Palette.primary else Palette.primarySoft)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SvgIcon(icon, 20.dp, if (filled) Color.White else Palette.primary)
        Spacer(Modifier.width(8.dp))
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = if (filled) Color.White else Palette.primary)
    }
}
