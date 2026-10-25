package com.yijiang.attention.card

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.core.graphics.createBitmap
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.CardTemplate
import com.yijiang.attention.model.LinkMeta
import kotlin.math.roundToInt

object CardRenderer {
    /** 360 dp × 3 = 1080 px wide, the same output size as the iOS app. */
    const val SHARE_SCALE = 3f

    fun render(
        meta: LinkMeta,
        style: CardStyle,
        images: CardImages = CardImages.decode(meta),
        scale: Float = SHARE_SCALE,
    ): Bitmap {
        val metrics = CardMetrics(style.aspect)
        val palette = CardPalette(meta.kind)
        val bitmap = createBitmap((metrics.width * scale).roundToInt(), (metrics.height * scale).roundToInt())
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        canvas.drawColor(palette.background)
        val drawer = CardDrawer(canvas, meta, images, palette, metrics)
        when (style.template.resolved(meta)) {
            CardTemplate.AUTO, CardTemplate.HERO -> drawer.drawHero()
            CardTemplate.POST -> drawer.drawPost()
            CardTemplate.MINIMAL -> drawer.drawMinimal()
            CardTemplate.QR -> drawer.drawQr()
        }
        return bitmap
    }
}
