extends CanvasLayer
# Colour-blind assistance: a full-screen shader that shifts the colours a given kind of colour blindness cannot tell apart
# (red / green / blue) into ones that it can. Off by default, and costs nothing while off.

const MODES := ["Off", "Protanopia (red)", "Deuteranopia (green)", "Tritanopia (blue)"]

const SHADER := """
shader_type canvas_item;
uniform int mode = 1;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0).rgb;
	vec3 r0; vec3 r1; vec3 r2; vec3 e0; vec3 e1; vec3 e2;
	if (mode == 1) {
		r0 = vec3(0.152286, 1.052583, -0.204868); r1 = vec3(0.114503, 0.786281, 0.099216); r2 = vec3(-0.003882, -0.048116, 1.051998);
		e0 = vec3(0.0); e1 = vec3(0.7, 1.0, 0.0); e2 = vec3(0.7, 0.0, 1.0);
	} else if (mode == 2) {
		r0 = vec3(0.367322, 0.860646, -0.227968); r1 = vec3(0.280085, 0.672501, 0.047413); r2 = vec3(-0.011820, 0.042940, 0.968881);
		e0 = vec3(0.0); e1 = vec3(0.7, 1.0, 0.0); e2 = vec3(0.7, 0.0, 1.0);
	} else {
		r0 = vec3(1.255528, -0.076749, -0.178779); r1 = vec3(-0.078411, 0.930809, 0.147602); r2 = vec3(0.004733, 0.691367, 0.303900);
		e0 = vec3(1.0, 0.0, 0.7); e1 = vec3(0.0, 1.0, 0.7); e2 = vec3(0.0);
	}
	vec3 sim = vec3(dot(r0, c), dot(r1, c), dot(r2, c));
	vec3 err = c - sim;
	vec3 fixed = c + vec3(dot(e0, err), dot(e1, err), dot(e2, err));
	COLOR = vec4(mix(c, clamp(fixed, 0.0, 1.0), strength), 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial


func _ready() -> void:
	layer = 120
	rect = ColorRect.new()
	rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	apply()


# Reads the preference (0 = off, 1..3 = the three kinds) and shows or hides the filter.
func apply() -> void:
	var m := int(Settings.pref("colorblind"))
	rect.visible = m > 0
	if m > 0:
		mat.set_shader_param("mode", m)
		mat.set_shader_param("strength", float(Settings.pref("colorblind_strength")))
