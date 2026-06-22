# Media3 Migration Feature-Parity Audit

Date: 2026-06-18
Target: Android 11 / MIUI 12.1.4

## Previous stack responsibilities

- `just_audio`: foreground player lifecycle, seek/position streams, duration resolution, speed/pitch, queue source loading, loop/shuffle, skip/seek/play/pause/stop, gapless-oriented single-player playback.
- `audio_service` / `BackgroundAudioHandler`: Android media session, notification, lockscreen controls, headset/Bluetooth/Android Auto transport commands, playback-state and metadata publication.
- `BackgroundAudioHandler`: app-level callbacks for play, pause, skip next/previous, seek, repeat, and shuffle.
- `AudioEffectsService`: persisted user settings for normalize/ReplayGain, equalizer, loudness, bass boost, reverb, spatial audio, playback speed, pitch, crossfade, gapless, lyrics path, and output mode.
- `AudioEngine`: active player facade, Android audio-session attachment, native DSP support flags, ReplayGain/loudness application, output mode / MIUI Hi-Fi parameter toggles, effect retry on Android 11.
- `DualPlayerManager`: primary/secondary player ownership, preloading, promotion callbacks, and future crossfade/gapless compatibility hooks.
- `CrossfadeController`: 20 ms transition monitoring, fade ramp, promotion, and gapless-album bypass logic.

## Missing or at-risk functionality found during audit

1. Native position updates were emitted every 500 ms, which was visibly coarse for seek bars and lyric/animation sync.
2. Native Media3 playback had no explicit Android audio-focus policy for transient loss, ducking, incoming calls, or permanent loss.
3. Headphone unplug / becoming-noisy events were not explicitly handled at the service boundary.
4. Media3 equalizer and loudness methods were placeholders, so `setEqualizerEnabled`, `setEqualizerBandGain`, `setLoudnessTargetGain`, and `setLoudnessEnabled` did not affect audio.
5. Native audio-session IDs were not bridged back to Flutter, preventing `AudioEngine` from reliably attaching existing Android DSP effects on Android 11 / MIUI.
6. The Flutter facade loaded one Media3 item at a time, so native MediaSession controllers did not see the full queue for Bluetooth, notification, lockscreen, headset, or Android Auto skip actions.
7. The Media3 service had no documented validation matrix for Bluetooth, lockscreen, Android Auto, headset buttons, notification controls, repeat, shuffle, queue insertion, and queue replacement.
8. `DualPlayerManager.secondaryPlayer` is still intentionally `null` in the Media3-backed implementation. This preserves compile-time compatibility, but true dual-player crossfade is not feature-complete yet; gapless currently relies on native Media3 queueing and the existing fallback reload path.
9. A rollback path must remain available until every validation item below passes on Android 11 / MIUI 12.1.4 hardware. Legacy dependencies should not be removed until that point.

## Implemented in this migration pass

- Position tick changed from 500 ms to 200 ms. This is smooth enough for seek bars and lyric animations while avoiding a 50/60 fps UI-side polling loop.
- Media3 service now requests and abandons Android audio focus around playback.
- Transient focus loss pauses and remembers whether playback should resume.
- Ducking lowers player volume and restores it on focus gain.
- Permanent focus loss pauses playback and clears the resume flag.
- Becoming-noisy broadcasts pause playback when wired/Bluetooth output disconnects.
- Native Equalizer and LoudnessEnhancer are attached to the active Media3 audio session and wired to the existing Flutter APIs.
- Audio-session IDs are emitted over a Flutter event channel so existing `AudioEngine` DSP attachment remains compatible.
- The Flutter player facade can now set the full queue into Media3, preserving native skip/previous behavior for external MediaSession controllers.

## Required device validation before removing legacy rollback

Run these on Android 11 and MIUI 12.1.4 physical devices:

- Bluetooth AVRCP: play, pause, skip next, skip previous, seek if supported, disconnect pause behavior.
- Lockscreen: play, pause, skip next, skip previous, seek bar, metadata, artwork.
- Android Auto: browse/session connection, play, pause, next, previous, repeat, shuffle.
- Wired headset button: single press play/pause, double/triple press if the headset maps them to next/previous.
- Notification controls: play, pause, next, previous, dismiss/stop behavior.
- Queue behavior: play next, append, reorder, replace queue, jump to index, skip previous restart-after-3-seconds behavior.
- Repeat modes: off, all, one from in-app UI and external controller.
- Shuffle modes: on/off, current-track preservation, external controller sync.
- Audio focus: incoming call, notification sound, navigation voice prompt ducking, alarm/permanent focus loss.
- Audio effects: equalizer enable/disable, each band gain, ReplayGain/loudness target, loudness enable/disable, bass boost, reverb, spatial, and MIUI Hi-Fi output mode.
- Gapless/crossfade compatibility: same-album gapless transition, non-gapless transition with crossfade disabled, and no crash when crossfade is enabled while Media3 dual-player support remains pending.

## Rollback rule

Do not remove `just_audio` or `audio_service` dependencies until all required device validation items pass. Keep the Media3 backend behind a release/configuration decision so a legacy backend can be restored quickly if Android 11 / MIUI 12.1.4 regressions are found.
