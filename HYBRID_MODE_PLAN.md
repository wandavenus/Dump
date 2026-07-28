# Hybrid Mode Implementation Plan
**Offline Library + Online Music Downloader dengan Extension System**

> **Status:** PLAN ONLY — belum diimplementasi  
> **Dibuat:** 2026-07-28  
> **Referensi:** SpotiFlac Mobile v4.8.0 (github.com/spotiflacapp/SpotiFLAC-Mobile)  
> **Target device:** Xiaomi Mi 9T / MIUI 12 / Android 11

---

## Ringkasan Keputusan Arsitektur

| Aspek | Keputusan |
|---|---|
| Backend Engine | Adopt pendekatan SpotiFlac: Dart+Kotlin layer, JS runtime via QuickJS FFI atau `flutter_js` |
| Metadata Source | Extension-only (tidak hardcode provider apapun) |
| Audio Source | Extension-only (decentralized, user install sendiri) |
| UI Integration | Unified — Search yang sudah ada extend ke online |
| Scope | Bertahap: Phase 1 → Phase 2 → Phase 3 |
| Ekstensi format | Kompatibel dengan `.spotiflac-ext` (manifest.json + index.js) |

---

## Gambaran Besar Arsitektur Target

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter UI Layer                         │
│  SearchPage (unified)  │  DownloadQueuePage  │  ExtensionStore  │
└──────────────┬─────────────────┬──────────────────┬─────────────┘
               │                 │                  │
       ┌───────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
       │  SearchService  │ │ DownloadMgr │ │ ExtensionService│
       │  (online+offln) │ │  (Dart)     │ │  (Dart)         │
       └───────┬─────────┘ └──────┬──────┘ └────────┬────────┘
               │                 │                  │
       ┌───────▼─────────────────▼──────────────────▼────────┐
       │               ExtensionRuntime (JS Engine)           │
       │   QuickJS via Dart FFI  OR  flutter_js (JavaScriptCore) │
       │   Menjalankan index.js dari .spotiflac-ext sandboxed  │
       └──────────────────────────┬───────────────────────────┘
                                  │
       ┌──────────────────────────▼───────────────────────────┐
       │                  Kotlin Android Layer                  │
       │  DownloadWorkerService  │  SAF Storage  │ Notifications│
       └──────────────────────────┬───────────────────────────┘
                                  │
       ┌──────────────────────────▼───────────────────────────┐
       │              Existing Media3/ExoPlayer Stack          │
       │  (TIDAK DIUBAH — downloaded file langsung diplay)     │
       └──────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation — Unified Search + Download Sederhana
**Estimasi kompleksitas:** Besar (2–3 sesi kerja)  
**Prasyarat:** Tidak ada (bisa langsung dikerjakan)

### Tujuan Phase 1
- Search page bisa cari lagu secara online (via extension metadata provider) DAN offline (MediaStore) dalam satu tampilan
- Download single track ke storage dengan metadata dasar
- Download queue dengan progress indicator
- File yang didownload langsung bisa diputar via player existing

### 1.1 Model Baru

**File: `lib/models/online_track.dart`**
```dart
// Model untuk hasil search online (dari extension)
class OnlineTrack {
  final String id;           // ID dari provider (e.g. spotify ID, deezer ID)
  final String name;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String? artistId;
  final String? albumId;
  final String? coverUrl;
  final String? isrc;
  final String? previewUrl;   // 30-detik preview URL jika tersedia
  final int durationMs;
  final int? trackNumber;
  final int? discNumber;
  final String? releaseDate;
  final String? audioQuality; // e.g. "LOSSLESS", "HIGH", "NORMAL"
  final String? explicit;
  final String source;        // extension ID yang memberikan data ini
  
  // ...constructor, fromJson, toJson
}
```

**File: `lib/models/download_item.dart`** (baru)
```dart
enum DownloadStatus { queued, downloading, finalizing, completed, failed, skipped }
enum DownloadErrorType { unknown, notFound, rateLimit, network, permission }

class DownloadItem {
  final String id;             // UUID
  final OnlineTrack track;
  final String extensionId;    // extension yang dipakai untuk download
  final DownloadStatus status;
  final double progress;       // 0.0 – 1.0
  final double speedMBps;
  final String? filePath;      // setelah completed
  final String? error;
  final DownloadErrorType? errorType;
  final String quality;        // e.g. "LOSSLESS", "MP3_320"
  final DateTime createdAt;
  
  // ...constructor, copyWith, fromJson, toJson
}
```

