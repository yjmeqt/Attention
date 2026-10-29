package com.yijiang.attention.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateOffsetAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.yijiang.attention.R
import com.yijiang.attention.model.BRAND_NAME
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/** The steps of pinning Attention in the Android share sheet: touch and hold it, then Pin. */
private enum class Phase(val target: Target?) {
    HOME(Target.SHARE),
    SHEET(Target.APP),
    MENU(Target.PIN),
    FINISHED(null),
}

private enum class Target { SHARE, APP, PIN }

@Composable
private fun Phase.caption(): String = when (this) {
    Phase.HOME -> stringResource(R.string.guide_tap_share)
    Phase.SHEET -> stringResource(R.string.guide_hold_app, BRAND_NAME)
    Phase.MENU -> stringResource(R.string.guide_tap_pin)
    Phase.FINISHED -> stringResource(R.string.guide_finished, BRAND_NAME)
}

/**
 * Full-screen walkthrough. On first launch [lockedUntilWatched] keeps Done off, and back from closing it,
 * until the animation reaches its last step, like the iOS guide.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareSheetGuideDialog(lockedUntilWatched: Boolean, onDismiss: () -> Unit) {
    var watched by remember { mutableStateOf(!lockedUntilWatched) }
    Dialog(
        onDismissRequest = { if (watched) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnBackPress = false),
    ) {
        BackHandler(enabled = true) { if (watched) onDismiss() }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.guide_title)) },
                    actions = { TextButton(onClick = onDismiss, enabled = watched) { Text(stringResource(R.string.done)) } },
                )
            },
        ) { padding ->
            ShareSheetGuide(modifier = Modifier.padding(padding), onWatched = { watched = true })
        }
    }
}

@Composable
fun ShareSheetGuide(modifier: Modifier = Modifier, onWatched: () -> Unit = {}) {
    var phase by remember { mutableStateOf(Phase.HOME) }
    var target by remember { mutableStateOf<Target?>(null) }
    var pressing by remember { mutableStateOf(false) }
    var run by remember { mutableIntStateOf(0) }
    // Each target's layout, measured against the phone frame to place the touch dot.
    val anchors = remember { mutableStateMapOf<Target, LayoutCoordinates>() }
    var frame by remember { mutableStateOf<LayoutCoordinates?>(null) }

    LaunchedEffect(run) {
        while (true) {
            phase = Phase.HOME
            target = null
            delay(800)
            for (step in Phase.entries.dropLast(1)) {
                target = step.target
                delay(900)
                pressing = true
                // Pinning is a touch and hold, so the app press lasts longer than a tap.
                delay(if (step == Phase.SHEET) 700 else 160)
                pressing = false
                val next = Phase.entries[step.ordinal + 1]
                phase = next
                if (next == Phase.FINISHED) {
                    target = null
                    onWatched()
                }
                delay(1300)
            }
            delay(2400)
        }
    }

    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Box(
            modifier = Modifier
                .size(290.dp, 560.dp)
                .clip(RoundedCornerShape(36.dp))
                .border(5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f), RoundedCornerShape(36.dp))
                .background(MaterialTheme.colorScheme.surface)
                .onGloballyPositioned { frame = it },
        ) {
            SourcePage(onAnchor = { anchors[Target.SHARE] = it })
            androidx.compose.animation.AnimatedVisibility(phase != Phase.HOME, enter = fadeIn(), exit = fadeOut()) {
                Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)))
            }
            androidx.compose.animation.AnimatedVisibility(
                phase != Phase.HOME,
                modifier = Modifier.align(Alignment.BottomCenter),
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut(),
            ) {
                MockShareSheet(
                    pinned = phase == Phase.FINISHED,
                    showsMenu = phase == Phase.MENU,
                    onAnchor = { t, offset -> anchors[t] = offset },
                )
            }
            val dot = target?.let { anchors[it] }?.takeIf { it.isAttached }?.let { node ->
                frame?.takeIf { it.isAttached }?.localPositionOf(node, Offset(node.size.width / 2f, node.size.height / 2f))
            }
            TouchDot(dot, pressing)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (p in Phase.entries) {
                    Box(
                        modifier = Modifier
                            .animateContentSize()
                            .size(if (p == phase) 18.dp else 6.dp, 6.dp)
                            .background(
                                if (p == phase) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest,
                                CircleShape,
                            ),
                    )
                }
            }
            Text(
                phase.caption(),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.heightIn(min = 48.dp).width(320.dp),
            )
            FilledTonalButton(onClick = { run++ }) {
                Icon(Icons.Default.Replay, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.replay))
            }
        }
    }
}

@Composable
private fun TouchDot(at: Offset?, pressing: Boolean) {
    val density = LocalDensity.current
    val position by animateOffsetAsState(at ?: Offset.Zero, tween(600), label = "dot")
    val scale by animateFloatAsState(if (pressing) 0.7f else 1f, tween(150), label = "press")
    if (at == null) return
    val half = with(density) { 20.dp.toPx() }
    Box(
        modifier = Modifier
            .offset { IntOffset((position.x - half).roundToInt(), (position.y - half).roundToInt()) }
            .size(40.dp)
            .scale(scale)
            .background(Color.White.copy(alpha = 0.55f), CircleShape)
            .border(2.dp, Color.White, CircleShape),
    )
}

/** A page in some app, with Share in its bottom bar. */
@Composable
private fun SourcePage(onAnchor: (LayoutCoordinates) -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.padding(start = 18.dp, end = 18.dp, top = 48.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(150.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Brush.linearGradient(listOf(Color(0xCCFF3B30), Color(0xB3FF9500)))),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Default.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(48.dp)) }
            Text("WWDC 2025 Keynote", style = MaterialTheme.typography.titleMedium)
            for (width in listOf(1f, 0.9f, 0.95f, 0.6f)) {
                Box(Modifier.fillMaxWidth(width).height(8.dp).background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape))
            }
        }
        Spacer(Modifier.weight(1f))
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            val muted = MaterialTheme.colorScheme.onSurfaceVariant
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = muted)
            Icon(Icons.Default.Share, contentDescription = null, tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.onGloballyPositioned(onAnchor))
            Icon(Icons.Default.Bookmark, contentDescription = null, tint = muted)
            Icon(Icons.Default.Info, contentDescription = null, tint = muted)
        }
    }
}

