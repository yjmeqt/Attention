package com.yijiang.attention.data

import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.CardTemplate
import com.yijiang.attention.model.LinkMeta
import kotlinx.serialization.Serializable
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import com.yijiang.attention.model.Links
import java.util.UUID

/** A saved link or image. Its images live in files next to the library index; see [Library]. */
@Serializable
data class LibraryItem(
    val id: String = UUID.randomUUID().toString(),
    /** Cleaned URL for links, `image:<sha256>` for images. */
    val key: String,
    val url: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = createdAt,
    val site: String = "",
    val title: String = "",
    val authorName: String? = null,
    val authorHandle: String? = null,
    val ocrText: String? = null,
    val template: String = CardTemplate.AUTO.name,
    val tags: List<String> = emptyList(),
    val isPrivate: Boolean = false,
    /** Hidden from the feed but kept, unlike deleted items. */
    val isArchived: Boolean = false,
    /** For links shared as an image: show that image instead of the link's preview image. */
    val usesSharedImage: Boolean = false,
    /** Width ÷ height of the thumbnail, so the feed can lay out tiles before loading them; 0 when there's none. */
    val thumbnailAspect: Float = 0f,
) {
    val httpUrl: HttpUrl? get() = url?.toHttpUrlOrNull()
    val isImage: Boolean get() = url == null

    val style: CardStyle get() = CardStyle(CardTemplate.named(template))

    /** The automatic tag: the normalized domain, or [DomainTag.IMAGES] for image items. */
    val domain: String get() = httpUrl?.let(DomainTag::domain) ?: DomainTag.IMAGES

    /** The site's own name when known, else its domain. Image items have neither; the UI labels those. */
    val platformName: String get() = site.ifEmpty { domain }

    /** Null for image items without recognized text, which the UI titles with their date. */
    val displayTitle: String?
        get() = when {
            title.isNotEmpty() -> title
            url != null -> LinkMeta(url = url, site = site, title = "").displayUrl
            else -> null
        }

    fun matches(search: String): Boolean {
        val query = search.trim()
        if (query.isEmpty()) return true
        return listOf(title, url.orEmpty(), ocrText.orEmpty(), site).any { it.contains(query, ignoreCase = true) }
    }
}

object DomainTag {
    const val IMAGES = "Images"

    private val aliases = mapOf(
        "youtu.be" to "youtube.com",
        "b23.tv" to "bilibili.com",
        "xhslink.com" to "xiaohongshu.com",
        "twitter.com" to "x.com",
    )

    fun domain(url: HttpUrl): String {
        var host = url.host.lowercase()
        for (prefix in listOf("www.", "m.", "mobile.")) {
            if (host.startsWith(prefix)) host = host.removePrefix(prefix)
        }
        return aliases[host] ?: host
    }

    fun key(url: HttpUrl): String = Links.cleanedForSharing(url).toString()
}

object LibraryRules {
    const val MAX_ITEMS = 5000

    fun normalizedTag(tag: String): String = tag.trim().trimStart('#')

    /** Most common first, ties alphabetical. */
    fun ranked(values: List<String>): List<String> =
        values.groupingBy { it }.eachCount().entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key }

    /** Over the cap, the oldest archived items go first, then the oldest others. Private items are never removed. */
    fun overCap(newestFirst: List<LibraryItem>, max: Int = MAX_ITEMS): List<LibraryItem> {
        val excess = newestFirst.size - max
        if (excess <= 0) return emptyList()
        val oldest = newestFirst.asReversed().filter { !it.isPrivate }
        return (oldest.filter { it.isArchived } + oldest.filter { !it.isArchived }).take(excess)
    }

    /** Tiles crop their photo to this width ÷ height range, like Messages link previews. */
    val tileAspects = 0.6f..1.9f
}
