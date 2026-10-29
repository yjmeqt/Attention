package com.yijiang.attention.model

enum class CardTemplate {
    AUTO, TILE, MINIMAL, QR;

    fun resolved(meta: LinkMeta): CardTemplate {
        if (this != AUTO) return this
        return if (meta.hasPreview) TILE else QR
    }

    companion object {
        /** Saved names of removed templates (`HERO`, `POST`) come back as Auto. */
        fun named(name: String?): CardTemplate = entries.firstOrNull { it.name == name } ?: AUTO
    }
}

data class CardStyle(
    val template: CardTemplate = CardTemplate.AUTO,
)
