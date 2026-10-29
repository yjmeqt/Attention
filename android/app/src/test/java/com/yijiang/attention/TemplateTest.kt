package com.yijiang.attention

import com.yijiang.attention.card.tileImageRatio
import com.yijiang.attention.model.CardTemplate
import com.yijiang.attention.model.LinkMeta
import com.yijiang.attention.model.PixelSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TemplateTest {
    private fun web(width: Int, height: Int) = LinkMeta(
        url = "https://example.com/article?utm_source=x",
        site = "example.com",
        title = "一篇用来测试不同 og:image 尺寸的文章标题",
        imageSize = PixelSize(width, height),
    )

    @Test
    fun autoIsTileWithPreviewElseQr() {
        assertEquals(CardTemplate.TILE, CardTemplate.AUTO.resolved(web(1200, 630)))
        assertEquals(CardTemplate.TILE, CardTemplate.AUTO.resolved(web(1, 1).copy(imageSize = null)))
        assertEquals(CardTemplate.TILE, CardTemplate.AUTO.resolved(web(1200, 630).copy(url = "https://x.com/jack/status/20")))
        assertEquals(CardTemplate.QR, CardTemplate.AUTO.resolved(web(1200, 630).copy(title = "")))
    }

    @Test
    fun explicitTemplateWins() {
        val meta = web(1200, 630).copy(title = "")
        for (template in CardTemplate.entries.filter { it != CardTemplate.AUTO }) {
            assertEquals(template, template.resolved(meta))
        }
    }

    @Test
    fun tilePhotoKeepsItsShapeWithinLimits() {
        assertEquals(720f / 1080, tileImageRatio(web(1080, 720))!!, 0.001f)
        assertEquals(9f / 16, tileImageRatio(web(1200, 630))!!, 0.001f)
        assertEquals(1f, tileImageRatio(web(1024, 1024))!!, 0.001f)
        assertEquals(16f / 9, tileImageRatio(web(1080, 2400))!!, 0.001f)
        assertEquals(9f / 16, tileImageRatio(web(2400, 600))!!, 0.001f)
    }

    @Test
    fun tileSkipsIconLikeImages() {
        assertNull(tileImageRatio(web(300, 300)))
        assertNull(tileImageRatio(web(600, 600)))
        assertNull(tileImageRatio(web(360, 200)))
        assertNull(tileImageRatio(web(1, 1).copy(imageSize = null)))
    }

    @Test
    fun removedTemplatesLoadAsAuto() {
        assertEquals(CardTemplate.AUTO, CardTemplate.named("HERO"))
        assertEquals(CardTemplate.AUTO, CardTemplate.named("POST"))
        assertEquals(CardTemplate.AUTO, CardTemplate.named(null))
        assertEquals(CardTemplate.MINIMAL, CardTemplate.named("MINIMAL"))
    }
}
