package com.yijiang.attention.card

import android.graphics.Bitmap
import android.graphics.Color
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.scale
import com.yijiang.attention.model.LinkKind

class CardPalette(kind: LinkKind) {
    val background = Color.WHITE
    val primary = Color.rgb(18, 18, 20)
    val secondary = ColorUtils.setAlphaComponent(primary, (0.62f * 255).toInt())
    val tertiary = ColorUtils.setAlphaComponent(primary, (0.38f * 255).toInt())
    val accent = when (kind) {
        LinkKind.YOUTUBE -> Color.rgb(255, 0, 51)
        LinkKind.BILIBILI -> Color.rgb(250, 115, 153)
        LinkKind.X -> Color.BLACK
        LinkKind.WEB -> Color.rgb(46, 107, 255)
    }
    val onAccent = Color.WHITE
}

/** Sizes in dp. Every card is [WIDTH] wide and as tall as its content. */
object CardMetrics {
    const val WIDTH = 360f
    const val MINIMAL_LINES = 6
    const val FOOTER_QR_SIZE = 80f
    const val BIG_QR_SIZE = 180f
}

/** A tile card's band color and the text colors that read on it. */
class CardTint(val color: Int, val isDark: Boolean) {
    val primary = if (isDark) Color.WHITE else Color.rgb(18, 18, 20)
    val secondary = ColorUtils.setAlphaComponent(primary, ((if (isDark) 0.72f else 0.6f) * 255).toInt())

    companion object {
        val neutral = CardTint(Color.rgb(242, 242, 245), isDark = false)

        /** From the image's bottom edge, like the iOS feed. */
        fun fromImage(image: Bitmap): CardTint {
            val strip = maxOf(1, image.height / 8)
            val edge = Bitmap.createBitmap(image, 0, image.height - strip, image.width, strip)
            return of(averageColor(edge))
        }

        /** Colorful favicons tint the card; black, white and gray ones would make it a slab, so they don't. */
        fun fromFavicon(icon: Bitmap): CardTint? {
            val color = averageColor(icon)
            val high = maxOf(Color.red(color), Color.green(color), Color.blue(color)) / 255f
            val low = minOf(Color.red(color), Color.green(color), Color.blue(color)) / 255f
            if (high <= 0.15f || (high - low) / high <= 0.35f) return null
            return of(color)
        }

        private fun of(color: Int): CardTint {
            val luma = (0.299f * Color.red(color) + 0.587f * Color.green(color) + 0.114f * Color.blue(color)) / 255f
            return CardTint(color, isDark = luma < 0.6f)
        }

        private fun averageColor(bitmap: Bitmap): Int {
            // A bilinear scale straight to 1×1 samples only a few pixels, so average a 16×16 copy.
            val small = bitmap.scale(16, 16, filter = true)
            val pixels = IntArray(16 * 16).also { small.getPixels(it, 0, 16, 0, 0, 16, 16) }
            var red = 0L
            var green = 0L
            var blue = 0L
            // Premultiplied like iOS, so transparent favicon pixels count as black.
            for (pixel in pixels) {
                val alpha = Color.alpha(pixel)
                red += Color.red(pixel) * alpha / 255
                green += Color.green(pixel) * alpha / 255
                blue += Color.blue(pixel) * alpha / 255
            }
            return Color.rgb((red / pixels.size).toInt(), (green / pixels.size).toInt(), (blue / pixels.size).toInt())
        }
    }
}
