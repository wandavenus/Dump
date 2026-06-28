part of '../settings_page.dart';

// ── Reverb ─────────────────────────────────────────────────────────────────────
//
// Kontrol Reverb dipindahkan ke halaman Equalizer (lib/pages/settings/equalizer_page).
// Di sana, section Reverb menampilkan 7 preset Android PresetReverb secara native,
// atau pesan "tidak tersedia" jika perangkat tidak mendukung AudioEffect.EFFECT_TYPE_PRESET_REVERB.
//
// Referensi API native:
//   android.media.audiofx.PresetReverb — hanya menyediakan preset diskrit:
//     PRESET_NONE, PRESET_SMALLROOM, PRESET_MEDIUMROOM, PRESET_LARGEROOM,
//     PRESET_MEDIUMHALL, PRESET_LARGEHALL, PRESET_PLATE
//   Tidak ada parameter kontinu (wetLevel, roomSize, decay, dll.) di API ini.
