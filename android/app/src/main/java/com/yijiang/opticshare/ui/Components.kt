package com.yijiang.opticshare.ui

import android.graphics.BitmapFactory
import android.text.format.DateUtils
import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yijiang.opticshare.R
import com.yijiang.opticshare.data.HistoryEntry
import com.yijiang.opticshare.model.CardTemplate
import com.yijiang.opticshare.model.LinkMeta

@get:StringRes
val CardTemplate.labelRes: Int
    get() = when (this) {
        CardTemplate.AUTO -> R.string.template_auto
        CardTemplate.HERO -> R.string.template_hero
        CardTemplate.POST -> R.string.template_post
        CardTemplate.MINIMAL -> R.string.template_minimal
        CardTemplate.QR -> R.string.template_qr
    }

val LinkMeta.listTitle: String get() = if (hasPreview) title else displayUrl

@Composable
fun HistoryEntry.relativeDate(): String {
    val now = System.currentTimeMillis()
    if (now - date < DateUtils.MINUTE_IN_MILLIS) return stringResource(R.string.just_now)
    return DateUtils.getRelativeTimeSpanString(date, now, DateUtils.MINUTE_IN_MILLIS).toString()
}

/** Site icon for in-app lists, with a link glyph when there's no favicon. */
@Composable
fun FaviconView(meta: LinkMeta, size: Dp = 28.dp) {
    val icon = remember(meta.icon) {
        meta.icon?.let { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }
    }
    Box(
        modifier = Modifier
            .size(size)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(size * 0.25f)),
        contentAlignment = Alignment.Center,
    ) {
        if (icon != null) {
            Image(icon, contentDescription = null, modifier = Modifier.padding(size * 0.12f))
        } else {
            Icon(
                Icons.Default.Link,
                contentDescription = null,
                modifier = Modifier.size(size * 0.55f),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
