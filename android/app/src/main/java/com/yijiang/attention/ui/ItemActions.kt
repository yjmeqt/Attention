package com.yijiang.attention.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.yijiang.attention.R
import com.yijiang.attention.data.LibraryItem
import com.yijiang.attention.data.LibraryRules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Actions on a saved item, shared by the feed's long-press menu, select mode and the detail page. */
class ItemActions(private val context: Context, val vm: HomeViewModel, private val scope: CoroutineScope) {
    private val activity: Activity? = context.findActivity()

    fun shareLink(item: LibraryItem) {
        val url = vm.shareUrl(item) ?: return
        Sharing.shareLink(context, url, item.displayTitle)
    }

    fun copyLink(item: LibraryItem) {
        val url = vm.shareUrl(item) ?: return
        Sharing.copyLink(context, url)
        vm.copied = Copied.LINK
        if (vm.openId == null) vm.show(R.string.copied)
    }

    /** The card image to the share sheet, with the link on the clipboard to paste after it. */
    fun shareImage(item: LibraryItem) {
        scope.launch {
            val image = withContext(Dispatchers.Default) { vm.library.fullImage(item) } ?: return@launch
            vm.shareUrl(item)?.let {
                Sharing.copyLink(context, it)
                vm.copied = Copied.LINK_FOR_IMAGE
                if (vm.openId == null) vm.show(R.string.link_copied)
            }
            Sharing.shareCard(context, image, item.displayTitle)
        }
    }

    fun openInBrowser(item: LibraryItem) = item.url?.let { Opening.openInBrowser(context, it) }

    fun openInApp(item: LibraryItem) = item.url?.let { Opening.openInApp(context, it) }

    fun editTags(ids: List<String>) {
        vm.tagTargets = ids
    }

    /** Taking items out of Private asks for the device owner, unless Private is already unlocked. */
    fun setPrivate(isPrivate: Boolean, ids: List<String>) {
        if (isPrivate || vm.filter.privateUnlocked) return vm.setPrivate(isPrivate, ids)
        val activity = activity ?: return
        scope.launch {
            when (DeviceOwner.authenticate(activity, context.getString(R.string.remove_items_from_private))) {
                DeviceOwner.Outcome.AUTHENTICATED -> vm.setPrivate(false, ids)
                DeviceOwner.Outcome.FAILED -> Unit
                DeviceOwner.Outcome.UNAVAILABLE -> vm.showsPasscodeRequired = true
            }
        }
    }

    fun unlockPrivate() {
        val activity = activity ?: return
        scope.launch {
            when (DeviceOwner.authenticate(activity, context.getString(R.string.show_private_items))) {
                DeviceOwner.Outcome.AUTHENTICATED -> vm.unlockPrivate()
                DeviceOwner.Outcome.FAILED -> Unit
                DeviceOwner.Outcome.UNAVAILABLE -> vm.showsPasscodeRequired = true
            }
        }
    }

    fun setArchived(isArchived: Boolean, ids: List<String>) = vm.setArchived(isArchived, ids)

    fun delete(ids: List<String>) {
        vm.pendingDelete = ids
    }
}

