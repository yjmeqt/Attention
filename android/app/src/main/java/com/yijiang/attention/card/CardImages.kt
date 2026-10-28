package com.yijiang.attention.card

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.yijiang.attention.model.LinkMeta

/** Decoded once per link so restyling doesn't decode the cover again. */
class CardImages(val image: Bitmap?, val icon: Bitmap?) {
    companion object {
        private const val MAX_IMAGE_WIDTH = 1600

        fun decode(meta: LinkMeta): CardImages = CardImages(
            image = meta.image?.let { decode(it, MAX_IMAGE_WIDTH) },
            icon = meta.icon?.let { decode(it, 400) },
        )

        private fun decode(data: ByteArray, maxWidth: Int): Bitmap? {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxWidth) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            return BitmapFactory.decodeByteArray(data, 0, data.size, options)
        }
    }
}
