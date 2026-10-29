package com.yijiang.attention.unfurl

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.core.graphics.scale
import com.yijiang.attention.model.LinkKind
import com.yijiang.attention.model.LinkMeta
import com.yijiang.attention.model.Links
import com.yijiang.attention.model.PixelSize
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.Charset
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.roundToInt

object Unfurler {
    data class Result(val meta: LinkMeta, val isFallback: Boolean)

    private const val TAG = "Unfurler"

    private class Picture(val data: ByteArray, val size: PixelSize)

    private const val BROWSER_AGENT =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    /** For pages that send the iPhone agent on to an app scheme, such as the App Store's itms-appss://. */
    private const val DESKTOP_AGENT =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private const val MAX_PAGE_BYTES = 512L * 1024

    private val blockedTitles = listOf(
        "安全验证", "验证码", "Sina Visitor System", "出错啦", "Just a moment", "Access Denied", "Attention Required",
    )
    private val blockedHosts = listOf("sec.", "passport.", "captcha", "verify", "login.")

    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    /** Google's favicon service is unreachable in mainland China, so it gets a short timeout. */
    private val quickClient = client.newBuilder().callTimeout(3, TimeUnit.SECONDS).build()

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun unfurlWithFallback(url: HttpUrl): Result = withContext(Dispatchers.IO) {
        val originIcon = async { runCatching { favicon(url) }.getOrNull() }
        val googleIcon = async { runCatching { googleFavicon(url) }.getOrNull() }
        val result = unfurl(url)
        var icon = result.meta.icon?.let { data -> result.meta.iconSize?.let { Picture(data, it) } }
        if (icon == null) icon = originIcon.await() else originIcon.cancel()
        if ((icon?.size?.width ?: 0) < 64) {
            val better = googleIcon.await()
            if (better != null && better.size.width > (icon?.size?.width ?: 0)) icon = better
        } else {
            googleIcon.cancel()
        }
        result.copy(meta = result.meta.copy(icon = icon?.data, iconSize = icon?.size))
    }

    private suspend fun unfurl(url: HttpUrl): Result {
        val special = runCatching {
            when (LinkKind.of(url)) {
                LinkKind.YOUTUBE -> youtube(url)
                LinkKind.BILIBILI -> bilibili(url)
                LinkKind.X -> twitter(url)
                LinkKind.WEB -> null
            }
        }.onFailure { Log.w(TAG, "API unfurl failed for $url", it) }.getOrNull()
        if (special != null) return Result(special, isFallback = false)
        runCatching { html(url) }
            .onFailure { Log.w(TAG, "HTML unfurl failed for $url", it) }
            .getOrNull()?.let { return Result(it, isFallback = false) }
        return Result(LinkMeta(url = url.toString(), site = siteName(url), title = ""), isFallback = true)
    }

