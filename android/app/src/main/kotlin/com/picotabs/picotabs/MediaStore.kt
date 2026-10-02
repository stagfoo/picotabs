package com.picotabs.picotabs

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File

/**
 * The pictures this launcher has been given: tile images, custom app icons and
 * tab backgrounds.
 *
 * Copied into the app's own storage rather than referenced where they were
 * picked. The picker grants access to one URI, and the app that owns it may
 * revoke it, move the file or be uninstalled - a launcher whose home screen goes
 * blank because a gallery app was updated is not one worth having.
 */
class MediaStore(private val dir: File, private val resolver: ContentResolver) {

    /**
     * An animated file is stored byte for byte; anything else is scaled down.
     *
     * This is the whole reason the store is not just "decode and re-encode".
     * Decoding a GIF yields its first frame, so re-encoding one - which is what
     * the card-image code this replaces did - silently turns every animation
     * into a still, and nothing about the result says it used to move.
     *
     * Verbatim copies are capped rather than scaled, because there is no way to
     * resize an animation with BitmapFactory and a launcher does not need one
     * badly enough to carry a decoder that can.
     */
    fun store(mediaId: String, uri: Uri): String? {
        val file = fileFor(mediaId)
        return try {
            val head = ByteArray(headBytes)
            val read = resolver.openInputStream(uri)?.use { it.read(head) } ?: return null
            val animated = read > 0 && isAnimated(head, read)

            if (animated) {
                val size = resolver.openInputStream(uri)?.use { input ->
                    file.outputStream().use { output -> input.copyTo(output) }
                } ?: return null
                // A home screen redrawing a 40MB GIF every frame is a flat
                // battery, so one that large is refused outright rather than
                // stored and blamed later.
                if (size > maxAnimatedBytes) {
                    file.delete()
                    return null
                }
                file.absolutePath
            } else {
                storeScaled(file, uri)
            }
        } catch (e: Throwable) {
            file.delete()
            null
        }
    }

    /**
     * GIF, animated WebP, or APNG.
     *
     * Read from the file's own bytes rather than from the MIME type the picker
     * reports: that type comes from the providing app and is routinely wrong, or
     * just the generic image wildcard, and being wrong here means a flattened
     * animation.
     *
     * (Written without the literal wildcard on purpose: Kotlin block comments
     * nest, so a slash-star inside one opens a comment that never closes.)
     */
    private fun isAnimated(head: ByteArray, length: Int): Boolean {
        // ISO_8859_1 maps every byte to one character, so byte offsets and
        // character offsets stay the same - which UTF-8 would not do on the
        // high bytes an image header is full of.
        val text = String(head, 0, length, Charsets.ISO_8859_1)

        // Every GIF is treated as animated. A still one costs only the scaling
        // it does not get, where a wrongly flattened animation cannot be undone.
        if (text.startsWith("GIF87a") || text.startsWith("GIF89a")) return true

        // RIFF....WEBP, then VP8X: the extended form, the only one that can
        // carry animation.
        if (text.startsWith("RIFF") && length >= 16 &&
            text.regionMatches(8, "WEBP", 0, 4)
        ) {
            return text.regionMatches(12, "VP8X", 0, 4)
        }

        // APNG is a PNG carrying an acTL chunk. The signature's first byte is
        // 0x89, so the readable part starts at offset 1, and acTL sits after the
        // 8-byte signature and the IHDR chunk - past offset 37, which is why
        // this reads more than a bare signature's worth of bytes.
        if (length > 4 && head[0] == 0x89.toByte() &&
            text.regionMatches(1, "PNG", 0, 3)
        ) {
            return text.contains("acTL")
        }
        return false
    }

    private fun storeScaled(file: File, uri: Uri): String? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }

        var sample = 1
        while (bounds.outWidth / sample > target * 2) sample *= 2

        val decoded = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(
                it,
                null,
                BitmapFactory.Options().apply { inSampleSize = sample }
            )
        } ?: return null

        val scale = target.toFloat() / maxOf(decoded.width, decoded.height)
        val bitmap = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt().coerceAtLeast(1),
                (decoded.height * scale).toInt().coerceAtLeast(1),
                true
            )
        } else {
            decoded
        }

        // PNG, not JPEG: an icon or a tile image is as likely to have a
        // transparent background as not, and JPEG would fill it with black.
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return file.absolutePath
    }

    /**
     * Every stored picture, by id.
     *
     * Read off disk rather than remembered, so a picture that arrived while the
     * launcher was destroyed - which can happen, the picker is another app - is
     * found the next time anyone looks.
     */
    fun all(): Map<String, String> {
        val files = dir.listFiles() ?: return emptyMap()
        return files.filter { it.isFile }.associate { it.name to it.absolutePath }
    }

    fun remove(mediaId: String) {
        fileFor(mediaId).delete()
    }

    /**
     * Deletes every stored picture not in [keep].
     *
     * Media outlive the tiles that referenced them - a tile deleted, an icon
     * replaced - and nothing else removes those files, so without this the store
     * only ever grows.
     */
    fun reap(keep: Set<String>) {
        val files = dir.listFiles() ?: return
        for (file in files) {
            if (file.isFile && file.name !in keep) file.delete()
        }
    }

    /**
     * One file per id, with the id sanitised rather than trusted.
     *
     * The id arrives from stored JSON, and a "../" in one would otherwise write
     * wherever it pointed.
     */
    private fun fileFor(mediaId: String): File =
        File(dir, mediaId.replace(Regex("[^A-Za-z0-9_-]"), "_"))

    private companion object {
        const val target = 1080
        const val maxAnimatedBytes = 12L * 1024 * 1024

        /** Enough to reach a PNG's first chunk type, where acTL would be. */
        const val headBytes = 64
    }
}
