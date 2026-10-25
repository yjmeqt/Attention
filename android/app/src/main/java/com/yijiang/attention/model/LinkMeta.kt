package com.yijiang.attention.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl

const val BRAND_NAME = "Attention"

enum class LinkKind {
    YOUTUBE, BILIBILI, X, WEB;

    val isVideo: Boolean get() = this == YOUTUBE || this == BILIBILI

    companion object {
        fun of(url: HttpUrl): LinkKind {
            val host = url.host.lowercase()
            fun matches(domain: String) = host == domain || host.endsWith(".$domain")
            return when {
                matches("youtube.com") || host == "youtu.be" -> YOUTUBE
                matches("bilibili.com") || host == "b23.tv" -> BILIBILI
                matches("x.com") || matches("twitter.com") -> X
                else -> WEB
            }
        }
    }
}

@Serializable
data class PixelSize(val width: Int, val height: Int)

/** Image bytes are kept out of the serialized form; [com.yijiang.attention.data.HistoryStore] stores them as files. */
@Serializable
data class LinkMeta(
    val url: String,
    val site: String,
    /** Empty when no preview could be fetched. */
    val title: String,
    val authorName: String? = null,
    val authorHandle: String? = null,
    val imageSize: PixelSize? = null,
    val iconSize: PixelSize? = null,
    @Transient val image: ByteArray? = null,
    @Transient val avatar: ByteArray? = null,
    @Transient val icon: ByteArray? = null,
) {
    val httpUrl: HttpUrl get() = url.toHttpUrl()
    val kind: LinkKind get() = LinkKind.of(httpUrl)
    val hasPreview: Boolean get() = title.isNotEmpty()

    /** A favicon big enough to show at 64 dp on a 3x card without looking blurry. */
    val hasLargeIcon: Boolean get() = icon != null && (iconSize?.width ?: 0) >= 120

    val byline: String?
        get() = when {
            authorName != null && authorHandle != null -> "$authorName @$authorHandle"
            authorName != null -> authorName
            authorHandle != null -> "@$authorHandle"
            else -> null
        }

    /** Width ÷ height of the source og:image. */
    val imageAspectRatio: Float?
        get() = imageSize?.takeIf { it.height > 0 }?.let { it.width.toFloat() / it.height }

    /** Small or squarish images are usually site logos and look blurry or badly cropped as a banner. */
    val imageIsIcon: Boolean
        get() {
            val size = imageSize ?: return false
            val ratio = imageAspectRatio ?: return false
            return size.width < 400 || (ratio < 1.25f && size.width < 640)
        }

    val shareUrl: HttpUrl get() = Links.cleanedForSharing(httpUrl)

    /** Host and path, for display on the card. */
    val displayUrl: String
        get() {
            val url = shareUrl
            val host = url.host.removePrefix("www.")
            val path = url.pathSegments.joinToString("/")
            return if (path.isEmpty()) host else "$host/$path"
        }
}
