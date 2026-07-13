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
 * Resolves scoped-storage write access to a MediaStore-owned audio file
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
 * Requests are serialized through [queue]: Android can only meaningfully
 * show one `startIntentSenderForResult` grant dialog at a time for our
 * single [REQUEST_CODE], so concurrent callers (e.g. the batch "write tags"
 * library scan, which scans/writes 2 songs at a time) must NOT each fire
 * their own `startIntentSenderForResult` in parallel — a second call while
 * the first dialog is still pending would silently replace it, orphaning
 * the first caller's callback forever (root cause of a permanent hang: the
 * first song's `writeReplayGain` MethodChannel result would never be
 * resolved). Every [ensureWriteAccess] call that needs a dialog is queued
 * and only the head of the queue has a dialog in flight at any time; the
 * next queued request starts only after the current one resolves.
 */
class MediaStoreWriteGate {

    private data class PendingRequest(
        val activity: Activity,
        val uri: Uri,
        val onResult: (Boolean) -> Unit,
    )

    // Callback for whichever request currently has a system dialog in
    // flight (resolved from handleActivityResult). Only ever one at a time.
    private var pendingCallback: ((Boolean) -> Unit)? = null

    // Requests waiting for their turn to (re-)check access / show a dialog.
    // Not accessed off the main thread — ensureWriteAccess/handleActivityResult
    // are both required to run on the main thread already.
    private val queue = ArrayDeque<PendingRequest>()

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
     * processed one at a time; see the class doc for why.
     *
     * Must be called on the main thread; [onResult] is also invoked on the
     * main thread (either synchronously, for the already-granted case, or
     * from [handleActivityResult]).
     */
    fun ensureWriteAccess(activity: Activity, uri: Uri, onResult: (Boolean) -> Unit) {
        val resolver = activity.contentResolver
        when (tryOpenForWrite(resolver, uri)) {
            is OpenAttempt.Granted -> onResult(true)
            else -> {
                queue.addLast(PendingRequest(activity, uri, onResult))
                drainQueue()
            }
        }
    }

    /** Starts the next queued request's dialog if none is currently in flight. */
    private fun drainQueue() {
        if (dialogInFlight) return
        val next = queue.removeFirstOrNull() ?: return
        val resolver = next.activity.contentResolver

        // Re-check now (not just at enqueue time) — a queued request may no
        // longer need a dialog at all, e.g. if it targets a file whose grant
        // was already obtained by an earlier request in the same batch.
        when (val attempt = tryOpenForWrite(resolver, next.uri)) {
            is OpenAttempt.Granted -> {
                next.onResult(true)
                drainQueue()
            }
            is OpenAttempt.NeedsAction ->
                requestGrant(next.activity, resolver, next.uri, attempt.intentSender, next.onResult)
            is OpenAttempt.Denied -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val pi = MediaStore.createWriteRequest(resolver, listOf(next.uri))
                        requestGrant(next.activity, resolver, next.uri, pi.intentSender, next.onResult)
                    } catch (e: Exception) {
                        Log.w(TAG, "createWriteRequest failed for ${next.uri}", e)
                        next.onResult(false)
                        drainQueue()
                    }
                } else {
                    // API 29 with a non-recoverable denial (e.g. file genuinely
                    // owned by another app with no grant path) — nothing more
                    // we can do short of MANAGE_EXTERNAL_STORAGE, which this
                    // app deliberately doesn't request.
                    next.onResult(false)
                    drainQueue()
                }
            }
        }
    }

    private fun requestGrant(
        activity: Activity,
        resolver: ContentResolver,
        uri: Uri,
        intentSender: IntentSender,
        onResult: (Boolean) -> Unit,
    ) {
        dialogInFlight = true
        pendingCallback = { granted ->
            dialogInFlight = false
            onResult(granted && tryOpenForWrite(resolver, uri) is OpenAttempt.Granted)
            drainQueue()  // let the next queued request (if any) take its turn
        }
        try {
            activity.startIntentSenderForResult(intentSender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            Log.w(TAG, "startIntentSenderForResult failed for $uri", e)
            dialogInFlight = false
            pendingCallback = null
            onResult(false)
            drainQueue()
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
