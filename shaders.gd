## All shaders as source strings. No .gdshader files, no textures sampled.
class_name Shaders
extends RefCounted

const NOISE := """
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1.0,0.0)), f.x), mix(hash(i+vec2(0.0,1.0)), hash(i+vec2(1.0,1.0)), f.x), f.y); }
float fbm(vec2 p){ float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++){ v += a*vnoise(p); p = p*2.03 + 1.7; a *= 0.5; } return v; }
"""

## Torch flame: a Y-billboarded quad whose whole look is evaluated per pixel.
const FLAME := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float seed = 0.0;
""" + NOISE + """
void vertex(){
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = cross(right, up);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
}
void fragment(){
	float y = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME + seed;
	float n = fbm(vec2(x * 2.5 + seed, y * 3.0 - t * 4.0));
	float n2 = fbm(vec2(x * 5.0 - seed, y * 6.0 - t * 7.0));
	float w = mix(0.75, 0.05, pow(y, 0.8));
	float xs = x + (n - 0.5) * 0.6 * y;
	float body = 1.0 - smoothstep(w * 0.45, w, abs(xs));
	body *= smoothstep(0.0, 0.1, y) * (1.0 - smoothstep(0.35, 0.95, y + (n2 - 0.5) * 0.5));
	float heat = body * (0.55 + 0.7 * n);
	vec3 c = mix(vec3(0.9, 0.18, 0.02), vec3(1.0, 0.62, 0.18), smoothstep(0.2, 0.7, heat));
	c = mix(c, vec3(1.0, 0.93, 0.75), smoothstep(0.75, 1.1, heat));
	ALBEDO = c * heat * 3.2;
}
"""

## Fake volumetric moon shaft: additive cone, brightest where it is seen through
## the most "air" (facing ratio), faded at both ends, with drifting dust noise.
const SHAFT := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float height = 14.0;
uniform vec3 tint : source_color = vec3(0.55, 0.65, 0.95);
varying vec3 wpos;
varying float hy;
""" + NOISE + """
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; hy = VERTEX.y / height + 0.5; }
void fragment(){
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, 3.0);
	float fade = smoothstep(0.0, 0.18, hy) * (1.0 - smoothstep(0.7, 1.0, hy));
	float dust = 0.55 + 0.45 * fbm(vec2(wpos.x * 1.3 + wpos.y * 0.4, wpos.z * 1.3 - TIME * 0.15));
	ALBEDO = tint * (0.25 + edge) * fade * dust * 0.30;
}
"""

## Screen-space finish: vignette + animated film grain, no texture.
const GRADE := """
shader_type canvas_item;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	float d = distance(SCREEN_UV, vec2(0.5, 0.5));
	float vig = smoothstep(0.32, 0.9, d) * 0.7;
	float g = h(floor(FRAGCOORD.xy) + fract(TIME * 7.13) * 91.0) - 0.5;
	COLOR = vec4(vec3(0.5 + g * 0.3), clamp(vig + abs(g) * 0.025, 0.0, 1.0));
	COLOR.rgb *= (1.0 - vig);
}
"""