**File: `lib/models/search_result.dart`** (baru)
```dart
// Unified result: bisa dari local library ATAU online
class SearchResult {
  final SearchResultType type;  // local / online / album / artist / playlist
  final LocalSong? localSong;
  final OnlineTrack? onlineTrack;
  final OnlineAlbum? album;
  final OnlineArtist? artist;
  
  // helper getters: title, artist, coverUrl, etc.
}

enum SearchResultType { localSong, onlineTrack, onlineAlbum, onlineArtist, onlinePlaylist }
```

### 1.2 Extension System (Stub — Phase 1 versi sederhana)

Di Phase 1, Extension Runtime belum penuh (itu Phase 2). Di Phase 1, kita pakai **HTTP proxy sederhana**: extension JS dieksekusi oleh sebuah Kotlin WebView/JavascriptEngine yang minimal, hanya untuk pemanggilan `search()` dan `getDownloadUrl()`.

**File: `lib/services/extension_service.dart`** (baru)
```dart
// Phase 1: minimal stub + loader
class ExtensionService {
  // Load .spotiflac-ext file dari disk
  Future<ExtensionManifest?> loadExtension(File extFile);
  
  // List semua extension yang terinstall
  List<ExtensionManifest> get installedExtensions;
  
  // Panggil fungsi search() dari metadata provider extension
  Future<List<OnlineTrack>> search(String query, {String? extensionId});
  
  // Panggil fungsi getDownloadUrl() dari download provider extension
  Future<DownloadUrlResult?> getDownloadUrl(OnlineTrack track, String quality, String extensionId);
  
  // Install extension dari .spotiflac-ext file
  Future<bool> installExtension(File extFile);
  
  // Uninstall extension
  Future<void> uninstallExtension(String extensionId);
}

class ExtensionManifest {
  final String id;           // "name" dari manifest.json
  final String displayName;
  final String version;
  final String description;
  final String? author;
  final String? homepage;
  final List<String> type;   // ["metadata_provider", "download_provider", ...]
  final List<ExtensionQualityOption> qualityOptions;
  final List<ExtensionSetting> settings;
  final bool skipBuiltInFallback;
  // ...
}
```

**File: `lib/services/extension_js_runtime.dart`** (baru — Phase 1 menggunakan `flutter_js`)
```dart
// Wraps flutter_js / QuickJS untuk menjalankan extension index.js
// Phase 1: pakai flutter_js (lebih mudah setup)
// Phase 2: migrasi ke QuickJS via FFI untuk performa lebih baik

class ExtensionJsRuntime {
  // Inisialisasi JS engine dengan index.js dari extension
  Future<void> initialize(String jsCode, ExtensionManifest manifest);
  
  // Panggil function search() di JS
  Future<List<Map<String, dynamic>>> callSearch(String query, Map<String, dynamic> settings);
  
  // Panggil function getDownloadUrl() di JS
  Future<Map<String, dynamic>?> callGetDownloadUrl(Map<String, dynamic> track, String quality, Map<String, dynamic> settings);
  
  // Panggil function getAlbumTracks() di JS
  Future<List<Map<String, dynamic>>> callGetAlbumTracks(String albumId, Map<String, dynamic> settings);
  
  // Cleanup
  void dispose();
}
```

> **Catatan JS Runtime (penting untuk implementor):**
> - **Option A: `flutter_js`** (package: flutter_js ^0.8.0) — pakai JavaScriptCore (iOS) / QuickJS (Android). Lebih mudah tapi performa terbatas.
> - **Option B: `quickjs_flutter`** (package: quickjs_flutter) — binding langsung ke QuickJS C library via FFI.
> - **Option C: Android `WebView.evaluateJavascript()`** via Kotlin MethodChannel — paling powerful (V8), sudah ada di Android, tapi overhead tinggi.
> - **Rekomendasi Phase 1:** Option A (`flutter_js`) untuk kemudahan. Migrasi ke Option C (WebView/V8) di Phase 2 jika butuh kompatibilitas ekstensi SpotiFlac yang lebih penuh.
> - Verifikasi dulu apakah `flutter_js` bisa di-ship di Android 11 tanpa Gradle conflict dengan Media3.

### 1.3 Download Manager

