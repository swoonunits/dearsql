// sample custom shader for DearSQL (Shadertoy / Ghostty compatible).
// iChannel0 is the rendered app; iResolution / iTime are provided.
// load it with:  DEARSQL_CUSTOM_SHADER=assets/shaders/sample.glsl open DearSQL.app
// a gentle animated chromatic-aberration + scanline wobble over the UI.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // wavy horizontal displacement that drifts over time
    float wave = sin(uv.y * 40.0 + iTime * 2.0) * 0.0015;

    // sample the app with a small per-channel offset -> chromatic aberration
    float r = texture(iChannel0, uv + vec2(wave + 0.0010, 0.0)).r;
    float g = texture(iChannel0, uv + vec2(wave, 0.0)).g;
    float b = texture(iChannel0, uv + vec2(wave - 0.0010, 0.0)).b;
    float a = texture(iChannel0, uv).a;

    vec3 col = vec3(r, g, b);

    // faint moving scanlines
    col *= 0.92 + 0.08 * sin(uv.y * iResolution.y * 1.5 - iTime * 6.0);

    fragColor = vec4(col, a);
}
