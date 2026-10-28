package com.yijiang.attention.data

import android.content.Context
import androidx.core.content.edit
import com.yijiang.attention.model.CardStyle
import com.yijiang.attention.model.CardTemplate

class StyleStore(context: Context) {
    private val prefs = context.getSharedPreferences("card_style", Context.MODE_PRIVATE)

    /** An old `aspect` key is ignored. */
    fun load(): CardStyle = CardStyle(template = CardTemplate.named(prefs.getString(TEMPLATE, null)))

    fun save(style: CardStyle) = prefs.edit {
        putString(TEMPLATE, style.template.name)
        remove(ASPECT)
    }

    private companion object {
        const val TEMPLATE = "template"
        const val ASPECT = "aspect"
    }
}
