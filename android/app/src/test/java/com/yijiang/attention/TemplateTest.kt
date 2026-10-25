package com.yijiang.attention

import com.yijiang.attention.model.CardTemplate
import com.yijiang.attention.model.LinkMeta
import com.yijiang.attention.model.PixelSize
import org.junit.Assert.assertEquals
import org.junit.Test

class TemplateTest {
    private fun web(width: Int, height: Int) = LinkMeta(
        url = "https://example.com/article?utm_source=x",
        site = "example.com",
        title = "一篇用来测试不同 og:image 尺寸的文章标题",
        imageSize = PixelSize(width, height),
    )

    @Test
    fun picksTemplateByImageShape() {
        val cases = listOf(
            Triple(1200, 630, CardTemplate.HERO),
            Triple(1280, 720, CardTemplate.HERO),
            Triple(1080, 1440, CardTemplate.HERO),
            Triple(1024, 1024, CardTemplate.HERO),
            Triple(300, 300, CardTemplate.MINIMAL),
            Triple(600, 600, CardTemplate.MINIMAL),
            Triple(360, 200, CardTemplate.MINIMAL),
        )
        for ((width, height, expected) in cases) {
            assertEquals("${width}x$height", expected, CardTemplate.AUTO.resolved(web(width, height)))
        }
    }

    @Test
    fun autoByKind() {
        val noImage = web(1, 1).copy(imageSize = null)
        assertEquals(CardTemplate.MINIMAL, CardTemplate.AUTO.resolved(noImage))
        assertEquals(CardTemplate.QR, CardTemplate.AUTO.resolved(noImage.copy(title = "")))
        assertEquals(CardTemplate.HERO, CardTemplate.AUTO.resolved(noImage.copy(url = "https://youtu.be/abc")))
        assertEquals(CardTemplate.HERO, CardTemplate.AUTO.resolved(noImage.copy(url = "https://www.bilibili.com/video/BV1")))
        assertEquals(CardTemplate.POST, CardTemplate.AUTO.resolved(noImage.copy(url = "https://x.com/jack/status/20")))
    }

    @Test
    fun explicitTemplateWins() {
        val meta = web(1200, 630).copy(title = "")
        for (template in CardTemplate.entries.filter { it != CardTemplate.AUTO }) {
            assertEquals(template, template.resolved(meta))
        }
    }
}
