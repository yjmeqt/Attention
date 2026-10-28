package com.yijiang.attention.card

import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.text.Layout
import android.text.TextUtils
import com.yijiang.attention.model.LinkKind
import com.yijiang.attention.model.LinkMeta

// Each template draws from the top of the canvas and returns the card's height: every card is as tall as its content.

private const val TILE_PADDING = 18f

/** Image height ÷ width for the tile, kept between 16:9 and 9:16. Null when there's no photo to show. */
fun tileImageRatio(meta: LinkMeta): Float? {
    val size = meta.imageSize ?: return null
    val ratio = meta.imageAspectRatio?.takeIf { it > 0 } ?: return null
    val isIcon = maxOf(size.width, size.height) < 400 || (ratio in 0.8f..1.25f && size.width < 640)
    if (isIcon) return null
    return (1 / ratio).coerceIn(9f / 16, 16f / 9)
}

/** Looks like the iOS feed tile: the photo close to its own shape, its color carried into the text, and a QR code. */
internal fun CardDrawer.drawTile(): Float {
    val image = images.image
    val ratio = tileImageRatio(meta)
    val height = if (image == null || ratio == null) drawTextTile() else {
        val tint = CardTint.fromImage(image)
        val photoHeight = width * ratio
        val info = tileInfo(tint)
        if (ratio > 1) {
            drawFill(image, RectF(0f, 0f, width, photoHeight))
            // Fades the photo into the band color so the text reads like it's on the band.
            val scrimTop = photoHeight - info.height - 90
            canvas.drawRect(0f, scrimTop, width, photoHeight, Paint().apply {
                shader = LinearGradient(
                    0f, scrimTop, 0f, photoHeight,
                    intArrayOf(withAlpha(tint.color, 0f), withAlpha(tint.color, 0.75f), tint.color),
                    floatArrayOf(0f, 0.35f, 0.7f), Shader.TileMode.CLAMP,
                )
            })
            info.draw(photoHeight - info.height)
            photoHeight
        } else {
            canvas.drawColor(tint.color)
            drawFill(image, RectF(0f, 0f, width, photoHeight))
            info.draw(photoHeight)
            photoHeight + info.height
        }
    }
    if (meta.kind.isVideo && image != null) drawPlayGlyph(width / 2, height / 2)
    return height
}

private class Block(val height: Float, val draw: (top: Float) -> Unit)

private fun CardDrawer.tileInfo(tint: CardTint): Block {
    val textWidth = width - TILE_PADDING * 2
    val eyebrow = eyebrow(tint)
    val title = shrinkingLayout(
        meta.title, paint(titleSize(lines = 1), Weight.BOLD, tint.primary), textWidth,
        maxLines = 4, minScale = 0.85f, lineSpacing = 1f,
    )
    val bylinePaint = paint(14f, Weight.MEDIUM, tint.secondary)
    val byline = meta.byline
    val bylineHeight = if (byline != null) 6 + lineHeight(bylinePaint) else 0f
    val footer = tileFooter(tint, textWidth)
    val height = TILE_PADDING + eyebrow.height + 6 + title.height + bylineHeight + 16 + footer.height + TILE_PADDING
    return Block(height) { top ->
        var y = top + TILE_PADDING
        eyebrow.draw(y)
        y += eyebrow.height + 6
        draw(title, TILE_PADDING, y)
        y += title.height
        if (byline != null) drawLine(byline, bylinePaint, TILE_PADDING, y + 6, textWidth)
        footer.draw(top + height - TILE_PADDING - footer.height)
    }
}

