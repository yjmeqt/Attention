package com.yijiang.attention.ui

import android.app.Activity
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.staggeredgrid.LazyVerticalStaggeredGrid
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridCells
import androidx.compose.foundation.lazy.staggeredgrid.StaggeredGridItemSpan
import androidx.compose.foundation.lazy.staggeredgrid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yijiang.attention.R
import com.yijiang.attention.data.LibraryItem
import kotlinx.coroutines.delay
import okhttp3.HttpUrl.Companion.toHttpUrl

@Composable
fun HomeScreen(vm: HomeViewModel) {
    val items by vm.library.items.collectAsStateWithLifecycle()
    val actions = rememberItemActions(vm)

    PrivacyGuard(vm)
    val open = vm.openId?.let { id -> items.firstOrNull { it.id == id } }
    if (open != null) {
        BackHandler { vm.openId = null }
        DetailScreen(open, vm, actions, onBack = { vm.openId = null })
    } else {
        Feed(vm, items, actions)
    }

    ItemActionPresentations(vm)
    if (vm.showsScanner) {
        QrScanSheet(onLink = { url ->
            vm.showsScanner = false
            vm.open(url)
        }, onDismiss = { vm.showsScanner = false })
    }
    if (vm.showsLinkEntry) LinkEntryDialog(vm)
    if (vm.showsGuide) {
        ShareSheetGuideDialog(lockedUntilWatched = !vm.seenShareGuide, onDismiss = vm::guideDismissed)
    }
}

