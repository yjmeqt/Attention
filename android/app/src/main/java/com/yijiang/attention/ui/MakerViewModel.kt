package com.yijiang.attention.ui

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.yijiang.attention.R
import com.yijiang.attention.card.CardImages
import com.yijiang.attention.card.CardRenderer
import com.yijiang.attention.data.HistoryEntry
import com.yijiang.attention.data.HistoryStore
import com.yijiang.attention.data.StyleStore
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.LinkMeta
import com.yijiang.attention.model.Links
import com.yijiang.attention.unfurl.Unfurler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MakerViewModel(application: Application) : AndroidViewModel(application) {
    private val styleStore = StyleStore(application)
    val history = HistoryStore(application)

    var input by mutableStateOf(TextFieldValue())
    /** A string resource shown under the input. */
    var notice by mutableStateOf<Int?>(null)
    var loading by mutableStateOf(false)
        private set
    var meta by mutableStateOf<LinkMeta?>(null)
        private set
    var images by mutableStateOf<CardImages?>(null)
        private set
    var card by mutableStateOf<Bitmap?>(null)
        private set
    var style by mutableStateOf(styleStore.load())
        private set

    /** Set when a link arrives from another app's share sheet, so the card is shared as soon as it's ready. */
    var autoSharePending by mutableStateOf(false)

    private var makeJob: Job? = null
    private var renderJob: Job? = null

    init {
        viewModelScope.launch(Dispatchers.IO) { history.load() }
    }

    val showsGenerate: Boolean
        get() = loading || (input.text.isNotEmpty() && input.text != meta?.url)

    fun make(text: String = input.text) {
        val url = Links.extract(text)
        if (url == null) {
            notice = R.string.notice_no_link
            return
        }
        makeJob?.cancel()
        makeJob = viewModelScope.launch {
            loading = true
            notice = null
            val result = Unfurler.unfurlWithFallback(url)
            loading = false
            show(result.meta)
            withContext(Dispatchers.IO) { history.add(result.meta) }
            if (result.isFallback) notice = R.string.notice_fallback
        }
    }

    fun receiveShared(text: String) {
        input = TextFieldValue(text)
        autoSharePending = true
        make(text)
    }

    fun paste(text: String?) {
        val url = text?.let(Links::extract)
        if (url == null) {
            notice = R.string.notice_no_clipboard_link
            return
        }
        input = TextFieldValue(url.toString())
        make()
    }

    fun show(entry: HistoryEntry) {
        viewModelScope.launch {
            show(withContext(Dispatchers.IO) { history.meta(entry) })
        }
    }

    private fun show(meta: LinkMeta) {
        this.meta = meta
        input = TextFieldValue(meta.url, TextRange.Zero)
        notice = null
        renderJob?.cancel()
        renderJob = viewModelScope.launch {
            images = withContext(Dispatchers.Default) { CardImages.decode(meta) }
            render()
        }
    }

    fun updateStyle(style: CardStyle) {
        this.style = style
        styleStore.save(style)
        renderJob?.cancel()
        renderJob = viewModelScope.launch { render() }
    }

    fun removeFromHistory(entry: HistoryEntry) {
        viewModelScope.launch(Dispatchers.IO) { history.remove(entry) }
    }

    private suspend fun render() {
        val meta = meta ?: return
        val images = images ?: return
        val style = style
        card = withContext(Dispatchers.Default) { CardRenderer.render(meta, style, images) }
    }
}
