package com.yijiang.attention.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import com.yijiang.attention.R
import com.yijiang.attention.card.CardRenderer
import com.yijiang.attention.card.CardTint
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.LinkMeta
import com.yijiang.attention.model.PixelSize
import com.yijiang.attention.unfurl.Unfurler
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Every saved link and image: a JSON index plus a folder of image files per item.
 * Methods do file work, so call them off the main thread.
 */
class Library(context: Context, private val directory: File = File(context.filesDir, "library")) {
    private val appContext = context.applicationContext
    private val index = File(directory, "index.json")
    private val json = Json { ignoreUnknownKeys = true }

    private val _items = MutableStateFlow<List<LibraryItem>>(emptyList())
    /** Newest first. */
    val items: StateFlow<List<LibraryItem>> = _items.asStateFlow()

    private val _revision = MutableStateFlow(0)
    /** Bumped whenever an item's files change, so views showing thumbnails refresh. */
    val revision: StateFlow<Int> = _revision.asStateFlow()

    private val _enriching = MutableStateFlow<Set<String>>(emptySet())
    /** Items whose preview is still being fetched. */
    val enriching: StateFlow<Set<String>> = _enriching.asStateFlow()

    private val thumbnails = LruCache<String, Bitmap>(64)
    private val favicons = LruCache<String, Bitmap>(256)
    private val tints = LruCache<String, CardTint>(256)
    /** Items whose tile was regenerated this session, so ones without a photo aren't retried every render. */
    private val checked = mutableSetOf<String>()
    private val retriedPreviews = mutableSetOf<String>()

    init {
        directory.mkdirs()
        _items.value = runCatching { json.decodeFromString<List<LibraryItem>>(index.readText()) }
            .getOrDefault(emptyList())
            .sortedByDescending { it.updatedAt }
    }

    fun item(id: String): LibraryItem? = _items.value.firstOrNull { it.id == id }

    fun itemWithKey(key: String): LibraryItem? = _items.value.firstOrNull { it.key == key }

    /** Returns the existing item for [key], moved to the top, or inserts a new one. */
    @Synchronized
    fun upsert(key: String, url: HttpUrl?, site: String, style: CardStyle): LibraryItem {
        itemWithKey(key)?.let { existing ->
            return update(existing.id) { it.copy(updatedAt = System.currentTimeMillis()) }!!
        }
        val item = LibraryItem(key = key, url = url?.toString(), site = site, template = style.template.name)
        save(listOf(item) + _items.value)
        enforceCap()
        return item
    }

    @Synchronized
    fun update(id: String, transform: (LibraryItem) -> LibraryItem): LibraryItem? {
        var updated: LibraryItem? = null
        save(_items.value.map { if (it.id == id) transform(it).also { new -> updated = new } else it })
        return updated
    }

    @Synchronized
    private fun updateAll(ids: Collection<String>, transform: (LibraryItem) -> LibraryItem) {
        val targets = ids.toSet()
        save(_items.value.map { if (it.id in targets) transform(it) else it })
    }

    @Synchronized
    fun delete(ids: Collection<String>) {
        val doomed = ids.toSet()
        for (id in doomed) {
            folder(id).deleteRecursively()
            thumbnails.remove(id)
            favicons.remove(id)
            tints.remove(id)
        }
        save(_items.value.filterNot { it.id in doomed })
    }

    fun addTag(tag: String, ids: Collection<String>) {
        val normalized = LibraryRules.normalizedTag(tag)
        if (normalized.isEmpty()) return
        updateAll(ids) { if (normalized in it.tags) it else it.copy(tags = it.tags + normalized) }
    }

    fun removeTag(tag: String, ids: Collection<String>) = updateAll(ids) { it.copy(tags = it.tags - tag) }

    fun setPrivate(isPrivate: Boolean, ids: Collection<String>) = updateAll(ids) { it.copy(isPrivate = isPrivate) }

    fun setArchived(isArchived: Boolean, ids: Collection<String>) = updateAll(ids) { it.copy(isArchived = isArchived) }

    fun setStyle(style: CardStyle, id: String) = update(id) { it.copy(template = style.template.name) }

    /** Manual tags across the library, most used first. */
    val allTags: List<String> get() = LibraryRules.ranked(_items.value.flatMap { it.tags })

    private fun enforceCap() {
        val excess = LibraryRules.overCap(_items.value)
        if (excess.isNotEmpty()) delete(excess.map { it.id })
    }

    private fun save(items: List<LibraryItem>) {
        val sorted = items.sortedByDescending { it.updatedAt }
        _items.value = sorted
        val temp = File(directory, "index.json.tmp")
        temp.writeText(json.encodeToString(sorted))
        temp.renameTo(index)
    }

    // region Files

    enum class Kind(val fileName: String) { COVER("cover"), AVATAR("avatar"), ICON("icon"), SOURCE("source"), THUMBNAIL("tile") }

