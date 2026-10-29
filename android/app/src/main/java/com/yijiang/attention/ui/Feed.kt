package com.yijiang.attention.ui

import android.graphics.Bitmap
import android.text.format.DateUtils
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yijiang.attention.R
import com.yijiang.attention.card.CardTint
import com.yijiang.attention.data.DomainTag
import com.yijiang.attention.data.FeedFilter
import com.yijiang.attention.data.Library
import com.yijiang.attention.data.LibraryItem
import com.yijiang.attention.data.LibraryRules
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Columns for the waterfall: one per 240 dp, between 2 and 6, like the iOS feed. */
fun feedColumns(width: Dp): Int = (width.value / 240).toInt().coerceIn(2, 6)

@Composable
fun domainLabel(domain: String): String = if (domain == DomainTag.IMAGES) stringResource(R.string.images) else domain

/** Loads off the main thread; [revision] reloads it when the item's files change. */
@Composable
private fun rememberThumbnail(library: Library, item: LibraryItem, revision: Int): Pair<ImageBitmap, CardTint?>? {
    val loaded by produceState<Pair<Bitmap, CardTint?>?>(null, item.id, revision, item.thumbnailAspect) {
        value = withContext(Dispatchers.IO) { library.thumbnail(item)?.let { it to library.tint(item) } }
    }
    return loaded?.let { (bitmap, tint) -> remember(bitmap) { bitmap.asImageBitmap() } to tint }
}

@Composable
fun rememberFavicon(library: Library, item: LibraryItem, revision: Int): ImageBitmap? {
    val icon by produceState<Bitmap?>(null, item.id, revision) {
        value = withContext(Dispatchers.IO) { library.favicon(item) }
    }
    return icon?.let { remember(it) { it.asImageBitmap() } }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FeedTile(
    item: LibraryItem,
    library: Library,
    revision: Int,
    enriching: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    isSelecting: Boolean = false,
    isSelected: Boolean = false,
    onOpen: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(16.dp)
    val interaction = remember { MutableInteractionSource() }
    // Shrinks a little while pressed, like App Store cards.
    val pressed by interaction.collectIsPressedAsState()
    val thumbnail = rememberThumbnail(library, item, revision)
    val favicon = rememberFavicon(library, item, revision)
    Box(
        modifier = modifier
            .scale(if (pressed) 0.97f else 1f)
            .alpha(if (isSelecting && !isSelected) 0.85f else 1f)
            .clip(shape)
            .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f), shape)
            .combinedClickable(interactionSource = interaction, indication = null, onClick = onClick, onLongClick = onLongClick),
    ) {
        // The stored aspect lays the tile out before its photo has loaded, so the grid doesn't jump.
        if (item.thumbnailAspect > 0) {
            PhotoCard(item, thumbnail?.first, thumbnail?.second, favicon, onOpen)
        } else {
            Lockup(item, favicon, onOpen)
        }
        if (isSelecting) {
            Icon(
                if (isSelected) Icons.Default.CheckCircle else Icons.Outlined.Circle,
                contentDescription = null,
                tint = if (isSelected) MaterialTheme.colorScheme.primary else Color.White,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(26.dp)
                    .background(if (isSelected) Color.White else Color.Black.copy(alpha = 0.3f), CircleShape),
            )
        }
        if (enriching) {
            Surface(shape = CircleShape, tonalElevation = 3.dp, modifier = Modifier.align(Alignment.Center)) {
                CircularProgressIndicator(modifier = Modifier.padding(10.dp).size(22.dp), strokeWidth = 2.dp)
            }
        }
    }
}