**File: `lib/services/download_manager.dart`** (baru)
```dart
class DownloadManager extends ChangeNotifier {
  final _queue = <DownloadItem>[];
  final _completedItems = <DownloadItem>[];
  
  // State
  List<DownloadItem> get activeItems;   // queued + downloading + finalizing
  List<DownloadItem> get completedItems;
  DownloadItem? get currentDownload;
  
  // Actions
  Future<void> enqueue(OnlineTrack track, {String? qualityOverride, String? extensionId});
  Future<void> enqueueBatch(List<OnlineTrack> tracks, {String? extensionId});
  void cancel(String itemId);
  void cancelAll();
  void retry(String itemId);
  void clearCompleted();
  
  // Internal pipeline:
  // 1. ExtensionService.getDownloadUrl(track, quality, extensionId)
  // 2. HTTP download ke temp file (dengan progress streaming)
  // 3. Embed metadata (title, artist, album, cover, track number, ISRC) via ffmpeg_kit atau taglib
  // 4. Move ke download folder (SAF atau app folder)
  // 5. Notify MediaStore (MediaScannerConnection) agar file muncul di library
  // 6. Update DownloadItem status → completed
}
```

**File: `android/app/src/main/kotlin/.../DownloadWorkerService.kt`** (baru)
```kotlin
// Android Foreground Service untuk download background
// Komunikasi via MethodChannel: "musicplayer/download_worker"
// Events via EventChannel: "musicplayer/download_progress"
// 
// Channels:
// - startDownload(Map params) → void
// - cancelDownload(String itemId) → void
// - getActiveDownloads() → List<Map>
//
// Events (stream):
// - { itemId, progress, speedMBps, bytesReceived, bytesTotal, status, filePath?, error? }
```

**File: `lib/services/download_storage_service.dart`** (baru)
```dart
// Menangani storage mode: 'app' (getExternalStorageDirectory) atau 'saf' (SAF tree URI)
// Folder organization: Artist/Album/TrackNumber - Title.flac
// Filename format: "{trackNumber} - {title}.{ext}" atau "{artist} - {title}.{ext}"
class DownloadStorageService {
  Future<String> resolveOutputPath(OnlineTrack track, String format);
  Future<bool> validateStoragePermission();
  Future<bool> requestStoragePermission();
  Future<String?> pickDownloadFolder();  // SAF folder picker
  Future<void> notifyMediaStore(String filePath);
}
```

### 1.4 Metadata Embedding (Phase 1)

**File: `lib/services/metadata_embed_service.dart`** (baru)

Phase 1 gunakan `ffmpeg_kit_flutter_new_full` untuk embed metadata (sudah include di SpotiFlac):
```dart
class MetadataEmbedService {
  // Embed basic tags ke file audio (FLAC/MP3/M4A/OGG)
  Future<bool> embedTags({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    String? albumArtist,
    String? coverUrl,  // URL atau local path
    int? trackNumber,
    int? discNumber,
    String? date,
    String? isrc,
    String? genre,
    String? comment,
  });
  
  // Embed cover art (download dari URL lalu embed)
  Future<bool> embedCoverArt(String filePath, String coverUrl);
}
// Implementasi: ffmpeg -i input.flac -metadata title="..." -metadata artist="..." 
//               -c copy output.flac
```

> **Catatan:** `ffmpeg_kit_flutter_new_full` adalah package besar (~60MB). 
> Pertimbangkan: hanya load saat mode Online aktif pertama kali (lazy init).
> Alternatif Phase 1: gunakan TagLib via JNI (sudah ada di app kita untuk ReplayGain) — lebih ringan.

### 1.5 UI Changes — Unified Search

**File: `lib/widgets/pages/search_sections.dart`** — DIMODIFIKASI

Tambah segmen "Online" ke search results:
```
SearchPage
├── SearchBar (existing)
├── Tab: "Semua" | "Di Device" | "Online"
├── Section: Lagu di Device (existing — LocalSong)
├── Section: Online — Lagu     (baru — OnlineTrack)
├── Section: Online — Album     (baru — OnlineAlbum)
└── Section: Online — Artis     (baru — OnlineArtist)
```

**File: `lib/pages/search_page.dart`** — DIMODIFIKASI  
Tambah `_onlineMode` flag, integrasikan `ExtensionService.search()`.