    private fun folder(id: String) = File(directory, id)

    fun data(kind: Kind, item: LibraryItem): ByteArray? =
        File(folder(item.id), kind.fileName).takeIf { it.exists() }?.readBytes()

    fun write(data: ByteArray?, kind: Kind, item: LibraryItem) {
        val file = File(folder(item.id), kind.fileName)
        if (data == null) {
            file.delete()
            return
        }
        folder(item.id).mkdirs()
        val temp = File(folder(item.id), "${kind.fileName}.tmp")
        temp.writeBytes(data)
        temp.renameTo(file)
    }

    // endregion

    // region Metadata

    /** The link's metadata with its images, or null for image items. */
    fun meta(item: LibraryItem): LinkMeta? {
        val url = item.url ?: return null
        val cover = coverData(item)
        return LinkMeta(
            url = url, site = item.site, title = item.title,
            authorName = item.authorName, authorHandle = item.authorHandle,
            imageSize = cover?.let(::pixelSize),
            iconSize = data(Kind.ICON, item)?.let(::pixelSize),
            image = cover, avatar = data(Kind.AVATAR, item), icon = data(Kind.ICON, item),
        )
    }

    /** The image a link's card and tile show: its preview image, or the image it was shared as. */
    fun coverData(item: LibraryItem): ByteArray? {
        if (item.usesSharedImage) data(Kind.SOURCE, item)?.let { return it }
        return data(Kind.COVER, item)
    }

    /** Both a preview image and a different shared image, so there's a choice to make. */
    fun hasCoverChoice(item: LibraryItem): Boolean {
        if (item.isImage) return false
        val source = data(Kind.SOURCE, item) ?: return false
        val cover = data(Kind.COVER, item) ?: return false
        return !source.contentEquals(cover)
    }

    fun setUsesSharedImage(uses: Boolean, id: String) {
        val item = item(id)?.takeIf { it.usesSharedImage != uses } ?: return
        refreshThumbnail(update(item.id) { it.copy(usesSharedImage = uses) }!!)
    }

    fun setMeta(meta: LinkMeta, item: LibraryItem): LibraryItem {
        write(meta.image, Kind.COVER, item)
        write(meta.avatar, Kind.AVATAR, item)
        write(meta.icon, Kind.ICON, item)
        val updated = update(item.id) {
            it.copy(
                site = meta.site,
                title = if (meta.hasPreview || it.title.isEmpty()) meta.title else it.title,
                authorName = meta.authorName,
                authorHandle = meta.authorHandle,
                updatedAt = System.currentTimeMillis(),
            )
        } ?: return item
        return refreshThumbnail(updated)
    }

    // endregion

    // region Images

