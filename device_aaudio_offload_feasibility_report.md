# AAudio MMAP / Offload / Direct Playback Feasibility — Xiaomi Mi 9T / Redmi K20 (Snapdragon 730, MIUI 12, Android 11)

**Scope:** Research only. No code changed. This extends `bit_perfect_playback_report.md` with device-specific evidence for the Snapdragon 730 (SM7150) platform running MIUI 12 / Android 11, based on publicly documented Android/Qualcomm behavior. Findings are explicitly split into **confirmed**, **likely**, **unsupported**, and **unknown/requires runtime probing**.

---

## 1. Does the Qualcomm audio HAL for this device support the required paths?

| Feature | Status | Evidence |
|---|---|---|
| **AAudio MMAP (SHARED)** | **Likely supported at the SoC level** | SM7150 (Snapdragon 730) is the same platform family as the Google Pixel 4a ("sunfish"), whose AOSP device tree explicitly enables `aaudio.mmap_policy=2` (AUTO: try MMAP, fall back to legacy) and `aaudio.mmap_exclusive_policy=2` (AUTO: try EXCLUSIVE, fall back to SHARED). This proves the SM7150 audio HAL, kernel ALSA driver, and Qualcomm reference implementation are technically MMAP-capable. Community `getprop` captures from other Snapdragon 7-series devices (e.g. SD712 Vivo Z1x) show the same `aaudio.mmap_policy=2` default. |
| **AAudio Exclusive (MMAP-NOIRQ)** | **Confirmed possible on the SoC, OEM-dependent in practice** | Requires the HAL to expose a `mixPort` with `AUDIO_OUTPUT_FLAG_MMAP_NOIRQ \| AUDIO_OUTPUT_FLAG_DIRECT`, plus `anon_inode:dmabuf` SELinux passthrough. This is present in Qualcomm's reference audio HAL for SM7150-class chips (again, confirmed via the Pixel 4a AOSP tree using the same platform). Whether Xiaomi's derived HAL/SELinux policy preserves this is **not publicly documented** and is a known point of OEM divergence. |
| **PCM Offload** | **Hardware-capable, Android-version-gated** | The Hexagon 688 DSP on Snapdragon 730 is designed for offloaded audio processing. PCM offload as a distinct `AudioTrack` flag (`AUDIO_OUTPUT_FLAG_DIRECT_PCM`) is a very recent addition to AOSP (documented as landing around Android 16) — **Android 11 does not have this flag at all**, so it is architecturally unavailable on this device's OS version regardless of HAL capability. |
| **Compressed Audio Offload** | **Hardware-capable, available since Android 5.0, gated per-format at runtime** | `AUDIO_OUTPUT_FLAG_COMPRESS_OFFLOAD` has existed since Lollipop and is a standard Qualcomm HAL feature (ALSA `compress` API against the Hexagon DSP). This is the most mature/likely-supported path of the four on this device, but only for formats/sample rates the specific HAL's offload mix port advertises — commonly MP3/AAC and sometimes FLAC, not guaranteed for every combination. |
| **Direct AudioTrack (`AUDIO_OUTPUT_FLAG_DIRECT`, uncompressed)** | **Likely supported for a single non-mixed PCM stream** | This is the older, simpler "direct" mix port (bypass mixer, no MMAP, no offload) that's existed since Android 4.x. Qualcomm HALs generally expose at least one direct PCM output port. More likely to be granted than MMAP-exclusive or offload, but still an OEM/HAL policy decision, not guaranteed by SoC alone. |

**Bottom line for §1:** the SM7150 silicon and Qualcomm's reference HAL are demonstrably capable of all four paths (proven via the same-platform Pixel 4a AOSP source and general Snapdragon 7-series `getprop` evidence). What is *not* publicly verifiable is whether Xiaomi's MIUI-customized HAL preserves that capability rather than restricting it — see §2.

---

## 2. What does MIUI 12 / Android 11 actually expose on this device?

This is where the picture gets materially worse than "SoC supports it":

- **MIUI ships a custom `AudioPolicyManagerCustom`** that is documented (via community Oboe issue reports) to actively intercept and redirect fast/low-latency track requests. A known MIUI logcat signature is:
  `I/AudioPolicyManagerCustom: VR mode is 0, switch to primary output if request is for fast|raw` — meaning MIUI's policy layer redirects `fast`/`raw` (which underlies both the classic fast-mixer path and AAudio's low-latency path) back to the normal, non-fast primary output in non-VR contexts.
