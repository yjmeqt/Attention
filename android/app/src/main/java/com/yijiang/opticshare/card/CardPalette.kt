package com.yijiang.opticshare.card

import android.graphics.Color
import androidx.core.graphics.ColorUtils
import com.yijiang.opticshare.model.CardAspect
import com.yijiang.opticshare.model.LinkKind

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

class CardMetrics(val aspect: CardAspect) {
    val width = aspect.width.toFloat()
    val height = aspect.height.toFloat()
    val padding = 18f

    /** Banner height that shows the whole image when possible, within limits that keep room for the text. */
    fun heroImageHeight(ratio: Float?): Float {
        val range = when (aspect) {
            CardAspect.PORTRAIT -> 150f..250f
            CardAspect.SQUARE -> 110f..140f
            CardAspect.STORY -> 200f..400f
        }
        val middle = (range.start + range.endInclusive) / 2
        if (ratio == null || ratio <= 0) return middle
        val natural = width / ratio
        // Too tall to show whole; the hero letterboxes it, so a medium banner leaves more room for the title.
        if (natural > range.endInclusive) return middle
        return maxOf(natural, range.start)
    }

    fun heroTitleLines(imageHeight: Float, hasByline: Boolean): Int {
        val body = height - imageHeight - padding * 2
        val footer = footerQrSize + 33
        val byline = if (hasByline) 24 else 0
        return ((body - footer - byline - 14) / 28).toInt().coerceIn(1, 8)
    }

    fun postMediaHeight(ratio: Float?): Float {
        val maxHeight = when (aspect) {
            CardAspect.PORTRAIT -> 150f
            CardAspect.SQUARE -> 0f
            CardAspect.STORY -> 260f
        }
        if (maxHeight <= 0 || ratio == null || ratio <= 0) return 0f
        return ((width - padding * 2) / ratio).coerceIn(100f, maxHeight)
    }

    fun postLines(withMedia: Boolean): Int = when (aspect) {
        CardAspect.PORTRAIT -> if (withMedia) 3 else 8
        CardAspect.SQUARE -> 5
        CardAspect.STORY -> if (withMedia) 7 else 15
    }

    val minimalLines: Int
        get() = when (aspect) {
            CardAspect.PORTRAIT -> 6
            CardAspect.SQUARE -> 3
            CardAspect.STORY -> 10
        }

    val footerQrSize: Float
        get() = when (aspect) {
            CardAspect.PORTRAIT -> 80f
            CardAspect.SQUARE -> 72f
            CardAspect.STORY -> 112f
        }

    val bigQrSize: Float
        get() = when (aspect) {
            CardAspect.PORTRAIT -> 180f
            CardAspect.SQUARE -> 130f
            CardAspect.STORY -> 220f
        }
}