**File: `lib/widgets/online/online_track_tile.dart`** (baru)
```
OnlineTrackTile:
  - Cover art (cached_network_image)
  - Title + Artist + Album
  - Duration + Quality badge (FLAC / MP3 / OPUS)
  - Download button → enqueue ke DownloadManager
  - Three-dot menu: Preview (30s) | Download | Add to Queue | View Album
```

**File: `lib/widgets/online/download_status_indicator.dart`** (baru)
- Badge kecil di ujung tile yang menunjukkan status download (sudah ada / downloading / queued)

**File: `lib/pages/download_queue_page.dart`** (baru)  
Halaman full-screen untuk melihat download queue:
```
DownloadQueuePage:
  - Active downloads section (progress bar, speed, cancel button)
  - Completed section (file path, quality, play button)
  - Failed section (error message, retry button)
  - FAB: pause all / resume all
```

**Navigation:** Download Queue dibuka dari:
1. Icon download di AppBar (dengan badge count)
2. Swipe atau tap notifikasi download

### 1.6 Settings Additions (Phase 1)

Tambah section baru di Settings:
```
Settings → Online & Download
  ├── Download Location (folder picker)
  ├── Storage Mode (App Folder / Custom via SAF)  
  ├── Audio Quality (jika extension mendukung beberapa pilihan)
  ├── Filename Format ("{artist} - {title}" / "{trackNumber} - {title}" / dll)
  ├── Folder Organization (Artist/Album / Artist / Flat)
  ├── Embed Metadata (toggle — default ON)
  ├── Embed Cover Art (toggle — default ON)
  └── Max Concurrent Downloads (1 / 2 / 3)

Settings → Extensions  ← BARU (Phase 1, minimal)
  ├── Installed Extensions (list)
  ├── Install from file (.spotiflac-ext)
  └── Extension details / uninstall
```

### 1.7 Dependencies Baru (Phase 1)

Tambah ke `pubspec.yaml`:
```yaml
dependencies:
  # JS Runtime untuk extension
  flutter_js: ^0.8.0        # QuickJS bundled (Android + iOS)
  
  # FFmpeg untuk metadata embedding + audio conversion
  ffmpeg_kit_flutter_new_full: ^2.4.2   # ~60MB, harus lazy-load
  
  # File picker untuk install extension + pilih download folder
  file_picker: ^9.0.0        # CATI: cek versi terbaru, harus non-beta
  
  # ZIP extraction untuk .spotiflac-ext installer
  archive: ^4.0.0            # Pure Dart ZIP/TAR reader
  
  # Connectivity check sebelum download
  connectivity_plus: ^7.3.1
  
  # Download progress streaming
  # NOTE: app kita sudah punya http package, gunakan HttpClient sendiri
  # untuk download dengan progress — jangan tambah dio/get
  
  # JSON serialization (sudah ada shared_preferences, tambah sqflite untuk history)
  sqflite: ^2.4.3            # Download history database
```

> **⚠️ Perhatian Gradle/NDK:**  
> `ffmpeg_kit_flutter_new_full` menggunakan pre-built FFmpeg shared libs.  
> Cek kompatibilitas dengan NDK version kita (r27+) dan minSdkVersion.  
> Jika ada konflik, pertimbangkan `ffmpeg_kit_flutter_new_min` (lebih kecil, hanya audio).

---

## Phase 2: Extension System Penuh
**Estimasi kompleksitas:** Sangat besar (3–4 sesi kerja)  
**Prasyarat:** Phase 1 selesai

### Tujuan Phase 2
- JS runtime lebih powerful dan aman (sandbox dengan API whitelist)
- Extension Store (repo berbasis GitHub/URL seperti SpotiFlac)
- Dukungan penuh manifest.json features: OAuth, token refresh, home feed, track enrichment
- Extension settings UI per-extension
- Provider priority management

### 2.1 JS Runtime Upgrade — QuickJS via FFI atau WebView

**Option yang direkomendasikan untuk Phase 2: Android WebView via Kotlin**

