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
  // The fields below move only within bounded interior paths. Their motion is
  // slow and smooth, so the result feels like a mesh gradient rather than
  // fast fog/cloud shapes traveling across the screen.
  float aspect = uSize.x / uSize.y;
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

  // ── Moving Gaussian colour fields / mesh-gradient basins ─────────────────
  // Each basin follows a broad, bounded Lissajous-like path. All five can
  // cross the middle of the screen, but their centers stay in the safe
  // 0.16..0.84 interior so no field is thrown out of frame.
  vec2 center0 = vec2(
      0.50 + 0.33 * sin(t * 0.115),
      0.50 + 0.30 * cos(t * 0.083 + 0.5));
  vec2 center1 = vec2(
      0.50 + 0.31 * sin(t * 0.097 + 2.2),
      0.50 + 0.32 * cos(t * 0.071 + 1.4));
  vec2 center2 = vec2(
      0.50 + 0.28 * sin(t * 0.079 + 1.1),
      0.50 + 0.27 * cos(t * 0.061 + 2.7));
  vec2 center3 = vec2(
      0.50 + 0.32 * sin(t * 0.103 + 4.0),
      0.50 + 0.31 * cos(t * 0.075 + 3.1));
  vec2 center4 = vec2(
      0.50 + 0.30 * sin(t * 0.091 + 5.2),
      0.50 + 0.33 * cos(t * 0.067 + 4.4));

  vec2 field0Point = vec2((uv.x - center0.x) * aspect, uv.y - center0.y) /
                     vec2(0.52 * aspect, 0.50);
  vec2 field1Point = vec2((uv.x - center1.x) * aspect, uv.y - center1.y) /
                     vec2(0.52 * aspect, 0.50);
  vec2 field2Point = vec2((uv.x - center2.x) * aspect, uv.y - center2.y) /
                     vec2(0.56 * aspect, 0.54);
  vec2 field3Point = vec2((uv.x - center3.x) * aspect, uv.y - center3.y) /
                     vec2(0.52 * aspect, 0.50);
  vec2 field4Point = vec2((uv.x - center4.x) * aspect, uv.y - center4.y) /
                     vec2(0.52 * aspect, 0.50);

  float breathe0 = 1.0 + 0.08 * sin(t * 0.17 + 0.3);
  float breathe1 = 1.0 + 0.07 * sin(t * 0.14 + 2.0);
  float breathe2 = 1.0 + 0.09 * sin(t * 0.11 + 4.1);
  float breathe3 = 1.0 + 0.07 * sin(t * 0.16 + 1.2);
  float breathe4 = 1.0 + 0.08 * sin(t * 0.13 + 3.5);

  float layer0 = exp(-dot(field0Point, field0Point) * 1.20 /
                    (breathe0 * breathe0));
  float layer1 = exp(-dot(field1Point, field1Point) * 1.20 /
                    (breathe1 * breathe1));
  float layer2 = exp(-dot(field2Point, field2Point) * 1.12 /
                    (breathe2 * breathe2));
  float layer3 = exp(-dot(field3Point, field3Point) * 1.20 /
                    (breathe3 * breathe3));
  float layer4 = exp(-dot(field4Point, field4Point) * 1.20 /
                    (breathe4 * breathe4));

  // Different field strengths keep the result from becoming a flat average,
  // while the broad Gaussian widths keep neighboring fields overlapping.
  layer0 *= 0.90 + 0.14 * sin(t * 0.19 + 0.2);
  layer1 *= 0.90 + 0.14 * sin(t * 0.16 + 2.3);
  layer2 *= 0.94 + 0.12 * sin(t * 0.13 + 4.0);
  layer3 *= 0.90 + 0.14 * sin(t * 0.18 + 1.0);
  layer4 *= 0.90 + 0.14 * sin(t * 0.15 + 3.4);

  // Compress influence supaya satu layer ga terlalu dominan.
   layer0 = pow(layer0, 0.75);
   layer1 = pow(layer1, 0.75);
   layer2 = pow(layer2, 0.75);
   layer3 = pow(layer3, 0.75);
   layer4 = pow(layer4, 0.75);

  // Every basin can use every palette source. The three positive weights are
  // phase-shifted per basin, then normalized, so no layer is permanently tied
  // to dominant, secondary, or accent colour.
  vec3 weights0 = vec3(
      0.34 + 0.33 * sin(t * 0.142 + 0.4),
      0.34 + 0.33 * sin(t * 0.097 + 2.0),
      0.34 + 0.33 * sin(t * 0.071 + 4.1));
  vec3 weights1 = vec3(
      0.34 + 0.33 * sin(t * 0.118 + 2.4),
      0.34 + 0.33 * sin(t * 0.083 + 4.1),
      0.34 + 0.33 * sin(t * 0.061 + 0.8));
  vec3 weights2 = vec3(
      0.34 + 0.33 * sin(t * 0.094 + 4.5),
      0.34 + 0.33 * sin(t * 0.071 + 0.8),
      0.34 + 0.33 * sin(t * 0.053 + 2.7));
  vec3 weights3 = vec3(
      0.34 + 0.33 * sin(t * 0.126 + 1.2),
      0.34 + 0.33 * sin(t * 0.091 + 4.4),
      0.34 + 0.33 * sin(t * 0.067 + 2.0));
  vec3 weights4 = vec3(
      0.34 + 0.33 * sin(t * 0.108 + 3.6),
      0.34 + 0.33 * sin(t * 0.077 + 1.5),
      0.34 + 0.33 * sin(t * 0.059 + 4.8));

  vec3 layerColor0 = (uColor0 * weights0.x + uColor1 * weights0.y +
                      uColor2 * weights0.z) /
                     (weights0.x + weights0.y + weights0.z);
  vec3 layerColor1 = (uColor0 * weights1.x + uColor1 * weights1.y +
                      uColor2 * weights1.z) /
                     (weights1.x + weights1.y + weights1.z);
  vec3 layerColor2 = (uColor0 * weights2.x + uColor1 * weights2.y +
                      uColor2 * weights2.z) /
                     (weights2.x + weights2.y + weights2.z);
  vec3 layerColor3 = (uColor0 * weights3.x + uColor1 * weights3.y +
                      uColor2 * weights3.z) /
                     (weights3.x + weights3.y + weights3.z);
  vec3 layerColor4 = (uColor0 * weights4.x + uColor1 * weights4.y +
                      uColor2 * weights4.z) /
                     (weights4.x + weights4.y + weights4.z);

  // Normalized Gaussian weights create the mesh-gradient blend between basins
  // while preserving each field's local colour identity.
  float total = layer0 + layer1 + layer2 + layer3 + layer4;
  vec3 col = vec3(0.0);
  col += layerColor0 * layer0;
  col += layerColor1 * layer1;
  col += layerColor2 * layer2;
  col += layerColor3 * layer3;
  col += layerColor4 * layer4;
  col /= total;

  // Highlight and shadow also change only in intensity. Their fixed masks add
  // depth without creating moving ridges or drifting light patches.
  float highlightMask = exp(-dot((p - vec2(0.48, 0.30)) * vec2(1.0, 1.35),
                                 (p - vec2(0.48, 0.30)) * vec2(1.0, 1.35)) * 2.8);
  float shadowMask = 1.0 - smoothstep(0.15, 0.78, length(p - vec2(-0.10, -0.02)));
  float highlightPulse = 0.035 + 0.035 * (0.5 + 0.5 * sin(t * 0.104 + 1.7));
  float shadowPulse = 0.012 + 0.012 * (0.5 + 0.5 * sin(t * 0.076 + 3.0));
  col = mix(col, uHighlight, highlightMask * highlightPulse);
  col = mix(col, uShadow, shadowMask * shadowPulse);

  // ── Film grain ────────────────────────────────────────────────────────────
  // Original full-resolution screen-space grain: it adds visible texture
  // without changing the fixed colour masks or moving any layer.
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── Soft vignette ──
  float vig = 1.0 - length(uv - 0.5) * 0.25;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