/** Locks Private when the app goes to the background, and keeps private items out of screenshots and Recents. */
@Composable
private fun PrivacyGuard(vm: HomeViewModel) {
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> vm.lockPrivate()
                Lifecycle.Event.ON_START -> vm.onForeground()
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    val window = (LocalContext.current as? Activity)?.window
    val secure = vm.filter.showsPrivate
    DisposableEffect(window, secure) {
        if (secure) window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Feed(vm: HomeViewModel, items: List<LibraryItem>, actions: ItemActions) {
    val context = LocalContext.current
    val revision by vm.library.revision.collectAsStateWithLifecycle()
    val enriching by vm.library.enriching.collectAsStateWithLifecycle()
    val filter = vm.filter
    val visible = remember(items, filter) { filter.apply(items) }
    // While a site or tag filter is on, the bar stays so it can be changed or cleared.
    val showsFilterBar = items.isNotEmpty() && (vm.searching || filter.domains.isNotEmpty() || filter.tags.isNotEmpty())
    val selected = items.filter { it.id in vm.selection }.map { it.id }

    fun paste() = vm.paste(Sharing.clipboardText(context), Sharing.clipboardImage(context))

    if (vm.selecting) BackHandler { vm.stopSelecting() }
    else if (vm.searching) BackHandler { vm.searching = false; vm.filter = filter.copy(search = "") }
    else if (!filter.isAll) BackHandler { if (filter.showsPrivate) vm.leavePrivate() else vm.filter = filter.reset() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                actions = {
                    if (vm.selecting) {
                        TextButton(onClick = vm::stopSelecting) { Text(stringResource(R.string.done)) }
                    } else {
                        // Shown only while a section is open, so it's clear where you are and one tap gets you out.
                        if (filter.showsArchived) SectionButton(R.string.archived, Icons.Default.Archive) { vm.toggleArchived() }
                        if (filter.showsPrivate) SectionButton(R.string.private_section, Icons.Default.Lock) { vm.leavePrivate() }
                        MoreMenu(vm, items.isNotEmpty(), actions)
                    }
                },
            )
        },
        bottomBar = {
            if (vm.selecting) {
                BottomAppBar {
                    val none = selected.isEmpty()
                    BarButton(R.string.tag, Icons.Outlined.Sell, !none) { actions.editTags(selected) }
                    Spacer(Modifier.weight(1f))
                    if (filter.showsPrivate) {
                        BarButton(R.string.remove_from_private, Icons.Default.LockOpen, !none) { actions.setPrivate(false, selected) }
                    } else {
                        BarButton(R.string.move_to_private, Icons.Default.Lock, !none) { actions.setPrivate(true, selected) }
                    }
                    Spacer(Modifier.weight(1f))
                    if (filter.showsArchived) {
                        BarButton(R.string.unarchive, Icons.Default.Unarchive, !none) { actions.setArchived(false, selected) }
                    } else {
                        BarButton(R.string.archive, Icons.Default.Archive, !none) { actions.setArchived(true, selected) }
                    }
                    Spacer(Modifier.weight(1f))
                    BarButton(R.string.delete, Icons.Outlined.Delete, !none, tint = MaterialTheme.colorScheme.error) { actions.delete(selected) }
                }
            } else {
                Column {
                    AnimatedVisibility(showsFilterBar, enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
                        FilterBar(filter, items, vm.library, revision) { vm.filter = it }
                    }
                    BottomAppBar {
                        if (vm.searching) {
                            SearchField(vm)
                        } else {
                            BarButton(R.string.scan_qr_code, Icons.Default.QrCodeScanner) { vm.showsScanner = true }
                            BarButton(R.string.paste, Icons.Default.ContentPaste) { paste() }
                            Spacer(Modifier.weight(1f))
                            BarButton(R.string.search, Icons.Default.Search) { vm.searching = true }
                        }
                    }
                }
            }
        },
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            FeedContent(vm, items, visible, actions, revision, enriching, ::paste)
            NoticeCapsule(vm, Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun FeedContent(
    vm: HomeViewModel,
    items: List<LibraryItem>,
    visible: List<LibraryItem>,
    actions: ItemActions,
    revision: Int,
    enriching: Set<String>,
    paste: () -> Unit,
) {
    val filter = vm.filter
    when {
        items.isEmpty() || (visible.isEmpty() && filter.isAll && filter.search.isEmpty()) -> Box(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
            contentAlignment = Alignment.TopCenter,
        ) {
            EmptyState(
                onPaste = paste,
                onSample = { vm.open(SAMPLE_LINK.toHttpUrl()) },
                showsPinGuide = { vm.showsGuide = true },
                seenShareGuide = vm.seenShareGuide,
                modifier = Modifier.widthIn(max = 520.dp).padding(16.dp),
            )
        }
        filter.showsPrivate && !filter.privateUnlocked -> Unavailable(R.string.private_locked, Icons.Default.Lock)
        visible.isEmpty() && filter.search.isNotEmpty() ->
            Unavailable(R.string.no_results, Icons.Default.SearchOff, filter.search)
        visible.isEmpty() -> when {
            filter.showsArchived -> Unavailable(R.string.no_archived_items, Icons.Default.Archive)
            filter.showsPrivate -> Unavailable(R.string.no_private_items, Icons.Default.Inbox)
            else -> Unavailable(R.string.nothing_here, Icons.Default.Inbox)
        }
        else -> BoxWithConstraints {
            val columns = feedColumns(maxWidth)
            // Points out the long-press menu once the library has a few links in it.
            val showsTip = !vm.longPressTipShown && items.size >= 3 && !vm.selecting
            LaunchedEffect(showsTip) { if (showsTip) vm.longPressTipDisplayed() }
            // Like the iOS waterfall, each tile goes to the currently shortest column.
            LazyVerticalStaggeredGrid(
                columns = StaggeredGridCells.Fixed(columns),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalItemSpacing = 12.dp,
                modifier = Modifier.fillMaxSize(),
            ) {
                if (showsTip) {
                    item(key = "tip", span = StaggeredGridItemSpan.FullLine) { LongPressTip(onClose = vm::longPressTipDone) }
                }
                items(visible, key = { it.id }) { item ->
                    Tile(vm, item, actions, revision, item.id in enriching)
                }
            }
        }
    }
}

@Composable
private fun Tile(vm: HomeViewModel, item: LibraryItem, actions: ItemActions, revision: Int, enriching: Boolean) {
    var menu by remember { mutableStateOf(false) }
    Box {
        if (vm.selecting) {
            FeedTile(item, vm.library, revision, enriching, onClick = { vm.toggleSelected(item.id) }, onLongClick = null,
                isSelecting = true, isSelected = item.id in vm.selection)
        } else {
            FeedTile(
                item, vm.library, revision, enriching,
                onClick = { vm.openId = item.id },
                onLongClick = {
                    menu = true
                    vm.longPressTipDone()
                },
                onOpen = { actions.openInApp(item) },
            )
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            ItemMenuItems(item, actions, onSelect = { vm.startSelecting(item.id) }, dismiss = { menu = false })
        }
    }
}

@Composable
private fun LongPressTip(onClose: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.large) {
        Row(modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.TouchApp, contentDescription = null, modifier = Modifier.size(28.dp))
            Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
                Text(stringResource(R.string.tip_title), style = MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.tip_body), style = MaterialTheme.typography.bodySmall)
            }
            IconButton(onClick = onClose) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.close)) }
        }
    }
}