/** The system share sheet: a row of apps; touching and holding one opens its menu with Pin. */
@Composable
private fun MockShareSheet(pinned: Boolean, showsMenu: Boolean, onAnchor: (Target, LayoutCoordinates) -> Unit) {
    val others = listOf(
        "Chrome" to Color(0xFF4285F4), "Gmail" to Color(0xFFEA4335), "Drive" to Color(0xFF0F9D58),
        "WeChat" to Color(0xFF07C160), "Messages" to Color(0xFF1A73E8), "Notes" to Color(0xFFFBBC04),
    )
    Surface(
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.align(Alignment.CenterHorizontally).size(32.dp, 4.dp).background(MaterialTheme.colorScheme.outlineVariant, CircleShape))
            Text("Sharing link", style = MaterialTheme.typography.titleSmall)
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Row(modifier = Modifier.fillMaxWidth().padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("WWDC 2025 Keynote", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                        Text("youtu.be/0_DjDdfqtUE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                }
            }
            // Before pinning, Attention sits further along the row; pinned, it comes first with a pin badge.
            val row: List<Pair<String, Color>?> = if (pinned) listOf(null) + others.take(3) else others.take(2) + listOf(null) + others.drop(2).take(1)
            val glyph = painterResource(R.drawable.ic_launcher_foreground)
            Box {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    for (app in row) {
                        if (app == null) {
                            AppTarget(BRAND_NAME, glyph = glyph, pinned = pinned,
                                modifier = Modifier.onGloballyPositioned { onAnchor(Target.APP, it) })
                        } else {
                            AppTarget(app.first, color = app.second)
                        }
                    }
                }
                if (showsMenu) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        shadowElevation = 6.dp,
                        modifier = Modifier.align(Alignment.TopCenter).offset(y = (-58).dp),
                    ) {
                        Column(modifier = Modifier.width(170.dp).padding(vertical = 6.dp)) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 10.dp)
                                    .onGloballyPositioned { onAnchor(Target.PIN, it) },
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Default.PushPin, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(10.dp))
                                Text(stringResource(R.string.guide_pin_item, BRAND_NAME), style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun AppTarget(name: String, modifier: Modifier = Modifier, color: Color? = null, glyph: Painter? = null, pinned: Boolean = false) {
    Column(modifier = modifier.width(56.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box {
            if (glyph != null) {
                Box(
                    modifier = Modifier.size(48.dp).clip(CircleShape).background(Color(0xFFF2EDE4)),
                    contentAlignment = Alignment.Center,
                ) { Image(glyph, contentDescription = null, modifier = Modifier.size(72.dp)) }
            } else {
                Box(Modifier.size(48.dp).background(color ?: Color.Gray, CircleShape))
            }
            if (pinned) {
                Icon(
                    Icons.Default.PushPin, contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(18.dp)
                        .background(MaterialTheme.colorScheme.primary, CircleShape)
                        .padding(3.dp)
                        .rotate(45f),
                )
            }
        }
        Text(name, style = MaterialTheme.typography.labelSmall, maxLines = 1)
    }
}
