part of '../settings_page.dart';

// ─── Debug mode state (global, in-memory only) ────────────────────────────────
class _DebugState {
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<int> notifIcon = ValueNotifier(0);

  static const List<({String label, String icon})> notifIcons = [
    (label: 'Default', icon: 'ic_notification'),
    (label: 'Music Note', icon: 'ic_notif_note'),
    (label: 'Headphones', icon: 'ic_notif_headphones'),
    (label: 'Waveform', icon: 'ic_notif_wave'),
    (label: 'Disk', icon: 'ic_notif_disk'),
  ];
}

// ─── Page ─────────────────────────────────────────────────────────────────────
