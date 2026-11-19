shader_type canvas_item;
// Filtro de fita VHS por cima da tela: cores quentes e desbotadas,
// linhas de varredura, granulado animado, leve separação de cor e vinheta.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain_amount = 0.06;
uniform float scanline_strength = 0.07;
uniform float scanline_count = 360.0;
uniform float chroma_offset = 0.0018;
uniform float vignette = 0.35;
uniform float desaturate = 0.18;
uniform vec3 tint = vec3(1.03, 1.0, 0.93);

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(chroma_offset, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(chroma_offset, 0.0)).b;

	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray), desaturate);
	col = col * tint;
	col = mix(col, vec3(0.95, 0.92, 0.84), 0.035);  // véu creme, cor "lavada"

	col -= sin(uv.y * scanline_count * 3.14159) * scanline_strength * 0.5;
	col += (rand(uv * 600.0 + TIME) - 0.5) * grain_amount;

	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * vignette * 1.6;

	COLOR = vec4(col, 1.0);
}
