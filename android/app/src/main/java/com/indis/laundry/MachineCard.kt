package com.indis.laundry

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** 홈 화면 그리드의 기기 카드 하나 */
@Composable
fun MachineCard(
    machine: Machine,
    now: Long,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isNotifying: Boolean = false,
    /** 즐겨찾기 목록에서 보여줄 때 건물 이름 */
    roomName: String? = null,
    isFavorite: Boolean = false,
) {
    val state = machine.displayState(now)
    val overdue = machine.isPickupOverdue(now)
    val shape = RoundedCornerShape(16.dp)
    val course = machine.course
    val showCourse = course != null && state != DisplayState.AVAILABLE && state != DisplayState.BROKEN

    val description = buildString {
        if (isFavorite) append("즐겨찾기, ")
        if (roomName != null) append("$roomName ")
        append("${machine.name}, ${machine.statusText(now)}")
        if (showCourse) append(", ${course!!.name} 코스")
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 150.dp)
            .clip(shape)
            .background(if (state == DisplayState.BROKEN) Palette.mutedFill else Palette.card)
            .then(if (state == DisplayState.AVAILABLE) Modifier.border(2.dp, state.color, shape) else Modifier)
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            MachineIcon(machine.kind, state, 44.dp)
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (isFavorite) SvgIcon(R.drawable.ic_star_fill, 16.dp, Palette.star)
                if (overdue) {
                    Text(
                        "3분 초과",
                        color = Color.White,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(state.color)
                            .padding(horizontal = 6.dp, vertical = 3.dp),
                    )
                } else if (isNotifying) {
                    SvgIcon(R.drawable.ic_bell, 18.dp, Palette.subtle)
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (roomName != null) {
                Text(roomName, color = Palette.subtle, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            }
            Text(
                machine.name,
                color = Palette.ink,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                machine.statusText(now),
                color = state.color,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (showCourse) {
                Text(
                    if (machine.startedByMe) "${course!!.name} 코스 · 내 빨래" else "${course!!.name} 코스",
                    color = Palette.subtle,
                    fontSize = 12.sp,
                    maxLines = 1,
                )
            }
        }

        machine.progress(now)?.let { p ->
            LinearProgressIndicator(
                progress = { p },
                modifier = Modifier.fillMaxWidth(),
                color = state.color,
                trackColor = state.color.copy(alpha = 0.18f),
                strokeCap = StrokeCap.Round,
                gapSize = 0.dp,
                drawStopIndicator = {},
            )
        }
    }
}
