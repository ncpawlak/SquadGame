shader_type canvas_item;
// Portrait photo face: hair/brow tint + graying (mask red), iris recolour (mask green), team-coloured jersey,
// and a circular clip. The head image and mask are baked by tools/portraits/bake.py.

uniform sampler2D mask_tex : filter_linear;
uniform vec3 hair_mul = vec3(1.0);
uniform vec3 hair_add = vec3(0.0);
uniform float gray = 0.0;
uniform float eye_on = 0.0;
uniform float eye_hue = 0.07;
uniform float eye_sat = 0.6;
uniform vec3 team_col = vec3(0.5);
uniform float jersey_v = 0.8;
uniform vec2 clip_center = vec2(0.0);
uniform float clip_radius = 1.0;

varying vec2 local;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	if (length(local - clip_center) > clip_radius) {
		discard;
	}
	vec4 base = texture(TEXTURE, UV);
	vec3 m = texture(mask_tex, UV).rgb;
	vec3 c = base.rgb;
	// Hair, beard and brows.
	vec3 hair = c * hair_mul + hair_add;
	hair = mix(hair, vec3(0.74, 0.73, 0.71), gray);
	c = mix(c, hair, m.r);
	// Iris.
	if (eye_on > 0.5) {
		vec3 hsv = rgb2hsv(c);
		vec3 eye = hsv2rgb(vec3(eye_hue, mix(hsv.y, eye_sat, 0.65), hsv.z));
		c = mix(c, eye, m.g);
	}
	// Jersey: near-white, low-saturation pixels below the chin take the team colour.
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	float sat = rgb2hsv(c).y;
	float w = smoothstep(0.59, 0.78, luma) * (1.0 - smoothstep(0.03, 0.07, sat)) * smoothstep(jersey_v, jersey_v + 0.03, UV.y);
	c = mix(c, clamp(team_col * luma * 1.1, 0.0, 1.0), w);
	COLOR = vec4(c, base.a);
}
