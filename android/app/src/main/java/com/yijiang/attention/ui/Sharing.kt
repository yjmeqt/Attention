package com.yijiang.attention.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.core.content.FileProvider
import androidx.core.content.getSystemService
import com.yijiang.attention.R
import com.yijiang.attention.model.BRAND_NAME
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

object Sharing {
    fun copyLink(context: Context, url: String) {
        context.getSystemService<ClipboardManager>()?.setPrimaryClip(ClipData.newPlainText(BRAND_NAME, url))
    }

    fun copyText(context: Context, text: String) {
        context.getSystemService<ClipboardManager>()?.setPrimaryClip(ClipData.newPlainText(BRAND_NAME, text))
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
