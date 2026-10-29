package com.yijiang.attention.data

/** What the feed shows: a section (live, archived, private) narrowed by sites, tags and a search. */
data class FeedFilter(
    /** Items from any of these domains (an item has only one). */
    val domains: Set<String> = emptySet(),
    /** Items carrying all of these tags. */
    val tags: Set<String> = emptySet(),
    val showsPrivate: Boolean = false,
    /** Archived items of the current section (private or not) instead of its live ones. */
    val showsArchived: Boolean = false,
    /** Set once the device owner is confirmed; cleared whenever Private is left or the app goes to the background. */
    val privateUnlocked: Boolean = false,
    val search: String = "",
) {
    val isAll: Boolean get() = domains.isEmpty() && tags.isEmpty() && !showsPrivate && !showsArchived

    /** Back to the live section with no filters; the search is kept. */
    fun reset() = FeedFilter(search = search)

    /** Clears domain and tag filters, staying in the current section. */
    fun clearFilters() = copy(domains = emptySet(), tags = emptySet())

    fun onlyDomain(domain: String) = clearFilters().copy(domains = setOf(domain))

    fun onlyTag(tag: String) = clearFilters().copy(tags = setOf(tag))

    fun toggleDomain(domain: String) = copy(domains = if (domain in domains) domains - domain else domains + domain)

    fun toggleTag(tag: String) = copy(tags = if (tag in tags) tags - tag else tags + tag)

    /** Items in the current section (private or not, archived or not), before domain and tag filters. */
    fun section(items: List<LibraryItem>): List<LibraryItem> =
        items.filter { it.isPrivate == showsPrivate && it.isArchived == showsArchived }

    fun apply(items: List<LibraryItem>): List<LibraryItem> {
        if (showsPrivate && !privateUnlocked) return emptyList()
        return section(items).filter { item ->
            (domains.isEmpty() || item.domain in domains) && item.tags.containsAll(tags) && item.matches(search)
        }
    }
}