```kotlin
// android/app/src/main/kotlin/.../ExtensionJsEngine.kt
// Menggunakan WebView.evaluateJavascript() untuk menjalankan JS extension
// Keunggulan: V8 engine (full ES2020+), sudah ada di Android, tanpa dependency baru
// Cara kerja:
// 1. Buat WebView headless (tidak tampil di UI)
// 2. Load index.js extension + inject SpotiFlac API shim (fetch, storage, file, dll)
// 3. Expose MethodChannel ke JS via WebView.addJavascriptInterface()
// 4. Panggil function di JS: evaluateJavascript("JSON.stringify(await search(...))")
// 5. Return result ke Dart via MethodChannel callback

// API yang di-inject ke JS sandbox (sesuai SpotiFlac docs):
// - fetch(url, options) → response
// - storage.get/set/remove (sandboxed per-extension)
// - file.read/write/delete (sandboxed ke folder extension)
// - log(message)
// - auth.startOAuth(config) / auth.getToken()
```

**File: `lib/services/extension_js_runtime_v2.dart`** (baru — menggantikan Phase 1 flutter_js)
```dart
// Wrapper Dart untuk ExtensionJsEngine Kotlin
// Tambahan vs Phase 1:
// - Network sandbox (hanya domain yang ada di manifest.permissions.network)
// - Storage sandbox (isolated per extension)
// - Timeout handling (default 30s per call)
// - Error classification (network / auth / notFound / rateLimit)
// - Token refresh handling (auto-retry setelah refreshToken())
```

### 2.2 Extension Store (Repo System)

Persis seperti SpotiFlac: repo adalah URL yang mengarah ke JSON file berisi list extension.

**File: `lib/services/extension_repo_service.dart`** (baru)
```dart
class ExtensionRepoService {
  // Fetch daftar extension dari repo URL
  Future<List<ExtensionRepoEntry>> fetchRepoEntries(String repoUrl);
  
  // Download + install extension dari repo
  Future<bool> installFromRepo(ExtensionRepoEntry entry);
  
  // Cek updates untuk semua extension terinstall
  Future<Map<String, String>> checkUpdates();
  
  // Update extension ke versi terbaru
  Future<bool> updateExtension(String extensionId);
  
  // Persisted repo URLs
  List<String> get savedRepoUrls;
  Future<void> addRepoUrl(String url);
  Future<void> removeRepoUrl(String url);
}

class ExtensionRepoEntry {
  final String id;
  final String displayName;
  final String version;
  final String description;
  final String? author;
  final String downloadUrl;  // URL ke .spotiflac-ext file
  final String? iconUrl;
  final List<String> type;   // ["metadata_provider", "download_provider", ...]
  // ...
}
```

**File: `lib/pages/extension_store_page.dart`** (baru)
```
ExtensionStorePage:
  ├── Repo URL input (teks field + Add button)
  ├── Grid/List extension yang tersedia
  ├── Filter: All / Metadata / Download / Lyrics
  ├── Extension card: ikon, nama, deskripsi, type badges, Install/Update/Installed button
  ├── Installed section (dengan Update badge jika ada update)
  └── Manual install: "Install dari file .spotiflac-ext"
```

**Navigation:** Settings → Extensions → Store

### 2.3 OAuth & Authentication

Banyak extension (Spotify, Tidal, Qobuz, dll) butuh OAuth login. SpotiFlac sudah design ini.

**File: `lib/services/extension_auth_service.dart`** (baru)
```dart
class ExtensionAuthService {
  // Start OAuth flow (buka browser / in-app WebView)
  Future<bool> startOAuthFlow(String extensionId, OAuthConfig config);
  
  // Get stored token untuk extension
  Future<String?> getToken(String extensionId);
  
  // Store token (encrypted via flutter_secure_storage)
  Future<void> storeToken(String extensionId, OAuthToken token);
  
  // Refresh token jika expired
  Future<String?> refreshToken(String extensionId, OAuthToken token, OAuthConfig config);
  
  // Clear auth data
  Future<void> clearAuth(String extensionId);
  
  // Check apakah extension sudah authenticated
  Future<bool> isAuthenticated(String extensionId);
}
```

> **Dependency baru Phase 2:**
> ```yaml
> flutter_secure_storage: ^10.3.1  # Encrypted token storage
> url_launcher: ^6.3.2             # Sudah ada! Untuk buka OAuth URL
> receive_sharing_intent: ^1.9.0   # Handle OAuth callback deep link
> ```

### 2.4 Provider Priority + Metadata Enrichment

