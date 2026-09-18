package com.picotabs.picotabs

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream

/**
 * Home-screen widgets, hosted inside the launcher.
 *
 * A widget is not a picture of another app — it is another app's view, running
 * in this process's window. That means a real [AppWidgetHost], which has to be
 * listening for the widget to ever update, and an id per placement that
 * survives restarts and has to be handed back to the system when the placement
 * goes away. An id that is dropped without being deleted leaks a live widget
 * that nothing can see and nothing can remove.
 *
 * Binding needs permission the system only grants to the default launcher — or,
 * failing that, to whoever the user says yes to. Both paths are here: try
 * silently, and fall back to asking.
 */
class WidgetHost(private val activity: Activity) {

    // Any constant will do, but it has to *stay* the same: the host's ids are
    // scoped to it, so changing this orphans every widget already placed.
    private val hostId = 0x4D45 // "ME"

    private val manager: AppWidgetManager = AppWidgetManager.getInstance(activity)
    private val host = AppWidgetHost(activity, hostId)

    private var listening = false

    fun startListening() {
        if (listening) return
        try {
            host.startListening()
            listening = true
        } catch (e: Exception) {
            // A host that cannot listen still draws the last state it had,
            // which beats taking the launcher down with it.
        }
    }

    fun stopListening() {
        if (!listening) return
        try {
            host.stopListening()
        } catch (e: Exception) {
            // Nothing to do; the host is going away regardless.
        }
        listening = false
    }

    /** Every widget the phone can offer, for the launcher's own picker. */
    fun providers(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        for (info in manager.installedProviders) {
            val component = info.provider ?: continue
            out.add(
                mapOf(
                    "provider" to component.flattenToString(),
                    "packageName" to component.packageName,
                    "label" to providerLabel(info),
                    "minWidth" to toDp(info.minWidth),
                    "minHeight" to toDp(info.minHeight),
                    "resizeMode" to info.resizeMode,
                    "configurable" to (info.configure != null),
                    "preview" to previewOf(info)
                )
            )
        }
        out.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return out
    }

    /**
     * Reserves an id and binds it, or returns what still has to be asked.
     *
     * Never returns a bound id and a pending request at once: the caller acts
     * on exactly one of them.
     */
    fun allocate(providerName: String): Map<String, Any?> {
        val component = ComponentName.unflattenFromString(providerName)
            ?: return mapOf("error" to "bad provider")
        val id = host.allocateAppWidgetId()

        val bound = try {
            manager.bindAppWidgetIdIfAllowed(id, component)
        } catch (e: Exception) {
            false
        }

        if (!bound) {
            // Not a failure — the usual case for a launcher that is not the
            // default. The user is asked, and the answer comes back to
            // onActivityResult with this id attached.
            return mapOf("appWidgetId" to id, "needsPermission" to true)
        }
        return mapOf("appWidgetId" to id, "needsPermission" to false) + describe(id)
    }