    fun siteName(url: HttpUrl): String = when (LinkKind.of(url)) {
        LinkKind.YOUTUBE -> "YouTube"
        LinkKind.BILIBILI -> "哔哩哔哩"
        LinkKind.X -> "X"
        LinkKind.WEB -> url.host.lowercase().removePrefix("www.")
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onResponse(call: Call, response: Response) = continuation.resume(response)
            override fun onFailure(call: Call, e: IOException) = continuation.resumeWithException(e)
        })
    }

    private suspend fun fetch(url: HttpUrl, httpClient: OkHttpClient = client): ByteArray =
        httpClient.newCall(Request.Builder().url(url).build()).await().use { response ->
            if (response.code != 200) throw IOException("HTTP ${response.code}")
            response.body?.bytes() ?: throw IOException("Empty body")
        }

    private suspend fun fetchJson(url: HttpUrl): JsonObject =
        json.parseToJsonElement(fetch(url).decodeToString()) as? JsonObject ?: throw IOException("Not an object")

    private fun bounds(data: ByteArray): PixelSize? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, options)
        return if (options.outWidth > 0 && options.outHeight > 0) PixelSize(options.outWidth, options.outHeight) else null
    }

    private suspend fun image(string: String?): Picture? {
        val url = string?.toHttpUrlOrNull() ?: return null
        val data = runCatching { fetch(url) }.getOrNull() ?: return null
        val size = bounds(data)?.takeIf { it.width >= 48 && it.height >= 48 } ?: return null
        return Picture(data, size)
    }

    /** Downloads an icon and keeps it at most 192 px, preserving transparency. */
    private suspend fun icon(string: String?, httpClient: OkHttpClient = client, minWidth: Int = 16): Picture? {
        val url = string?.toHttpUrlOrNull() ?: return null
        val data = runCatching { fetch(url, httpClient) }.getOrNull() ?: return null
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return null
        if (bitmap.width < minWidth) return null
        val scaled = if (bitmap.width > 192) bitmap.scale(192, (192f * bitmap.height / bitmap.width).roundToInt()) else bitmap
        val png = ByteArrayOutputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
        return Picture(png, PixelSize(scaled.width, scaled.height))
    }

    private fun thumbnail(picture: Picture?, side: Int): ByteArray? {
        val data = picture?.data ?: return null
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return null
        val factor = side.toFloat() / maxOf(bitmap.width, bitmap.height)
        val scaled = if (factor < 1) {
            bitmap.scale((bitmap.width * factor).roundToInt(), (bitmap.height * factor).roundToInt())
        } else {
            bitmap
        }
        return ByteArrayOutputStream().use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }

    private fun iconHost(url: HttpUrl): String = when (LinkKind.of(url)) {
        LinkKind.YOUTUBE -> "www.youtube.com"
        LinkKind.BILIBILI -> "www.bilibili.com"
        LinkKind.X -> "x.com"
        LinkKind.WEB -> url.host
    }

    /** The site's touch icon or favicon at well-known paths. */
    private suspend fun favicon(url: HttpUrl): Picture? {
        val origin = "https://" + iconHost(url)
        return icon("$origin/apple-touch-icon.png") ?: icon("$origin/favicon.ico")
    }

    /** Google's favicon service has 128 px icons for many sites that only ship a 16–32 px favicon. */
    private suspend fun googleFavicon(url: HttpUrl): Picture? =
        icon("https://www.google.com/s2/favicons?domain=${iconHost(url)}&sz=128", quickClient, minWidth = 32)

    private val JsonElement?.string: String? get() = (this as? JsonPrimitive)?.contentOrNull
    private operator fun JsonElement?.get(key: String): JsonElement? = (this as? JsonObject)?.get(key)
    private operator fun JsonElement?.get(index: Int): JsonElement? = (this as? JsonArray)?.getOrNull(index)

    private suspend fun youtube(url: HttpUrl): LinkMeta? = coroutineScope {
        val api = "https://www.youtube.com/oembed".toHttpUrl().newBuilder()
            .addQueryParameter("url", url.toString())
            .addQueryParameter("format", "json")
            .build()
        val j = fetchJson(api)
        val title = j["title"].string?.takeIf { it.isNotEmpty() } ?: return@coroutineScope null
        val thumb = j["thumbnail_url"].string
        val picture = image(thumb?.replace("hqdefault", "maxresdefault")) ?: image(thumb)
        LinkMeta(
            url = url.toString(), site = "YouTube", title = title,
            authorName = j["author_name"].string,
            image = picture?.data, imageSize = picture?.size,
        )
    }

    private suspend fun twitter(url: HttpUrl): LinkMeta? = coroutineScope {
        val tweet = fetchJson("https://api.fxtwitter.com${url.encodedPath}".toHttpUrl())["tweet"] as? JsonObject
            ?: return@coroutineScope null
        val author = tweet["author"]
        val media = tweet["media"]
        val photo = media["photos"][0]["url"].string
        val video = media["videos"][0]["thumbnail_url"].string
        val name = author["name"].string
        val handle = author["screen_name"].string
        val avatarUrl = author["avatar_url"].string?.replace("_normal.", "_400x400.")
        val text = tweet["text"].string.orEmpty()
        val mediaPicture = async { image(photo ?: video) }
        val avatarPicture = async { image(avatarUrl) }
        val picture = mediaPicture.await()
        LinkMeta(
            url = url.toString(), site = "X",
            title = text.ifEmpty { "Post by ${name ?: handle ?: "X"}" },
            authorName = name, authorHandle = handle,
            image = picture?.data, imageSize = picture?.size,
            avatar = thumbnail(avatarPicture.await(), 144),
        )
    }

    private suspend fun bilibili(url: HttpUrl): LinkMeta? = coroutineScope {
        val resolved = if (url.host == "b23.tv") {
            client.newCall(Request.Builder().url(url).head().build()).await().use { it.request.url }
        } else {
            url
        }
        val id = resolved.pathSegments.firstOrNull { it.startsWith("BV") || it.lowercase().startsWith("av") }
            ?: return@coroutineScope null
        val query = if (id.startsWith("BV")) "bvid=$id" else "aid=${id.drop(2)}"
        val j = fetchJson("https://api.bilibili.com/x/web-interface/view?$query".toHttpUrl())
        if ((j["code"] as? JsonPrimitive)?.intOrNull != 0) return@coroutineScope null
        val data = j["data"]
        val title = data["title"].string?.takeIf { it.isNotEmpty() } ?: return@coroutineScope null
        val owner = data["owner"]
        val cover = async { image(data["pic"].string?.replace("http://", "https://")) }
        val face = async { image(owner["face"].string?.replace("http://", "https://")) }
        val picture = cover.await()
        LinkMeta(
            url = resolved.toString(), site = "哔哩哔哩", title = title,
            authorName = owner["name"].string,
            image = picture?.data, imageSize = picture?.size,
            avatar = thumbnail(face.await(), 144),
        )
    }

    private val metaCharset = Regex("""charset\s*=\s*["']?([\w-]+)""", RegexOption.IGNORE_CASE)

    /** Reads og:/twitter: tags directly from the page. Only page fetches look like Safari; Bilibili's API rejects that UA. */
    private suspend fun html(url: HttpUrl, agent: String = BROWSER_AGENT): LinkMeta? = coroutineScope {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", agent)
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .build()
        val response = client.newCall(request).await()
        // OkHttp follows http redirects itself, so one that comes back here points at an app scheme.
        if (response.isRedirect && agent != DESKTOP_AGENT) {
            response.close()
            return@coroutineScope html(url, DESKTOP_AGENT)
        }
        val (finalUrl, page) = response.use { response ->
            val body = response.body
            if (response.code != 200 || body == null) throw IOException("HTTP ${response.code}")
            val type = body.contentType()
            if (type != null && !type.subtype.contains("html")) throw IOException("Not HTML: $type")
            val source = body.source()
            source.request(MAX_PAGE_BYTES)
            val bytes = source.buffer.let { it.readByteArray(minOf(it.size, MAX_PAGE_BYTES)) }
            val charset = type?.charset() ?: sniffCharset(bytes) ?: Charsets.UTF_8
            response.request.url to String(bytes, charset)
        }
        val finalHost = finalUrl.host.lowercase()
        if (blockedHosts.any { it in finalHost }) return@coroutineScope null

        val tags = OpenGraph.tags(page)
        val title = (tags["og:title"] ?: tags["twitter:title"] ?: OpenGraph.title(page))?.trim()
        if (title.isNullOrEmpty() || blockedTitles.any { it in title }) return@coroutineScope null
        val imageUrl = (tags["og:image:secure_url"] ?: tags["og:image"] ?: tags["twitter:image"] ?: tags["twitter:image:src"])
            ?.let { finalUrl.resolve(it)?.toString() }
        val site = tags["og:site_name"]?.takeIf { it.length <= 12 } ?: siteName(url)
        val iconUrl = OpenGraph.icon(page)?.let { finalUrl.resolve(it)?.toString() }
        val picture = async { image(imageUrl) }
        val iconPicture = async { icon(iconUrl) }
        val pic = picture.await()
        val ico = iconPicture.await()
        LinkMeta(
            url = url.toString(), site = site, title = title,
            image = pic?.data, imageSize = pic?.size,
            icon = ico?.data, iconSize = ico?.size,
        )
    }

    private fun sniffCharset(bytes: ByteArray): Charset? {
        val head = String(bytes, 0, minOf(bytes.size, 4096), Charsets.ISO_8859_1)
        val name = metaCharset.find(head)?.groupValues?.get(1) ?: return null
        return runCatching { Charset.forName(name) }.getOrNull()
    }
}
