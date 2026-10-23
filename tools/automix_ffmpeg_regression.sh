#!/usr/bin/env bash
#
# Offline audio regression for the AutoMix crossfade envelope.
#
# 1. FFmpeg generates deterministic 48 kHz source A/B signals.
# 2. The JVM test renders the production AutomixGainEnvelope over those
#    sources and writes 32-bit float WAVs (current path + legacy fault models).
# 3. FFmpeg astats independently measures peak level and max sample-to-sample
#    difference on every rendered file.
#
# Run from anywhere:
#   tools/automix_ffmpeg_regression.sh
#
# Requirements: bash, ffmpeg/ffprobe, Java/Gradle wrapper (already in repo).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/automix-audio-regression"
SRC="$OUT/sources"
GRADLE_LOG="$OUT/gradle-test.log"
SAMPLE_RATE=48000
DURATION=4

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required" >&2; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe is required" >&2; exit 2; }
command -v java >/dev/null 2>&1 || { echo "java is required" >&2; exit 2; }

rm -rf "$OUT"
mkdir -p "$SRC"

# The JVM renderer expects a hard-cut sample at 1.7 s (0.5 s pre-roll + 40% of
# a 3 s fade): A=-0.5, B=+0.4. Keep these constants in sync with
# AutomixFadeRenderTest.CANCEL_TIME_SECONDS.
read -r A_PHASE B_PHASE <<EOF
$(awk 'BEGIN {
    pi = atan2(0, -1)
    printf "%.12f %.12f\n",
        -pi / 2 - 2 * pi * 220 * 1.7,
        pi / 2 - 2 * pi * 330 * 1.7
}')
EOF

echo "== Generating FFmpeg source signals =="
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "aevalsrc=0.5*sin(2*PI*220*t+($A_PHASE)):s=$SAMPLE_RATE:d=$DURATION" \
    -c:a pcm_f32le "$SRC/source_a.wav"
ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "aevalsrc=0.4*sin(2*PI*330*t+($B_PHASE)):s=$SAMPLE_RATE:d=$DURATION" \
    -c:a pcm_f32le "$SRC/source_b.wav"

echo "== Rendering production envelope through JVM test =="
if ! (
    cd "$ROOT/android"
    AUTOMIX_AUDIO_OUTPUT_DIR="$OUT" \
    AUTOMIX_AUDIO_SOURCE_DIR="$SRC" \
    AUTOMIX_AUDIO_REQUIRE_SOURCES=1 \
        ./gradlew :app:testDebugUnitTest \
            --tests "dev.wndavenz.music.automix.AutomixFadeRenderTest" \
            --rerun-tasks --console=plain
) >"$GRADLE_LOG" 2>&1; then
    echo "Gradle render test FAILED; last 100 lines:" >&2
    tail -100 "$GRADLE_LOG" >&2
    exit 1
fi

failures=0
pass() { printf '   PASS  %s\n' "$1"; }
fail() { printf '   FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }

check_lt() {
    local label="$1" value="$2" limit="$3"
    if awk -v v="$value" -v l="$limit" 'BEGIN { exit !(v < l) }'; then
        pass "$label ($value < $limit)"
    else
        fail "$label ($value !< $limit)"
    fi
}

check_gt() {
    local label="$1" value="$2" limit="$3"
    if awk -v v="$value" -v l="$limit" 'BEGIN { exit !(v > l) }'; then
        pass "$label ($value > $limit)"
    else
        fail "$label ($value !> $limit)"
    fi
}

analyze() {
    local name="$1" min_duration="$2" max_duration="$3"
    local file="$OUT/$name"
    if [[ ! -f "$file" ]]; then
        fail "$name is missing"
        return
    fi

    local probe
    probe="$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$file")"
    if [[ "$probe" == "pcm_f32le,$SAMPLE_RATE,1" ]]; then
        pass "$name format (pcm_f32le/${SAMPLE_RATE}Hz/mono)"
    else
        fail "$name format is '$probe', expected pcm_f32le,$SAMPLE_RATE,1"
    fi

    local duration
    duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$file")"
    if awk -v d="$duration" -v lo="$min_duration" -v hi="$max_duration" \
        'BEGIN { exit !(d >= lo && d <= hi) }'; then
        pass "$name duration (${duration}s)"
    else
        fail "$name duration ${duration}s outside ${min_duration}-${max_duration}s"
    fi

    local stats max_diff peak_db
    stats="$(ffmpeg -hide_banner -nostats -i "$file" \
        -af "astats=measure_perchannel=none:measure_overall=Peak_level+Max_difference" \
        -f null - 2>&1)"
    max_diff="$(printf '%s\n' "$stats" | awk '/Overall/ { found=1 } found && /Max difference:/ { print $NF; exit }')"
    peak_db="$(printf '%s\n' "$stats" | awk '/Overall/ { found=1 } found && /Peak level dB:/ { print $NF; exit }')"
    if [[ -z "$max_diff" || -z "$peak_db" ]]; then
        fail "$name astats did not report metrics"
        return
    fi

    printf '   %-38s maxDiff=%-10s peak=%s dB\n' "$name" "$max_diff" "$peak_db"
    echo "$name $max_diff $peak_db" >>"$OUT/metrics.txt"

    if awk -v p="$peak_db" 'BEGIN { exit !(p <= 0.01) }'; then
        pass "$name peak is below 0 dBFS"
    else
        fail "$name clips at ${peak_db} dBFS"
    fi
}

