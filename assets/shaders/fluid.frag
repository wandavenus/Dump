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

  // ── Five fixed colour layers ─────────────────────────────────────────────
  // Centers are kept inside the visible frame. The five compact regions are
  // distributed across the whole screen instead of being oversized blobs
  // whose overlap washes out the palette changes.
  vec2 layer0Point = vec2((uv.x - 0.18) * aspect, uv.y - 0.18) /
                     vec2(0.22 * aspect, 0.21);
  vec2 layer1Point = vec2((uv.x - 0.50) * aspect, uv.y - 0.16) /
                     vec2(0.22 * aspect, 0.20);
  vec2 layer2Point = vec2((uv.x - 0.80) * aspect, uv.y - 0.34) /
                     vec2(0.20 * aspect, 0.23);
  vec2 layer3Point = vec2((uv.x - 0.24) * aspect, uv.y - 0.68) /
                     vec2(0.22 * aspect, 0.22);
  vec2 layer4Point = vec2((uv.x - 0.72) * aspect, uv.y - 0.80) /
                     vec2(0.22 * aspect, 0.18);

  float layer0Base = exp(-dot(layer0Point, layer0Point) * 2.0);
  float layer1Base = exp(-dot(layer1Point, layer1Point) * 2.1);
  float layer2Base = exp(-dot(layer2Point, layer2Point) * 2.0);
  float layer3Base = exp(-dot(layer3Point, layer3Point) * 2.1);
  float layer4Base = exp(-dot(layer4Point, layer4Point) * 2.0);

  // Only each transition band breathes by a few percent. The centers and
  // overall locations remain fixed, so no layer can drift out of the frame.
  float edge0 = smoothstep(0.04, 0.35, layer0Base) *
                (1.0 - smoothstep(0.72, 0.94, layer0Base));
  float edge1 = smoothstep(0.04, 0.35, layer1Base) *
                (1.0 - smoothstep(0.72, 0.94, layer1Base));
  float edge2 = smoothstep(0.04, 0.35, layer2Base) *
                (1.0 - smoothstep(0.72, 0.94, layer2Base));
  float edge3 = smoothstep(0.04, 0.35, layer3Base) *
                (1.0 - smoothstep(0.72, 0.94, layer3Base));
  float edge4 = smoothstep(0.04, 0.35, layer4Base) *
                (1.0 - smoothstep(0.72, 0.94, layer4Base));

  float radius0 = 1.0 + 0.035 * sin(t * 0.17 + layer0Point.x * 4.0 +
                                      layer0Point.y * 3.0);
  float radius1 = 1.0 + 0.040 * sin(t * 0.145 + layer1Point.x * 3.0 -
                                      layer1Point.y * 4.0 + 1.8);
  float radius2 = 1.0 + 0.035 * sin(t * 0.12 + layer2Point.x * 4.0 +
                                      layer2Point.y * 2.5 + 3.7);
  float radius3 = 1.0 + 0.040 * sin(t * 0.155 + layer3Point.x * 3.5 +
                                      layer3Point.y * 3.0 + 1.1);
  float radius4 = 1.0 + 0.035 * sin(t * 0.13 + layer4Point.x * 4.0 -
                                      layer4Point.y * 2.5 + 2.6);

  float layer0Edge = exp(-dot(layer0Point, layer0Point) * 2.0 /
                         (radius0 * radius0));
  float layer1Edge = exp(-dot(layer1Point, layer1Point) * 2.1 /
                         (radius1 * radius1));
  float layer2Edge = exp(-dot(layer2Point, layer2Point) * 2.0 /
                         (radius2 * radius2));
  float layer3Edge = exp(-dot(layer3Point, layer3Point) * 2.1 /
                         (radius3 * radius3));
  float layer4Edge = exp(-dot(layer4Point, layer4Point) * 2.0 /
                         (radius4 * radius4));

  float layer0 = mix(layer0Base, layer0Edge, edge0);
  float layer1 = mix(layer1Base, layer1Edge, edge1);
  float layer2 = mix(layer2Base, layer2Edge, edge2);
  float layer3 = mix(layer3Base, layer3Edge, edge3);
  float layer4 = mix(layer4Base, layer4Edge, edge4);

  // ── Colour-only motion ────────────────────────────────────────────────────
  // Each layer breathes at a distinct, more noticeable rate. No time value is
  // applied to coordinates, so the regions never translate or warp.
  float pulse0 = 0.78 + 0.22 * sin(t * 0.210);
  float pulse1 = 0.78 + 0.22 * sin(t * 0.166 + 2.1);
  float pulse2 = 0.78 + 0.22 * sin(t * 0.134 + 4.2);
  float pulse3 = 0.78 + 0.22 * sin(t * 0.188 + 1.3);
  float pulse4 = 0.78 + 0.22 * sin(t * 0.152 + 3.5);

  layer0 *= pulse0;
  layer1 *= pulse1;
  layer2 *= pulse2;
  layer3 *= pulse3;
  layer4 *= pulse4;

  // Colour drift also reaches each layer's center. The centers stay fixed in
  // space, but their palette values crossfade strongly toward neighbouring
  // artwork colours so they do not remain locked to one RGB value.
  float shift0 = 0.18 + 0.46 * (0.5 + 0.5 * sin(t * 0.142 + 0.4));
  float shift1 = 0.18 + 0.46 * (0.5 + 0.5 * sin(t * 0.118 + 2.4));
  float shift2 = 0.18 + 0.46 * (0.5 + 0.5 * sin(t * 0.094 + 4.5));

  float shift0Next = 0.06 + 0.24 * (0.5 + 0.5 * sin(t * 0.097 + 2.0));
  float shift1Next = 0.06 + 0.24 * (0.5 + 0.5 * sin(t * 0.083 + 4.1));
  float shift2Next = 0.06 + 0.24 * (0.5 + 0.5 * sin(t * 0.071 + 0.8));
  float shift3 = 0.16 + 0.58 * (0.5 + 0.5 * sin(t * 0.126 + 1.2));
  float shift4 = 0.16 + 0.58 * (0.5 + 0.5 * sin(t * 0.108 + 3.6));
  float shift3Next = 0.06 + 0.28 * (0.5 + 0.5 * sin(t * 0.091 + 4.4));
  float shift4Next = 0.06 + 0.28 * (0.5 + 0.5 * sin(t * 0.077 + 1.5));

  vec3 layerColor0 = mix(mix(uColor0, uColor1, shift0), uColor2, shift0Next);
  vec3 layerColor1 = mix(mix(uColor1, uColor2, shift1), uColor0, shift1Next);
  vec3 layerColor2 = mix(mix(uColor2, uColor0, shift2), uColor1, shift2Next);
  vec3 layerColor3 = mix(
      mix(uColor0, uColor2, shift3), uColor1, shift3Next);
  vec3 layerColor4 = mix(
      mix(uColor1, uColor0, shift4), uColor2, shift4Next);

  // A restrained global colour exchange makes the overlap feel like colours
  // are blending, while the fixed masks prevent a liquid/cloud silhouette.
  float exchange = 0.5 + 0.5 * sin(t * 0.082);
  float backgroundWeight = 0.12 + 0.04 * exchange;
  float total = backgroundWeight + layer0 + layer1 + layer2 + layer3 + layer4;
  vec3 col = uColor0 * backgroundWeight;
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
