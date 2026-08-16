package dev.wndavenz.music.replaygain

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentResolver
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log

/**
 * Resolves scoped-storage write access to MediaStore-owned audio files
 * before any native tag write is attempted. Mirrors the createDeleteRequest
 * / RecoverableSecurityException dance MainActivity already uses for
 * `deleteSong` (see its comments for the full API-level matrix) — this
 * class is the write-side equivalent, kept separate so ReplayGainBridge only
 * ever sees a plain granted/denied callback.
 *
 * One system permission dialog per distinct file the app doesn't already
 * own is unavoidable on Android 10+ for a file it doesn't own; that grant
 * then lets the actual write happen through a normal
 * `ContentResolver.openFileDescriptor(uri, "rw")` call, no different from a
 * file the app already owned.
 *
 * Two entry points:
 * - [ensureWriteAccess] — single file, single dialog if needed.
 * - [ensureWriteAccessBatch] — many files, **one** dialog for the whole
 *   batch on Android 11+ (API 30+) via a single
 *   `MediaStore.createWriteRequest(resolver, uris)` grant covering every
 *   URI at once. A batch of exactly one file behaves identically to
 *   [ensureWriteAccess] (no change from prior behavior). On Android 10
 *   (API 29), `createWriteRequest` does not exist — there is no OS API to
 *   collapse multiple grants into one dialog on that version, so this
 *   falls back to resolving each file that still needs a grant one at a
 *   time (one dialog per file, same as this class's original behavior).
 *   Never requests `WRITE_EXTERNAL_STORAGE` or `MANAGE_EXTERNAL_STORAGE`.
 *
 * Both entry points funnel through [queue]: Android can only meaningfully
 * show one `startIntentSenderForResult` grant dialog at a time for our
 * single [REQUEST_CODE], so concurrent callers must NOT each fire their own
 * `startIntentSenderForResult` in parallel — a second call while the first
 * dialog is still pending would silently replace it, orphaning the first
 * caller's callback forever (this was a real bug: the batch "write tags"
 * library scan used to request access for 2 songs concurrently, and the
 * second request's dialog silently orphaned the first song's callback,
 * hanging its `writeReplayGain` result forever). Every request that needs a
 * dialog is queued and only the head of the queue has a dialog in flight at
 * any time; the next queued request starts only after the current one
 * resolves.
 */
class MediaStoreWriteGate {

    /** One entry in [queue] — either a single-file or whole-batch request. */
    private sealed class QueueItem {
        abstract val activity: Activity
        data class Single(
            override val activity: Activity,
            val uri: Uri,
            val onResult: (Boolean) -> Unit,
        ) : QueueItem()
        data class Batch(
            override val activity: Activity,
            val uris: List<Uri>,
            val onResult: (Map<Uri, Boolean>) -> Unit,
        ) : QueueItem()
    }

    // Callback for whichever request currently has a system dialog in
    // flight (resolved from handleActivityResult). Only ever one at a time.
    private var pendingCallback: ((Boolean) -> Unit)? = null

    // Requests waiting for their turn to (re-)check access / show a dialog.
    // Not accessed off the main thread — every public entry point plus
    // handleActivityResult are all required to run on the main thread already.
    private val queue = ArrayDeque<QueueItem>()

    // True while a request is between "dialog launched" and "activity result
    // handled" — guards against draining the queue while one is in flight.
    private var dialogInFlight = false

    companion object {
        const val REQUEST_CODE = 0x5752  // 'WR' — arbitrary unique code
        private const val TAG = "MediaStoreWriteGate"
    }

    private sealed class OpenAttempt {
        object Granted : OpenAttempt()
        data class NeedsAction(val intentSender: IntentSender) : OpenAttempt()
        object Denied : OpenAttempt()
    }

    /**
     * Ensures the app can open [uri] for writing, requesting a system grant
     * if a direct open fails. [onResult] is always invoked exactly once
     * with true only once an actual open-for-write attempt has succeeded
     * (not merely "the dialog said OK") — false covers user decline, a
     * failed grant request, or (pre-API 30 with a non-recoverable denial)
     * no available recovery path at all.
     *
     * Safe to call concurrently for different [uri]s (e.g. from parallel
     * batch operations) — requests needing a dialog are queued and
     * processed one at a time; see the class doc for why. Prefer
     * [ensureWriteAccessBatch] when the full set of target files is known
     * up front, so the user only sees one dialog instead of one per file.
     *
     * Must be called on the main thread; [onResult] is also invoked on the
     * main thread (either synchronously, for the already-granted case, or
     * from [handleActivityResult]).
     */
    fun ensureWriteAccess(activity: Activity, uri: Uri, onResult: (Boolean) -> Unit) {
        queue.addLast(QueueItem.Single(activity, uri, onResult))
        drainQueue()
    }

