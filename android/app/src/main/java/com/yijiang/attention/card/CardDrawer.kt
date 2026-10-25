package com.yijiang.attention.card

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.scale
import androidx.core.graphics.withTranslation
import com.yijiang.attention.model.BRAND_NAME
import com.yijiang.attention.model.LinkKind
import com.yijiang.attention.model.LinkMeta
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

enum class Weight(val value: Int) { REGULAR(400), MEDIUM(500), SEMIBOLD(600), BOLD(700) }

/** Draws card components on a canvas whose units are dp of the 360-wide card design. */
class CardDrawer(
    val canvas: Canvas,
    val meta: LinkMeta,
    val images: CardImages,
    val palette: CardPalette,
    val metrics: CardMetrics,
) {
    // region Text

    fun paint(size: Float, weight: Weight, color: Int) =
        TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            textSize = size
            this.color = color
            typeface = typeface(weight)
            textLocale = Locale.SIMPLIFIED_CHINESE
        }

    private fun typeface(weight: Weight): Typeface = Typeface.create(Typeface.DEFAULT, weight.value, false)

    fun lineHeight(paint: TextPaint): Float = paint.fontMetrics.let { it.descent - it.ascent }

    /** Wraps text up to [maxLines], dropping further lines (with an ellipsis) when it would exceed [maxHeight]. */
    fun layout(
        text: CharSequence,
        paint: TextPaint,
        width: Float,
        maxLines: Int,
        lineSpacing: Float = 0f,
        alignment: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL,
        maxHeight: Float = Float.MAX_VALUE,
    ): StaticLayout {
        fun build(lines: Int) = StaticLayout.Builder.obtain(text, 0, text.length, paint, width.toInt())
            .setAlignment(alignment)
            .setLineSpacing(lineSpacing, 1f)
            .setIncludePad(false)
            .setMaxLines(lines)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setBreakStrategy(Layout.BREAK_STRATEGY_HIGH_QUALITY)
            .setUseLineSpacingFromFallbacks(true)
            .build()

        val layout = build(maxLines)
        if (layout.height <= maxHeight) return layout
        val fitting = (0 until layout.lineCount).count { layout.getLineBottom(it) - lineSpacing <= maxHeight }
        return build(max(fitting, 1))
    }

    fun draw(layout: StaticLayout, x: Float, y: Float) = canvas.withTranslation(x, y) { layout.draw(this) }

    /** Draws one line whose top is at [y]; returns its height. */
    fun drawLine(
        text: String,
        paint: TextPaint,
        x: Float,
        y: Float,
        width: Float,
        truncateAt: TextUtils.TruncateAt = TextUtils.TruncateAt.END,
        centered: Boolean = false,
    ): Float {
        val fitted = TextUtils.ellipsize(text, paint, width, truncateAt).toString()
        val left = if (centered) x + (width - paint.measureText(fitted)) / 2 else x
        canvas.drawText(fitted, left, y - paint.fontMetrics.ascent, paint)
        return lineHeight(paint)
    }

    // endregion

    // region Shapes and images

    fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }

    fun roundRect(rect: RectF, radius: Float, color: Int) = canvas.drawRoundRect(rect, radius, radius, fill(color))

    /** Scales the bitmap to cover [rect], cropping the overflow, optionally with rounded corners. */
    fun drawFill(bitmap: Bitmap, rect: RectF, radius: Float = 0f, oval: Boolean = false) {
        val factor = max(rect.width() / bitmap.width, rect.height() / bitmap.height)
        val matrix = Matrix().apply {
            setScale(factor, factor)
            postTranslate(rect.centerX() - bitmap.width * factor / 2, rect.centerY() - bitmap.height * factor / 2)
        }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            shader = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(matrix) }
        }
        if (oval) canvas.drawOval(rect, paint) else canvas.drawRoundRect(rect, radius, radius, paint)
    }

    /** Scales the bitmap to fit inside [rect], centered. */
    fun drawFit(bitmap: Bitmap, rect: RectF) {
        val factor = min(rect.width() / bitmap.width, rect.height() / bitmap.height)
        val w = bitmap.width * factor
        val h = bitmap.height * factor
        val target = RectF(rect.centerX() - w / 2, rect.centerY() - h / 2, rect.centerX() + w / 2, rect.centerY() + h / 2)
        canvas.drawBitmap(bitmap, null, target, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }

    private fun blurred(bitmap: Bitmap): Bitmap {
        val tiny = bitmap.scale(12, max(1, 12 * bitmap.height / bitmap.width))
        return tiny.scale(120, max(1, 120 * bitmap.height / bitmap.width))
    }

    fun withAlpha(color: Int, alpha: Float) = ColorUtils.setAlphaComponent(color, (alpha * Color.alpha(color)).roundToInt())

    // endregion

    // region Components

    private val chipPaint = paint(13f, Weight.BOLD, palette.onAccent)

    private val chipLabel = when (meta.kind) {
        LinkKind.YOUTUBE -> "YouTube · 视频"
        LinkKind.BILIBILI -> "哔哩哔哩 · 视频"
        LinkKind.X -> "X · 帖子"
        LinkKind.WEB -> if (meta.site.length > 18) meta.site.take(17) + "…" else meta.site
    }

    /** Shown at 14 dp (42 px); smaller favicons would look blurry. */
    private val chipIcon = images.icon?.takeIf { (meta.iconSize?.width ?: 0) >= 32 }

    val chipHeight = lineHeight(chipPaint) + 8
    val chipWidth = (if (chipIcon != null) 4f + 18 + 5 else 10f) + chipPaint.measureText(chipLabel) + 10

    fun drawChip(x: Float, y: Float) {
        roundRect(RectF(x, y, x + chipWidth, y + chipHeight), chipHeight / 2, palette.accent)
        var textX = x + 10
        chipIcon?.let { icon ->
            val box = RectF(x + 4, y + (chipHeight - 18) / 2, x + 22, y + (chipHeight + 18) / 2)
            roundRect(box, 4f, Color.WHITE)
            drawFit(icon, RectF(box.left + 2, box.top + 2, box.right - 2, box.bottom - 2))
            textX = box.right + 5
        }
        val baseline = y + chipHeight / 2 - (chipPaint.fontMetrics.ascent + chipPaint.fontMetrics.descent) / 2
        canvas.drawText(chipLabel, textX, baseline, chipPaint)
    }

    private val captionPaint = paint(11f, Weight.MEDIUM, palette.secondary)

    fun qrBadgeHeight(size: Float) = size + 12 + 5 + lineHeight(captionPaint)

    fun drawQrBadge(centerX: Float, top: Float, size: Float, caption: String = "长按识别", logo: Bitmap? = null) {
        val left = centerX - size / 2 - 6
        roundRect(RectF(left, top, left + size + 12, top + size + 12), 8f, Color.WHITE)
        val qr = QrCode.bitmap(meta.shareUrl.toString(), highCorrection = logo != null)
        canvas.drawBitmap(qr, null, RectF(left + 6, top + 6, left + 6 + size, top + 6 + size), Paint().apply { isFilterBitmap = false })
        if (logo != null) {
            val inner = size * 0.18f
            val pad = size * 0.025f
            val cx = left + 6 + size / 2
            val cy = top + 6 + size / 2
            val half = inner / 2 + pad
            roundRect(RectF(cx - half, cy - half, cx + half, cy + half), size * 0.04f, Color.WHITE)
            drawFit(logo, RectF(cx - inner / 2, cy - inner / 2, cx + inner / 2, cy + inner / 2))
        }
        val captionWidth = captionPaint.measureText(caption)
        canvas.drawText(caption, centerX - captionWidth / 2, top + size + 12 + 5 - captionPaint.fontMetrics.ascent, captionPaint)
    }

    val brandPaint = paint(11f, Weight.REGULAR, palette.tertiary)
    val brandText = "由 $BRAND_NAME 生成"

    private val urlPaint = paint(12f, Weight.MEDIUM, palette.secondary)

    fun footerHeight(qrSize: Float) = qrBadgeHeight(qrSize)

    fun drawFooter(left: Float, right: Float, bottom: Float, qrSize: Float) {
        val badgeWidth = qrSize + 12
        drawQrBadge(right - badgeWidth / 2, bottom - qrBadgeHeight(qrSize), qrSize)
        val textWidth = right - left - badgeWidth - 12
        val brandTop = bottom - lineHeight(brandPaint)
        drawLine(brandText, brandPaint, left, brandTop, textWidth)
        val urlTop = brandTop - 4 - lineHeight(urlPaint)
        drawLine(meta.displayUrl, urlPaint, left, urlTop, textWidth, TextUtils.TruncateAt.MIDDLE)
    }

    /** Images much narrower than the banner are shown whole over a blurred fill instead of being cropped. */
    fun drawHeroImage(rect: RectF) {
        val image = images.image
        if (image != null) {
            val ratio = image.width.toFloat() / image.height
            if (ratio < rect.width() / rect.height() * 0.75f) {
                drawFill(blurred(image), rect)
                canvas.drawRect(rect, fill(withAlpha(Color.BLACK, 0.15f)))
                drawFit(image, rect)
            } else {
                drawFill(image, rect)
            }
            return
        }
        canvas.drawRect(rect, fill(palette.accent).apply {
            shader = LinearGradient(
                rect.left, rect.top, rect.right, rect.bottom,
                palette.accent, withAlpha(palette.accent, 0.55f), Shader.TileMode.CLAMP,
            )
        })
        val icon = images.icon?.takeIf { meta.hasLargeIcon }
        val sitePaint = paint(if (icon == null) 40f else 24f, Weight.BOLD, palette.onAccent)
        val maxWidth = rect.width() - 32
        val minSize = sitePaint.textSize * 0.4f
        while (sitePaint.measureText(meta.site) > maxWidth && sitePaint.textSize > minSize) sitePaint.textSize -= 1f
        val textHeight = lineHeight(sitePaint)
        val total = textHeight + if (icon != null) 80f + 10 else 0f
        var y = rect.centerY() - total / 2
        if (icon != null) {
            val box = RectF(rect.centerX() - 40, y, rect.centerX() + 40, y + 80)
            roundRect(box, 18f, Color.WHITE)
            drawFit(icon, RectF(box.left + 8, box.top + 8, box.right - 8, box.bottom - 8))
            y += 90
        }
        drawLine(meta.site, sitePaint, rect.left + 16, y, maxWidth, centered = true)
    }

    fun drawPlayGlyph(cx: Float, cy: Float) {
        canvas.drawCircle(cx, cy, 30f, fill(withAlpha(Color.BLACK, 0.55f)))
        val path = Path().apply {
            moveTo(cx - 8, cy - 11)
            lineTo(cx + 12, cy)
            lineTo(cx - 8, cy + 11)
            close()
        }
        canvas.drawPath(path, fill(Color.WHITE).apply {
            strokeJoin = Paint.Join.ROUND
            strokeWidth = 3f
            style = Paint.Style.FILL_AND_STROKE
        })
    }

    fun drawAvatar(rect: RectF) {
        val avatar = images.avatar
        if (avatar != null) {
            drawFill(avatar, rect, oval = true)
            return
        }
        canvas.drawOval(rect, fill(palette.accent))
        val initial = (meta.authorName ?: meta.site).take(1).uppercase()
        val initialPaint = paint(20f, Weight.BOLD, palette.onAccent)
        val baseline = rect.centerY() - (initialPaint.fontMetrics.ascent + initialPaint.fontMetrics.descent) / 2
        canvas.drawText(initial, rect.centerX() - initialPaint.measureText(initial) / 2, baseline, initialPaint)
    }

    // endregion
}