window_peak_db() {
    local file="$1"
    ffmpeg -hide_banner -nostats -i "$file" \
        -af "atrim=start=0.5:end=0.516,astats=measure_perchannel=none:measure_overall=Peak_level" \
        -f null - 2>&1 |
        awk '/Overall/ { found=1 } found && /Peak level dB:/ { print $NF; exit }'
}

echo
echo "== FFmpeg astats verification =="
analyze "current_envelope_gamma1.wav" 3.99 4.01
analyze "current_envelope_gamma135_trims.wav" 3.99 4.01
analyze "legacy_midfade_cancel.wav" 3.99 4.01
analyze "legacy_volume_copy.wav" 3.99 4.01

current_diff="$(awk '$1=="current_envelope_gamma1.wav" { print $2 }' "$OUT/metrics.txt")"
current_quick_diff="$(awk '$1=="current_envelope_gamma135_trims.wav" { print $2 }' "$OUT/metrics.txt")"
cancel_diff="$(awk '$1=="legacy_midfade_cancel.wav" { print $2 }' "$OUT/metrics.txt")"
copy_diff="$(awk '$1=="legacy_volume_copy.wav" { print $2 }' "$OUT/metrics.txt")"

check_lt "current envelope max sample step" "$current_diff" 0.05
check_lt "current envelope (gamma/trims) max sample step" "$current_quick_diff" 0.05
check_gt "legacy mid-fade cancel hard-cut sensitivity" "$cancel_diff" 0.25
check_gt "legacy volume-copy hard-cut sensitivity" "$copy_diff" 0.20

current_window_peak="$(window_peak_db "$OUT/current_envelope_gamma1.wav")"
legacy_window_peak="$(window_peak_db "$OUT/legacy_volume_copy.wav")"
printf '   first-fade-tick peak: current=%s dB legacy-copy=%s dB\n' \
    "$current_window_peak" "$legacy_window_peak"
if awk -v l="$legacy_window_peak" -v c="$current_window_peak" 'BEGIN { exit !(l > c + 5) }'; then
    pass "legacy volume copy leaks the incoming deck >5 dB above current"
else
    fail "legacy volume copy leak is not detectable in the first fade tick"
fi

# Optional visual artifacts for manual inspection.
for name in current_envelope_gamma1 legacy_midfade_cancel; do
    ffmpeg -hide_banner -loglevel error -y -i "$OUT/$name.wav" \
        -filter_complex "showwavespic=s=1400x260:colors=white" \
        -frames:v 1 "$OUT/$name.png"
done

echo
if (( failures > 0 )); then
    echo "RESULT: FAIL ($failures check(s) failed)" >&2
    exit 1
fi
echo "RESULT: PASS — current envelope stays continuous; both legacy fault models are detected"
echo "Artifacts: $OUT"
echo "  current_envelope_gamma1.wav / .png"
echo "  current_envelope_gamma135_trims.wav"
echo "  legacy_midfade_cancel.wav / .png"
echo "  legacy_volume_copy.wav"
echo "  metrics.txt"
