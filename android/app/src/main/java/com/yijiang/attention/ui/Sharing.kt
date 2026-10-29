package com.yijiang.attention.ui

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.view.textclassifier.TextClassifier
import androidx.core.content.FileProvider
import androidx.core.content.getSystemService
import com.yijiang.attention.R
import com.yijiang.attention.model.BRAND_NAME
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Spots a link copied in another app without reading the clipboard, so Android's "pasted" notice
 * doesn't appear. Only works while the window has focus; Android hides the clipboard otherwise.
 */
object Clipboard {
    private const val IGNORED_KEY = "ignoredClipTimestamp"

    private fun prefs(context: Context) = context.getSharedPreferences("clipboard", Context.MODE_PRIVATE)

    /** Marks the current clipboard contents as already handled so they aren't offered again. */
    fun ignoreCurrent(context: Context) {
        val description = context.getSystemService<ClipboardManager>()?.primaryClipDescription ?: return
        prefs(context).edit().putLong(IGNORED_KEY, description.timestamp).apply()
    }

    fun hasNewLink(context: Context): Boolean {
        val description = context.getSystemService<ClipboardManager>()?.primaryClipDescription ?: return false
        if (description.timestamp == prefs(context).getLong(IGNORED_KEY, -1)) return false
        if (description.hasMimeType(ClipDescription.MIMETYPE_TEXT_URILIST)) return true
        // The system classifies copied text in the background; until it's done there's no score to ask for.
        if (description.classificationStatus != ClipDescription.CLASSIFICATION_COMPLETE) return false
        return description.getConfidenceScore(TextClassifier.TYPE_URL) >= 0.5f
    }
}

object Sharing {
    fun copyLink(context: Context, url: String) = copyText(context, url)

    fun copyText(context: Context, text: String) {
        context.getSystemService<ClipboardManager>()?.setPrimaryClip(ClipData.newPlainText(BRAND_NAME, text))
        Clipboard.ignoreCurrent(context)
    }

    fun clipboardText(context: Context): String? =
        context.getSystemService<ClipboardManager>()?.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.coerceToText(context)?.toString()

    /** An image on the clipboard, e.g. a screenshot copied from the gallery. */
    fun clipboardImage(context: Context): android.net.Uri? {
        val clip = context.getSystemService<ClipboardManager>()?.primaryClip ?: return null
        if (clip.itemCount == 0 || !clip.description.hasMimeType("image/*")) return null
        return clip.getItemAt(0).uri
    }

    fun shareLink(context: Context, url: String, title: String?) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
            title?.let { putExtra(Intent.EXTRA_TITLE, it) }
        }
        context.startActivity(Intent.createChooser(send, context.getString(R.string.share_link)))
    }

    suspend fun shareCard(context: Context, card: Bitmap, title: String?) {
        val file = withContext(Dispatchers.IO) {
            val directory = File(context.cacheDir, "cards").apply { mkdirs() }
            directory.listFiles()?.forEach { it.delete() }
            // A fresh name per share keeps receiving apps from showing a cached older card.
            File(directory, "card-${System.currentTimeMillis()}.png").apply {
                outputStream().use { card.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(title, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, context.getString(R.string.share_title)))
    }
}
