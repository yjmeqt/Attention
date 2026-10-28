package com.yijiang.attention.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager.Authenticators
import android.hardware.biometrics.BiometricPrompt
import android.net.Uri
import android.os.CancellationSignal
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.getSystemService
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

object Opening {
    /** In an in-app browser tab, like the iOS app's Safari view. */
    fun openInBrowser(context: Context, url: String) {
        runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url)) }
            .onFailure { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }

    /** In the app that claims the link (YouTube, Bilibili…), or the browser when none does. */
    fun openInApp(context: Context, url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            openInBrowser(context, url)
        }
    }
}

object DeviceOwner {
    enum class Outcome { AUTHENTICATED, FAILED, UNAVAILABLE }

    private const val AUTHENTICATORS = Authenticators.BIOMETRIC_WEAK or Authenticators.DEVICE_CREDENTIAL

    /** Fingerprint or face, with the screen lock as fallback. */
    suspend fun authenticate(activity: Activity, reason: String): Outcome {
        val manager = activity.getSystemService<android.hardware.biometrics.BiometricManager>()
        if (manager?.canAuthenticate(AUTHENTICATORS) != android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS) {
            return Outcome.UNAVAILABLE
        }
        val prompt = BiometricPrompt.Builder(activity)
            .setTitle(reason)
            .setAllowedAuthenticators(AUTHENTICATORS)
            .build()
        return suspendCancellableCoroutine { continuation ->
            val cancel = CancellationSignal()
            continuation.invokeOnCancellation { cancel.cancel() }
            prompt.authenticate(cancel, activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (continuation.isActive) continuation.resume(Outcome.AUTHENTICATED)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (continuation.isActive) continuation.resume(Outcome.FAILED)
                }
            })
        }
    }
}
