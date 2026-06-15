part of '../settings_page.dart';

// ─── Debug mode state (global, in-memory only) ────────────────────────────────
class _DebugState {
  static final ValueNotifier<bool> enabled   = ValueNotifier(false);
  static final ValueNotifier<int>  notifIcon = ValueNotifier(0);

  static const List<({String label, String icon})> notifIcons = [
    (label: 'Default',    icon: 'ic_notification'),
    (label: 'Music Note', icon: 'ic_notif_note'),
    (label: 'Headphones', icon: 'ic_notif_headphones'),
    (label: 'Waveform',   icon: 'ic_notif_wave'),
    (label: 'Disk',       icon: 'ic_notif_disk'),
  ];

  // ── Sample audio tracks ──────────────────────────────────────────────────────

  static AudioPlayer?                    _samplePlayer;
  static final ValueNotifier<int>        playingSample = ValueNotifier(-1);
  static final ValueNotifier<bool>       sampleLoading = ValueNotifier(false);
  static final ValueNotifier<String>     sampleStatus  = ValueNotifier('');

  static const List<({String title, String genre, String url})> samples = [
    (
      title: 'Pop Groove',
      genre: 'Pop',
      url:   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    ),
    (
      title: 'Electronic Burst',
      genre: 'Electronic',
      url:   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    ),
    (
      title: 'Ambient Drift',
      genre: 'Ambient',
      url:   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    ),
    (
      title: 'Bass Pulse',
      genre: 'Bass',
      url:   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    ),
    (
      title: 'Classic Rise',
      genre: 'Classical',
      url:   'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    ),
  ];

  // ── Playback helpers ──────────────────────────────────────────────────────────

  static Future<void> playSample(int index) async {
    if (index < 0 || index >= samples.length) return;

    // Stop previous sample
    await stopSample();

    sampleLoading.value = true;
    sampleStatus.value  = 'Loading…';
    playingSample.value = index;

    try {
      _samplePlayer = AudioPlayer();
      final sample  = samples[index];

      await _samplePlayer!.setAudioSource(
        AudioSource.uri(Uri.parse(sample.url),
            tag: MediaItem(id: sample.url, title: sample.title)),
      );
      await _samplePlayer!.play();

      sampleLoading.value = false;
      sampleStatus.value  = 'Streaming (no local LUFS analysis)';

      // Auto-clear status when track finishes
      _samplePlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          playingSample.value = -1;
          sampleStatus.value  = '';
        }
      });
    } catch (e) {
      sampleLoading.value = false;
      sampleStatus.value  = 'Error: $e';
      playingSample.value = -1;
      _samplePlayer?.dispose();
      _samplePlayer = null;
    }
  }

  static Future<void> stopSample() async {
    playingSample.value = -1;
    sampleStatus.value  = '';
    sampleLoading.value = false;
    try { await _samplePlayer?.stop(); } catch (_) {}
    _samplePlayer?.dispose();
    _samplePlayer = null;
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────
