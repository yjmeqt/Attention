package com.yijiang.opticshare.card

import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.text.Layout

internal fun CardDrawer.drawHero() {
    val m = metrics
    val imageHeight = m.heroImageHeight(meta.imageAspectRatio)
    drawHeroImage(RectF(0f, 0f, m.width, imageHeight))
    if (meta.kind.isVideo && images.image != null) drawPlayGlyph(m.width / 2, imageHeight / 2)
    drawChip(12f, 12f)

    val width = m.width - m.padding * 2
    val footerTop = m.height - m.padding - footerHeight(m.footerQrSize)
    val bylinePaint = paint(15f, Weight.REGULAR, palette.secondary)
    val byline = meta.byline
    val bylineHeight = if (byline != null) 6 + lineHeight(bylinePaint) else 0f
    var y = imageHeight + m.padding
    val title = layout(
        meta.title, paint(22f, Weight.SEMIBOLD, palette.primary), width,
        maxLines = m.heroTitleLines(imageHeight, byline != null),
        lineSpacing = 2f,
        maxHeight = footerTop - 8 - bylineHeight - y,
    )
    draw(title, m.padding, y)
    y += title.height
    if (byline != null) drawLine(byline, bylinePaint, m.padding, y + 6, width)
    drawFooter(m.padding, m.width - m.padding, m.height - m.padding, m.footerQrSize)
}

internal fun CardDrawer.drawMinimal() {
    val m = metrics
    val pad = 22f
    canvas.drawRect(0f, 0f, m.width, m.height, Paint().apply {
        shader = LinearGradient(
            0f, 0f, m.width / 2, m.height / 2,
            withAlpha(palette.accent, 0.14f), Color.TRANSPARENT, Shader.TileMode.CLAMP,
        )
    })
    drawChip(pad, pad)
    val thumbnail = images.image ?: images.icon?.takeIf { meta.hasLargeIcon }
    if (thumbnail != null) {
        val rect = RectF(m.width - pad - 64, pad, m.width - pad, pad + 64)
        drawFill(thumbnail, rect, radius = 14f)
        canvas.drawRoundRect(RectF(rect.left + 0.5f, rect.top + 0.5f, rect.right - 0.5f, rect.bottom - 0.5f), 14f, 14f,
            fill(withAlpha(palette.primary, 0.08f)).apply {
                style = Paint.Style.STROKE
                strokeWidth = 1f
            })
    }
    val rowHeight = if (thumbnail != null) maxOf(chipHeight, 64f) else chipHeight

    val width = m.width - pad * 2
    val footerTop = m.height - pad - footerHeight(m.footerQrSize)
    val bylinePaint = paint(15f, Weight.REGULAR, palette.secondary)
    val byline = meta.byline
    val bylineHeight = if (byline != null) 14 + lineHeight(bylinePaint) else 0f
    var y = pad + rowHeight + 14
    val title = layout(
        meta.title, paint(26f, Weight.BOLD, palette.primary), width,
        maxLines = m.minimalLines,
        lineSpacing = 3f,
        maxHeight = footerTop - 14 - bylineHeight - y,
    )
    draw(title, pad, y)
    y += title.height
    if (byline != null) drawLine(byline, bylinePaint, pad, y + 14, width)
    drawFooter(pad, m.width - pad, m.height - pad, m.footerQrSize)
}

internal fun CardDrawer.drawPost() {
    val m = metrics
    val pad = m.padding
    val namePaint = paint(16f, Weight.SEMIBOLD, palette.primary)
    val handlePaint = paint(14f, Weight.REGULAR, palette.secondary)
    val handle = meta.authorHandle?.let { "@$it" }
    val nameBlock = lineHeight(namePaint) + if (handle != null) 2 + lineHeight(handlePaint) else 0f
    val rowHeight = maxOf(44f, nameBlock, chipHeight)

    drawAvatar(RectF(pad, pad + (rowHeight - 44) / 2, pad + 44, pad + (rowHeight + 44) / 2))
    val chipX = m.width - pad - chipWidth
    drawChip(chipX, pad + (rowHeight - chipHeight) / 2)
    val textX = pad + 44 + 10
    val textWidth = chipX - 8 - textX
    var nameY = pad + (rowHeight - nameBlock) / 2
    nameY += drawLine(meta.authorName ?: meta.site, namePaint, textX, nameY, textWidth)
    if (handle != null) drawLine(handle, handlePaint, textX, nameY + 2, textWidth)

    val mediaHeight = m.postMediaHeight(meta.imageAspectRatio)
    val media = images.image?.takeIf { mediaHeight > 0 && !meta.imageIsIcon }
    val width = m.width - pad * 2
    val footerTop = m.height - pad - footerHeight(m.footerQrSize)
    var y = pad + rowHeight + 14
    val mediaBlock = if (media != null) 14 + mediaHeight else 0f
    val title = layout(
        meta.title, paint(19f, Weight.REGULAR, palette.primary), width,
        maxLines = m.postLines(withMedia = media != null),
        lineSpacing = 3f,
        maxHeight = footerTop - 8 - mediaBlock - y,
    )
    draw(title, pad, y)
    y += title.height
    if (media != null) {
        val rect = RectF(pad, y + 14, pad + width, y + 14 + mediaHeight)
        drawFill(media, rect, radius = 12f)
        if (meta.kind.isVideo) drawPlayGlyph(rect.centerX(), rect.centerY())
    }
    drawFooter(pad, m.width - pad, m.height - pad, m.footerQrSize)
}

internal fun CardDrawer.drawQr() {
    val m = metrics
    val pad = 22f
    drawChip(pad, pad)

    val width = m.width - pad * 2
    val logo = images.icon?.takeIf { meta.hasLargeIcon }
    val title = layout(
        if (meta.hasPreview) meta.title else meta.displayUrl,
        paint(18f, Weight.SEMIBOLD, palette.primary), width,
        maxLines = 2, alignment = Layout.Alignment.ALIGN_CENTER,
    )
    val note = if (meta.hasPreview) null else layout(
        "无法获取预览，可识别二维码或粘贴链接打开",
        paint(13f, Weight.REGULAR, palette.secondary), width,
        maxLines = 2, alignment = Layout.Alignment.ALIGN_CENTER,
    )
    val qrSize = m.bigQrSize
    val groupHeight = qrBadgeHeight(qrSize) + 14 + title.height + (note?.let { 14f + it.height } ?: 0f)

    val brandHeight = lineHeight(brandPaint)
    val top = pad + chipHeight + 14
    val bottom = m.height - pad - brandHeight - 14
    var y = top + maxOf(0f, (bottom - top - groupHeight) / 2)
    drawQrBadge(m.width / 2, y, qrSize, caption = "长按识别二维码打开", logo = logo)
    y += qrBadgeHeight(qrSize) + 14
    draw(title, pad, y)
    y += title.height
    if (note != null) draw(note, pad, y + 14)
    drawLine(brandText, brandPaint, pad, m.height - pad - brandHeight, width, centered = true)
}
