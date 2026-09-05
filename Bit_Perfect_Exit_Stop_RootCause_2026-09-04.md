# Root Cause — Bit-Perfect OFF (kembali ke mode normal) menghentikan playback total

**Tanggal:** 4 September 2026
**Commit target:** `991aee2` (HEAD, build terbaru setelah 23 Agu)
**Gejala (device, Mi 9T/MIUI 12):** toggle Bit-Perfect OFF → playback **langsung berhenti
total**; semua tombol transport (play/next/prev/seek) **mati** sampai app di-restart.
**Status:** Akar masalah terkonfirmasi via static trace; fix 2 hunk di
`Media3PlaybackService.kt` sudah diterapkan (belum compile-verified — tanpa Android SDK).

---

## Ringkasan akar masalah

Selama Bit-Perfect Mode aktif, `activePlayer` = `bitPerfectPlayer` (player "clean").
Fungsi penentu slot standby:

```kotlin
// Media3PlaybackService.kt
private fun standbyPlayer(): ExoPlayer? =
    if (activePlayer === primaryPlayer) secondaryPlayer else primaryPlayer
```

karena `activePlayer !== primaryPlayer` selama mode, slot standby mengarah ke
**`primaryPlayer` — yaitu persis player yang disimpan sebagai `preBitPerfectPlayer`**
(akan di-restore saat keluar mode). Akibatnya, operasi teardown crossfade apa pun yang
dipanggil **selama mode berjalan** — pause, skip, setTrack, stop, `setQueue` (ganti
album/daftar putar), `handlePlayUri` (buka file audio) — memanggil
`clearStandbyQueue()` / `releaseStandbyPlayer()` pada `primaryPlayer`:

- `clearStandbyQueue()` → `stop()` + `clearMediaItems()` pada pre-bit-perfect player;
- `releaseStandbyPlayer()` (dipakai `setQueue`, `handlePlayUri`, `setCrossfadeDuration ≤ 0`)
  → **`release()` penuh** + slot `primaryPlayer = null`.

`preBitPerfectPlayer` sendiri **tidak ikut di-null** saat slot di-release. Maka
`switchFromBitPerfectPlayer()` memilih `restored = preBitPerfectPlayer` → sebuah
`ExoPlayer` yang **sudah di-release**. Semua operasi di jalur exit (`setQueue`,
`prepare`, `play`, dst.) terhadap player yang sudah di-release menjadi **silent
no-op** Media3 (tidak ada event, tidak ada audio), dan karena `activePlayer` kini
menunjuk player mati itu, **setiap perintah transport berikutnya juga no-op** —
gejala persis "berhenti total, semua tombol mati, harus restart app" (proses baru
= service baru = player baru).

Fix BP-06 sebelumnya hanya mem-guard jalur *preload* (`onPlaybackStateChanged`
READY, `maybeCrossfadeOut`, `onMediaItemTransition`) dengan `!bitPerfectModeOn` —
jalur *teardown* yang memanggil `clearStandbyQueue`/`releaseStandbyPlayer` dari
TransportCommands/handlePlayUri **tidak** di-guard.

---

## Rantai kegagalan (contoh yang paling mungkin di test device)

1. Playback normal di `primaryPlayer` (active = primary), queue berisi lagu.
2. Toggle Bit-Perfect ON → `preBitPerfectPlayer = primaryPlayer`; active = clean.
3. Selama mode, user melakukan aksi transport yang memanggil teardown standby:
   - ganti lagu/album → `"setQueue"` → `releaseStandbyPlayer()` → **`primaryPlayer.release()`**,
     slot `primaryPlayer = null`; atau
   - pause/skip/setTrack → `clearStandbyQueue()` → primary di-`stop()` + queue dihapus;
     atau
   - buka file audio → `handlePlayUri` → `releaseStandbyPlayer()` (jalur sama).
