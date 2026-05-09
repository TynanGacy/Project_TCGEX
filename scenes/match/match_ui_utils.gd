class_name MatchUIUtils

## Static UI helpers shared across match scene managers.


static func make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 120)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.97)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	return panel


static func zone_prefix(pid: int) -> String:
	return "" if pid == 0 else "Opp "


static func format_attack_cost(atk: AttackData) -> String:
	var parts: Array[String] = []
	for _i in range(atk.cost_fire):      parts.append("R")
	for _i in range(atk.cost_water):     parts.append("W")
	for _i in range(atk.cost_grass):     parts.append("G")
	for _i in range(atk.cost_lightning): parts.append("L")
	for _i in range(atk.cost_psychic):   parts.append("P")
	for _i in range(atk.cost_fighting):  parts.append("F")
	for _i in range(atk.cost_darkness):  parts.append("D")
	for _i in range(atk.cost_metal):     parts.append("M")
	for _i in range(atk.cost_colorless): parts.append("C")
	if parts.is_empty():
		return "[–]"
	return "[%s]" % "".join(parts)


## Returns the display label and tint color for an energy CardData entry,
## suitable for decorating checkboxes in energy-discard pickers.
static func energy_label_and_color(card: CardData) -> Dictionary:
	var name_str := card.display_name if card != null else "Energy"
	var type_str := ""
	if card is EnergyCardData:
		type_str = PokemonCardData.energy_type_to_string((card as EnergyCardData).energy_type)
	var label := "%s — %s" % [name_str, type_str.capitalize()] if type_str != "" else name_str
	return {"label": label, "color": AttachmentDisplay.energy_color(card)}
