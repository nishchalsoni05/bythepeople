#version 460 core
#include <flutter/runtime_effect.glsl>

// Holographic foil for Neta cards. Drawn twice over the card:
//   uPass 0  colour layer, composited with BlendMode.hardLight (0.5 grey = no change)
//   uPass 1  light layer (glare, brushed streak, glitter, rim, sweep), BlendMode.plus
//
// What makes it read as real foil rather than a rainbow gradient:
//  * thin-film interference palette (cosine hues), not an HSV wheel
//  * the foil sits BEHIND the surface, so it parallaxes against the print as you tilt
//  * organic fbm flow warps the bands the way embossed foil does
//  * two crossed diffraction gratings whose brightness changes with viewing angle
//  * glitter flakes each have their own normal and only flash when the view aligns
//  * foil is masked: strong in the art window and frame, subdued behind text

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uTilt;    // -1..1
uniform float uRarity; // 0 unrated, 1 common, 2 rare, 3 epic, 4 legendary
uniform float uPass;
uniform vec4 uArt;     // art window (x, y, w, h) in 0..1, w <= 0 means none
uniform float uSweep;  // reveal sweep 0..1, negative = off
uniform float uSeed;

out vec4 fragColor;

const float TAU = 6.28318530718;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
  float n = hash21(p);
  return vec2(n, hash21(p + n + 17.7));
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * vnoise(p);
    p = p * 2.03 + vec2(17.1, 9.2);
    a *= 0.5;
  }
  return v;
}

vec3 film(float t) {
  // softened chroma: foil shifts colour, it does not repaint the card
  return 0.5 + 0.34 * cos(TAU * (t + vec3(0.0, 0.33, 0.67)));
}

float roundBoxSd(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 px = uv * uSize;
  vec2 t = uTilt;
  float r = uRarity;

  float rainbowAmt = r < 1.5 ? 0.0 : (r < 2.5 ? 0.55 : (r < 3.5 ? 0.82 : 1.0));
  float gratingAmt = r < 2.5 ? 0.0 : (r < 3.5 ? 0.55 : 1.0);
  float glitterAmt = r < 2.5 ? 0.0 : (r < 3.5 ? 0.5 : 1.0);
  float sheen = r < 0.5 ? 0.0 : (r < 1.5 ? 0.55 : 1.0);

  // ---- masks -------------------------------------------------------------
  float artMask = 0.0;
  if (uArt.z > 0.0) {
    vec2 c = (uArt.xy + uArt.zw * 0.5) * uSize;
    vec2 h = uArt.zw * 0.5 * uSize;
    artMask = 1.0 - smoothstep(-1.5, 1.5, roundBoxSd(px - c, h, 18.0));
  }
  float edgePx = min(min(px.x, uSize.x - px.x), min(px.y, uSize.y - px.y));
  float frameMask = 1.0 - smoothstep(5.0, 15.0, edgePx);
  float foilMask = clamp(max(artMask, frameMask * 0.9) + 0.10, 0.0, 1.0);

  vec2 p = (uv - 0.5) * vec2(uSize.x / uSize.y, 1.0);

  if (uPass < 0.5) {
    // ---- colour layer ------------------------------------------------------
    vec2 par = p + t * 0.10; // foil is below the print: parallax
    float flow = fbm(par * 2.6 + vec2(uSeed, uSeed * 0.37) + t * 0.45);
    float phase = dot(par, vec2(0.9, 0.6)) * 1.9 + t.x * 0.95 + t.y * 0.55 + flow * 1.1;
    vec3 rainbow = film(phase);

    float g1 = 0.5 + 0.5 * sin(dot(par, vec2(0.866, -0.5)) * 190.0 + phase * 9.0);
    float g2 = 0.5 + 0.5 * sin(dot(par, vec2(0.5, 0.866)) * 150.0 - phase * 7.0);
    float pattern = mix(1.0, 0.55 + 0.9 * g1 * (0.6 + 0.4 * g2), gratingAmt);

    vec3 col = mix(vec3(0.5), rainbow, rainbowAmt);
    col = 0.5 + (col - 0.5) * pattern;

    // lower tiers: soft satin bands, no colour
    float satin = 0.5 + 0.5 * sin(dot(par, vec2(1.0, 0.7)) * 5.0 + t.x * 2.0 + t.y * 1.2 + flow * 2.0);
    col = mix(col, vec3(0.5 + 0.26 * (satin - 0.5) * 2.0), (1.0 - rainbowAmt) * sheen);

    float strength = rainbowAmt > 0.0 ? (0.06 + 0.46 * rainbowAmt) : 0.4 * sheen;
    float a = foilMask * strength;
    fragColor = vec4(col * a, a);
    return;
  }

  // ---- light layer ---------------------------------------------------------
  vec3 add = vec3(0.0);

  // broad glare that slides with the tilt
  vec2 gpos = vec2(0.5 + t.x * 0.55, 0.32 + t.y * 0.55);
  vec2 dg = (uv - gpos) * vec2(1.0, uSize.y / uSize.x);
  float glare = pow(clamp(1.0 - length(dg) * 1.5, 0.0, 1.0), 2.2) * 0.30 * sheen;

  // brushed-metal streak
  vec2 dir = normalize(vec2(0.8, -0.6));
  float band = dot(uv - gpos, dir);
  float streak = exp(-band * band * 180.0) * 0.20 * sheen * (0.6 + 0.4 * fbm(uv * vec2(3.0, 40.0) + uSeed));

  vec3 tint = mix(vec3(1.0), film(band * 3.0 + t.x), rainbowAmt * 0.6);
  add += tint * (glare + streak);

  // glitter: every flake has its own normal and flashes when the view aligns
  if (glitterAmt > 0.0) {
    vec2 grid = px / 11.0;
    vec2 cell = floor(grid);
    vec2 off = hash22(cell + uSeed);
    vec2 f = fract(grid) - off * 0.7 - 0.15;
    float h = hash21(cell + 7.7);
    vec2 nrm = (hash22(cell + 3.1) - 0.5) * 1.6;
    float align = 1.0 - clamp(length(nrm - t * 0.9) * 2.2, 0.0, 1.0);
    float flash = pow(align, 6.0);
    float shape = smoothstep(0.30, 0.0, length(f));
    float density = step(1.0 - 0.18 * glitterAmt, h);
    add += (film(h * 3.0 + t.x) * 0.55 + 0.45) * flash * shape * density * 1.25 * glitterAmt * foilMask;
  }

  // lit bevel on the card edge, brighter on the side facing the light
  vec2 toEdge = normalize(px - uSize * 0.5 + vec2(0.001));
  float side = clamp(dot(toEdge, -t) * 1.2 + 0.35, 0.0, 1.0);
  float rim = (1.0 - smoothstep(0.0, 3.0, edgePx)) * (0.18 + 0.55 * side) * sheen;
  add += vec3(rim);

  // reveal sweep
  if (uSweep >= 0.0) {
    float d = (uv.x + uv.y * 0.7) - (uSweep * 2.2 - 0.4);
    add += mix(vec3(1.0), film(d * 2.0), rainbowAmt * 0.5) * exp(-d * d * 70.0) * 0.55;
  }

  float a = clamp(max(max(add.r, add.g), add.b), 0.0, 1.0);
  fragColor = vec4(min(add, vec3(a)), a);
}
