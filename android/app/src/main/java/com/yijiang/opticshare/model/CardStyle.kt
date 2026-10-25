package com.yijiang.opticshare.model

enum class CardTemplate {
    AUTO, HERO, POST, MINIMAL, QR;

    fun resolved(meta: LinkMeta): CardTemplate {
        if (this != AUTO) return this
        if (!meta.hasPreview) return QR
        return when (meta.kind) {
            LinkKind.YOUTUBE, LinkKind.BILIBILI -> HERO
            LinkKind.X -> POST
            LinkKind.WEB -> if (meta.imageSize == null || meta.imageIsIcon) MINIMAL else HERO
        }
    }
}

/** Card sizes in dp; rendered at 3x (1080 px wide). */
enum class CardAspect(val width: Int, val height: Int, val label: String) {
    PORTRAIT(360, 450, "4:5"),
    SQUARE(360, 360, "1:1"),
    STORY(360, 640, "9:16"),
}

data class CardStyle(
    val template: CardTemplate = CardTemplate.AUTO,
    val aspect: CardAspect = CardAspect.PORTRAIT,
)