- **MIUI is documented to enforce `DEEP_BUFFER`** for most apps (except a short allow-list of Xiaomi's own apps), which precludes the FastMixer/AAudio-low-latency thread entirely for third-party apps in the common case.
- **The Redmi K20 / Mi 9T (codename `davinci`) specifically has a well-documented history of MIUI 12.x audio regressions** — XDA/Xiaomi community reports describe intermittent audio loss, distorted/robotic playback on some apps (while others were unaffected, implying an API-path-specific regression rather than a hardware fault), and audio/video desync during the MIUI 12.0–12.7 update cycle. This is independent evidence that MIUI 12's audio stack on this exact device had active regressions around the same era being targeted here, which further reduces confidence that HAL-level features like MMAP-exclusive survive unmodified.
- **No public, authoritative Xiaomi/MIUI document exists confirming or denying MMAP-exclusive/offload support for `davinci`** — everything above is inferred from platform commonality (SM7150) and known MIUI policy behavior, not a device-specific Xiaomi disclosure. This gap is explicitly called out as **unknown** rather than assumed.

**Conclusion for §2:** even where the underlying HAL is capable, MIUI's own policy layer is documented to actively work against fast/low-latency track grants for third-party apps, and this specific device generation has known MIUI 12.x audio-path regressions. Practical availability is best treated as *possible but suppressed by default*, not *available*.

---

## 3. Can Media3 realistically obtain those paths on this hardware?

- **AAudio MMAP/Exclusive:** Media3/ExoPlayer's `DefaultAudioSink` does not use the AAudio native API at all by default — it goes through the Java `AudioTrack` class, which internally may or may not route through AAudio's MMAP path depending on OS/OEM policy, entirely outside app control. Even if Media3 could reach this path, this project's own architecture (§4 of the prior report — dual ExoPlayer crossfade + always-attached software effects) is independently fatal to it, because effects and dual-player volume automation require the mixer path.
- **Offload (PCM/Compressed):** Media3 does support offload via `ExoPlayer.AudioOffloadListener` and internally requests it opportunistically based on the source format when `DefaultAudioSink` is configured to allow it — but this app's `AudioOffloadManager.kt` documents that offload is fatally incompatible with the existing crossfade + software-effects architecture (confirmed in the prior report), so Media3 would never realistically be granted (or would be immediately revoked from) offload in this app's current design regardless of device capability.
- **Direct AudioTrack (uncompressed, non-offload):** Same story — Media3 can use this in principle for a *single, unprocessed* player, but this app always attaches a `StereoWideningAudioProcessor` to the sink's `AudioProcessorChain` at construction time (`Media3PlaybackService.kt`), and the presence of any processor in the chain is understood to disqualify a sink from being considered direct/offload-eligible in AOSP's `DefaultAudioSink` logic.

**Conclusion for §3:** even in the best-case scenario where MIUI grants MMAP/exclusive/offload/direct to a well-formed request, **this app's current player configuration is architected such that it would never make (or qualify for) such a request in the first place.** This is an app-side gate independent of the device question.

---

## 4. Which APIs should be queried at runtime (instead of assuming)?

| API | Purpose | Availability |
|---|---|---|
| `AudioManager.getProperty(PROPERTY_SUPPORT_MMAP_LOW_LATENCY)` | Whether the device supports AAudio MMAP (SHARED or EXCLUSIVE) at all | API 29+ (Android 11 has it — this device qualifies) |
| `AudioManager.getProperty(PROPERTY_SUPPORT_MMAP_EXCLUSIVE)` | Whether MMAP EXCLUSIVE specifically is supported | API 29+ |
| `AudioManager.isOffloadedPlaybackSupported(AudioFormat, AudioAttributes)` | Whether the device/HAL can offload a *specific* format (encoding + sample rate + channel mask) — must be queried per-track, not once globally | API 29+ |
| `AAudioStream_isMMapUsed(AAudioStream*)` (NDK) | Confirms, after opening a stream, whether MMAP was actually granted vs silently downgraded to the legacy path | NDK-only; not reachable from the Java/Media3 layer without a native AAudio bridge, which does not exist in this codebase today |
| ADB `getprop | grep aaudio` (`aaudio.mmap_policy`, `aaudio.mmap_exclusive_policy`) | Device/OEM-set system properties showing the *default policy* (not a live grant) | Requires ADB shell access to the physical device — not queryable from app code |
| `adb shell dumpsys audio` → look for `F` flag next to the app's track in fast-track dump | Confirms whether a *currently playing* track is actually on a fast/low-latency mixer thread | ADB-only, manual verification tool, not an app-callable API |
| `AudioDeviceInfo.getSampleRates()` / `getEncodings()` / `getChannelCounts()` on `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` filtered to `TYPE_USB_DEVICE`/`TYPE_USB_HEADSET` | Discover a connected USB DAC's actual supported rates/formats (empty array = arbitrary rates supported) | API 23+ |

**None of these are currently called anywhere in this codebase** (confirmed by code search — `AudioOffloadManager.kt` only *observes* `onOffloadedPlayback()` after the fact; it never calls `isOffloadedPlaybackSupported()` or the MMAP property getters). This means today the app has **zero runtime visibility** into whether it's on a fast, direct, or mixed path on this or any device.

---

## 5. Is this device likely to silently fall back to the shared `AudioTrack` path?

**Yes, with high confidence, for the following converging reasons:**

1. AAudio's own documented fallback behavior is unconditional and silent-by-design: if MMAP or EXCLUSIVE isn't granted, it transparently uses the legacy AudioFlinger path with **no error, no exception, no callback** telling the app it was downgraded — this is true on every Android device, not specific to Xiaomi.
2. MIUI's `AudioPolicyManagerCustom` is documented to actively redirect fast/raw requests to the primary (non-fast) output outside VR mode — this is an *additional*, MIUI-specific layer of denial on top of AAudio's own opportunistic fallback.
3. This app's own audio pipeline (always-attached `StereoWideningAudioProcessor`, dual-player crossfade, software `AudioEffect`s) never requests a fast/direct/offload path from Media3/`AudioTrack` in the first place — so even absent any OEM restriction, the app is self-selecting into the shared mixer path today.

**Net assessment: on this exact device/OS/ROM combination, with this app's current architecture, the shared `AudioTrack`/AudioFlinger mixer path is not just likely — it is the only path the app currently ever uses**, independent of what the hardware could theoretically support.

---

## 6. Does USB DAC playback change the result on this device?

- A USB DAC changes *what's theoretically possible* (device-reported sample rates via `AudioDeviceInfo.getSampleRates()` can go well beyond the phone's internal 48 kHz-locked path — public reports show USB DACs on Android reporting 48/88.2/96/176.4/192 kHz support), but:
- **Bit-perfect/true direct USB passthrough (`BitPerfectThread`, `AUDIO_OUTPUT_FLAG_BIT_PERFECT`) is documented as an Android 14+ feature.** This device runs Android 11, so that specific bit-perfect USB path **does not exist on this OS version at all** — it is not an OEM/HAL question, it's an AOSP version gate this device cannot cross without an OS upgrade (which MIUI 12/Android 11 devices in this generation are unlikely to receive, given they predate Android 14 by multiple years).
- Without that Android 14+ mechanism, a USB DAC on this device still goes through the same AudioFlinger mixer/resampler by default — plugging one in does not, by itself, grant a direct or bit-perfect path on Android 11.
- **What *is* achievable today:** querying the connected DAC's supported rates via `AudioDeviceInfo` and at minimum avoiding *app-introduced* mismatch (e.g., not requesting a rate the DAC has to internally resample), plus attempting `AUDIO_OUTPUT_FLAG_DIRECT` (the older, non-MMAP direct path, available since Android 4.x) for a single unprocessed stream — which is more realistically obtainable than MMAP-exclusive or the Android 14+ bit-perfect path.