/** A photo with a band below it in the photo's own color, like App Store Today cards. */
@Composable
private fun PhotoCard(item: LibraryItem, photo: ImageBitmap?, tint: CardTint?, favicon: ImageBitmap?, onOpen: (() -> Unit)?) {
    val band = tint?.let { Color(it.color) } ?: MaterialTheme.colorScheme.surfaceContainerHigh
    val primary = tint?.let { Color(it.primary) } ?: MaterialTheme.colorScheme.onSurface
    val secondary = tint?.let { Color(it.secondary) } ?: MaterialTheme.colorScheme.onSurfaceVariant
    Column {
        val photoModifier = Modifier.fillMaxWidth().aspectRatio(item.thumbnailAspect)
        if (photo != null) {
            Image(photo, contentDescription = null, contentScale = ContentScale.Crop, modifier = photoModifier)
        } else {
            Box(photoModifier.background(MaterialTheme.colorScheme.surfaceContainerHighest))
        }
        CompositionLocalProvider(LocalContentColor provides primary) {
            Column(
                modifier = Modifier.fillMaxWidth().background(band).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Eyebrow(item, favicon, secondary)
                val title = item.displayTitle
                if (title != null && (!item.isImage || item.title.isNotEmpty())) {
                    Text(title, style = MaterialTheme.typography.titleSmall, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
                FooterRow(item, secondary, onOpen, isDark = tint?.isDark)
            }
        }
    }
}

/** Links without a photo: the same text as under a photo, on a plain band. */
@Composable
private fun Lockup(item: LibraryItem, favicon: ImageBitmap?, onOpen: (() -> Unit)?) {
    Column(
        modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val secondary = MaterialTheme.colorScheme.onSurfaceVariant
        Eyebrow(item, favicon, secondary)
        Text(
            item.displayTitle ?: formattedDate(item.createdAt),
            style = MaterialTheme.typography.titleSmall,
            maxLines = 6,
            overflow = TextOverflow.Ellipsis,
        )
        FooterRow(item, secondary, onOpen, isDark = null)
    }
}

/** The platform line above a title: favicon and site name. */
@Composable
private fun Eyebrow(item: LibraryItem, favicon: ImageBitmap?, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (favicon != null) {
            Image(favicon, contentDescription = null, modifier = Modifier.size(14.dp).clip(RoundedCornerShape(3.dp)))
        } else {
            Icon(if (item.isImage) Icons.Default.Photo else Icons.Default.Public, contentDescription = null,
                tint = color, modifier = Modifier.size(14.dp))
        }
        Text(
            (if (item.isImage && item.site.isEmpty()) domainLabel(item.domain) else item.platformName).uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Time on the left; links get an Open button on the right, like the App Store's Get button. */
@Composable
private fun FooterRow(item: LibraryItem, color: Color, onOpen: (() -> Unit)?, isDark: Boolean?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (item.isPrivate) Icon(Icons.Default.Lock, contentDescription = null, tint = color, modifier = Modifier.size(11.dp))
        if (item.isPrivate) Spacer(Modifier.size(4.dp))
        Text(relativeTime(item.updatedAt), style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1,
            modifier = Modifier.weight(1f))
        if (onOpen != null && item.url != null) {
            val container = when (isDark) {
                true -> Color.White.copy(alpha = 0.2f)
                false -> Color.Black.copy(alpha = 0.08f)
                null -> MaterialTheme.colorScheme.secondaryContainer
            }
            FilledTonalButton(
                onClick = onOpen,
                contentPadding = PaddingValues(horizontal = 12.dp),
                colors = androidx.compose.material3.ButtonDefaults.filledTonalButtonColors(
                    containerColor = container, contentColor = LocalContentColor.current,
                ),
                modifier = Modifier.height(28.dp),
            ) {
                Text(stringResource(R.string.open), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }
        }
    }
}

fun relativeTime(time: Long): String {
    val now = System.currentTimeMillis()
    return DateUtils.getRelativeTimeSpanString(minOf(time, now), now, DateUtils.MINUTE_IN_MILLIS, DateUtils.FORMAT_ABBREV_RELATIVE).toString()
}

fun formattedDate(time: Long): String =
    java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT).format(time)

/** All, then sites, then tags of the current section, most common first. */
@Composable
fun FilterBar(filter: FeedFilter, items: List<LibraryItem>, library: Library, revision: Int, onChange: (FeedFilter) -> Unit) {
    val section = filter.section(items)
    val byDomain = remember(section) { section.associateBy { it.domain } }
    val domains = remember(section) { LibraryRules.ranked(section.map { it.domain }) }
    val tags = remember(section) { LibraryRules.ranked(section.flatMap { it.tags }) }
    val state = rememberLazyListState()
    // "Only youtube.com" or "Only #tag" can pick a chip that's off screen, so bring the first selected one into view.
    LaunchedEffect(Unit) {
        val domain = domains.indexOfFirst { it in filter.domains }
        val tag = tags.indexOfFirst { it in filter.tags }
        when {
            domain >= 0 -> state.scrollToItem(1 + domain)
            tag >= 0 -> state.scrollToItem(1 + domains.size + tag)
        }
    }
    LazyRow(
        state = state,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Chip(stringResource(R.string.all), selected = filter.domains.isEmpty() && filter.tags.isEmpty(),
                icon = { Icon(Icons.Default.GridView, contentDescription = null, modifier = Modifier.size(16.dp)) },
                onClick = { onChange(filter.clearFilters()) })
        }
        items(domains, key = { "domain:$it" }) { domain ->
            Chip(domainLabel(domain), selected = domain in filter.domains,
                icon = {
                    val icon = byDomain[domain]?.let { rememberFavicon(library, it, revision) }
                    if (icon != null) {
                        Image(icon, contentDescription = null, modifier = Modifier.size(16.dp).clip(RoundedCornerShape(4.dp)))
                    } else {
                        Icon(if (domain == DomainTag.IMAGES) Icons.Default.Photo else Icons.Default.Public,
                            contentDescription = null, modifier = Modifier.size(16.dp))
                    }
                },
                onClick = { onChange(filter.toggleDomain(domain)) })
        }
        items(tags, key = { "tag:$it" }) { tag ->
            Chip(tag, selected = tag in filter.tags,
                icon = { Icon(Icons.Default.Tag, contentDescription = null, modifier = Modifier.size(16.dp)) },
                onClick = { onChange(filter.toggleTag(tag)) })
        }
    }
}

@Composable
private fun Chip(text: String, selected: Boolean, icon: @Composable () -> Unit, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(text, maxLines = 1, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal) },
        leadingIcon = icon,
        shape = CircleShape,
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primary,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
            selectedLeadingIconColor = MaterialTheme.colorScheme.onPrimary,
        ),
    )
}
