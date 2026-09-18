package com.picotabs.picotabs

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * The oldest "add to home screen" of all: a broadcast.
 *
 * An app that finds isRequestPinShortcutSupported false — or that predates the
 * modern API — sends this instead, and if nothing is listening the shortcut
 * simply evaporates. Launcher3 has carried a receiver for it for years, and it
 * costs nothing to keep one.
 *
 * It writes into the same place the pin path does, so a shortcut arriving this
 * way is collected the same way and needs no special case anywhere else.
 */
class InstallShortcutReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        @Suppress("DEPRECATION")
        val shortcutIntent =
            intent.getParcelableExtra<Intent>(Intent.EXTRA_SHORTCUT_INTENT) ?: return
        @Suppress("DEPRECATION")
        val label = intent.getStringExtra(Intent.EXTRA_SHORTCUT_NAME) ?: "Shortcut"
        @Suppress("DEPRECATION")
        val icon = intent.getParcelableExtra<Bitmap>(Intent.EXTRA_SHORTCUT_ICON)

        val prefs =
            context.getSharedPreferences("picotabs.shortcuts", Context.MODE_PRIVATE)
        val array = try {
            JSONArray(prefs.getString("pending", null) ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }
        array.put(
            JSONObject()
                .put("label", label)
                .put("packageName", "")
                .put("shortcutId", "")
                .put("intentUri", shortcutIntent.toUri(Intent.URI_INTENT_SCHEME))
                .put(
                    "icon",
                    icon?.let {
                        val stream = ByteArrayOutputStream()
                        it.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
                    } ?: ""
                )
        )
        prefs.edit()
            .putString("pending", array.toString())
            .putString("lastOutcome", "arrived by install-shortcut broadcast")
            .apply()
    }
}