    fun bindIntent(appWidgetId: Int, providerName: String): Intent {
        val component = ComponentName.unflattenFromString(providerName)
        return Intent(AppWidgetManager.ACTION_APPWIDGET_BIND).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, component)
        }
    }

    /** Whether the widget wants a setup screen before it is any use. */
    fun needsConfigure(appWidgetId: Int): Boolean =
        manager.getAppWidgetInfo(appWidgetId)?.configure != null

    fun startConfigure(appWidgetId: Int, requestCode: Int): Boolean {
        return try {
            host.startAppWidgetConfigureActivityForResult(
                activity, appWidgetId, 0, requestCode, null
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /** What a placed widget is, or null once the app behind it is gone. */
    fun describe(appWidgetId: Int): Map<String, Any?> {
        val info = manager.getAppWidgetInfo(appWidgetId)
            ?: return mapOf("missing" to true)
        return mapOf(
            "missing" to false,
            "provider" to (info.provider?.flattenToString() ?: ""),
            "packageName" to (info.provider?.packageName ?: ""),
            "label" to providerLabel(info),
            "minWidth" to toDp(info.minWidth),
            "minHeight" to toDp(info.minHeight),
            "resizeMode" to info.resizeMode
        )
    }

    /**
     * Hands the id back to the system.
     *
     * The one thing that must not be skipped: a placement removed without this
     * leaves a widget the user is still paying for and can no longer reach.
     */
    fun delete(appWidgetId: Int) {
        try {
            host.deleteAppWidgetId(appWidgetId)
        } catch (e: Exception) {
            // Already gone, which is the state we wanted.
        }
    }

    fun createView(context: Context, appWidgetId: Int): AppWidgetHostView? {
        val info = manager.getAppWidgetInfo(appWidgetId) ?: return null
        return try {
            host.createView(context, appWidgetId, info)
        } catch (e: Exception) {
            null
        }
    }

    fun resize(view: AppWidgetHostView, widthDp: Int, heightDp: Int) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                view.updateAppWidgetSize(
                    Bundle.EMPTY,
                    listOf(android.util.SizeF(widthDp.toFloat(), heightDp.toFloat()))
                )
            } else {
                @Suppress("DEPRECATION")
                view.updateAppWidgetSize(null, widthDp, heightDp, widthDp, heightDp)
            }
        } catch (e: Exception) {
            // A widget that will not take a size hint still draws at the size
            // its view is given.
        }
    }

    private fun providerLabel(info: AppWidgetProviderInfo): String {
        return try {
            info.loadLabel(activity.packageManager)
        } catch (e: Exception) {
            info.provider?.shortClassName ?: "Widget"
        }
    }

    private fun previewOf(info: AppWidgetProviderInfo): String? {
        val drawable: Drawable? = try {
            info.loadPreviewImage(activity, activity.resources.displayMetrics.densityDpi)
                ?: info.loadIcon(activity, activity.resources.displayMetrics.densityDpi)
        } catch (e: Exception) {
            null
        }
        val bitmap = rasterise(drawable ?: return null, 320) ?: return null
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
        return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
    }

    private fun rasterise(drawable: Drawable, maxSide: Int): Bitmap? {
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return it }
        }
        val width = drawable.intrinsicWidth.takeIf { it > 0 } ?: maxSide
        val height = drawable.intrinsicHeight.takeIf { it > 0 } ?: maxSide
        val scale = minOf(1f, maxSide.toFloat() / maxOf(width, height))
        val w = maxOf(1, (width * scale).toInt())
        val h = maxOf(1, (height * scale).toInt())
        return try {
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, w, h)
            drawable.draw(canvas)
            bitmap
        } catch (e: Exception) {
            null
        }
    }

    private fun toDp(px: Int): Int =
        (px / activity.resources.displayMetrics.density).toInt()
}

/**
 * Puts a hosted widget on screen inside the Flutter view.
 *
 * The host view is the real thing, so everything inside it stays interactive —
 * a widget you can only look at is a screenshot.
 */
class WidgetViewFactory(private val hostOf: () -> WidgetHost?) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val appWidgetId = (params?.get("appWidgetId") as? Number)?.toInt() ?: -1
        val widthDp = (params?.get("width") as? Number)?.toInt() ?: 0
        val heightDp = (params?.get("height") as? Number)?.toInt() ?: 0
        return HostedWidget(context, hostOf(), appWidgetId, widthDp, heightDp)
    }
}

private class HostedWidget(
    context: Context,
    host: WidgetHost?,
    appWidgetId: Int,
    widthDp: Int,
    heightDp: Int
) : PlatformView {

    private val view: View

    init {
        val hosted = if (appWidgetId >= 0) host?.createView(context, appWidgetId) else null
        if (hosted != null) {
            hosted.layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            if (widthDp > 0 && heightDp > 0) host?.resize(hosted, widthDp, heightDp)
            view = hosted
        } else {
            // An empty view rather than nothing: the placement still exists and
            // Flutter draws its own "this widget is gone" over the top.
            view = View(context)
        }
    }

    override fun getView(): View = view

    override fun dispose() {
        // The host owns the view and the id; the id is only released when the
        // placement is actually removed, not when it scrolls out of sight.
    }
}
