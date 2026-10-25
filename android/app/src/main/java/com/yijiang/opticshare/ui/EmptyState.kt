package com.yijiang.opticshare.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yijiang.opticshare.R
import com.yijiang.opticshare.card.CardRenderer
import com.yijiang.opticshare.data.HistoryEntry
import com.yijiang.opticshare.model.BRAND_NAME
import com.yijiang.opticshare.model.CardAspect
import com.yijiang.opticshare.model.CardStyle
import com.yijiang.opticshare.model.LinkMeta
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private val sampleMeta = LinkMeta(
    url = "https://youtu.be/dQw4w9WgXcQ",
    site = "YouTube",
    title = "Rick Astley - Never Gonna Give You Up (Official Video)",
    authorName = "Rick Astley",
)

@Composable
fun EmptyState(entries: List<HistoryEntry>, onPaste: () -> Unit, onOpen: (HistoryEntry) -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
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
        RecentList(entries.take(3), onOpen)
    }
}

@Composable
private fun SampleCard() {
    val sample by produceState<Bitmap?>(null) {
        value = withContext(Dispatchers.Default) { CardRenderer.render(sampleMeta, CardStyle(), scale = 1.5f) }
    }
    val aspect = CardAspect.PORTRAIT
    val width = (aspect.width * 0.42f).dp
    val height = (aspect.height * 0.42f).dp
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

@Composable
private fun RecentList(entries: List<HistoryEntry>, onOpen: (HistoryEntry) -> Unit) {
    if (entries.isEmpty()) return
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.recent),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        entries.forEachIndexed { index, entry ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onOpen(entry) }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                FaviconView(entry.meta)
                Text(entry.meta.listTitle, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(
                    entry.meta.site,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.outline,
                )
            }
            if (index != entries.lastIndex) HorizontalDivider()
        }
    }
}
