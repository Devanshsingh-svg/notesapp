#include <flutter/runtime_effect.glsl>

uniform vec2 uCameraOffset;
uniform float uZoom;
uniform float uPixelRatio;
uniform float uGrainStrength;

out vec4 fragColor;

float paperGrainNoise(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 logicalPos = FlutterFragCoord() / max(uPixelRatio, 1.0);
    vec2 worldPos = (logicalPos - uCameraOffset) / max(uZoom, 0.001);

    float n1 = paperGrainNoise(floor(worldPos * 1.4));
    float n2 = paperGrainNoise(floor(worldPos * 2.8 + 17.0));
    float tooth = mix(n1, n2, 0.4);

    float grainMask = smoothstep(0.15, 0.85, tooth);
    float alpha = mix(1.0, 0.30 + 0.70 * grainMask, clamp(uGrainStrength, 0.0, 1.0));

    fragColor = vec4(1.0, 1.0, 1.0, alpha);
}
