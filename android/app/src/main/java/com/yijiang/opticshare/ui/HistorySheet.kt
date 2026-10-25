package com.yijiang.opticshare.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yijiang.opticshare.R
import com.yijiang.opticshare.data.HistoryEntry

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistorySheet(
    entries: List<HistoryEntry>,
    onOpen: (HistoryEntry) -> Unit,
    onDelete: (HistoryEntry) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text(
            stringResource(R.string.history),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
        )
        if (entries.isEmpty()) {
            Text(
                stringResource(R.string.history_empty),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp),
            )
            return@ModalBottomSheet
        }
        LazyColumn(modifier = Modifier.padding(bottom = 16.dp)) {
            items(entries, key = { it.id }) { entry ->
                ListItem(
                    headlineContent = { Text(entry.meta.listTitle, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                    supportingContent = { Text("${entry.meta.site} · ${entry.relativeDate()}", maxLines = 1) },
                    leadingContent = { FaviconView(entry.meta, size = 36.dp) },
                    trailingContent = {
                        IconButton(onClick = { onDelete(entry) }) {
                            Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.delete))
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                    modifier = Modifier.clickable { onOpen(entry) },
                )
            }
        }
    }
}