**Conclusion for §6: a USB DAC meaningfully raises the format/rate ceiling but does not unlock a bit-perfect path on this Android 11 device** — that specific capability is version-gated to Android 14+, several major versions beyond what this device runs.

---

## 7. What can be verified programmatically from the app (no assumptions needed)?

These are things the app *can* determine on-device, today, without any code changes to the playback engine itself (e.g. as a diagnostic/debug-menu addition):

- `AudioManager.getProperty(PROPERTY_SUPPORT_MMAP_LOW_LATENCY)` / `PROPERTY_SUPPORT_MMAP_EXCLUSIVE` — direct, documented API, works on Android 11.
- `AudioManager.isOffloadedPlaybackSupported()` for the actual formats in the user's library (per format/sample-rate combination).
- `AudioManager.getProperty(PROPERTY_OUTPUT_SAMPLE_RATE)` / `PROPERTY_OUTPUT_FRAMES_PER_BUFFER` — the device's fixed mixer output configuration (this reveals, e.g., whether the mixer runs at 48 kHz, which by itself proves 44.1 kHz sources will always be resampled through the standard path).
- `AudioDeviceInfo.getSampleRates()/getEncodings()/getChannelCounts()` for any attached USB device.
- Media3's existing `AudioOffloadListener.onOffloadedPlayback(Boolean)` — already wired up in `AudioOffloadManager.kt` — confirms, after the fact, whether the OS granted offload for the currently playing session (it currently never will, per §3, because the app's own configuration disqualifies it).

