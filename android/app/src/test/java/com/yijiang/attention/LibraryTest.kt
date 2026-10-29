package com.yijiang.attention

import com.yijiang.attention.data.DomainTag
import com.yijiang.attention.data.FeedFilter
import com.yijiang.attention.data.LibraryItem
import com.yijiang.attention.data.LibraryRules
import com.yijiang.attention.data.TextReader
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryTest {
    private fun link(url: String, vararg tags: String, isPrivate: Boolean = false, isArchived: Boolean = false, updatedAt: Long = 0) =
        LibraryItem(key = url, url = url, tags = tags.toList(), isPrivate = isPrivate, isArchived = isArchived, updatedAt = updatedAt)

    @Test
    fun domainsDropMobilePrefixesAndFollowAliases() {
        assertEquals("youtube.com", DomainTag.domain("https://m.youtube.com/watch?v=1".toHttpUrl()))
        assertEquals("youtube.com", DomainTag.domain("https://youtu.be/abc".toHttpUrl()))
        assertEquals("x.com", DomainTag.domain("https://mobile.twitter.com/a/status/1".toHttpUrl()))
        assertEquals("bilibili.com", DomainTag.domain("https://b23.tv/xyz".toHttpUrl()))
        assertEquals("example.com", DomainTag.domain("https://www.example.com/".toHttpUrl()))
        assertEquals(DomainTag.IMAGES, LibraryItem(key = "image:1").domain)
    }

    @Test
    fun keysAreCleanedLinks() {
        assertEquals("https://youtu.be/abc", DomainTag.key("https://www.youtube.com/watch?v=abc&si=track".toHttpUrl()))
    }

    @Test
    fun filterKeepsTheSectionAndNeedsEveryTag() {
        val items = listOf(
            link("https://a.com/1", "news", "tech"),
            link("https://a.com/2", "news"),
            link("https://b.com/3", "tech"),
            link("https://a.com/4", "news", isArchived = true),
            link("https://a.com/5", "news", isPrivate = true),
        )
        assertEquals(3, FeedFilter().apply(items).size)
        assertEquals(listOf("https://a.com/1"), FeedFilter(tags = setOf("news", "tech")).apply(items).map { it.url })
        assertEquals(2, FeedFilter(domains = setOf("a.com")).apply(items).size)
        assertEquals(listOf("https://a.com/4"), FeedFilter(showsArchived = true).apply(items).map { it.url })
        assertTrue(FeedFilter(showsPrivate = true).apply(items).isEmpty())
        assertEquals(1, FeedFilter(showsPrivate = true, privateUnlocked = true).apply(items).size)
    }

    @Test
    fun searchMatchesTitleLinkTextAndSite() {
        val item = LibraryItem(key = "k", url = "https://example.com/post", title = "Rust 入门", site = "Example", ocrText = "扫码关注")
        assertTrue(item.matches("rust"))
        assertTrue(item.matches("example.com"))
        assertTrue(item.matches("关注"))
        assertTrue(item.matches("  "))
        assertFalse(item.matches("swift"))
    }

    @Test
    fun onlyAndClearStayInTheSection() {
        val filter = FeedFilter(showsArchived = true, tags = setOf("a")).onlyDomain("x.com")
        assertEquals(setOf("x.com"), filter.domains)
        assertTrue(filter.tags.isEmpty())
        assertTrue(filter.showsArchived)
        assertFalse(filter.reset().showsArchived)
    }

    @Test
    fun tagsAreNormalizedAndRankedByUse() {
        assertEquals("work", LibraryRules.normalizedTag("  ##work "))
        assertEquals(listOf("b", "a", "c"), LibraryRules.ranked(listOf("a", "b", "b", "c")))
    }

    @Test
    fun overTheCapArchivedGoFirstAndPrivateStay() {
        val newestFirst = listOf(
            link("https://a.com/new", updatedAt = 4),
            link("https://a.com/archived", isArchived = true, updatedAt = 3),
            link("https://a.com/old", updatedAt = 2),
            link("https://a.com/private", isPrivate = true, updatedAt = 1),
        )
        assertEquals(listOf("https://a.com/archived"), LibraryRules.overCap(newestFirst, max = 3).map { it.url })
        assertEquals(listOf("https://a.com/archived", "https://a.com/old"), LibraryRules.overCap(newestFirst, max = 2).map { it.url })
        assertTrue(LibraryRules.overCap(newestFirst, max = 4).isEmpty())
    }

    @Test
    fun ocrTitleIsTheBiggestTextNearTheTop() {
        val lines = listOf(
            TextReader.Line("小红书", 0.05, 0.02),
            TextReader.Line("周末去哪儿", 0.06, 0.20),
            TextReader.Line("北京胡同散步路线", 0.058, 0.27),
            TextReader.Line("正文内容比较小的一行", 0.02, 0.40),
            TextReader.Line("@作者", 0.07, 0.10),
        )
        assertEquals("周末去哪儿北京胡同散步路线", TextReader.title(lines))
        assertEquals("Big Title", TextReader.title(listOf(TextReader.Line("Big Title", 0.05, 0.1), TextReader.Line("body", 0.02, 0.3))))
        assertNull(TextReader.title(listOf(TextReader.Line("Footer", 0.05, 0.9))))
    }
}
