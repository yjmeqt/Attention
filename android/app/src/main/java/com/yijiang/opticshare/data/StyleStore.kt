package com.yijiang.opticshare.data

import android.content.Context
import androidx.core.content.edit
import com.yijiang.opticshare.model.CardAspect
import com.yijiang.opticshare.model.CardStyle
import com.yijiang.opticshare.model.CardTemplate

class StyleStore(context: Context) {
    private val prefs = context.getSharedPreferences("card_style", Context.MODE_PRIVATE)

    fun load(): CardStyle = CardStyle(
        template = enumOrNull<CardTemplate>(prefs.getString(TEMPLATE, null)) ?: CardTemplate.AUTO,
        aspect = enumOrNull<CardAspect>(prefs.getString(ASPECT, null)) ?: CardAspect.PORTRAIT,
    )

    fun save(style: CardStyle) = prefs.edit {
        putString(TEMPLATE, style.template.name)
        putString(ASPECT, style.aspect.name)
    }

    private inline fun <reified T : Enum<T>> enumOrNull(name: String?): T? =
        enumValues<T>().firstOrNull { it.name == name }

    private companion object {
        const val TEMPLATE = "template"
        const val ASPECT = "aspect"
    }
}
