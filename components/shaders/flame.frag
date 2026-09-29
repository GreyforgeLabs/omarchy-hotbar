#version 440
// Hotbar Places cell — the hot bar. A hollow pill with an ember outline, a
// flame highlight sweeping along it, and either a short amber bar (minimal)
// or the HOTBAR letters (badge) sharing the sweep. Everything the old Canvas
// painted per frame in JavaScript is computed here per pixel on the GPU;
// the CPU only moves `phase` and `heat`.
//
// Compiled with qsb (see Makefile `shaders`); Qt 6 loads the .qsb.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // item size in pixels
    float lineWidth;  // outline stroke width (px)
    float phase;      // 0..1 position of the lick along the pill
    float lick;       // flame intensity already scaled by heat/lit (0..1)
    float glow;       // alpha of the ember glow behind the outline
    float vertical;   // 1 when the bar is vertical (sweep runs along y)
    float badge;      // 1: letters from the texture; 0: the minimal amber bar
    vec4 ember;       // outline base colour
    vec4 flame;       // amber
    vec4 hot;         // near-white peak
};
layout(binding = 1) uniform sampler2D letters;

// Signed distance to a rounded rectangle (pill when r = half the short side).
float pillDistance(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - (halfSize - vec2(r));
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Heat of the sweep at 0..1 along the pill, wrapping at the ends (the same
// curve the Canvas used: a quadratic bump 0.22 wide).
float lickAt(float t) {
    float d = abs(t - phase);
    d = min(d, 1.0 - d);
    float k = max(0.0, 1.0 - d / 0.22);
    return k * k * lick;
}

vec3 outlineColor(float t) {
    float k = lickAt(t);
    return k < 0.5 ? mix(ember.rgb, flame.rgb, k * 2.0) : mix(flame.rgb, hot.rgb, clamp((k - 0.5) * 1.6, 0.0, 1.0));
}

vec3 textColor(float t) {
    return mix(flame.rgb, hot.rgb, clamp(lickAt(t) * 0.9, 0.0, 1.0));
}

void main() {
    vec2 px = qt_TexCoord0 * size;
    // Same geometry as the Canvas: a 3 px margin for the glow, the stroke
    // centred inside it.
    float inset = 3.0 + lineWidth * 0.5;
    vec2 origin = vec2(inset);
    vec2 extent = size - 2.0 * origin;
    vec2 centre = origin + extent * 0.5;
    float r = min(extent.x, extent.y) * 0.5;
    float d = pillDistance(px - centre, extent * 0.5, r);
    float t = vertical > 0.5 ? (px.y - origin.y) / extent.y : (px.x - origin.x) / extent.x;

    // Ember glow: a stroke three times as wide, at `glow` alpha.
    float glowMask = 1.0 - smoothstep(lineWidth * 1.5 - 0.75, lineWidth * 1.5 + 0.75, abs(d));
    vec3 color = ember.rgb * glow * glowMask;
    float alpha = glow * glowMask;

    // The outline with the flame sweep.
    float strokeMask = 1.0 - smoothstep(lineWidth * 0.5 - 0.75, lineWidth * 0.5 + 0.75, abs(d));
    vec3 stroke = outlineColor(t);
    color = mix(color, stroke, strokeMask);
    alpha = alpha + strokeMask * (1.0 - alpha);

    if (badge < 0.5) {
        // Minimal: a short amber bar in the middle of the pill.
        float along = vertical > 0.5 ? extent.y : extent.x;
        float across = vertical > 0.5 ? extent.x : extent.y;
        float barLength = floor(along * 0.42 + 0.5);
        float barThick = max(2.0, floor(across * 0.24 + 0.5));
        vec2 halfBar = vertical > 0.5 ? vec2(barThick, barLength) * 0.5 : vec2(barLength, barThick) * 0.5;
        vec2 q = abs(px - centre) - halfBar;
        float barMask = 1.0 - smoothstep(-0.5, 0.5, max(q.x, q.y));
        vec3 bar = textColor(t);
        color = mix(color, bar, barMask);
        alpha = alpha + barMask * (1.0 - alpha);
    } else {
        // Badge: the letters come pre-rendered (white, premultiplied) and
        // take the sweep colour.
        float textMask = texture(letters, qt_TexCoord0).a;
        vec3 text = textColor(t);
        color = mix(color, text, textMask);
        alpha = alpha + textMask * (1.0 - alpha);
    }

    fragColor = vec4(color * alpha, alpha) * qt_Opacity;
}
