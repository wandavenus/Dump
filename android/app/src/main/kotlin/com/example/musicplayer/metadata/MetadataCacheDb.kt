package com.example.musicplayer.metadata

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.File

/**
 * SQLite-backed persistent cache for per-song metadata.
 *
 * Stores ReplayGain / R128 / iTunNORM tags and embedded lyrics after
 * first extraction, keyed by MediaStore song-id + file mtime.
 * Cache entries are invalidated automatically when the file's
 * lastModified timestamp changes (e.g. after a re-tag).
 *
 * Thread-safety: every public method may be called from any thread.
 * SQLite itself serialises concurrent writes; reads are concurrent-safe
 * via WAL journal mode.
 */
class MetadataCacheDb private constructor(context: Context)
    : SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    // ── Singleton ─────────────────────────────────────────────────────────────

    companion object {
        private const val TAG        = "MetadataCacheDb"
        private const val DB_NAME    = "metadata_cache.db"
        private const val DB_VERSION = 1

        private const val TABLE      = "song_metadata_cache"
        private const val COL_ID     = "song_id"
        private const val COL_PATH   = "path"
        private const val COL_MTIME  = "mtime"
        // ReplayGain fields (stored as plain text to preserve exact formatting)
        private const val COL_RG_TRACK_GAIN  = "rg_track_gain"
        private const val COL_RG_TRACK_PEAK  = "rg_track_peak"
        private const val COL_RG_ALBUM_GAIN  = "rg_album_gain"
        private const val COL_RG_ALBUM_PEAK  = "rg_album_peak"
        private const val COL_R128_TRACK     = "r128_track_gain"
        private const val COL_R128_ALBUM     = "r128_album_gain"
        private const val COL_ITUN_NORM      = "itun_norm"
        // Embedded lyrics (null = no lyrics / not yet read)
        private const val COL_LYRICS         = "lyrics"
        // Sentinel: LYRICS_NONE means we already checked and found nothing
        const val LYRICS_NONE                = "\u0000NONE\u0000"
        private const val COL_CACHED_AT      = "cached_at"

        @Volatile
        private var instance: MetadataCacheDb? = null

        fun getInstance(context: Context): MetadataCacheDb =
            instance ?: synchronized(this) {
                instance ?: MetadataCacheDb(context).also { instance = it }
            }

        /** Returns [File.lastModified], or 0 if the file does not exist. */
        fun mtime(path: String): Long =
            try { File(path).lastModified() } catch (_: Exception) { 0L }
    }

    // ── Schema ────────────────────────────────────────────────────────────────

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS $TABLE (
                $COL_ID          INTEGER PRIMARY KEY,
                $COL_PATH        TEXT    NOT NULL,
                $COL_MTIME       INTEGER NOT NULL,
                $COL_RG_TRACK_GAIN TEXT,
                $COL_RG_TRACK_PEAK TEXT,
                $COL_RG_ALBUM_GAIN TEXT,
                $COL_RG_ALBUM_PEAK TEXT,
                $COL_R128_TRACK  TEXT,
                $COL_R128_ALBUM  TEXT,
                $COL_ITUN_NORM   TEXT,
                $COL_LYRICS      TEXT,
                $COL_CACHED_AT   INTEGER NOT NULL
            )
        """.trimIndent())
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_path ON $TABLE($COL_PATH)")
    }

    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE")
        onCreate(db)
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        if (!db.isReadOnly) {
            // WAL = concurrent readers + one writer without blocking
            db.execSQL("PRAGMA journal_mode=WAL")
            db.execSQL("PRAGMA synchronous=NORMAL")
        }
    }

    // ── Public data model ─────────────────────────────────────────────────────

    /**
     * Null field = tag not present in file.
     * LYRICS_NONE = lyrics was searched but not found (avoids re-parsing).
     */
    data class CachedEntry(
        val rgTrackGain : String?,
        val rgTrackPeak : String?,
        val rgAlbumGain : String?,
        val rgAlbumPeak : String?,
        val r128Track   : String?,
        val r128Album   : String?,
        val iTunNorm    : String?,
        val lyrics      : String?,   // null = not cached yet; LYRICS_NONE = confirmed absent
    )

    // ── Read ──────────────────────────────────────────────────────────────────

    /**
     * Returns the cached entry for [songId] if the file's [mtime] matches.
     * Returns null if no entry exists or the entry is stale.
     */
    fun get(songId: Int, mtime: Long): CachedEntry? {
        return try {
            readableDatabase.query(
                TABLE,
                arrayOf(
                    COL_RG_TRACK_GAIN, COL_RG_TRACK_PEAK,
                    COL_RG_ALBUM_GAIN, COL_RG_ALBUM_PEAK,
                    COL_R128_TRACK, COL_R128_ALBUM,
                    COL_ITUN_NORM, COL_LYRICS, COL_MTIME
                ),
                "$COL_ID = ?",
                arrayOf(songId.toString()),
                null, null, null
            ).use { cursor ->
                if (!cursor.moveToFirst()) return null
                val storedMtime = cursor.getLong(cursor.getColumnIndexOrThrow(COL_MTIME))
                if (storedMtime != mtime) return null   // stale — file changed

                CachedEntry(
                    rgTrackGain = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_TRACK_GAIN)),
                    rgTrackPeak = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_TRACK_PEAK)),
                    rgAlbumGain = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_ALBUM_GAIN)),
                    rgAlbumPeak = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_ALBUM_PEAK)),
                    r128Track   = cursor.getString(cursor.getColumnIndexOrThrow(COL_R128_TRACK)),
                    r128Album   = cursor.getString(cursor.getColumnIndexOrThrow(COL_R128_ALBUM)),
                    iTunNorm    = cursor.getString(cursor.getColumnIndexOrThrow(COL_ITUN_NORM)),
                    lyrics      = cursor.getString(cursor.getColumnIndexOrThrow(COL_LYRICS)),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "get($songId) failed: ${e.message}")
            null
        }
    }

    /**
     * Returns a cached entry looked up by file [path] if the file's [mtime] matches.
     * Used when songId is unavailable (e.g. ReplayGain scan flow).
     */
    fun getByPath(path: String, mtime: Long): CachedEntry? {
        return try {
            readableDatabase.query(
                TABLE,
                arrayOf(
                    COL_RG_TRACK_GAIN, COL_RG_TRACK_PEAK,
                    COL_RG_ALBUM_GAIN, COL_RG_ALBUM_PEAK,
                    COL_R128_TRACK, COL_R128_ALBUM,
                    COL_ITUN_NORM, COL_LYRICS, COL_MTIME
                ),
                "$COL_PATH = ?",
                arrayOf(path),
                null, null, null, "1"
            ).use { cursor ->
                if (!cursor.moveToFirst()) return null
                val storedMtime = cursor.getLong(cursor.getColumnIndexOrThrow(COL_MTIME))
                if (storedMtime != mtime) return null

                CachedEntry(
                    rgTrackGain = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_TRACK_GAIN)),
                    rgTrackPeak = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_TRACK_PEAK)),
                    rgAlbumGain = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_ALBUM_GAIN)),
                    rgAlbumPeak = cursor.getString(cursor.getColumnIndexOrThrow(COL_RG_ALBUM_PEAK)),
                    r128Track   = cursor.getString(cursor.getColumnIndexOrThrow(COL_R128_TRACK)),
                    r128Album   = cursor.getString(cursor.getColumnIndexOrThrow(COL_R128_ALBUM)),
                    iTunNorm    = cursor.getString(cursor.getColumnIndexOrThrow(COL_ITUN_NORM)),
                    lyrics      = cursor.getString(cursor.getColumnIndexOrThrow(COL_LYRICS)),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "getByPath($path) failed: ${e.message}")
            null
        }
    }

    // ── Write ─────────────────────────────────────────────────────────────────

    /**
     * Inserts or replaces the cached entry for [songId].
     * Pass [mtime] = File(path).lastModified() from the caller.
     */
    fun put(songId: Int, path: String, mtime: Long, entry: CachedEntry) {
        try {
            val values = ContentValues().apply {
                put(COL_ID,           songId)
                put(COL_PATH,         path)
                put(COL_MTIME,        mtime)
                put(COL_RG_TRACK_GAIN, entry.rgTrackGain)
                put(COL_RG_TRACK_PEAK, entry.rgTrackPeak)
                put(COL_RG_ALBUM_GAIN, entry.rgAlbumGain)
                put(COL_RG_ALBUM_PEAK, entry.rgAlbumPeak)
                put(COL_R128_TRACK,   entry.r128Track)
                put(COL_R128_ALBUM,   entry.r128Album)
                put(COL_ITUN_NORM,    entry.iTunNorm)
                put(COL_LYRICS,       entry.lyrics)
                put(COL_CACHED_AT,    System.currentTimeMillis())
            }
            writableDatabase.insertWithOnConflict(TABLE, null, values,
                SQLiteDatabase.CONFLICT_REPLACE)
        } catch (e: Exception) {
            Log.w(TAG, "put($songId) failed: ${e.message}")
        }
    }

    /**
     * Inserts or replaces by path when songId is unknown (e.g. scan-only flow).
     * Uses -1 as the song_id sentinel; will be overwritten by next put() call
     * that has the real ID.
     */
    fun putByPath(path: String, mtime: Long, entry: CachedEntry) {
        try {
            val values = ContentValues().apply {
                put(COL_ID,           path.hashCode())   // synthetic id from path
                put(COL_PATH,         path)
                put(COL_MTIME,        mtime)
                put(COL_RG_TRACK_GAIN, entry.rgTrackGain)
                put(COL_RG_TRACK_PEAK, entry.rgTrackPeak)
                put(COL_RG_ALBUM_GAIN, entry.rgAlbumGain)
                put(COL_RG_ALBUM_PEAK, entry.rgAlbumPeak)
                put(COL_R128_TRACK,   entry.r128Track)
                put(COL_R128_ALBUM,   entry.r128Album)
                put(COL_ITUN_NORM,    entry.iTunNorm)
                put(COL_LYRICS,       entry.lyrics)
                put(COL_CACHED_AT,    System.currentTimeMillis())
            }
            writableDatabase.insertWithOnConflict(TABLE, null, values,
                SQLiteDatabase.CONFLICT_REPLACE)
        } catch (e: Exception) {
            Log.w(TAG, "putByPath($path) failed: ${e.message}")
        }
    }

    /**
     * Updates only the lyrics column for an existing entry (keyed by path).
     * No-op if no entry exists yet.
     */
    fun updateLyrics(path: String, lyrics: String?) {
        try {
            val values = ContentValues().apply {
                put(COL_LYRICS, lyrics)
                put(COL_CACHED_AT, System.currentTimeMillis())
            }
            writableDatabase.update(TABLE, values, "$COL_PATH = ?", arrayOf(path))
        } catch (e: Exception) {
            Log.w(TAG, "updateLyrics($path) failed: ${e.message}")
        }
    }

    /** Removes the entry for a single song (call after user re-tags a file). */
    fun invalidate(songId: Int) {
        try {
            writableDatabase.delete(TABLE, "$COL_ID = ?", arrayOf(songId.toString()))
        } catch (e: Exception) {
            Log.w(TAG, "invalidate($songId) failed: ${e.message}")
        }
    }

    /** Removes ALL cache entries older than [olderThanMs] milliseconds. */
    fun pruneOld(olderThanMs: Long = 90L * 24 * 60 * 60 * 1000) {
        try {
            val cutoff = System.currentTimeMillis() - olderThanMs
            val deleted = writableDatabase.delete(
                TABLE, "$COL_CACHED_AT < ?", arrayOf(cutoff.toString())
            )
            if (deleted > 0) Log.d(TAG, "Pruned $deleted stale cache entries")
        } catch (e: Exception) {
            Log.w(TAG, "pruneOld failed: ${e.message}")
        }
    }

    /** Total number of cached entries (for diagnostics). */
    fun count(): Int = try {
        val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE", null)
        cursor.use { if (it.moveToFirst()) it.getInt(0) else 0 }
    } catch (_: Exception) { 0 }
}
