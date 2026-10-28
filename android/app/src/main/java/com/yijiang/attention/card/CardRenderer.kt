package com.yijiang.attention.card

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Picture
import androidx.core.graphics.createBitmap
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.CardTemplate
import com.yijiang.attention.model.LinkMeta
import kotlin.math.roundToInt

object CardRenderer {
    /** 360 dp × 3 = 1080 px wide, the same output size as the iOS app. */
    const val SHARE_SCALE = 3f

    /** Taller than any template gets; the card is cropped to the height the template returns. */
    private const val MAX_HEIGHT = 2000

    fun render(
        meta: LinkMeta,
        style: CardStyle,
        images: CardImages = CardImages.decode(meta),
        scale: Float = SHARE_SCALE,
    ): Bitmap {
        val palette = CardPalette(meta.kind)
        // Recorded first, because the height is only known once the template has laid itself out.
        val picture = Picture()
        val recording = picture.beginRecording(CardMetrics.WIDTH.roundToInt(), MAX_HEIGHT)
        recording.drawColor(palette.background)
        val drawer = CardDrawer(recording, meta, images, palette)
        val height = when (style.template.resolved(meta)) {
            CardTemplate.AUTO, CardTemplate.TILE -> drawer.drawTile()
            CardTemplate.MINIMAL -> drawer.drawMinimal()
            CardTemplate.QR -> drawer.drawQr()
        }
        picture.endRecording()

        val bitmap = createBitmap((CardMetrics.WIDTH * scale).roundToInt(), (height * scale).roundToInt())
        Canvas(bitmap).apply {
            scale(scale, scale)
            drawPicture(picture)
        }
        return bitmap
    }
}
