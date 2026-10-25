package com.yijiang.attention.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.SaveAlt
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yijiang.attention.R
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MakerScreen(vm: MakerViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val snackbar = remember { SnackbarHostState() }
    val entries by vm.history.entries.collectAsStateWithLifecycle()
    var showHistory by rememberSaveable { mutableStateOf(false) }
    var showStyle by rememberSaveable { mutableStateOf(false) }

    val linkCopied = stringResource(R.string.link_copied)
    val saved = stringResource(R.string.saved_to_gallery)
    val saveFailed = stringResource(R.string.save_failed)

    fun share() {
        val card = vm.card ?: return
        val meta = vm.meta ?: return
        Sharing.copyLink(context, meta.shareUrl.toString())
        scope.launch { snackbar.showSnackbar(linkCopied) }
        scope.launch { Sharing.shareCard(context, card, meta.listTitle) }
    }

    fun save() {
        val card = vm.card ?: return
        scope.launch { snackbar.showSnackbar(if (Sharing.saveToGallery(context, card)) saved else saveFailed) }
    }


    fun paste() {
        focusManager.clearFocus()
        vm.paste(Sharing.clipboardText(context))
    }

    fun generate() {
        focusManager.clearFocus()
        vm.make()
    }

    LaunchedEffect(vm.card) {
        if (vm.autoSharePending && vm.card != null) {
            vm.autoSharePending = false
            delay(300)
            share()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                actions = {
                    IconButton(onClick = { showHistory = true }) {
                        Icon(Icons.Default.History, contentDescription = stringResource(R.string.history))
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState()),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                modifier = Modifier.widthIn(max = 520.dp).fillMaxWidth().padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                val isEmpty = vm.meta == null && !vm.loading
                InputRow(vm, showsPaste = !isEmpty, onPaste = ::paste, onGo = ::generate)
                if (vm.showsGenerate) {
                    Button(onClick = ::generate, enabled = !vm.loading) { Text(stringResource(R.string.generate)) }
                }
                if (vm.loading) CircularProgressIndicator()
                vm.notice?.let {
                    Text(
                        stringResource(it),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (isEmpty) {
                    EmptyState(entries = entries, onPaste = ::paste, onOpen = vm::show)
                } else if (vm.meta != null) {
                    CardPane(vm, onShare = ::share, onStyle = { showStyle = true }, onSave = ::save)
                }
            }
        }
    }

    if (showHistory) {
        HistorySheet(
            entries = entries,
            onOpen = {
                vm.show(it)
                showHistory = false
            },
            onDelete = vm::removeFromHistory,
            onDismiss = { showHistory = false },
        )
    }
    if (showStyle) {
        StyleSheet(vm, onDismiss = { showStyle = false })
    }
}

@Composable
private fun InputRow(vm: MakerViewModel, showsPaste: Boolean, onPaste: () -> Unit, onGo: () -> Unit) {
    // A tap that focuses the field also moves the cursor, so select-all is re-applied on the first selection change.
    var selectAllPending by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = vm.input,
            onValueChange = { value ->
                val selectAll = selectAllPending && value.text == vm.input.text
                selectAllPending = false
                if (value.text != vm.input.text) vm.notice = null
                vm.input = if (selectAll) value.copy(selection = TextRange(0, value.text.length)) else value
            },
            placeholder = { Text(stringResource(R.string.paste_link)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go, autoCorrectEnabled = false),
            keyboardActions = KeyboardActions(onGo = { onGo() }),
            trailingIcon = if (vm.input.text.isNotEmpty()) {
                {
                    IconButton(onClick = { vm.input = vm.input.copy(text = "", selection = TextRange.Zero) }) {
                        Icon(Icons.Default.Cancel, contentDescription = stringResource(R.string.clear))
                    }
                }
            } else {
                null
            },
            modifier = Modifier
                .weight(1f)
                .onFocusChanged { state ->
                    if (state.isFocused && vm.input.text.isNotEmpty()) {
                        selectAllPending = true
                        vm.input = vm.input.copy(selection = TextRange(0, vm.input.text.length))
                    }
                },
        )
        if (showsPaste) {
            FilledTonalIconButton(onClick = onPaste) {
                Icon(Icons.Default.ContentPaste, contentDescription = stringResource(R.string.paste))
            }
        }
    }
}

@Composable
private fun CardPane(vm: MakerViewModel, onShare: () -> Unit, onStyle: () -> Unit, onSave: () -> Unit) {
    val card = vm.card
    val shape = RoundedCornerShape(16.dp)
    val aspect = vm.style.aspect
    val imageModifier = Modifier
        .fillMaxWidth()
        .aspectRatio(aspect.width.toFloat() / aspect.height)
        .shadow(4.dp, shape)
        .clip(shape)
    if (card != null) {
        val bitmap = remember(card) { card.asImageBitmap() }
        Image(
            bitmap,
            contentDescription = vm.meta?.listTitle ?: stringResource(R.string.card_preview),
            contentScale = ContentScale.Fit,
            modifier = imageModifier,
        )
    } else {
        Surface(modifier = imageModifier, color = MaterialTheme.colorScheme.surfaceContainer) {}
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Button(onClick = onShare, enabled = card != null, contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
            Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
            Spacer(Modifier.width(ButtonDefaults.IconSpacing))
            Text(stringResource(R.string.share))
        }
        FilledTonalButton(onClick = onSave, enabled = card != null, contentPadding = ButtonDefaults.ButtonWithIconContentPadding) {
            Icon(Icons.Default.SaveAlt, contentDescription = null, modifier = Modifier.size(ButtonDefaults.IconSize))
            Spacer(Modifier.width(ButtonDefaults.IconSpacing))
            Text(stringResource(R.string.save))
        }
        FilledTonalIconButton(onClick = onStyle) {
            Icon(Icons.Default.Tune, contentDescription = stringResource(R.string.style))
        }
    }
}