```dart
// lib/services/extension_priority_service.dart
class ExtensionPriorityService {
  // Urutan provider untuk metadata (user bisa atur)
  List<String> get metadataProviderPriority;
  Future<void> setMetadataProviderPriority(List<String> order);
  
  // Urutan provider untuk download (user bisa atur)
  List<String> get downloadProviderPriority;
  Future<void> setDownloadProviderPriority(List<String> order);
  
  // Coba download dengan fallback ke provider berikutnya jika gagal
  Future<DownloadUrlResult?> getDownloadUrlWithFallback(
    OnlineTrack track, String quality);
}
```

### 2.5 UI Additions Phase 2

**Extension detail/settings sheet:**
```
ExtensionDetailSheet:
  - Header: ikon, nama, versi, author
  - Status: aktif/tidak aktif, login status
  - Login/Logout button (untuk extension dengan OAuth)
  - Settings fields (sesuai manifest.settings[])
  - Quality selector default
  - Permissions list (domain whitelist yang bisa diakses)
  - Uninstall button
```

**Home Feed dari Extension:**
```
// lib/screens/home extension section (Phase 2)
// Extension dengan "homeFeedSupport: true" bisa muncul di Home
// Mirip "Recommended", "New Releases", "Charts" tapi dari provider extension
```

---

## Phase 3: Format Conversion + Advanced Features
**Estimasi kompleksitas:** Besar (2–3 sesi kerja)  
**Prasyarat:** Phase 2 selesai

### Tujuan Phase 3
- Konversi format audio (FLAC → MP3/AAC/OPUS, dll) via FFmpeg
- Download batch (album/playlist penuh)
- Download history database lengkap
- ReplayGain embedding setelah download
- Lyric provider extension type
- CUE sheet support (opsional)

### 3.1 FFmpeg Conversion Pipeline

**File: `lib/services/audio_conversion_service.dart`** (baru)
```dart
class AudioConversionService {
  // Convert file ke format target
  Future<ConversionResult> convertFile({
    required String inputPath,
    required String outputPath,
    required AudioOutputFormat format,
    int? bitrate,      // kbps untuk lossy formats
    int? sampleRate,   // Hz — null = preserve original
    int? bitDepth,     // 16/24/32 — null = preserve original
  });
  
  // Check apakah konversi diperlukan
  bool needsConversion(String filePath, AudioOutputFormat targetFormat);
  
  // Get available output formats
  List<AudioOutputFormat> get supportedFormats;
}

enum AudioOutputFormat {
  flac,       // Lossless — preserves quality
  mp3_320,    // MP3 320kbps CBR
  mp3_v0,     // MP3 VBR ~245kbps
  aac_256,    // AAC-LC 256kbps
  opus_128,   // Opus 128kbps (paling efisien)
  alac,       // Apple Lossless (M4A)
  wav,        // PCM WAV (lossless, uncompressed)
  // ogg_vorbis ← opsional
}
```

### 3.2 Batch Download (Album/Playlist)

**File: `lib/services/batch_download_service.dart`** (baru)
```dart
class BatchDownloadService {
  // Download seluruh album
  Future<void> downloadAlbum(String albumId, {
    required String extensionId,
    String? quality,
    bool createSubfolder = true,
  });
  
  // Download seluruh playlist
  Future<void> downloadPlaylist(String playlistId, {
    required String extensionId,
    String? quality,
  });
  
  // Resolusi track list dari album/playlist via extension
  Future<List<OnlineTrack>> resolveAlbumTracks(String albumId, String extensionId);
  Future<List<OnlineTrack>> resolvePlaylistTracks(String playlistId, String extensionId);
}
```

**UI Changes:**
- AlbumPage (online): "Download Album" button → batch enqueue
- PlaylistPage (online): "Download Semua" button
- Download queue grouping berdasarkan album/playlist

### 3.3 Download History Database

**File: `lib/services/download_history_service.dart`** (baru — SQLite via sqflite)
```dart
// Schema tabel download_history:
// id, track_id, track_name, artist_name, album_name, cover_url,
// file_path, quality, format, extension_id, downloaded_at,
// bit_depth, sample_rate, bitrate, isrc, file_size_bytes, has_lyrics,
// has_replaygain, error?, error_type?

class DownloadHistoryService {
  Future<void> addEntry(DownloadHistoryEntry entry);
  Future<List<DownloadHistoryEntry>> queryHistory({int? limit, int? offset, String? filter});
  Future<bool> isDownloaded(String trackId);              // quick check by track ID
  Future<bool> isDownloadedByIsrc(String isrc);           // ISRC-based dedup check
  Future<DownloadHistoryEntry?> findByFilePath(String path);
  Future<void> removeEntry(String id);
  Future<void> clearAll();
}
```

