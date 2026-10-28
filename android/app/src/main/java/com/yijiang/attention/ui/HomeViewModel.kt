package com.yijiang.attention.ui

import android.app.Application
import android.net.Uri
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.yijiang.attention.R
import com.yijiang.attention.data.Capture
import com.yijiang.attention.data.FeedFilter
import com.yijiang.attention.data.Intake
import com.yijiang.attention.data.Library
import com.yijiang.attention.data.LibraryItem
import com.yijiang.attention.data.StyleStore
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.Links
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl

/** A notice shown in a capsule at the bottom of the screen for a few seconds. */
data class Notice(@param:StringRes val text: Int, val id: Long = System.nanoTime())

enum class Copied { LINK, LINK_FOR_IMAGE }

class HomeViewModel(application: Application) : AndroidViewModel(application) {
    val library = Library(application)
    private val styleStore = StyleStore(application)
    private val prefs = application.getSharedPreferences("home", 0)

    var filter by mutableStateOf(FeedFilter())
    var searching by mutableStateOf(false)
    var selecting by mutableStateOf(false)
        private set
    var selection by mutableStateOf<Set<String>>(emptySet())
    /** The item whose detail page is open. */
    var openId by mutableStateOf<String?>(null)
    var notice by mutableStateOf<Notice?>(null)
    var copied by mutableStateOf<Copied?>(null)
    var tagTargets by mutableStateOf<List<String>?>(null)
    var pendingDelete by mutableStateOf<List<String>?>(null)
    var showsPasscodeRequired by mutableStateOf(false)
    var showsScanner by mutableStateOf(false)
    var showsLinkEntry by mutableStateOf(false)
    /** Opened on first launch; Done stays off until the animation has played once. */
    var showsGuide by mutableStateOf(!prefs.getBoolean(SEEN_GUIDE, false))
    var seenShareGuide by mutableStateOf(prefs.getBoolean(SEEN_GUIDE, false))
        private set
    var longPressTipShown by mutableStateOf(prefs.getInt(TIP_COUNT, 0) >= TIP_MAX_DISPLAYS)
        private set

    init {
        io {
            library.importHistory()
            library.retryMissingPreviews()
        }
    }

    // region Feed

    fun startSelecting(first: String? = null) {
        selecting = true
        selection = setOfNotNull(first)
    }

    fun stopSelecting() {
        selecting = false
        selection = emptySet()
    }

    fun toggleSelected(id: String) {
        selection = if (id in selection) selection - id else selection + id
    }

    fun toggleArchived() {
        filter = if (filter.showsArchived) filter.copy(showsArchived = false) else filter.clearFilters().copy(showsArchived = true)
    }

    fun unlockPrivate() {
        stopSelecting()
        filter = filter.reset().copy(showsPrivate = true, privateUnlocked = true)
    }

    fun leavePrivate() = lockPrivate()

    /** On leaving Private or going to the background. */
    fun lockPrivate() {
        val wasShowing = filter.showsPrivate
        filter = if (wasShowing) filter.reset() else filter.copy(privateUnlocked = false)
        val privateIds = library.items.value.filter { it.isPrivate }.map { it.id }.toSet()
        if (openId in privateIds) openId = null
        selection = selection - privateIds
    }

    /** Counts toward the tip's three showings; opening the menu retires it for good. */
    fun longPressTipDisplayed() = prefs.edit { putInt(TIP_COUNT, prefs.getInt(TIP_COUNT, 0) + 1) }

    fun longPressTipDone() {
        longPressTipShown = true
        prefs.edit { putInt(TIP_COUNT, TIP_MAX_DISPLAYS) }
    }

    fun guideDismissed() {
        showsGuide = false
        seenShareGuide = true
        prefs.edit { putBoolean(SEEN_GUIDE, true) }
    }

    fun onForeground() = io { library.retryMissingPreviews() }

    // endregion

    // region Item actions

    fun item(id: String): LibraryItem? = library.item(id)

    fun shareUrl(item: LibraryItem): String? = item.url?.let { Links.cleanedForSharing(it.toHttpUrl()).toString() }

    fun setPrivate(isPrivate: Boolean, ids: Collection<String>) = io { library.setPrivate(isPrivate, ids) }

    fun setArchived(isArchived: Boolean, ids: Collection<String>) {
        selection = selection - ids.toSet()
        io { library.setArchived(isArchived, ids) }
    }

    fun confirmDelete() {
        val ids = pendingDelete ?: return
        pendingDelete = null
        selection = selection - ids.toSet()
        if (openId in ids) openId = null
        io { library.delete(ids) }
    }

    fun addTag(tag: String, ids: Collection<String>) = io { library.addTag(tag, ids) }

    fun removeTag(tag: String, ids: Collection<String>) = io { library.removeTag(tag, ids) }

    /** Also the default for links saved from now on, like the iOS app. */
    fun setStyle(style: CardStyle, id: String) {
        styleStore.save(style)
        io { library.setStyle(style, id) }
    }

    fun setUsesSharedImage(uses: Boolean, id: String) = io { library.setUsesSharedImage(uses, id) }

    // endregion

    // region Intake

    fun submit(text: String) {
        val url = Links.extract(text) ?: return show(R.string.notice_no_link)
        open(Capture.Link(url))
    }

    fun paste(text: String?, image: Uri?) = receive(text, image, R.string.notice_no_clipboard_link)

    fun receive(text: String?, image: Uri?, @StringRes missing: Int = R.string.nothing_to_save) {
        viewModelScope.launch {
            val capture = Intake.capture(getApplication(), text, image) ?: return@launch show(missing)
            open(capture)
        }
    }

    fun open(url: HttpUrl) = open(Capture.Link(url))

    private fun open(capture: Capture) {
        notice = null
        viewModelScope.launch {
            val item = withContext(Dispatchers.IO) { library.save(capture, styleStore.load()) }
            launch(Dispatchers.IO) { library.enrich(item)?.let { withContext(Dispatchers.Main) { show(it) } } }
            if (item.isPrivate && !filter.privateUnlocked) return@launch show(R.string.already_private)
            stopSelecting()
            openId = item.id
        }
    }

    // endregion

    fun show(@StringRes text: Int) {
        notice = Notice(text)
    }

    private fun io(block: suspend () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) { block() }
    }

    private companion object {
        const val SEEN_GUIDE = "seenShareGuide"
        const val TIP_COUNT = "longPressTipCount"
        const val TIP_MAX_DISPLAYS = 3
    }
}