    /**
     * Batch variant of [ensureWriteAccess]: requests write access for every
     * entry in [uris] with **at most one system permission dialog** for the
     * whole batch, then invokes [onResult] with a map from each input URI to
     * whether it is now writable — no further dialogs are shown while
     * processing files that were already covered by that one grant.
     *
     * - 0 or 1 URIs: delegates straight to [ensureWriteAccess] (unchanged
     *   single-file behavior).
     * - 2+ URIs on Android 11+ (API 30+): files already writable are
     *   resolved immediately with no dialog; the rest are requested in a
     *   single `MediaStore.createWriteRequest(resolver, uris)` call, which
     *   shows exactly one confirmation dialog covering all of them — the
     *   user either grants every file in the batch or none of them.
     * - 2+ URIs on Android 10 (API 29): `createWriteRequest` isn't
     *   available on this API level (added in 30), so there is no OS-level
     *   way to merge multiple grants into a single dialog. Falls back to
     *   resolving each file that still needs a grant one at a time (still
     *   serialized through [queue], so at most one dialog is ever on screen
     *   simultaneously — just not collapsed into one for the whole batch,
     *   which the platform does not support pre-30).
     *
     * Never requests `WRITE_EXTERNAL_STORAGE` or `MANAGE_EXTERNAL_STORAGE`.
     *
     * Must be called on the main thread; [onResult] is invoked on the main
     * thread once every file in [uris] has been resolved.
     */
    fun ensureWriteAccessBatch(
        activity: Activity,
        uris: List<Uri>,
        onResult: (Map<Uri, Boolean>) -> Unit,
    ) {
        if (uris.isEmpty()) {
            onResult(emptyMap())
            return
        }
        if (uris.size == 1) {
            val uri = uris[0]
            ensureWriteAccess(activity, uri) { granted -> onResult(mapOf(uri to granted)) }
            return
        }
        queue.addLast(QueueItem.Batch(activity, uris.distinct(), onResult))
        drainQueue()
    }

    /** Starts the next queued request's dialog if none is currently in flight. */
    private fun drainQueue() {
        if (dialogInFlight) return
        when (val next = queue.removeFirstOrNull() ?: return) {
            is QueueItem.Single -> {
                resolveSingleUri(next.activity, next.uri) { granted ->
                    next.onResult(granted)
                    drainQueue()
                }
            }
            is QueueItem.Batch -> drainBatch(next)
        }
    }

    private fun drainBatch(item: QueueItem.Batch) {
        val resolver = item.activity.contentResolver
        val alreadyGranted = item.uris.filter { tryOpenForWrite(resolver, it) is OpenAttempt.Granted }.toSet()
        val stillNeeded = item.uris.filterNot { it in alreadyGranted }

        if (stillNeeded.isEmpty()) {
            item.onResult(item.uris.associateWith { true })
            drainQueue()
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Single dialog covering every still-needed URI at once.
            try {
                val pi = MediaStore.createWriteRequest(resolver, stillNeeded)
                requestGrantForUris(item.activity, resolver, stillNeeded, pi.intentSender) { granted ->
                    item.onResult(item.uris.associateWith { it in alreadyGranted || granted })
                    drainQueue()
                }
            } catch (e: Exception) {
                Log.w(TAG, "createWriteRequest (batch, ${stillNeeded.size} files) failed", e)
                item.onResult(item.uris.associateWith { it in alreadyGranted })
                drainQueue()
            }
        } else {
            // No batch grant API pre-API 30 — resolve sequentially, one
            // dialog per file that still needs one. Still only ever one
            // dialog on screen at a time (dialogInFlight is shared), just
            // not collapsed into a single dialog for the whole batch.
            resolveLegacyBatch(item.activity, resolver, stillNeeded) { legacyResults ->
                item.onResult(item.uris.associateWith { uri ->
                    alreadyGranted.contains(uri) || legacyResults[uri] == true
                })
                drainQueue()
            }
        }
    }

    /** Resolves [uris] one at a time, each via [resolveSingleUri], in order. */
    private fun resolveLegacyBatch(
        activity: Activity,
        resolver: ContentResolver,
        uris: List<Uri>,
        onDone: (Map<Uri, Boolean>) -> Unit,
    ) {
        if (uris.isEmpty()) {
            onDone(emptyMap())
            return
        }
        val results = LinkedHashMap<Uri, Boolean>()
        fun step(index: Int) {
            if (index >= uris.size) {
                onDone(results)
                return
            }
            resolveSingleUri(activity, uris[index]) { granted ->
                results[uris[index]] = granted
                step(index + 1)
            }
        }
        step(0)
    }

