#version 460 core
#include <flutter/runtime_effect.glsl>

// Soft moving colour blobs. uMode 0 = pastel light canvas, 1 = ember hero.
uniform vec2 uSize;
uniform float uTime;
uniform float uMode;

out vec4 fragColor;

float blob(vec2 uv, vec2 p, float k) {
  return exp(-dot(uv - p, uv - p) * k);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float t = uTime * 0.12;
  vec3 col;
  if (uMode < 0.5) {
    vec3 base = vec3(0.965, 0.961, 0.949);
    vec3 peach = vec3(1.0, 0.86, 0.80);
    vec3 lilac = vec3(0.87, 0.85, 0.98);
    vec3 mint = vec3(0.84, 0.95, 0.90);
    vec3 sky = vec3(0.84, 0.91, 0.99);
    col = base;
    col = mix(col, peach, blob(uv, vec2(0.12 + 0.10 * sin(t), 0.08 + 0.05 * cos(t * 1.3)), 5.0) * 0.9);
    col = mix(col, lilac, blob(uv, vec2(0.95 + 0.05 * cos(t * 0.9), 0.30 + 0.08 * sin(t)), 4.5) * 0.85);
    col = mix(col, mint, blob(uv, vec2(0.10 + 0.06 * cos(t * 1.1), 0.70 + 0.08 * sin(t * 0.8)), 4.0) * 0.7);
    col = mix(col, sky, blob(uv, vec2(0.85 + 0.08 * sin(t * 0.7), 0.95), 4.0) * 0.75);
  } else {
    vec3 top = vec3(1.0, 0.70, 0.28);
    vec3 mid = vec3(1.0, 0.35, 0.21);
    vec3 bot = vec3(0.10, 0.06, 0.08);
    float y = uv.y + 0.04 * sin(uv.x * 4.0 + t * 3.0);
    col = mix(top, mid, smoothstep(0.0, 0.45, y));
    col = mix(col, bot, smoothstep(0.42, 0.85, y));
    col += vec3(1.0, 0.55, 0.2) * blob(uv, vec2(0.8 + 0.1 * sin(t * 2.0), 0.25), 6.0) * 0.18;
  }
  fragColor = vec4(col, 1.0);
}