    /** The feed image: the link's preview image or the shared image. Null when there's none. */
    fun thumbnail(item: LibraryItem): Bitmap? {
        thumbnails.get(item.id)?.let { return it }
        if (data(Kind.THUMBNAIL, item) == null && checked.add(item.id)) refreshThumbnail(item)
        val bitmap = data(Kind.THUMBNAIL, item)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } ?: return null
        thumbnails.put(item.id, bitmap)
        return bitmap
    }

    /** The band color under a tile's photo, taken from the photo's bottom edge. */
    fun tint(item: LibraryItem): CardTint? {
        tints.get(item.id)?.let { return it }
        val tint = CardTint.fromImage(thumbnail(item) ?: return null)
        tints.put(item.id, tint)
        return tint
    }

    fun favicon(item: LibraryItem): Bitmap? {
        favicons.get(item.id)?.let { return it }
        val icon = data(Kind.ICON, item)?.let { downsample(it, 128) } ?: return null
        favicons.put(item.id, icon)
        return icon
    }

    /** The full-size card for links, the shared image for images. */
    fun fullImage(item: LibraryItem): Bitmap? {
        meta(item)?.let { return CardRenderer.render(it, item.style) }
        return data(Kind.SOURCE, item)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
    }

    fun refreshThumbnail(item: LibraryItem): LibraryItem {
        val source = if (item.isImage) data(Kind.SOURCE, item) else coverData(item)
        val image = source?.let { downsample(it, 720) }
            ?.takeIf { item.isImage || minOf(it.width, it.height) >= 200 }
        val aspect = image?.let {
            (it.width.toFloat() / it.height).coerceIn(LibraryRules.tileAspects.start, LibraryRules.tileAspects.endInclusive)
        } ?: 0f
        write(image?.let { jpeg(it, 80) }, Kind.THUMBNAIL, item)
        thumbnails.remove(item.id)
        favicons.remove(item.id)
        tints.remove(item.id)
        val updated = update(item.id) { it.copy(thumbnailAspect = aspect) } ?: item
        _revision.update { it + 1 }
        return updated
    }

    // endregion

    // region Intake

    /** Saves a capture right away, before its preview is fetched. */
    fun save(capture: Capture, style: CardStyle): LibraryItem = when (capture) {
        is Capture.Link -> {
            val url = upgradedToHttps(capture.url)
            var item = upsert(DomainTag.key(url), url, Unfurler.siteName(url), style)
            capture.image?.let { write(it, Kind.SOURCE, item) }
            if (data(Kind.THUMBNAIL, item) == null) item = refreshThumbnail(item)
            item
        }
        is Capture.Image -> {
            val item = upsert(Capture.imageKey(capture.data), null, "", style)
            write(capture.data, Kind.SOURCE, item)
            refreshThumbnail(item)
        }
    }

    /**
     * Fetches the link preview, updating the saved item.
     * Returns a string resource to show when only a basic card could be made.
     */
    suspend fun enrich(item: LibraryItem): Int? = coroutineScope {
        _enriching.update { it + item.id }
        try {
            val source = data(Kind.SOURCE, item)
            val text = async { source?.let { TextReader.read(it) } }
            val url = item.httpUrl
            if (url == null) {
                val read = text.await()
                update(item.id) { it.copy(title = read?.title.orEmpty(), ocrText = read?.fullText) }
                return@coroutineScope null
            }
            val result = Unfurler.unfurlWithFallback(url)
            val read = text.await()
            val current = update(item.id) { it.copy(ocrText = read?.fullText) } ?: return@coroutineScope null
            var meta = result.meta
            if ((meta.image == null || meta.imageIsIcon) && source != null) {
                meta = meta.copy(image = source, imageSize = pixelSize(source))
            }
            if (!meta.hasPreview) read?.title?.let { meta = meta.copy(title = it) }
            if (result.isFallback && current.title.isNotEmpty() && data(Kind.COVER, current) != null) return@coroutineScope null
            setMeta(meta, current)
            if (result.isFallback && !meta.hasPreview) R.string.notice_fallback else null
        } finally {
            _enriching.update { it - item.id }
        }
    }

    /**
     * Retries links saved without a preview, e.g. when the app was closed before the page loaded.
     * Each item is retried once per launch so pages that never preview don't refetch forever.
     */
    suspend fun retryMissingPreviews() {
        val stale = _items.value.filter {
            !it.isImage && it.title.isEmpty() && data(Kind.COVER, it) == null &&
                it.id !in _enriching.value && retriedPreviews.add(it.id)
        }
        for (item in stale.take(20)) {
            val url = item.httpUrl
            val secure = url?.let(::upgradedToHttps)
            val upgraded = if (secure != null && secure != url) {
                val key = DomainTag.key(secure)
                if (itemWithKey(key) == null) update(item.id) { it.copy(url = secure.toString(), key = key) } else null
            } else null
            enrich(upgraded ?: item)
        }
    }

    /** One-time import of the pre-library history (`history/index.json` plus image files per entry). */
    fun importHistory() {
        val history = File(appContext.filesDir, "history")
        val historyIndex = File(history, "index.json")
        if (!historyIndex.exists()) return
        val entries = runCatching { json.decodeFromString<List<HistoryEntry>>(historyIndex.readText()) }.getOrDefault(emptyList())
        fun read(entry: HistoryEntry, kind: String) = File(history, "${entry.id}.$kind").takeIf { it.exists() }?.readBytes()
        for (entry in entries.asReversed()) {
            val url = entry.meta.httpUrl
            val key = DomainTag.key(url)
            if (itemWithKey(key) != null) continue
            val meta = entry.meta.copy(image = read(entry, "image"), icon = read(entry, "icon"), avatar = read(entry, "avatar"))
            val item = upsert(key, url, meta.site, CardStyle())
            setMeta(meta, item)
            update(item.id) { it.copy(createdAt = entry.date, updatedAt = entry.date) }
        }
        historyIndex.renameTo(File(history, "index.imported.json"))
    }

    // endregion

    companion object {
        fun upgradedToHttps(url: HttpUrl): HttpUrl = if (url.scheme == "http") url.newBuilder().scheme("https").build() else url

        fun pixelSize(data: ByteArray): PixelSize? {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(data, 0, data.size, options)
            return if (options.outWidth > 0 && options.outHeight > 0) PixelSize(options.outWidth, options.outHeight) else null
        }

        /** Decodes at most [maxPixel] on the long side. */
        fun downsample(data: ByteArray, maxPixel: Int): Bitmap? {
            val size = pixelSize(data) ?: return null
            var sample = 1
            while (maxOf(size.width, size.height) / (sample * 2) >= maxPixel) sample *= 2
            val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return null
            val long = maxOf(decoded.width, decoded.height)
            if (long <= maxPixel) return decoded
            val factor = maxPixel.toFloat() / long
            return Bitmap.createScaledBitmap(decoded, (decoded.width * factor).toInt().coerceAtLeast(1),
                (decoded.height * factor).toInt().coerceAtLeast(1), true)
        }

        fun jpeg(bitmap: Bitmap, quality: Int = 85): ByteArray =
            ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
    }
}
