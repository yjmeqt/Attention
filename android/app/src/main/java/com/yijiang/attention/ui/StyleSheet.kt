package com.yijiang.attention.ui

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StyleSheet(vm: MakerViewModel, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.style), style = MaterialTheme.typography.titleLarge)
            val meta = vm.meta
            val images = vm.images
            if (meta != null && images != null) {
                Text(stringResource(R.string.template), style = MaterialTheme.typography.titleSmall)
                TemplatePicker(meta, images, vm.style, onSelect = { vm.updateStyle(vm.style.copy(template = it)) })
            }
            meta?.let { SourceImageInfo(it) }
            if (vm.style != CardStyle()) {
                TextButton(onClick = { vm.updateStyle(CardStyle()) }, contentPadding = ButtonDefaults.TextButtonWithIconContentPadding) {
                    Icon(Icons.Default.Restore, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
                    Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                    Text(stringResource(R.string.restore_default))
                }
            }
        }
    }
}

@Composable
private fun TemplatePicker(meta: LinkMeta, images: CardImages, style: CardStyle, onSelect: (CardTemplate) -> Unit) {
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
private fun SourceImageInfo(meta: LinkMeta) {
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