**UI:** Download history section di DownloadQueuePage, dengan filter dan search.

### 3.4 ReplayGain Post-Download

Setelah download selesai, kalau user aktifkan ReplayGain embedding:
1. Gunakan `ReplayGainService` yang sudah ada di app (ebur128 analyzer)
2. Scan file yang baru didownload
3. Embed RG tags (via JNI TagLib yang sudah ada)

```dart
// lib/providers/download_queue_provider_replaygain.dart (ikutin pola SpotiFlac)
// Triggered dari DownloadManager._finalizeItem() setelah file complete
```

### 3.5 Lyrics Provider Extension Type

Extension type `lyrics_provider` sudah didukung SpotiFlac. Integrasikan dengan `LyricsService` kita yang sudah ada:

```dart
// Tambah extension lyrics provider ke LyricsFetchManager
// Priority: Local LRC → Embedded → Extension Providers → LRCLIB → dll
// (sudah ada pipeline, tinggal tambah provider baru dari extension)
```

---

## Struktur File Lengkap (Semua Phase)

### File Baru yang Perlu Dibuat

```
lib/
├── models/
│   ├── online_track.dart              [Phase 1]
│   ├── online_album.dart              [Phase 1]
│   ├── online_artist.dart             [Phase 1]
│   ├── download_item.dart             [Phase 1]
│   └── search_result.dart             [Phase 1]
│
├── services/
│   ├── extension_service.dart         [Phase 1 — stub]
│   ├── extension_js_runtime.dart      [Phase 1 — flutter_js]
│   ├── extension_js_runtime_v2.dart   [Phase 2 — WebView/QuickJS upgrade]
│   ├── extension_repo_service.dart    [Phase 2]
│   ├── extension_auth_service.dart    [Phase 2]
│   ├── extension_priority_service.dart [Phase 2]
│   ├── download_manager.dart          [Phase 1]
│   ├── download_storage_service.dart  [Phase 1]
│   ├── metadata_embed_service.dart    [Phase 1]
│   ├── online_search_service.dart     [Phase 1]
│   ├── audio_conversion_service.dart  [Phase 3]
│   ├── batch_download_service.dart    [Phase 3]
│   └── download_history_service.dart  [Phase 3]
│
├── pages/
│   ├── download_queue_page.dart       [Phase 1]
│   ├── extension_store_page.dart      [Phase 2]
│   ├── online_album_page.dart         [Phase 1]
│   ├── online_artist_page.dart        [Phase 1]
│   └── online_playlist_page.dart      [Phase 2]
│
└── widgets/
    ├── online/
    │   ├── online_track_tile.dart     [Phase 1]
    │   ├── online_album_card.dart     [Phase 1]
    │   ├── online_artist_card.dart    [Phase 1]
    │   ├── download_status_indicator.dart [Phase 1]
    │   ├── download_progress_tile.dart [Phase 1]
    │   └── extension_list_tile.dart   [Phase 2]
    └── pages/
        └── search_sections.dart       [DIMODIFIKASI — Phase 1]

android/app/src/main/kotlin/.../
├── DownloadWorkerService.kt           [Phase 1]
├── ExtensionJsEngine.kt               [Phase 2]
└── StorageAccessHelper.kt             [Phase 1 — SAF utils]
```

### File yang Dimodifikasi

```
lib/
├── pages/search_page.dart             [Phase 1 — tambah online mode]
├── pages/settings_page.dart           [Phase 1 — tambah Download & Extension sections]
├── pages/settings_page/               [Phase 1 — file baru: download_settings.dart, extension_settings.dart]
├── widgets/pages/search_sections.dart [Phase 1 — unified search results]
├── services/lyrics_service/           [Phase 3 — tambah extension lyrics provider]
└── main.dart                          [Phase 1 — init ExtensionService, DownloadManager]

pubspec.yaml                           [Phase 1 — dependencies baru]
android/app/src/main/AndroidManifest.xml [Phase 1 — service + INTERNET + storage perms]
android/app/build.gradle               [Phase 1 — tambah dependency ffmpeg_kit jika via native]
```

---

## Risiko & Mitigasi