@Composable
private fun MoreMenu(vm: HomeViewModel, hasItems: Boolean, actions: ItemActions) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) { Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.more)) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            fun run(action: () -> Unit) {
                expanded = false
                action()
            }
            if (hasItems) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.archived)) },
                    leadingIcon = { Icon(Icons.Default.Archive, contentDescription = null) },
                    trailingIcon = { Checkbox(checked = vm.filter.showsArchived, onCheckedChange = null) },
                    onClick = { run(vm::toggleArchived) },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.private_section)) },
                    leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
                    trailingIcon = { Checkbox(checked = vm.filter.showsPrivate, onCheckedChange = null) },
                    onClick = { run { if (vm.filter.showsPrivate) vm.leavePrivate() else actions.unlockPrivate() } },
                )
                HorizontalDivider()
            }
            MenuItem(R.string.enter_link_ellipsis, Icons.Default.TextFields) { run { vm.showsLinkEntry = true } }
            if (hasItems) MenuItem(R.string.select, Icons.Default.CheckCircle) { run { vm.startSelecting() } }
            MenuItem(R.string.pin_guide_link, Icons.Default.PushPin) { run { vm.showsGuide = true } }
        }
    }
}

@Composable
private fun SectionButton(text: Int, icon: ImageVector, onClick: () -> Unit) {
    Button(onClick = onClick, contentPadding = PaddingValues(horizontal = 12.dp), modifier = Modifier.padding(end = 4.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.size(6.dp))
        Text(stringResource(text))
    }
}

@Composable
private fun BarButton(text: Int, icon: ImageVector, enabled: Boolean = true, tint: Color? = null, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled) {
        Icon(icon, contentDescription = stringResource(text), tint = if (enabled && tint != null) tint else androidx.compose.material3.LocalContentColor.current)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.SearchField(vm: HomeViewModel) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    TextField(
        value = vm.filter.search,
        onValueChange = { vm.filter = vm.filter.copy(search = it) },
        placeholder = { Text(stringResource(R.string.search)) },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
        singleLine = true,
        shape = CircleShape,
        colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
        modifier = Modifier.weight(1f).focusRequester(focus),
    )
    IconButton(onClick = {
        vm.searching = false
        vm.filter = vm.filter.copy(search = "")
    }) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cancel)) }
}

@Composable
private fun Unavailable(text: Int, icon: ImageVector, vararg args: Any) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.size(12.dp))
        Text(stringResource(text, *args), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
    }
}

/** A capsule above the bottom bar that hides itself after three seconds. */
@Composable
fun NoticeCapsule(vm: HomeViewModel, modifier: Modifier = Modifier) {
    val notice = vm.notice
    LaunchedEffect(notice) {
        if (notice != null) {
            delay(3000)
            if (vm.notice == notice) vm.notice = null
        }
    }
    AnimatedVisibility(notice != null, modifier = modifier.padding(bottom = 8.dp), enter = fadeIn(), exit = fadeOut()) {
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.inverseSurface, shadowElevation = 4.dp) {
            Text(
                notice?.let { stringResource(it.text) }.orEmpty(),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun LinkEntryDialog(vm: HomeViewModel) {
    var text by rememberSaveable { mutableStateOf("") }
    fun go() {
        vm.showsLinkEntry = false
        vm.submit(text)
    }
    AlertDialog(
        onDismissRequest = { vm.showsLinkEntry = false },
        title = { Text(stringResource(R.string.enter_link)) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text("https://") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go, autoCorrectEnabled = false),
                keyboardActions = KeyboardActions(onGo = { go() }),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = { TextButton(onClick = ::go) { Text(stringResource(R.string.go)) } },
        dismissButton = { TextButton(onClick = { vm.showsLinkEntry = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

/** A first link to save, so the library is never a dead end; the iOS app uses the same placeholder store page. */
const val SAMPLE_LINK = "https://apps.apple.com/app/apple-music/id1108187390"
