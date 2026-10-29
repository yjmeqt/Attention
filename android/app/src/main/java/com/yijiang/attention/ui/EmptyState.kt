package com.yijiang.attention.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.Button
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yijiang.attention.R
import com.yijiang.attention.card.CardMetrics
import com.yijiang.attention.card.CardRenderer
import com.yijiang.attention.model.BRAND_NAME
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.LinkMeta
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private val sampleMeta = LinkMeta(
    url = "https://youtu.be/0_DjDdfqtUE",
    site = "YouTube",
    title = "WWDC 2025 — June 9 | Apple",
    authorName = "Apple",
)

@Composable
fun EmptyState(
    onPaste: () -> Unit,
    onSample: () -> Unit,
    showsPinGuide: () -> Unit,
    seenShareGuide: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
        if (!seenShareGuide) PinGuideLink(seenShareGuide, showsPinGuide)
        SampleCard()
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                stringResource(R.string.empty_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            Text(
                stringResource(R.string.empty_body),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        FilledTonalButton(onClick = onPaste, contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
            Icon(Icons.Default.ContentPaste, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
            Spacer(Modifier.width(ButtonDefaults.IconSpacing))
            Text(stringResource(R.string.paste))
        }
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainer,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                StepRow(Icons.Default.Link, stringResource(R.string.step_copy, BRAND_NAME))
                StepRow(Icons.Default.PhotoLibrary, stringResource(R.string.step_card))
                StepRow(Icons.Default.Forum, stringResource(R.string.step_send))
            }
        }
        if (seenShareGuide) PinGuideLink(seenShareGuide, showsPinGuide)
        SampleLink(onSample)
    }
}

/** A first link to save, so the library is never a dead end. */
@Composable
private fun SampleLink(onAdd: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(10.dp)).background(Color(0xFFF2EDE4)),
                contentAlignment = Alignment.Center,
            ) { Image(painterResource(R.drawable.ic_launcher_foreground), contentDescription = null, modifier = Modifier.size(80.dp)) }
            Column(modifier = Modifier.weight(1f)) {
                Text(BRAND_NAME, style = MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.try_saving), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Button(onClick = onAdd) { Text(stringResource(R.string.add), fontWeight = FontWeight.Bold) }
        }
    }
}

/** Prominent until the guide has been seen, then a quiet row at the bottom. */
@Composable
private fun PinGuideLink(seen: Boolean, onClick: () -> Unit) {
    Surface(
        color = if (seen) MaterialTheme.colorScheme.surfaceContainer else MaterialTheme.colorScheme.primaryContainer,
        shape = RoundedCornerShape(12.dp),
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(if (seen) Icons.Outlined.Lightbulb else Icons.Default.PushPin, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary)
            Text(
                stringResource(R.string.pin_guide_link, BRAND_NAME),
                style = if (seen) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium,
                fontWeight = if (seen) FontWeight.Normal else FontWeight.Medium,
                modifier = Modifier.weight(1f),
            )
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.outline)
        }
    }
}

@Composable
private fun SampleCard() {
    val sample by produceState<Bitmap?>(null) {
        value = withContext(Dispatchers.Default) { CardRenderer.render(sampleMeta, CardStyle(), scale = 1.5f) }
    }
    val width = (CardMetrics.WIDTH * 0.42f).dp
    // A 4:5 placeholder until the sample has rendered and its height is known.
    val height = sample?.let { width * (it.height.toFloat() / it.width) } ?: (width * 1.25f)
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier = Modifier
            .padding(vertical = 8.dp)
            .rotate(-4f)
            .size(width, height)
            .shadow(12.dp, shape)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceContainerLowest),
    ) {
        sample?.let { Image(it.asImageBitmap(), contentDescription = null) }
    }
}

@Composable
private fun StepRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(20.dp))
        }
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

