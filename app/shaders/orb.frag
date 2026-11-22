#version 460 core
#include <flutter/runtime_effect.glsl>

// Iridescent glass orb (rank badge, empty states).
uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

vec3 hue(float h) {
  vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
  vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
  return clamp(p - 1.0, 0.0, 1.0);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv * 2.0 - 1.0;
  float r = length(p);
  if (r > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  float z = sqrt(1.0 - r * r);
  vec3 n = vec3(p, z);
  vec3 l = normalize(vec3(-0.5, -0.6, 0.7));
  float diff = clamp(dot(n, l), 0.0, 1.0);
  float fres = pow(1.0 - z, 2.2);
  float h = 0.55 + n.x * 0.18 - n.y * 0.12 + sin(uTime * 0.6 + n.y * 2.0) * 0.06;
  vec3 base = mix(vec3(0.80, 0.86, 1.0), vec3(1.0, 0.85, 0.92), diff);
  vec3 irid = hue(h) * 0.55 + 0.45;
  vec3 col = mix(base, irid, 0.55 * (0.4 + fres));
  col += vec3(1.0) * pow(diff, 14.0) * 0.8;
  col = mix(col, vec3(1.0), fres * 0.25);
  float edge = smoothstep(1.0, 0.97, r);
  fragColor = vec4(col * edge, edge);
}
