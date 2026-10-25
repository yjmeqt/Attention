package com.yijiang.attention.data

import android.content.Context
import com.yijiang.attention.model.LinkMeta
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

@Serializable
data class HistoryEntry(
    val id: String = UUID.randomUUID().toString(),
    val date: Long = System.currentTimeMillis(),
    val meta: LinkMeta,
)

/** Index in JSON; image bytes as sibling files. Icons and avatars load eagerly for list rows, covers on demand. */
class HistoryStore(context: Context) {
    private val directory = File(context.filesDir, "history").apply { mkdirs() }
    private val index = File(directory, "index.json")
    private val json = Json { ignoreUnknownKeys = true }

    private val _entries = MutableStateFlow<List<HistoryEntry>>(emptyList())
    val entries: StateFlow<List<HistoryEntry>> = _entries.asStateFlow()

    @Synchronized
    fun load() {
        val stored = runCatching { json.decodeFromString<List<HistoryEntry>>(index.readText()) }.getOrDefault(emptyList())
        _entries.value = stored.map { entry ->
            entry.copy(meta = entry.meta.copy(icon = read(entry, "icon"), avatar = read(entry, "avatar")))
        }
    }

    @Synchronized
    fun add(meta: LinkMeta) {
        val current = _entries.value.toMutableList()
        current.filter { it.meta.url == meta.url }.forEach { deleteFiles(it) }
        current.removeAll { it.meta.url == meta.url }
        val entry = HistoryEntry(meta = meta.copy(image = null))
        write(entry, "image", meta.image)
        write(entry, "icon", meta.icon)
        write(entry, "avatar", meta.avatar)
        current.add(0, entry)
        while (current.size > MAX_ENTRIES) deleteFiles(current.removeAt(current.lastIndex))
        save(current)
    }

    @Synchronized
    fun remove(entry: HistoryEntry) {
        deleteFiles(entry)
        save(_entries.value.filterNot { it.id == entry.id })
    }

    fun meta(entry: HistoryEntry): LinkMeta = entry.meta.copy(image = read(entry, "image"))

    private fun file(entry: HistoryEntry, kind: String) = File(directory, "${entry.id}.$kind")

    private fun read(entry: HistoryEntry, kind: String): ByteArray? =
        file(entry, kind).takeIf { it.exists() }?.readBytes()

    private fun write(entry: HistoryEntry, kind: String, data: ByteArray?) {
        if (data != null) file(entry, kind).writeBytes(data)
    }

    private fun deleteFiles(entry: HistoryEntry) {
        listOf("image", "icon", "avatar").forEach { file(entry, it).delete() }
    }

    private fun save(entries: List<HistoryEntry>) {
        _entries.value = entries
        val temp = File(directory, "index.json.tmp")
        temp.writeText(json.encodeToString(entries))
        temp.renameTo(index)
    }

    private companion object {
        const val MAX_ENTRIES = 50
    }
}
