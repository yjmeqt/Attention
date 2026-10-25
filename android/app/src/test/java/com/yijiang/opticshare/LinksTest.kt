package com.yijiang.opticshare

import com.yijiang.opticshare.model.LinkKind
import com.yijiang.opticshare.model.LinkMeta
import com.yijiang.opticshare.model.Links
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LinksTest {
    @Test
    fun cleansShareUrls() {
        val cases = mapOf(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc&t=42" to "https://youtu.be/dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ?si=abc" to "https://youtu.be/dQw4w9WgXcQ",
            "https://youtube.com/shorts/abc123?feature=share" to "https://youtu.be/abc123",
            "https://x.com/jack/status/20?s=20&t=xyz" to "https://x.com/jack/status/20",
            "https://www.bilibili.com/video/BV1xx411c7mD?spm_id_from=333&vd_source=a&p=2" to
                "https://www.bilibili.com/video/BV1xx411c7mD?p=2",
            "https://example.com/a?utm_source=x&utm_medium=y" to "https://example.com/a",
            "https://www.xiaohongshu.com/explore/1?xsec_token=keep" to "https://www.xiaohongshu.com/explore/1?xsec_token=keep",
            "https://example.com/search?q=a%20b&fbclid=1" to "https://example.com/search?q=a%20b",
        )
        for ((input, expected) in cases) {
            assertEquals(input, expected, Links.cleanedForSharing(input))
        }
    }

    @Test
    fun extractsFirstLinkFromShareText() {
        val cases = mapOf(
            "看看这个 https://youtu.be/dQw4w9WgXcQ?si=x，很好笑" to "https://youtu.be/dQw4w9WgXcQ?si=x",
            "【标题】 https://b23.tv/BV1xx411c7mD 复制此链接" to "https://b23.tv/BV1xx411c7mD",
            "Read this: https://example.com/post." to "https://example.com/post",
            "(see https://en.wikipedia.org/wiki/Mercury_(planet))" to "https://en.wikipedia.org/wiki/Mercury_(planet)",
            "youtube.com/watch?v=dQw4w9WgXcQ" to "https://youtube.com/watch?v=dQw4w9WgXcQ",
            "HTTPS://X.com/jack/status/20" to "https://x.com/jack/status/20",
        )
        for ((input, expected) in cases) {
            assertEquals(input, expected, Links.extract(input)?.toString())
        }
        assertNull(Links.extract("no links here"))
        assertNull(Links.extract(""))
    }

    @Test
    fun youTubeIds() {
        assertEquals("abc", Links.youTubeId("https://youtu.be/abc".toHttpUrl()))
        assertEquals("abc", Links.youTubeId("https://www.youtube.com/live/abc?x=1".toHttpUrl()))
        assertEquals("abc", Links.youTubeId("https://m.youtube.com/watch?v=abc".toHttpUrl()))
        assertNull(Links.youTubeId("https://www.youtube.com/@channel".toHttpUrl()))
    }

    @Test
    fun linkKinds() {
        assertEquals(LinkKind.YOUTUBE, LinkKind.of("https://m.youtube.com/watch?v=a".toHttpUrl()))
        assertEquals(LinkKind.BILIBILI, LinkKind.of("https://b23.tv/x".toHttpUrl()))
        assertEquals(LinkKind.X, LinkKind.of("https://mobile.twitter.com/a".toHttpUrl()))
        assertEquals(LinkKind.WEB, LinkKind.of("https://notyoutube.com/".toHttpUrl()))
    }

    @Test
    fun displayUrlDropsWwwAndQuery() {
        val meta = LinkMeta(url = "https://www.example.com/a/b?utm_source=x", site = "example.com", title = "t")
        assertEquals("example.com/a/b", meta.displayUrl)
        assertEquals("example.com", meta.copy(url = "https://www.example.com").displayUrl)
        assertEquals("youtu.be/dQw4w9WgXcQ", meta.copy(url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ").displayUrl)
    }

    @Test
    fun byline() {
        val meta = LinkMeta(url = "https://x.com/jack/status/20", site = "X", title = "t")
        assertNull(meta.byline)
        assertEquals("jack @jack", meta.copy(authorName = "jack", authorHandle = "jack").byline)
        assertEquals("@jack", meta.copy(authorHandle = "jack").byline)
    }
}
