package com.yijiang.attention.ui

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.yijiang.attention.R
import com.yijiang.attention.card.CardImages
import com.yijiang.attention.card.CardRenderer
import com.yijiang.attention.card.CardMetrics
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.CardTemplate
import com.yijiang.attention.model.LinkMeta
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val THUMBNAIL_SCALE = 0.2f

@Composable
fun TemplatePicker(meta: LinkMeta, images: CardImages, style: CardStyle, onSelect: (CardTemplate) -> Unit) {
    val thumbnails by produceState<Map<CardTemplate, Bitmap>>(emptyMap(), meta, images) {
        value = withContext(Dispatchers.Default) {
            CardTemplate.entries.associateWith { template ->
                CardRenderer.render(meta, style.copy(template = template), images, scale = 0.6f)
            }
        }
    }
    // Cards are as tall as their content, so each thumbnail takes its card's shape.
    val width = (CardMetrics.WIDTH * THUMBNAIL_SCALE).dp
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CardTemplate.entries.forEach { template ->
            val selected = style.template == template
            val shape = RoundedCornerShape(6.dp)
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { onSelect(template) }.padding(2.dp),
            ) {
                val thumbnail = thumbnails[template]
                val height = thumbnail?.let { width * (it.height.toFloat() / it.width) } ?: width
                Box(
                    modifier = Modifier
                        .size(width, height)
                        .clip(shape)
                        .border(
                            if (selected) BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
                            else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                            shape,
                        ),
                ) {
                    thumbnail?.let {
                        Image(it.asImageBitmap(), contentDescription = null, modifier = Modifier.size(width, height))
                    }
                }
                val label = if (template == CardTemplate.AUTO) {
                    stringResource(R.string.template_auto_resolved, stringResource(template.resolved(meta).labelRes))
                } else {
                    stringResource(template.labelRes)
                }
                Text(
                    label,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
fun SourceImageInfo(meta: LinkMeta) {
    val size = meta.imageSize
    val (icon, text, color) = when {
        size != null && size.width < 800 -> Triple(
            Icons.Outlined.Warning,
            stringResource(R.string.source_image_low, size.width, size.height),
            Color(0xFFE08A00),
        )
        size != null -> Triple(
            Icons.Outlined.Image,
            stringResource(R.string.source_image, size.width, size.height),
            MaterialTheme.colorScheme.onSurfaceVariant,
        )
        meta.hasPreview -> Triple(Icons.Outlined.Image, stringResource(R.string.no_source_image), MaterialTheme.colorScheme.onSurfaceVariant)
        else -> return
    }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = color)
    }
}

/** For links shared as an image: the link's preview image or the shared image. */
@Composable
fun CoverPicker(preview: Bitmap?, shared: Bitmap?, usesShared: Boolean, onSelect: (Boolean) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CoverOption(stringResource(R.string.link_preview), preview, selected = !usesShared) { onSelect(false) }
        CoverOption(stringResource(R.string.shared_image), shared, selected = usesShared) { onSelect(true) }
    }
}

@Composable
private fun CoverOption(title: String, image: Bitmap?, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(6.dp)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(2.dp),
    ) {
        Box(
            modifier = Modifier
                .size(96.dp, 72.dp)
                .clip(shape)
                .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                .border(
                    if (selected) BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
                    else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    shape,
                ),
        ) {
            image?.let {
                Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(96.dp, 72.dp))
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.labelSmall,
            color = if (selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
