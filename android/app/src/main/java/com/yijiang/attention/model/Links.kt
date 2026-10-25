package com.yijiang.attention.model

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

object Links {
    private const val URL_CHARS = """[^\s<>"'，。、；：！？（）【】《》「」“”‘’]"""
    private val schemed = Regex("""https?://$URL_CHARS+""", RegexOption.IGNORE_CASE)
    private val bare = Regex(
        """(?<![@\w.-])(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:/$URL_CHARS*)?""",
        RegexOption.IGNORE_CASE,
    )
    private const val TRAILING_PUNCTUATION = ".,;:!?'\"…]}"

    private val trackingParameters = setOf(
        "fbclid", "gclid", "igsh", "igshid", "si", "ref_src", "ref_url",
        "spm_id_from", "from_spmid", "vd_source", "unique_k",
        "share_source", "share_medium", "share_plat", "share_session_id", "share_tag", "share_times",
    )

    /** The first web link in free-form text, such as a share blurb copied from another app. */
    fun extract(text: String): HttpUrl? {
        val match = schemed.find(text)?.value ?: bare.find(text)?.value?.let { "https://$it" } ?: return null
        return trimTrailing(match).toHttpUrlOrNull()
    }

    private fun trimTrailing(candidate: String): String {
        var result = candidate
        while (result.isNotEmpty()) {
            val last = result.last()
            result = when {
                last in TRAILING_PUNCTUATION -> result.dropLast(1)
                last == ')' && result.count { it == '(' } < result.count { it == ')' } -> result.dropLast(1)
                else -> return result
            }
        }
        return result
    }

    fun youTubeId(url: HttpUrl): String? {
        val segments = url.pathSegments.filter { it.isNotEmpty() }
        if (url.host.lowercase() == "youtu.be") return segments.firstOrNull()
        if (segments.size > 1 && segments[0] in setOf("shorts", "live", "embed")) return segments[1]
        return url.queryParameter("v")?.takeIf { it.isNotEmpty() }
    }

    /** The link without tracking parameters; used for the QR code and the clipboard. */
    fun cleanedForSharing(url: HttpUrl): HttpUrl = when (LinkKind.of(url)) {
        LinkKind.YOUTUBE -> youTubeId(url)?.let { "https://youtu.be/$it".toHttpUrlOrNull() } ?: url
        LinkKind.X -> url.newBuilder().query(null).fragment(null).build()
        LinkKind.BILIBILI, LinkKind.WEB -> {
            val kept = url.encodedQuery?.split('&')?.filter { pair ->
                val name = pair.substringBefore('=').lowercase()
                pair.isNotEmpty() && !name.startsWith("utm_") && name !in trackingParameters
            }
            url.newBuilder().encodedQuery(kept?.takeIf { it.isNotEmpty() }?.joinToString("&")).build()
        }
    }

    fun cleanedForSharing(url: String): String = cleanedForSharing(url.toHttpUrl()).toString()
}
