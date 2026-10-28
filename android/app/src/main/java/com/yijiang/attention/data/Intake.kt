package com.yijiang.attention.data

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.yijiang.attention.model.Links
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import java.security.MessageDigest
import kotlin.coroutines.resume

/** Something shared into or pasted into Attention, before it's saved. */
sealed interface Capture {
    /** A link; [image] is the shared image it was read from, if any. */
    data class Link(val url: HttpUrl, val image: ByteArray? = null) : Capture
    class Image(val data: ByteArray) : Capture

    companion object {
        fun imageKey(data: ByteArray): String =
            "image:" + MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
    }
}

object Intake {
    /** Shared images are kept at most this big on the long side. */
    private const val MAX_IMAGE_PIXEL = 2048

    /** An image wins over text: a QR code in it gives the link, else the text's link, else it's saved as an image. */
    suspend fun capture(context: Context, text: String?, imageUri: Uri?): Capture? = withContext(Dispatchers.IO) {
        val link = text?.let(Links::extract)
        val data = imageUri?.let { runCatching { context.contentResolver.openInputStream(it)?.use { s -> s.readBytes() } }.getOrNull() }
        val bitmap = data?.let { Library.downsample(it, MAX_IMAGE_PIXEL) } ?: return@withContext link?.let { Capture.Link(it) }
        val normalized = Library.jpeg(bitmap)
        QrReader.firstWebLink(bitmap)?.let { return@withContext Capture.Link(it, normalized) }
        if (link != null) Capture.Link(link, normalized) else Capture.Image(normalized)
    }
}

object QrReader {
    private val hints = mapOf(
        DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
        DecodeHintType.TRY_HARDER to true,
    )

    fun payload(bitmap: Bitmap): String? {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return payload(RGBLuminanceSource(bitmap.width, bitmap.height, pixels))
    }

    fun payload(source: com.google.zxing.LuminanceSource): String? =
        runCatching { MultiFormatReader().decode(BinaryBitmap(HybridBinarizer(source)), hints).text }.getOrNull()

    fun firstWebLink(bitmap: Bitmap): HttpUrl? =
        payload(bitmap)?.let(Links::extract)?.takeIf { it.scheme.startsWith("http") }
}

object TextReader {
    data class Line(
        val text: String,
        /** Normalized line height; bigger type means a bigger value. */
        val height: Double,
        /** Normalized distance from the top of the image to the top of the line. */
        val top: Double,
    )

    data class Result(val title: String?, val fullText: String)

    private val recognizer by lazy { TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()) }

    /** On-device recognition with ML Kit's bundled Chinese and Latin model; no Play services needed. */
    suspend fun read(data: ByteArray): Result? {
        val bitmap = withContext(Dispatchers.IO) { Library.downsample(data, 2048) } ?: return null
        val text = suspendCancellableCoroutine<Text?> { continuation ->
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { continuation.resume(it) }
                .addOnFailureListener { continuation.resume(null) }
        } ?: return null
        val height = bitmap.height.toDouble()
        val lines = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
            val box = line.boundingBox ?: return@mapNotNull null
            Line(line.text, box.height() / height, box.top / height)
        }
        if (lines.isEmpty()) return null
        return Result(title(lines), lines.sortedBy { it.top }.joinToString("\n") { it.text })
    }

    private val boilerplate = listOf(
        "小红书", "扫码", "扫一扫", "长按", "二维码", "打开App", "打开app", "查看笔记", "查看更多",
        "xiaohongshu", "Scan", "QR code", "rednote", "REDnote",
    )

    /** The 1–2 lines with the biggest type in the top 60% of the image, skipping app boilerplate. */
    fun title(lines: List<Line>): String? {
        val candidates = lines.filter { line ->
            val text = line.text.trim()
            line.top < 0.6 && text.length >= 2 && !text.startsWith("@") && text.any { it.isLetter() } &&
                boilerplate.none { text.contains(it, ignoreCase = true) }
        }
        val tallest = candidates.maxOfOrNull { it.height } ?: return null
        val big = candidates.filter { it.height >= tallest * 0.8 }.sortedBy { it.top }
        val first = big.firstOrNull() ?: return null
        val picked = mutableListOf(first)
        if (big.size > 1 && big[1].top - (first.top + first.height) < first.height * 1.5) picked.add(big[1])
        val joinsTight = picked.any { line -> line.text.codePoints().anyMatch { Character.isIdeographic(it) } }
        return picked.joinToString(if (joinsTight) "" else " ") { it.text.trim() }.take(80)
    }
}