    /**
     * Resolves a single [uri]: immediate success if already writable,
     * otherwise requests whichever grant path applies (recoverable
     * exception intent, or `createWriteRequest` for a single URI) and shows
     * its dialog right away. Does NOT itself consult [queue] / [dialogInFlight]
     * beyond what [requestGrantForUris] already guards — callers are
     * responsible for only invoking this when it's actually this request's
     * turn (i.e. from [drainQueue] or [resolveLegacyBatch]'s sequential step).
     */
    private fun resolveSingleUri(activity: Activity, uri: Uri, onResult: (Boolean) -> Unit) {
        val resolver = activity.contentResolver
        when (val attempt = tryOpenForWrite(resolver, uri)) {
            is OpenAttempt.Granted -> onResult(true)
            is OpenAttempt.NeedsAction ->
                requestGrantForUris(activity, resolver, listOf(uri), attempt.intentSender, onResult)
            is OpenAttempt.Denied -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val pi = MediaStore.createWriteRequest(resolver, listOf(uri))
                        requestGrantForUris(activity, resolver, listOf(uri), pi.intentSender, onResult)
                    } catch (e: Exception) {
                        Log.w(TAG, "createWriteRequest failed for $uri", e)
                        onResult(false)
                    }
                } else {
                    // API 29 with a non-recoverable denial (e.g. file genuinely
                    // owned by another app with no grant path) — nothing more
                    // we can do short of MANAGE_EXTERNAL_STORAGE, which this
                    // app deliberately doesn't request.
                    onResult(false)
                }
            }
        }
    }

    /**
     * Launches the system dialog for [intentSender] covering [uris] (one
     * URI for a single-file request, many for a batch grant). [onResult]
     * fires once with true only if the dialog was accepted AND every URI in
     * [uris] is now actually openable for write. Does not itself drain
     * [queue] — callers own that, since batch/single/legacy-batch callers
     * each need to do different bookkeeping with the result first.
     */
    private fun requestGrantForUris(
        activity: Activity,
        resolver: ContentResolver,
        uris: List<Uri>,
        intentSender: IntentSender,
        onResult: (Boolean) -> Unit,
    ) {
        dialogInFlight = true
        pendingCallback = { granted ->
            dialogInFlight = false
            onResult(granted && uris.all { tryOpenForWrite(resolver, it) is OpenAttempt.Granted })
        }
        try {
            activity.startIntentSenderForResult(intentSender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            Log.w(TAG, "startIntentSenderForResult failed for ${uris.size} uri(s)", e)
            dialogInFlight = false
            pendingCallback = null
            onResult(false)
        }
    }

    /**
     * Call from `Activity.onActivityResult`. Returns true if this gate
     * handled the given [requestCode] (caller should not process it
     * further); false otherwise.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val cb = pendingCallback
        pendingCallback = null
        cb?.invoke(resultCode == Activity.RESULT_OK)
        return true
    }

    /**
     * K6 fix: resolves every outstanding grant request as denied. Called from
     * `Activity.onDestroy` — without this, callers (ReplayGain write/remove
     * channel requests) queued behind a system dialog would wait forever for
     * an `onActivityResult` that will never arrive, leaving their
     * MethodChannel results (and the awaiting Dart futures) hanging.
     */
    fun failPending() {
        val cb = pendingCallback
        pendingCallback = null
        dialogInFlight = false
        cb?.invoke(false)
        while (true) {
            when (val item = queue.removeFirstOrNull() ?: break) {
                is QueueItem.Single -> item.onResult(false)
                is QueueItem.Batch -> item.onResult(item.uris.associateWith { false })
            }
        }
    }

    private fun tryOpenForWrite(resolver: ContentResolver, uri: Uri): OpenAttempt {
        return try {
            resolver.openFileDescriptor(uri, "rw")?.use { OpenAttempt.Granted } ?: OpenAttempt.Denied
        } catch (e: RecoverableSecurityException) {
            OpenAttempt.NeedsAction(e.userAction.actionIntent.intentSender)
        } catch (e: SecurityException) {
            OpenAttempt.Denied
        } catch (e: Exception) {
            Log.w(TAG, "openFileDescriptor(rw) failed for $uri", e)
            OpenAttempt.Denied
        }
    }
}
