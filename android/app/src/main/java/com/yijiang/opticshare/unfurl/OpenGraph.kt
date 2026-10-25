package com.yijiang.opticshare.unfurl

object OpenGraph {
    private val metaTag = Regex("""<meta\b[^>]*>""", RegexOption.IGNORE_CASE)
    private val linkTag = Regex("""<link\b[^>]*>""", RegexOption.IGNORE_CASE)
    private val attribute = Regex("""([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""")
    private val titleTag = Regex("""<title[^>]*>([^<]*)</title>""", RegexOption.IGNORE_CASE)
    private val numericEntity = Regex("""&#([xX]?)([0-9a-fA-F]+);""")

    private fun attributes(tag: String): Map<String, String> =
        attribute.findAll(tag).associate { match ->
            val (name, double, single, bare) = match.destructured
            name.lowercase() to double.ifEmpty { single.ifEmpty { bare } }
        }

    /** `og:`, `twitter:` and other named meta tags; the first occurrence of each key wins. */
    fun tags(html: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        for (match in metaTag.findAll(html)) {
            val attributes = attributes(match.value)
            val key = (attributes["property"] ?: attributes["name"])?.lowercase() ?: continue
            val content = attributes["content"]?.takeIf { it.isNotEmpty() } ?: continue
            if (key !in result) result[key] = decodeEntities(content)
        }
        return result
    }

    /** The best declared icon: apple-touch-icon first, then the largest `rel=icon`. SVGs are skipped. */
    fun icon(html: String): String? {
        var bestScore = -1
        var bestHref: String? = null
        for (match in linkTag.findAll(html)) {
            val attributes = attributes(match.value)
            val rel = attributes["rel"]?.lowercase() ?: continue
            val href = attributes["href"]?.takeIf { it.isNotEmpty() } ?: continue
            if (href.lowercase().endsWith(".svg")) continue
            val size = attributes["sizes"]?.lowercase()?.substringBefore('x')?.toIntOrNull() ?: 0
            val score = when {
                "apple-touch-icon" in rel -> 10_000 + size
                "icon" in rel.split(' ') -> size
                else -> continue
            }
            if (score > bestScore) {
                bestScore = score
                bestHref = decodeEntities(href)
            }
        }
        return bestHref
    }

    fun title(html: String): String? = titleTag.find(html)?.groupValues?.get(1)?.let(::decodeEntities)

    fun decodeEntities(string: String): String {
        if ('&' !in string) return string
        return string
            .replace(numericEntity) { match ->
                val (hex, digits) = match.destructured
                val code = digits.toIntOrNull(if (hex.isEmpty()) 10 else 16)
                if (code != null && Character.isValidCodePoint(code)) String(Character.toChars(code)) else ""
            }
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
    }
}
