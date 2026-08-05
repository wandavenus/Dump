#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Slow chromatic colour-field shader for the player background.
//
// Uniforms (bound in order by Dart FragmentShader.setFloat):
//   0-1  : uSize      vec2   canvas size in logical pixels
//   2    : uTime      float  monotonically increasing time (seconds)
//   3-5  : uColor0    vec3   primary colour    (RGB 0-1)  — dominant mood
//   6-8  : uColor1    vec3   secondary colour  (RGB 0-1)  — supporting
//   9-11 : uColor2    vec3   accent colour     (RGB 0-1)  — vibrant pop
//   12-14: uHighlight vec3   highlight colour  (RGB 0-1)  — bright ridges
//   15-17: uShadow    vec3   shadow colour     (RGB 0-1)  — dark depth
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;
uniform vec3  uColor1;
uniform vec3  uColor2;
uniform vec3  uHighlight;
uniform vec3  uShadow;

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  // ── Aspect-correct coordinates ────────────────────────────────────────────
  // The layer anchors below never move. Only their colour and blend amount
  // changes over time, so the result feels alive without becoming fog/cloud
  // shapes that travel across the screen.
  float aspect = uSize.x / uSize.y;
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

  // ── Fixed colour layers ───────────────────────────────────────────────────
  // These soft regions are deliberately static. The artwork palette remains
  // recognizable while the overlap between regions gently changes colour.
  vec2 layer0Center = vec2(-0.20, -0.18);
  vec2 layer1Center = vec2(0.22, -0.02);
  vec2 layer2Center = vec2(-0.08, 0.27);

  float layer0 = exp(-dot((p - layer0Center) * vec2(1.05, 1.10),
                          (p - layer0Center) * vec2(1.05, 1.10)) * 2.0);
  float layer1 = exp(-dot((p - layer1Center) * vec2(1.15, 0.95),
                          (p - layer1Center) * vec2(1.15, 0.95)) * 2.2);
  float layer2 = exp(-dot((p - layer2Center) * vec2(0.95, 1.20),
                          (p - layer2Center) * vec2(0.95, 1.20)) * 2.1);

  // ── Colour-only motion ────────────────────────────────────────────────────
  // Each layer breathes at a different, very slow rate. No time value is
  // applied to coordinates, so the regions never translate or warp.
  float pulse0 = 0.82 + 0.18 * sin(t * 0.105);
  float pulse1 = 0.82 + 0.18 * sin(t * 0.083 + 2.1);
  float pulse2 = 0.82 + 0.18 * sin(t * 0.067 + 4.2);

  layer0 *= pulse0;
  layer1 *= pulse1;
  layer2 *= pulse2;

  // Subtle colour drift happens inside each fixed layer. The shift is toward
  // a neighboring palette colour, not toward white, so artwork identity stays
  // intact while the three colours visibly mix over time.
  float shift0 = 0.08 + 0.10 * (0.5 + 0.5 * sin(t * 0.071 + 0.4));
  float shift1 = 0.08 + 0.10 * (0.5 + 0.5 * sin(t * 0.059 + 2.4));
  float shift2 = 0.08 + 0.10 * (0.5 + 0.5 * sin(t * 0.047 + 4.5));

  vec3 layerColor0 = mix(uColor0, uColor1, shift0);
  vec3 layerColor1 = mix(uColor1, uColor2, shift1);
  vec3 layerColor2 = mix(uColor2, uColor0, shift2);

  // A restrained global colour exchange makes the overlap feel like colours
  // are blending, while the fixed masks prevent a liquid/cloud silhouette.
  float exchange = 0.5 + 0.5 * sin(t * 0.041);
  float total = 0.34 + layer0 + layer1 + layer2;
  vec3 col = uColor0 * (0.34 + 0.06 * exchange);
  col += layerColor0 * layer0;
  col += layerColor1 * layer1;
  col += layerColor2 * layer2;
  col /= total;

  // Highlight and shadow also change only in intensity. Their fixed masks add
  // depth without creating moving ridges or drifting light patches.
  float highlightMask = exp(-dot((p - vec2(0.48, 0.30)) * vec2(1.0, 1.35),
                                 (p - vec2(0.48, 0.30)) * vec2(1.0, 1.35)) * 2.8);
  float shadowMask = 1.0 - smoothstep(0.15, 0.78, length(p - vec2(-0.10, -0.02)));
  float highlightPulse = 0.035 + 0.035 * (0.5 + 0.5 * sin(t * 0.052 + 1.7));
  float shadowPulse = 0.012 + 0.012 * (0.5 + 0.5 * sin(t * 0.038 + 3.0));
  col = mix(col, uHighlight, highlightMask * highlightPulse);
  col = mix(col, uShadow, shadowMask * shadowPulse);

  // ── Soft vignette ──
  float vig = 1.0 - length(uv - 0.5) * 0.25;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