private fun CardDrawer.drawTextTile(): Float {
    val tint = images.icon?.let(CardTint::fromFavicon) ?: CardTint.neutral
    val pad = TILE_PADDING + 4
    val textWidth = width - pad * 2
    canvas.drawColor(tint.color)
    val eyebrow = eyebrow(tint, left = pad)
    val title = shrinkingLayout(
        meta.title,
        paint(titleSize(lines = 2), if (meta.kind == LinkKind.X) Weight.MEDIUM else Weight.BOLD, tint.primary),
        textWidth, maxLines = 12, minScale = 0.8f, lineSpacing = 3f,
    )
    val bylinePaint = paint(14f, Weight.MEDIUM, tint.secondary)
    val byline = meta.byline
    val footer = tileFooter(tint, textWidth, left = pad)

    var y = pad
    eyebrow.draw(y)
    y += eyebrow.height + 10
    draw(title, pad, y)
    y += title.height
    if (byline != null) y += 8 + drawLine(byline, bylinePaint, pad, y + 8, textWidth)
    val height = maxOf(y + 28 + footer.height + pad, width * 0.8f)
    footer.draw(height - pad - footer.height)
    return height
}

/** Shorter titles get bigger type; [lines] raises the size for cards with nothing but text. */
private fun CardDrawer.titleSize(lines: Int): Float {
    var length = 0
    meta.title.codePoints().forEach { length += if (it > 0x2E80) 2 else 1 }
    val base = if (length <= 30) 26f else if (length <= 70) 22f else 19f
    return if (lines > 1) base + 1 else base
}

private fun CardDrawer.eyebrow(tint: CardTint, left: Float = TILE_PADDING): Block {
    val iconSize = 16f
    val labelPaint = paint(12f, Weight.SEMIBOLD, tint.secondary)
    val height = maxOf(iconSize, lineHeight(labelPaint))
    return Block(height) { top ->
        val box = RectF(left, top + (height - iconSize) / 2, left + iconSize, top + (height + iconSize) / 2)
        roundRect(box, iconSize * 0.24f, Color.WHITE)
        val icon = images.icon
        if (icon != null) {
            val inset = iconSize * 0.12f
            drawFit(icon, RectF(box.left + inset, box.top + inset, box.right - inset, box.bottom - inset))
        } else {
            drawGlobe(box.centerX(), box.centerY(), iconSize * 0.28f)
        }
        val label = (if (meta.kind == LinkKind.X) "X" else meta.site).uppercase()
        val labelLeft = box.right + 6
        drawLine(label, labelPaint, labelLeft, top + (height - lineHeight(labelPaint)) / 2, width - TILE_PADDING - labelLeft)
    }
}

private fun CardDrawer.drawGlobe(cx: Float, cy: Float, radius: Float) {
    val stroke = fill(Color.GRAY).apply {
        style = Paint.Style.STROKE
        strokeWidth = 0.8f
    }
    canvas.drawCircle(cx, cy, radius, stroke)
    canvas.drawOval(RectF(cx - radius * 0.45f, cy - radius, cx + radius * 0.45f, cy + radius), stroke)
    canvas.drawLine(cx - radius, cy, cx + radius, cy, stroke)
}

/** The link, a "made with" line and a QR code where the iOS feed tile has its Open button. */
private fun CardDrawer.tileFooter(tint: CardTint, textWidth: Float, left: Float = TILE_PADDING): Block {
    val qrBox = 60f + 10
    val urlPaint = paint(12f, Weight.MEDIUM, tint.secondary)
    val brandPaint = paint(12f, Weight.SEMIBOLD, tint.secondary)
    val brandRow = maxOf(18f, lineHeight(brandPaint))
    val textHeight = lineHeight(urlPaint) + 6 + brandRow
    val height = maxOf(qrBox, textHeight)
    return Block(height) { top ->
        val bottom = top + height
        val right = left + textWidth
        roundRect(RectF(right - qrBox, bottom - qrBox, right, bottom), 9f, Color.WHITE)
        val qr = QrCode.bitmap(meta.shareUrl.toString())
        canvas.drawBitmap(qr, null, RectF(right - qrBox + 5, bottom - qrBox + 5, right - 5, bottom - 5),
            Paint().apply { isFilterBitmap = false })

        val leftWidth = textWidth - qrBox - 12
        val textTop = bottom - textHeight
        drawLine(meta.displayUrl, urlPaint, left, textTop, leftWidth, TextUtils.TruncateAt.MIDDLE)
        val rowTop = bottom - brandRow
        drawAppGlyph(left, rowTop + (brandRow - 18) / 2, 18f)
        drawLine(brandText, brandPaint, left + 18 + 6, rowTop + (brandRow - lineHeight(brandPaint)) / 2, leftWidth - 24)
    }
}

