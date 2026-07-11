shader_type canvas_item;

// 스프라이트를 단색 실루엣으로 렌더링 (알파는 원본 유지)
uniform vec4 tint : source_color = vec4(0.13, 0.13, 0.18, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tint.rgb, tex.a * tint.a);
}
