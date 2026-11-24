package com.indis.laundry

import android.provider.Settings
import androidx.annotation.DrawableRes
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** 색 (iOS Theme.swift와 동일) */
object Palette {
    val background = Color(0xFFF6F7F9)
    val card = Color.White
    val mutedFill = Color(0xFFEEF0F3)
    val ink = Color(0xFF16181D)
    val subtle = Color(0xFF4B5563)
    val border = Color(0xFFD5D9E0)
    val primary = Color(0xFF1D4ED8)
    val primarySoft = Color(0xFFE6EEFF)
    val primaryDeep = Color(0xFF1E3A8A)
    val star = Color(0xFFA16207)
    val danger = Color(0xFFB91C1C)
}

@Composable
fun IndisTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Palette.primary,
            onPrimary = Color.White,
            primaryContainer = Palette.primarySoft,
            background = Palette.background,
            onBackground = Palette.ink,
            surface = Color.White,
            onSurface = Palette.ink,
            onSurfaceVariant = Palette.subtle,
            surfaceContainerLow = Color.White,
            surfaceContainer = Color.White,
            surfaceContainerHigh = Color.White,
        ),
        content = content,
    )
}

/** 디자인한 SVG 아이콘(벡터)을 색을 입혀 쓰는 뷰 */
@Composable
fun SvgIcon(
    @DrawableRes id: Int,
    size: Dp = 24.dp,
    color: Color = Palette.ink,
    contentDescription: String? = null,
    modifier: Modifier = Modifier,
) {
    Icon(
        painter = painterResource(id),
        contentDescription = contentDescription,
        tint = color,
        modifier = modifier.size(size),
    )
}

/** 시스템 설정에서 '애니메이션 끄기'를 켰는지 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/**
 * 기기 아이콘 + 오른쪽 아래 상태 배지.
 * 사용 중일 때는 문 안의 드럼이 빙글빙글 돌아갑니다.
 */
@Composable
fun MachineIcon(kind: MachineKind, state: DisplayState, size: Dp = 44.dp) {
    Box(Modifier.size(size)) {
        if (state.isSpinning) {
            SvgIcon(kind.bodyIcon, size, state.color)
            SpinningDrum(kind, state.color, size)
        } else {
            SvgIcon(kind.icon, size, state.color)
        }

        val badge = size * 0.48f
        Box(
            modifier = Modifier
                .offset(x = size - badge + size * 0.16f, y = size - badge + size * 0.1f)
                .size(badge)
                .clip(CircleShape)
                .background(state.color)
                .border(2.dp, Color.White, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            SvgIcon(state.icon, size * 0.32f, Color.White)
        }
    }
}

/** 세탁기 문(원) 안에서 회전하는 드럼 */
@Composable
fun SpinningDrum(kind: MachineKind, color: Color, size: Dp, periodMillis: Int = 1400) {
    val reduceMotion = rememberReduceMotion()
    val transition = rememberInfiniteTransition(label = "drum")
    val spin by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(periodMillis, easing = LinearEasing), RepeatMode.Restart),
        label = "drumAngle",
    )
    val angle = if (reduceMotion) 0f else spin

    // 아이콘은 24×24 격자. 문 중심은 (12, 14.2), 반지름 4.6
    val unit = size / 24f
    Box(
        modifier = Modifier
            .offset(x = unit * (12f - 4.6f), y = unit * (14.2f - 4.6f))
            .size(unit * 9.2f)
            .rotate(angle),
    ) {
        // 문 안쪽 내용물(물결/바람)이 회전
        SvgIcon(kind.drumIcon, unit * 9.2f, color)
        // 문 테두리를 따라 도는 굵은 호
        Canvas(Modifier.fillMaxSize()) {
            drawArc(
                color = color,
                startAngle = 0f,
                sweepAngle = 0.22f * 360f,
                useCenter = false,
                style = Stroke(width = (unit * 2.4f).toPx(), cap = StrokeCap.Round),
            )
        }
    }
}
