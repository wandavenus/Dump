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
 */
class MediaStoreWriteGate {

    private var pendingCallback: ((Boolean) -> Unit)? = null

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
     * Must be called on the main thread; [onResult] is also invoked on the
     * main thread (either synchronously, for the already-granted case, or
     * from [handleActivityResult]).
     */
    fun ensureWriteAccess(activity: Activity, uri: Uri, onResult: (Boolean) -> Unit) {
        val resolver = activity.contentResolver
        when (val attempt = tryOpenForWrite(resolver, uri)) {
            is OpenAttempt.Granted -> onResult(true)
            is OpenAttempt.NeedsAction -> requestGrant(activity, resolver, uri, attempt.intentSender, onResult)
            is OpenAttempt.Denied -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val pi = MediaStore.createWriteRequest(resolver, listOf(uri))
                        requestGrant(activity, resolver, uri, pi.intentSender, onResult)
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

    private fun requestGrant(
        activity: Activity,
        resolver: ContentResolver,
        uri: Uri,
        intentSender: IntentSender,
        onResult: (Boolean) -> Unit,
    ) {
        pendingCallback = { granted ->
            onResult(granted && tryOpenForWrite(resolver, uri) is OpenAttempt.Granted)
        }
        try {
            activity.startIntentSenderForResult(intentSender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            Log.w(TAG, "startIntentSenderForResult failed for $uri", e)
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
