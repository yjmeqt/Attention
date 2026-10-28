package com.yijiang.attention.ui

import androidx.annotation.StringRes
import com.yijiang.attention.R
import com.yijiang.attention.model.CardTemplate

@get:StringRes
val CardTemplate.labelRes: Int
    get() = when (this) {
        CardTemplate.AUTO -> R.string.template_auto
        CardTemplate.TILE -> R.string.template_tile
        CardTemplate.MINIMAL -> R.string.template_minimal
        CardTemplate.QR -> R.string.template_qr
    }