@Composable
fun rememberItemActions(vm: HomeViewModel): ItemActions {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    return remember(context, vm, scope) { ItemActions(context, vm, scope) }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** The long-press menu of a feed tile, in the same order as the iOS context menu. */
@Composable
fun ItemMenuItems(item: LibraryItem, actions: ItemActions, onSelect: (() -> Unit)?, dismiss: () -> Unit) {
    val vm = actions.vm
    fun run(action: () -> Unit) {
        dismiss()
        action()
    }
    if (item.url != null) {
        MenuItem(R.string.open_in_app, Icons.AutoMirrored.Filled.OpenInNew) { run { actions.openInApp(item) } }
        MenuItem(R.string.open_in_browser, Icons.Default.Public) { run { actions.openInBrowser(item) } }
        HorizontalDivider()
        MenuItem(R.string.share_link, Icons.Default.Link) { run { actions.shareLink(item) } }
        MenuItem(R.string.copy_link, Icons.Default.ContentCopy) { run { actions.copyLink(item) } }
    }
    MenuItem(R.string.share_as_image, Icons.Default.Image) { run { actions.shareImage(item) } }
    HorizontalDivider()
    DropdownMenuItem(
        text = { Text(stringResource(R.string.only, domainLabel(item.domain))) },
        leadingIcon = { Icon(Icons.Default.FilterList, contentDescription = null) },
        onClick = { run { vm.filter = vm.filter.onlyDomain(item.domain) } },
    )
    for (tag in item.tags) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.only, "#$tag")) },
            leadingIcon = { Icon(Icons.Default.FilterList, contentDescription = null) },
            onClick = { run { vm.filter = vm.filter.onlyTag(tag) } },
        )
    }
    HorizontalDivider()
    MenuItem(R.string.edit_tags, Icons.Outlined.Sell) { run { actions.editTags(listOf(item.id)) } }
    if (item.isPrivate) {
        MenuItem(R.string.remove_from_private, Icons.Default.LockOpen) { run { actions.setPrivate(false, listOf(item.id)) } }
    } else {
        MenuItem(R.string.move_to_private, Icons.Default.Lock) { run { actions.setPrivate(true, listOf(item.id)) } }
    }
    if (onSelect != null) MenuItem(R.string.select, Icons.Default.CheckCircle) { run(onSelect) }
    HorizontalDivider()
    if (item.isArchived) {
        MenuItem(R.string.unarchive, Icons.Default.Unarchive) { run { actions.setArchived(false, listOf(item.id)) } }
    } else {
        MenuItem(R.string.archive, Icons.Default.Archive) { run { actions.setArchived(true, listOf(item.id)) } }
    }
    DropdownMenuItem(
        text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
        leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
        onClick = { run { actions.delete(listOf(item.id)) } },
    )
}

@Composable
fun MenuItem(text: Int, icon: ImageVector, enabled: Boolean = true, onClick: () -> Unit) =
    MenuItem(stringResource(text), icon, enabled, onClick)

@Composable
fun MenuItem(text: String, icon: ImageVector, enabled: Boolean = true, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        enabled = enabled,
        onClick = onClick,
    )
}

/** The tag editor, delete confirmation and passcode alert that [ItemActions] opens. */
@Composable
fun ItemActionPresentations(vm: HomeViewModel) {
    vm.tagTargets?.let { targets -> TagEditor(vm, targets, onDismiss = { vm.tagTargets = null }) }
    vm.pendingDelete?.let { ids ->
        AlertDialog(
            onDismissRequest = { vm.pendingDelete = null },
            title = {
                Text(if (ids.size == 1) stringResource(R.string.delete_one) else pluralStringResource(R.plurals.delete_many, ids.size, ids.size))
            },
            confirmButton = {
                TextButton(onClick = vm::confirmDelete) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { vm.pendingDelete = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (vm.showsPasscodeRequired) {
        AlertDialog(
            onDismissRequest = { vm.showsPasscodeRequired = false },
            title = { Text(stringResource(R.string.passcode_required_title)) },
            text = { Text(stringResource(R.string.passcode_required_body)) },
            confirmButton = { TextButton(onClick = { vm.showsPasscodeRequired = false }) { Text(stringResource(android.R.string.ok)) } },
        )
    }
}

/** Adds or removes manual tags on one or more items. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TagEditor(vm: HomeViewModel, ids: List<String>, onDismiss: () -> Unit) {
    val items by vm.library.items.collectAsState()
    val targets = items.filter { it.id in ids }
    var newTag by rememberSaveable { mutableStateOf("") }
    fun add() {
        vm.addTag(newTag, ids)
        newTag = ""
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text(
            if (ids.size == 1) stringResource(R.string.tags) else pluralStringResource(R.plurals.tag_items, ids.size, ids.size),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = newTag,
                onValueChange = { newTag = it },
                placeholder = { Text(stringResource(R.string.new_tag)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }),
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = ::add, enabled = LibraryRules.normalizedTag(newTag).isNotEmpty()) { Text(stringResource(R.string.add)) }
        }
        val tags = LibraryRules.ranked(items.flatMap { it.tags })
        LazyColumn(modifier = Modifier.padding(bottom = 24.dp)) {
            items(tags, key = { it }) { tag ->
                val count = targets.count { tag in it.tags }
                val all = count == targets.size && count > 0
                ListItem(
                    headlineContent = { Text("#$tag") },
                    leadingContent = { Icon(Icons.Outlined.Sell, contentDescription = null) },
                    trailingContent = {
                        when {
                            all -> Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            count > 0 -> Icon(Icons.Default.Remove, contentDescription = null)
                        }
                    },
                    modifier = Modifier.clickable { if (all) vm.removeTag(tag, ids) else vm.addTag(tag, ids) },
                )
            }
        }
    }
}
