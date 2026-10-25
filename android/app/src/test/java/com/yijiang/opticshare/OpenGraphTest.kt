package com.yijiang.opticshare

import com.yijiang.opticshare.unfurl.OpenGraph
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OpenGraphTest {
    @Test
    fun parsesTagsAndEntities() {
        val html = """
            <head><title>Fallback &amp; title</title>
            <meta content="https://cdn.example.com/a.jpg" property="og:image">
            <meta property='og:title' content='Mark Zuckerberg&#xff08;&#064;zuck&#xff09;&#x2022; Threads'>
            <meta name="twitter:image" content="/b.jpg" />
            <meta property="og:image" content="https://cdn.example.com/second.jpg">
            <meta name="description" content="">
            </head>
        """.trimIndent()
        val tags = OpenGraph.tags(html)
        assertEquals("https://cdn.example.com/a.jpg", tags["og:image"])
        assertEquals("Mark Zuckerberg（@zuck）• Threads", tags["og:title"])
        assertEquals("/b.jpg", tags["twitter:image"])
        assertNull(tags["description"])
        assertEquals("Fallback & title", OpenGraph.title(html))
    }

    @Test
    fun tagKeysAreCaseInsensitive() {
        val tags = OpenGraph.tags("""<META Property="OG:Title" CONTENT="Hello">""")
        assertEquals("Hello", tags["og:title"])
    }

    @Test
    fun decodesEntities() {
        assertEquals("a & b", OpenGraph.decodeEntities("a &amp; b"))
        assertEquals("\"q\" <t> 'x'", OpenGraph.decodeEntities("&quot;q&quot; &lt;t&gt; &#39;x&apos;"))
        assertEquals("中文", OpenGraph.decodeEntities("&#20013;&#x6587;"))
        assertEquals("&lt;", OpenGraph.decodeEntities("&amp;lt;"))
        assertEquals("😀", OpenGraph.decodeEntities("&#x1F600;"))
        assertEquals("plain", OpenGraph.decodeEntities("plain"))
    }

    @Test
    fun prefersTouchIconThenLargestIcon() {
        val html = """
            <link rel="icon" href="/16.png" sizes="16x16">
            <link rel="shortcut icon" href="/32.png" sizes="32x32">
            <link rel="apple-touch-icon" href="/touch.png">
            <link rel="icon" href="/logo.svg">
        """.trimIndent()
        assertEquals("/touch.png", OpenGraph.icon(html))
        assertEquals("/b.png", OpenGraph.icon("<link rel=icon href='/a.png'><link rel='icon' href='/b.png' sizes='64x64'>"))
        assertEquals("/32.png", OpenGraph.icon("""<link rel="icon" href="/16.png" sizes="16x16"><link rel="icon" href="/32.png" sizes="32x32">"""))
        assertNull(OpenGraph.icon("""<link rel="stylesheet" href="/a.css"><link rel="icon" href="/a.svg">"""))
    }
}