All of the above are **runtime facts specific to the individual physical unit and its current MIUI build**, not assumptions — they should be queried and logged rather than inferred, since (per §2) MIUI's actual behavior on this generation of devices has documented build-to-build regressions.

---

## 8. What cannot be determined until runtime (depends on the OEM HAL) — clearly separated

| Confirmed (public docs / cross-platform evidence) | Likely (inferred from platform commonality) | Unsupported (version-gated, provably absent) | Unknown / requires on-device runtime probing |
|---|---|---|---|
| SM7150 platform + Qualcomm reference HAL support AAudio MMAP and MMAP-EXCLUSIVE (proven via Pixel 4a AOSP tree on the same platform) | Xiaomi's MIUI-derived HAL for `davinci` (Mi 9T/K20) preserves the same MMAP capability | PCM offload (`AUDIO_OUTPUT_FLAG_DIRECT_PCM`) — not part of Android 11 at all | Whether MIUI 12's `AudioPolicyManagerCustom` on this specific device grants or denies AAudio low-latency requests from a third-party app in practice |
| `AudioManager.getProperty()` MMAP query APIs exist and are callable on Android 11 (API 29+) | Compressed audio offload is available for common formats given the Hexagon 688 DSP | Android 14+ `AUDIO_OUTPUT_FLAG_BIT_PERFECT` USB passthrough — this device runs Android 11 | Whether this specific device's persist/audio-calibration partition (referenced in community MIUI 12.x audio bug reports) is in a "known good" or "known regressed" state |
| MIUI enforces `DEEP_BUFFER` and redirects fast/raw requests via `AudioPolicyManagerCustom` (documented via Oboe issue reports) | `AUDIO_OUTPUT_FLAG_DIRECT` (older, non-MMAP direct PCM path) is obtainable for a single unprocessed stream | MMAP-exclusive/offload grant while this app's dual-player + software-effects architecture remains unchanged — architecturally excluded by the app itself, not the device | Exact MIUI sub-version behavior — community reports show MIUI 12.0 and 12.7 behaving differently from intermediate 12.1–12.5 builds on this exact device family |
| This app currently makes zero API calls that would request/query any of these paths | — | — | Actual `getprop aaudio.mmap_policy` / `aaudio.mmap_exclusive_policy` values on this specific unit — must be read via ADB, cannot be inferred |

---

## Summary

- The **Snapdragon 730 silicon and Qualcomm's reference audio HAL are capable of AAudio MMAP, MMAP-Exclusive, compressed offload, and basic direct PCM** — this is well-evidenced by the same-platform Pixel 4a AOSP configuration and general Snapdragon 7-series behavior.
- **MIUI 12 on Android 11 is documented to actively work against fast/low-latency track grants** for third-party apps (custom audio policy manager, forced `DEEP_BUFFER`), and this exact device generation (`davinci`) has a known history of MIUI 12.x audio-path regressions — independent of this app's own code.
- **Android 11 categorically lacks** PCM offload (`AUDIO_OUTPUT_FLAG_DIRECT_PCM`) and the Android 14+ USB bit-perfect path — these are unavailable on this device regardless of HAL or MIUI behavior, and cannot be unlocked without an OS upgrade this device is unlikely to receive.
- **This app's own architecture is currently a stronger gating factor than the device itself**: the always-attached `StereoWideningAudioProcessor`, dual-player crossfade, and software `AudioEffect`s mean the app never requests a fast/direct/offload path today, so the question of what MIUI *would* grant is currently moot until the app's own pipeline is restructured (as outlined in §9 of the prior bit-perfect report).
- The only way to resolve the genuine unknowns (MIUI's actual runtime grant behavior on this unit, and its current persist/audio-calibration state) is **on-device runtime probing** using the APIs listed in §4/§7 — not further static analysis or public documentation, since Xiaomi has not published device-specific HAL policy details for `davinci`.
