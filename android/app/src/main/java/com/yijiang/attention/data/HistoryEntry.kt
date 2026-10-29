package com.yijiang.attention.data

import com.yijiang.attention.model.LinkMeta
import kotlinx.serialization.Serializable

/** An entry of the pre-library history, read once by [Library.importHistory]. */
@Serializable
data class HistoryEntry(
    val id: String,
    val date: Long,
    val meta: LinkMeta,
)
