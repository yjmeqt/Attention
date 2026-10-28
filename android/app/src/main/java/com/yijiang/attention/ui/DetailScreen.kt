package com.yijiang.attention.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yijiang.attention.R
import com.yijiang.attention.card.CardImages
import com.yijiang.attention.data.Library
import com.yijiang.attention.data.LibraryItem
import com.yijiang.attention.model.LinkMeta
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private class DetailData(
    val image: Bitmap?,
    val meta: LinkMeta?,
    val images: CardImages?,
    /** The link's preview image and the image it was shared as, when they differ. */
    val covers: Pair<Bitmap?, Bitmap?>?,
)

/** A saved item: its card (or image), tags, template and actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(item: LibraryItem, vm: HomeViewModel, actions: ItemActions, onBack: () -> Unit) {
    val library = vm.library
    val revision by library.revision.collectAsStateWithLifecycle()
    val enriching by library.enriching.collectAsStateWithLifecycle()
    val isLoading = item.id in enriching
    val data by produceState<DetailData?>(null, item.id, revision, item.template, item.usesSharedImage, item.title) {
        value = withContext(Dispatchers.Default) {
            val meta = library.meta(item)
            DetailData(
                image = library.fullImage(item),
                meta = meta,
                images = meta?.let(CardImages::decode),
                covers = if (library.hasCoverChoice(item)) {
                    library.data(Library.Kind.COVER, item)?.let { Library.downsample(it, 300) } to
                        library.data(Library.Kind.SOURCE, item)?.let { Library.downsample(it, 300) }
                } else {
                    null
                },
            )
        }
    }
    LaunchedEffect(item.id) { vm.copied = null }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (item.isImage) stringResource(R.string.image) else domainLabel(item.domain), maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = { DetailMenu(item, actions) },
            )
        },
        bottomBar = { BottomBar(item, vm, actions, imageReady = data?.image != null) },
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            Column(
                modifier = Modifier
                    .widthIn(max = 520.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Preview(item, data?.image, isLoading)
                Details(item, vm, actions, data, isLoading)
            }
            NoticeCapsule(vm, Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun Preview(item: LibraryItem, image: Bitmap?, isLoading: Boolean) {
    val shape = RoundedCornerShape(16.dp)
    Box(modifier = Modifier.fillMaxWidth().heightIn(min = 240.dp), contentAlignment = Alignment.Center) {
        if (image != null) {
            val bitmap = remember(image) { image.asImageBitmap() }
            Image(
                bitmap,
                contentDescription = item.displayTitle,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxWidth().aspectRatio(image.width.toFloat() / image.height).shadow(4.dp, shape).clip(shape),
            )
        } else {
            Surface(shape = shape, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth().aspectRatio(0.8f)) {}
        }
        if (isLoading) {
            Surface(shape = CircleShape, tonalElevation = 3.dp) {
                CircularProgressIndicator(modifier = Modifier.padding(12.dp).size(24.dp), strokeWidth = 2.dp)
            }
        }
    }
}

@Composable
private fun Details(item: LibraryItem, vm: HomeViewModel, actions: ItemActions, data: DetailData?, isLoading: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (item.title.isNotEmpty()) {
            SelectionContainer { Text(item.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
        }
        if (item.url != null) {
            TextButton(onClick = { actions.openInBrowser(item) }, contentPadding = ButtonDefaults.TextButtonContentPadding) {
                Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(LinkMeta(url = item.url, site = item.site, title = "").displayUrl,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
            }
        }
        Text(formattedDate(item.createdAt), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }

    TagRow(item, vm, actions)

    val meta = data?.meta
    val images = data?.images
    if (meta != null && images != null) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            data.covers?.let { (preview, shared) ->
                Text(stringResource(R.string.cover), style = MaterialTheme.typography.titleSmall)
                CoverPicker(preview, shared, item.usesSharedImage) { vm.setUsesSharedImage(it, item.id) }
            }
            Text(stringResource(R.string.template), style = MaterialTheme.typography.titleSmall)
            TemplatePicker(meta, images, item.style) { vm.setStyle(item.style.copy(template = it), item.id) }
            if (!isLoading) SourceImageInfo(meta)
        }
    }

    item.ocrText?.takeIf { it.isNotEmpty() }?.let { RecognizedText(it) }
}

@Composable
private fun TagRow(item: LibraryItem, vm: HomeViewModel, actions: ItemActions) {
    val revision by vm.library.revision.collectAsStateWithLifecycle()
    val favicon = if (item.isImage) null else rememberFavicon(vm.library, item, revision)
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // The site's favicon when it has one, like the filter bar.
        TagChip(domainLabel(item.domain), icon = favicon, fallback = if (item.isImage) Icons.Default.Photo else Icons.Default.Public)
        if (item.isPrivate) TagChip(stringResource(R.string.private_section), fallback = Icons.Default.Lock)
        for (tag in item.tags) TagChip("#$tag")
        FilledTonalIconButton(onClick = { actions.editTags(listOf(item.id)) }, modifier = Modifier.size(32.dp)) {
            Icon(Icons.Default.Add, contentDescription = stringResource(R.string.add_tag), modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun TagChip(text: String, icon: ImageBitmap? = null, fallback: androidx.compose.ui.graphics.vector.ImageVector? = null) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) {
            Image(icon, contentDescription = null, modifier = Modifier.size(16.dp).clip(RoundedCornerShape(4.dp)))
        } else if (fallback != null) {
            Icon(fallback, contentDescription = null, modifier = Modifier.size(16.dp))
        }
        Text(text, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
    }
}

@Composable
private fun RecognizedText(text: String) {
    val context = LocalContext.current
    var expanded by rememberSaveable { mutableStateOf(false) }
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, shape = RoundedCornerShape(16.dp)) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.text_in_image), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                IconButton(onClick = { Sharing.copyText(context, text) }) {
                    Icon(Icons.Default.ContentCopy, contentDescription = stringResource(R.string.copy))
                }
            }
            SelectionContainer {
                Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = if (expanded) Int.MAX_VALUE else 6, overflow = TextOverflow.Ellipsis)
            }
            if (!expanded && text.lines().size > 6) {
                TextButton(onClick = { expanded = true }) { Text(stringResource(R.string.show_all)) }
            }
        }
    }
}

@Composable
private fun DetailMenu(item: LibraryItem, actions: ItemActions) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) { Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.more)) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            fun run(action: () -> Unit) {
                expanded = false
                action()
            }
            if (item.url != null) {
                MenuItem(R.string.open_in_app, Icons.AutoMirrored.Filled.OpenInNew) { run { actions.openInApp(item) } }
                MenuItem(R.string.open_in_browser, Icons.Default.Public) { run { actions.openInBrowser(item) } }
            }
            MenuItem(R.string.edit_tags, Icons.Outlined.Sell) { run { actions.editTags(listOf(item.id)) } }
            if (item.isPrivate) {
                MenuItem(R.string.remove_from_private, Icons.Default.LockOpen) { run { actions.setPrivate(false, listOf(item.id)) } }
            } else {
                MenuItem(R.string.move_to_private, Icons.Default.Lock) { run { actions.setPrivate(true, listOf(item.id)) } }
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                onClick = { run { actions.delete(listOf(item.id)) } },
            )
        }
    }
}

/** Open leads for links, with the Share menu next to it; image items, which have no link, get a single Share button. */
@Composable
private fun BottomBar(item: LibraryItem, vm: HomeViewModel, actions: ItemActions, imageReady: Boolean) {
    Column(
        modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        vm.copied?.let { copied ->
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
                Row(modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.ContentPaste, contentDescription = null, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        stringResource(if (copied == Copied.LINK) R.string.copied else R.string.link_copied),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        Row(modifier = Modifier.widthIn(max = 520.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (item.url != null) {
                Button(onClick = { actions.openInApp(item) }, modifier = Modifier.weight(1f)) {
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
                    Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                    Text(stringResource(R.string.open))
                }
                ShareMenu(item, actions, imageReady, Modifier.weight(1f))
            } else {
                Button(onClick = { actions.shareImage(item) }, enabled = imageReady, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
                    Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                    Text(stringResource(R.string.share))
                }
            }
        }
    }
}

/** Share Link, Copy Link and Share as Image, like the iOS Share menu. */
@Composable
private fun ShareMenu(item: LibraryItem, actions: ItemActions, imageReady: Boolean, modifier: Modifier) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        FilledTonalButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
            Spacer(Modifier.width(ButtonDefaults.IconSpacing))
            Text(stringResource(R.string.share))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            MenuItem(R.string.share_link, Icons.Default.Link) { expanded = false; actions.shareLink(item) }
            MenuItem(R.string.copy_link, Icons.Default.ContentCopy) { expanded = false; actions.copyLink(item) }
            MenuItem(R.string.share_as_image, Icons.Default.Image, enabled = imageReady) { expanded = false; actions.shareImage(item) }
        }
    }
}
