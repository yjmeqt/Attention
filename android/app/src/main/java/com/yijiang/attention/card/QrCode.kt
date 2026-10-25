package com.yijiang.attention.card

import android.graphics.Bitmap
import android.graphics.Color
import android.util.LruCache
import androidx.core.graphics.createBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

object QrCode {
    private val cache = LruCache<String, Bitmap>(8)

    /** One pixel per module; draw it scaled with filtering off. Use [highCorrection] when a logo covers the center. */
    fun bitmap(text: String, highCorrection: Boolean = false): Bitmap {
        val key = "$highCorrection$text"
        cache.get(key)?.let { return it }
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to if (highCorrection) ErrorCorrectionLevel.H else ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 1,
            EncodeHintType.CHARACTER_SET to "UTF-8",
        )
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, hints)
        val pixels = IntArray(matrix.width * matrix.height) { i ->
            if (matrix[i % matrix.width, i / matrix.width]) Color.BLACK else Color.WHITE
        }
        val bitmap = createBitmap(matrix.width, matrix.height).apply {
            setPixels(pixels, 0, matrix.width, 0, 0, matrix.width, matrix.height)
        }
        cache.put(key, bitmap)
        return bitmap
    }
}
