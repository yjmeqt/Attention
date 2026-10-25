package com.yijiang.opticshare

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.yijiang.opticshare.ui.MakerScreen
import com.yijiang.opticshare.ui.MakerViewModel
import com.yijiang.opticshare.ui.OpticShareTheme

class MainActivity : ComponentActivity() {
    private val viewModel: MakerViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) receive(intent)
        setContent {
            OpticShareTheme {
                MakerScreen(viewModel)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    private fun receive(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND) return
        intent.getStringExtra(Intent.EXTRA_TEXT)?.let(viewModel::receiveShared)
    }
}
