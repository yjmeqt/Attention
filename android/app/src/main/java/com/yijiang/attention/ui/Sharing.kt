package com.yijiang.attention.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Environment
import android.provider.MediaStore
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

    fun clipboardText(context: Context): String? =
        context.getSystemService<ClipboardManager>()?.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.coerceToText(context)?.toString()

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

    suspend fun saveToGallery(context: Context, card: Bitmap): Boolean = withContext(Dispatchers.IO) {
        val name = "$BRAND_NAME-${System.currentTimeMillis()}.png"
        runCatching {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$BRAND_NAME")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return@runCatching false
            resolver.openOutputStream(uri)?.use { card.compress(Bitmap.CompressFormat.PNG, 100, it) }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        }.getOrDefault(false)
    }
}
