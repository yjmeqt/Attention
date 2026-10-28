package com.yijiang.attention

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.content.IntentCompat
import com.yijiang.attention.ui.AttentionTheme
import com.yijiang.attention.ui.HomeScreen
import com.yijiang.attention.ui.HomeViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: HomeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) receive(intent)
        setContent {
            AttentionTheme {
                HomeScreen(viewModel)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    /** A link or image shared from another app is saved right away and opened, like the iOS share extension. */
    private fun receive(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val image = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            ?.takeIf { intent.type?.startsWith("image/") == true }
        if (text != null || image != null) viewModel.receive(text, image)
    }
}