internal fun CardDrawer.drawMinimal(): Float {
    val pad = 22f
    val thumbnail = images.image ?: images.icon?.takeIf { meta.hasLargeIcon }
    val rowHeight = if (thumbnail != null) maxOf(chipHeight, 64f) else chipHeight
    val textWidth = width - pad * 2
    val title = layout(
        meta.title, paint(26f, Weight.BOLD, palette.primary), textWidth,
        maxLines = CardMetrics.MINIMAL_LINES, lineSpacing = 3f,
    )
    val bylinePaint = paint(15f, Weight.REGULAR, palette.secondary)
    val byline = meta.byline
    val titleTop = pad + rowHeight + 14
    val textBottom = titleTop + title.height + if (byline != null) 14 + lineHeight(bylinePaint) else 0f
    val footerBottom = textBottom + 14 + 18 + footerHeight(CardMetrics.FOOTER_QR_SIZE)
    val height = footerBottom + pad

    canvas.drawRect(0f, 0f, width, height, Paint().apply {
        shader = LinearGradient(
            0f, 0f, width / 2, height / 2,
            withAlpha(palette.accent, 0.14f), Color.TRANSPARENT, Shader.TileMode.CLAMP,
        )
    })
    drawChip(pad, pad)
    if (thumbnail != null) {
        val rect = RectF(width - pad - 64, pad, width - pad, pad + 64)
        drawFill(thumbnail, rect, radius = 14f)
        canvas.drawRoundRect(RectF(rect.left + 0.5f, rect.top + 0.5f, rect.right - 0.5f, rect.bottom - 0.5f), 14f, 14f,
            fill(withAlpha(palette.primary, 0.08f)).apply {
                style = Paint.Style.STROKE
                strokeWidth = 1f
            })
    }
    draw(title, pad, titleTop)
    if (byline != null) drawLine(byline, bylinePaint, pad, titleTop + title.height + 14, textWidth)
    drawFooter(pad, width - pad, footerBottom, CardMetrics.FOOTER_QR_SIZE)
    return height
}

internal fun CardDrawer.drawQr(): Float {
    val pad = 22f
    drawChip(pad, pad)

    val textWidth = width - pad * 2
    val logo = images.icon?.takeIf { meta.hasLargeIcon }
    val title = layout(
        if (meta.hasPreview) meta.title else meta.displayUrl,
        paint(18f, Weight.SEMIBOLD, palette.primary), textWidth,
        maxLines = 2, alignment = Layout.Alignment.ALIGN_CENTER,
    )
    val note = if (meta.hasPreview) null else layout(
        "无法获取预览，可识别二维码或粘贴链接打开",
        paint(13f, Weight.REGULAR, palette.secondary), textWidth,
        maxLines = 2, alignment = Layout.Alignment.ALIGN_CENTER,
    )
    val qrSize = CardMetrics.BIG_QR_SIZE
    var y = pad + chipHeight + 14 + 20
    drawQrBadge(width / 2, y, qrSize, caption = "长按识别二维码打开", logo = logo)
    y += qrBadgeHeight(qrSize) + 14
    draw(title, pad, y)
    y += title.height
    if (note != null) {
        draw(note, pad, y + 14)
        y += 14 + note.height
    }
    y += 14 + 20
    drawLine(brandText, brandPaint, pad, y, textWidth, centered = true)
    return y + lineHeight(brandPaint) + pad
}