4. Toggle OFF → `switchFromBitPerfectPlayer()`:
   - `restored = preBitPerfectPlayer` (referensi player yang sudah di-release / di-stop);
   - `activePlayer = restored`; `proxy.switchTo(restored)`;
   - `setQueue`/`prepare`/`play` terhadap player mati → no-op diam-diam;
   - semua tombol (lewat `getPlayer() = activePlayer`) → no-op;
   - satu-satunya pemulihan: restart app (service baru).

Kasus yang juga rusak tanpa aksi user: masuk mode saat active = `secondaryPlayer`
(habis crossfade-promotion) → di *entry* `releaseStandbyPlayer()` melepas `primaryPlayer`
(benar), tetapi pola slot yang sama tetap membuat operasi teardown selama mode
menyasar player yang salah. Perbaikan di bawah menutup kelas bug ini di semua varian.

---

## Fix (Media3PlaybackService.kt — 2 hunk)

### Fix 1 (inti) — `standbyPlayer()` tidak boleh mengarah ke slot pre-bit-perfect selama mode

```kotlin
private fun standbyPlayer(): ExoPlayer? {
    // BP-10: ... (komentar lengkap di kode)
    if (bitPerfectModeOn) return null
    return if (activePlayer === primaryPlayer) secondaryPlayer else primaryPlayer
}
```

Selama mode, `getStandbyPlayer()` = null → `clearStandbyQueue()` dan
`releaseStandbyPlayer()` menjadi no-op → `preBitPerfectPlayer` tidak mungkin lagi
di-stop/clear/release dari jalur transport mana pun. Berlaku otomatis untuk semua
pemanggil (pause, skip, setTrack, stop, setQueue, setShuffle, setCrossfadeDuration,
handlePlayUri, …) karena semuanya lewat `standbyPlayer()`.

### Fix 2 (hardening) — `switchFromBitPerfectPlayer()` tidak boleh menghidupkan player mati

Setelah pemilihan `restored`, validasi bahwa player itu masih objek slot yang hidup;
bila tidak (state wedge lama / refactor masa depan), fallback ke `primaryPlayer` saat
ini atau player baru:

```kotlin
val restoredPlayer: ExoPlayer = run {
    val candidate = restored
    when {
        candidate === primaryPlayer || candidate === secondaryPlayer -> candidate
        primaryPlayer != null -> primaryPlayer!!
        else -> createConfiguredPlayer(streamSlot = 0).also {
            primaryPlayer = it
            attachPlayerListener(it)
        }
    }
}
// … seluruh jalur exit (proxy.switchTo, setQueue, repeat/shuffle, offload
// listener, resetAndReattach, play) memakai restoredPlayer
```

## Verifikasi (statis)

- `git diff`: hanya `Media3PlaybackService.kt`, 2 hunk (standbyPlayer guard +
  restoredPlayer hardening); struktur file balance (brace/paren check).
- Kotlin **tidak bisa** di-compile di environment ini (tanpa Android SDK), sama
  seperti audit-audit sebelumnya.
- Dart tidak berubah → tidak perlu `flutter analyze`.

## Test device yang disarankan (Mi 9T / MIUI 12)

1. Play lagu → Bit-Perfect ON → **ganti lagu/album lain** → Bit-Perfect OFF →
   playback harus lanjut normal di lagu baru, tombol hidup. (Sebelum fix: mati total.)
2. Play → Bit-Perfect ON → pause → Bit-Perfect OFF → play harus jalan.
3. Play → Bit-Perfect ON → skip next → Bit-Perfect OFF → play lanjut benar.
4. Play → Bit-Perfect ON → buka file audio dari file manager → Bit-Perfect OFF.
5. Crossfade ON (mis. 5 s) + EQ ON → ON/OFF mode → EQ kembali terdengar, crossfade
   lanjut normal (regresi BP-01/BP-06).
6. Log native di Log Viewer: harus ada `BitPerfect: disabling — restoring normal
   pipeline` … `BitPerfect: deactivated — session=… playing=true`, tanpa
   `attachEffects`/`Preload`/`Transport` aneh setelahnya.
