part of '../audio_effects_service.dart';

// ── Reverb preset labels ───────────────────────────────────────────────────────

const List<String> _kReverbPresetNames = [
  'Off', 'Small Room', 'Medium Room', 'Large Room',
  'Medium Hall', 'Large Hall', 'Plate',
];

// ── Room acoustic presets ──────────────────────────────────────────────────────

const List<Map<String, dynamic>> _kRoomPresets = [
  {'name': 'Flat',         'reverb': 0, 'gains': <double>[0.0,  0.0,  0.0,  0.0,  0.0], 'desc': 'Tanpa efek ruangan'},
  {'name': 'Studio',       'reverb': 0, 'gains': <double>[2.0,  1.0,  0.0, -1.0,  1.0], 'desc': 'Rekaman studio profesional'},
  {'name': 'Live Stage',   'reverb': 3, 'gains': <double>[3.0,  0.0,  2.0,  1.0,  2.0], 'desc': 'Panggung pertunjukan langsung'},
  {'name': 'Concert Hall', 'reverb': 5, 'gains': <double>[4.0,  1.0, -1.0,  2.0,  4.0], 'desc': 'Aula konser klasik'},
  {'name': 'Cathedral',    'reverb': 6, 'gains': <double>[3.0,  0.0, -2.0,  0.0,  5.0], 'desc': 'Gema katedral besar'},
  {'name': 'Club',         'reverb': 2, 'gains': <double>[6.0,  3.0,  1.0,  0.0, -1.0], 'desc': 'Club malam dengan bass kuat'},
  {'name': 'Outdoor',      'reverb': 1, 'gains': <double>[1.0,  0.0,  0.0,  2.0,  3.0], 'desc': 'Ruang terbuka di luar ruangan'},
  {'name': 'Car',          'reverb': 1, 'gains': <double>[4.0,  2.0,  1.0, -1.0,  0.0], 'desc': 'Interior kabin mobil'},
  {'name': 'Bathroom',     'reverb': 2, 'gains': <double>[0.0,  1.0,  3.0,  2.0,  1.0], 'desc': 'Ruang kecil dengan dinding keras'},
];

// ── Audio output labels ────────────────────────────────────────────────────────

const List<String> _kAudioOutputNames = [
  'Auto (AAudio)', 'OpenSL ES', 'Hi-Res Audio',
];

const List<String> _kAudioOutputDesc = [
  'AAudio — jalur audio default, direkomendasikan untuk Android 8+',
  'OpenSL ES — kompatibel dengan semua versi Android',
  'Hi-Res Audio — aktifkan DAC Hi-Res/Hi-Fi hardware. '
      'Mendukung MIUI 12, Qualcomm, Sony, dan OEM lain. '
      'Perlu headset atau DAC hi-res terhubung.',
];

// ── EQ genre presets ───────────────────────────────────────────────────────────

const List<Map<String, dynamic>> _kEqPresets = [
  {'name': 'Normal',      'gains': <double>[0.0,  0.0,  0.0,  0.0,  0.0]},
  {'name': 'Classical',   'gains': <double>[5.0,  3.0,  0.0,  3.0,  4.0]},
  {'name': 'Dance',       'gains': <double>[6.0,  0.0,  2.0,  4.0,  1.0]},
  {'name': 'Flat',        'gains': <double>[0.0,  0.0,  0.0,  0.0,  0.0]},
  {'name': 'Folk',        'gains': <double>[3.0,  0.0,  0.0,  2.0, -1.0]},
  {'name': 'Heavy Metal', 'gains': <double>[4.0,  1.0,  9.0,  3.0,  0.0]},
  {'name': 'Hip-Hop',     'gains': <double>[5.0,  4.0,  1.0,  1.0,  3.0]},
  {'name': 'Jazz',        'gains': <double>[4.0,  2.0, -2.0,  2.0,  5.0]},
  {'name': 'Pop',         'gains': <double>[-1.0, 2.0,  5.0,  1.0, -2.0]},
  {'name': 'Rock',        'gains': <double>[5.0,  3.0, -1.0,  3.0,  5.0]},
];
