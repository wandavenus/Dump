package dev.wndavenz.music.ui.components

import androidx.compose.animation.core.InfiniteRepeatableSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun FluidShaderView(
    modifier: Modifier = Modifier,
    primaryColor: Color = Color(0xFFF92D48),
    secondaryColor: Color = Color(0xFF7A1C32),
    tertiaryColor: Color = Color(0xFF1E1233),
) {
    val infiniteTransition = rememberInfiniteTransition(label = "fluid_shader")
    val time by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 6.28318f,
        animationSpec = InfiniteRepeatableSpec(
            animation = tween(durationMillis = 12000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "time"
    )

    Canvas(modifier = modifier.fillMaxSize()) {
        val w = size.width
        val h = size.height

        val node0 = Offset(w * (0.3f + 0.2f * sin(time)), h * (0.3f + 0.15f * cos(time)))
        val node1 = Offset(w * (0.7f + 0.15f * cos(time * 0.8f)), h * (0.2f + 0.2f * sin(time * 0.8f)))
        val node2 = Offset(w * (0.2f + 0.25f * cos(time * 1.2f)), h * (0.8f + 0.1f * sin(time * 1.2f)))
        val node3 = Offset(w * (0.8f + 0.1f * sin(time * 0.9f)), h * (0.7f + 0.2f * cos(time * 0.9f)))

        // Draw radial mesh gradients to emulate fluid effect on Android 11
        drawRect(Color(0xFF0F0814))

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(primaryColor.copy(alpha = 0.6f), Color.Transparent),
                center = node0,
                radius = w * 0.85f
            ),
            center = node0,
            radius = w * 0.85f
        )

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(secondaryColor.copy(alpha = 0.5f), Color.Transparent),
                center = node1,
                radius = w * 0.9f
            ),
            center = node1,
            radius = w * 0.9f
        )

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(tertiaryColor.copy(alpha = 0.6f), Color.Transparent),
                center = node2,
                radius = w * 0.8f
            ),
            center = node2,
            radius = w * 0.8f
        )

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(primaryColor.copy(alpha = 0.4f), Color.Transparent),
                center = node3,
                radius = w * 0.75f
            ),
            center = node3,
            radius = w * 0.75f
        )

        drawRect(Color.Black.copy(alpha = 0.25f))
    }
}