| Risiko | Probabilitas | Dampak | Mitigasi |
|---|---|---|---|
| `flutter_js` tidak support semua JS modern yang dipakai extension SpotiFlac (ESM, async iterator, dll) | Tinggi | Tinggi | Test dulu dengan sample extension. Fallback ke WebView-based JS engine (Phase 2 early) |
| `ffmpeg_kit_flutter_new_full` APK size +60MB | Pasti | Medium | Lazy-load saat mode online pertama aktif. Atau pakai JNI TagLib (sudah ada) untuk metadata saja, FFmpeg hanya untuk conversion |
| Konflik NDK/Gradle antara ffmpeg_kit dan native_audio_runtime kita | Medium | Tinggi | Test build dulu sebelum menulis code apapun. ffmpeg_kit punya ABI filter tersendiri |
| Extension JS bisa akses API tidak aman | Medium | Tinggi | Whitelist network domain sesuai manifest.permissions.network. Sandbox storage. Block `eval` pada input luar |
| MediaStore scan lambat setelah download | Low | Medium | Panggil `MediaScannerConnection.scanFile()` langsung setelah file complete |
| Storage Permission di MIUI 12 | Medium | Medium | Gunakan SAF (Storage Access Framework) sebagai default — lebih reliable dari MANAGE_EXTERNAL_STORAGE di MIUI |

---

## Urutan Pengerjaan yang Direkomendasikan (Phase 1)

1. **Setup Dependencies & Test Build** — tambah flutter_js + archive + sqflite ke pubspec, pastikan APK masih bisa build tanpa error NDK/Gradle conflict.

2. **Models** — buat semua model baru (OnlineTrack, DownloadItem, SearchResult, ExtensionManifest).

3. **ExtensionService (stub)** — loader manifest.json dari .spotiflac-ext, tanpa JS execution dulu. Test install/uninstall extension dari file.

4. **ExtensionJsRuntime (Phase 1)** — wrapping flutter_js, test panggil `search()` dari sample extension.

5. **OnlineSearchService** — integration ExtensionService → UI, test search di SearchPage.

6. **DownloadManager + Storage** — pipeline download HTTP → file, tanpa metadata embedding dulu.

7. **MetadataEmbedService** — test embed tags ke FLAC/MP3 via ffmpeg_kit.

8. **DownloadWorkerService (Kotlin)** — foreground service untuk background download.

9. **UI: OnlineTrackTile + SearchPage unified** — tampilkan hasil search online di SearchPage.

10. **UI: DownloadQueuePage** — full download queue management.

11. **Settings: Download + Extensions** — konfigurasi folder, format, dll.

12. **Test end-to-end** — install extension → search → download → play di Media3 player.

---

## Catatan Tambahan

### Kompatibilitas .spotiflac-ext
Kita tidak perlu 100% kompatibel dengan SEMUA fitur SpotiFlac. Yang paling penting di Phase 1-2:
- `search(query, settings)` → array of track objects
- `getDownloadUrl(track, quality, settings)` → `{ url, headers, fileExt }`
- `getAlbumTracks(albumId, settings)` → array of track objects
- Manifest fields: `name`, `displayName`, `version`, `type`, `qualityOptions`, `settings`, `permissions.network`

Yang bisa ditunda ke Phase 3 atau dibiarkan opsional:
- `homeFeedSupport` (home section dari extension)
- `postProcessingHooks` (post-download hooks)
- `customUrlHandler` (handle URL share intent)
- `lyrics_provider` type
- `enrichTrack()` (metadata enrichment)

### Tidak Ada "Built-in" Provider
Sesuai keputusan: app tidak hardcode satu pun provider. User **wajib** install extension dulu sebelum bisa search online. Ini mirip persis dengan SpotiFlac v3.8.0+.

Di setup screen (first launch), tampilkan:
1. Penjelasan singkat extension system
2. Prompt masukkan Extension Repository URL
3. Atau "Install dari file" untuk offline install

### Player Integration
Downloaded files langsung bisa diputar via **Media3/ExoPlayer kita yang sudah ada** — tidak perlu modifikasi player sama sekali. File FLAC/MP3/AAC/OGG semuanya sudah didukung ExoPlayer + FFmpeg extension kita.

Setelah download complete → `MediaScannerConnection.scanFile()` → file muncul di MediaStore → muncul di "Semua Lagu" di Home page. **Zero additional player work.**

---

*Plan ini bisa dilanjutkan di sesi manapun. Mulai dari Phase 1 Step 1 (Setup Dependencies & Test Build).*
