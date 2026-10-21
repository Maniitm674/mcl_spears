mcl_spears = {}

local S = core.get_translator(core.get_current_modname())

------------------------------------------------------------------------
-- 1. SPEAR DATA DEFINITION TABLE
------------------------------------------------------------------------
local SPEAR_TYPES = {
	wood = {
		description = S("Wooden Spear"),
		material = "group:wood",
		damage = 4.0,
		uses = 60,
		rarity = 1,
	},
	stone = {
		description = S("Stone Spear"),
		material = "mcl_core:cobble",
		damage = 5.0,
		uses = 132,
		rarity = 1,
	},
	iron = {
		description = S("Iron Spear"),
		material = "mcl_core:iron_ingot",
		damage = 6.0,
		uses = 250,
		rarity = 2,
	},
	gold = {
		description = S("Golden Spear"),
		material = "mcl_core:gold_ingot",
		damage = 4.0,
		uses = 32,
		rarity = 1,
	},
	diamond = {
		description = S("Diamond Spear"),
		material = "mcl_core:diamond",
		damage = 7.0,
		uses = 1562,
		rarity = 3,
	},
	netherite = {
		description = S("Netherite Spear"),
		material = "mcl_nether:netherite_ingot",
		damage = 8.0,
		uses = 2031,
		rarity = 4,
	},
}

------------------------------------------------------------------------
-- 2. HELPER FUNCTIONS FOR ENTITIES & SHOOTING
------------------------------------------------------------------------
local function rotate_spear_entity(obj, v)
	local yaw = math.atan2(v.z, v.x)
	local pitch = math.atan2(v.y, math.sqrt(v.z * v.z + v.x * v.x))
	local euler = vector.new(math.deg(-pitch), math.deg(-yaw) + 45, 0)
	obj:set_rotation(euler)
end

function mcl_spears.shoot_spear(spear_type, stack, obj, pos, yaw, pitch, dir)
	local dx, dy, dz
	if not dir then
		local ycos = math.cos(pitch)
		dx = -math.sin(yaw) * ycos
		dy = -math.sin(pitch)
		dz = math.cos(yaw) * ycos
	else
		local len = vector.length(dir)
		dx = dir.x / len
		dy = dir.y / len
		dz = dir.z / len
	end

	local v = vector.multiply(vector.new(dx, dy, dz), 40.0)
	local object = core.add_entity(pos, "mcl_spears:" .. spear_type .. "_entity")

	if object then
		object:set_velocity(v)
		local entity = object:get_luaentity()
		if obj and obj:is_player() then
			entity._shooter = obj:get_player_name()
		else
			entity._shooter = nil
		end
		entity._itemstack = stack
		rotate_spear_entity(object, v)

		core.sound_play("mcl_tridents_throw_1", {
			pos = pos, gain = 0.5, max_hear_distance = 16
		}, true)
		return true
	end
	return false
end

------------------------------------------------------------------------
-- 3. REGISTER SPEARS (ENTITIES, TOOLS, RECIPES)
------------------------------------------------------------------------
for name, def in pairs(SPEAR_TYPES) do
	local item_id = "mcl_spears:" .. name .. "_spear"
	local entity_id = "mcl_spears:" .. name .. "_entity"
	local tex_entity = "mcl_spears_" .. name .. "_spear_entity.png"
	local tex_wield = "mcl_spears_" .. name .. "_spear_wield.png"

	-- A. Entity Registration
	local spear_entity = {
		initial_properties = {
			visual = "sprite",
			textures = { tex_entity },
			visual_size = { x = 1.0, y = 1.0 },
			collisionbox = { -0.15, -0.15, -0.15, 0.15, 0.15, 0.15 },
			selectionbox = { 0, 0, 0, 0, 0, 0 },
			pointable = false,
			physical = true,
			collide_with_objects = false,
			static_save = true,
			use_texture_alpha = true,
		},
		_in_block = false,
		_shooter = nil,
		_itemstack = ItemStack(""),
		_timer = 0,
	}

	function spear_entity:on_step(dtime, moveresult)
		self._timer = self._timer + dtime
		local pos = self.object:get_pos()
		if not pos then return end

		local v = self.object:get_velocity()
		if not v then return end

		if not self._in_block then
			if v.x ~= 0 or v.y ~= 0 or v.z ~= 0 then
				rotate_spear_entity(self.object, v)
			end

			-- Mobs & Players collision
			for _, object in ipairs(core.get_objects_inside_radius(pos, 1.2)) do
				if object ~= self.object and (object:is_player() or (object:get_luaentity() and object:get_luaentity().is_mob)) then
					local shooter_obj = self._shooter and core.get_player_by_name(self._shooter) or nil
					local mcl_reason = {
						type = "spear",
						source = shooter_obj,
						direct = self.object,
					}
					if mcl_damage and mcl_damage.finish_reason then
						mcl_damage.finish_reason(mcl_reason)
					end

					if mcl_util and mcl_util.deal_damage then
						mcl_util.deal_damage(object, def.damage, mcl_reason)
					else
						object:punch(self.object, 1.1, {full_punch_interval = 1.1, damage_groups = {fleshy = def.damage}}, v)
					end

					-- Knockback
					local entity = object:get_luaentity()
					if entity and entity.is_mob and entity.projectile_knockback then
						entity:projectile_knockback(1, vector.normalize(v))
					elseif object:is_player() and mcl_player and mcl_player.player_knockback then
						mcl_player.player_knockback(object, self.object, vector.normalize(v), nil, def.damage)
					end

					core.sound_play("mcl_tridents_hit", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
					core.add_item(pos, self._itemstack)
					self.object:remove()
					return
				end
			end

			-- Block collisions
			if moveresult and moveresult.collisions and #moveresult.collisions > 0 then
				for _, collision in ipairs(moveresult.collisions) do
					if collision.type == "node" then
						self._in_block = true
						self.object:set_velocity(vector.zero())
						self.object:set_acceleration(vector.zero())
						self.object:set_properties({physical = false})
						core.sound_play("mcl_tridents_stuck", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
						break
					end
				end
			end
		else
			-- Item pickup
			for _, player in ipairs(core.get_connected_players()) do
				local ppos = player:get_pos()
				if ppos and vector.distance(pos, ppos) < 1.45 then
					local inv = player:get_inventory()
					if inv and inv:room_for_item("main", self._itemstack) then
						inv:add_item("main", self._itemstack)
					else
						core.add_item(pos, self._itemstack)
					end
					core.sound_play("default_place_node", {pos = pos, gain = 0.5}, true)
					self.object:remove()
					return
				end
			end
		end

		if self._timer > 60 then
			core.add_item(pos, self._itemstack)
			self.object:remove()
		end
	end

	function spear_entity:on_activate(staticdata, dtime)
		self.object:set_armor_groups({immortal = 1})
		if not self._in_block then
			self.object:set_acceleration(vector.new(0, -24, 0))
		end
	end

	core.register_entity(entity_id, spear_entity)

	-- B. Tool Item Registration
	core.register_tool(item_id, {
		description = def.description,
		_tt_help = S("A thrusting melee weapon that can be thrown"),
		groups = {
			weapon = 1,
			spear = 1,
			enchantability = 1,
			rarity = def.rarity,
			offhand_item = 1,
		},
		inventory_image = tex_wield,
		wield_image = tex_wield,
		wield_scale = vector.new(2.0, 2.0, 1.0),
		stack_max = 1,
		_mcl_uses = def.uses,
		tool_capabilities = {
			full_punch_interval = 1.2,
			max_drop_level = 1,
			damage_groups = {
				fleshy = def.damage + 1,
			},
		},
		_on_dispense = function(itemstack, dispenserpos, _, _, dropdir)
			local shootpos = vector.add(dispenserpos, vector.multiply(dropdir, 0.6))
			mcl_spears.shoot_spear(name, itemstack:take_item(), nil, shootpos, nil, nil, dropdir)
		end,
	})

	-- C. Crafting Recipe
	if name ~= "netherite" then
		core.register_craft({
			output = item_id,
			recipe = {
				{"", "", def.material},
				{"", "mcl_core:stick", ""},
				{"mcl_core:stick", "", ""}
			}
		})
	end
end

-- Netherite Upgrade Recipe
if mcl_smithing and mcl_smithing.register_upgrade then
	mcl_smithing.register_upgrade({
		type = "upgrade",
		base = "mcl_spears:diamond_spear",
		addition = "mcl_nether:netherite_ingot",
		template = "mcl_smithing:netherite_upgrade_smithing_template",
		result = "mcl_spears:netherite_spear",
	})
else
	core.register_craft({
		output = "mcl_spears:netherite_spear",
		recipe = {
			{"mcl_nether:netherite_ingot", "mcl_spears:diamond_spear"}
		}
	})
end

------------------------------------------------------------------------
-- 4. TAP & HOLD RMB CHARGE MECHANIC
------------------------------------------------------------------------
local spear_held_times = {}

core.register_on_joinplayer(function(player)
	spear_held_times[player] = -math.huge
end)

core.register_on_leaveplayer(function(player)
	spear_held_times[player] = nil
end)

if controls and controls.register_on_hold then
	controls.register_on_hold(function(player, key)
		if key ~= "RMB" then return end
		local wielditem = player:get_wielded_item()
		if core.get_item_group(wielditem:get_name(), "spear") > 0 then
			if spear_held_times[player] == -math.huge then
				spear_held_times[player] = 0
			end
		end
	end)

	core.register_globalstep(function(dtime)
		for player, time in pairs(spear_held_times) do
			if time ~= -math.huge then
				if time < 0.4 and time + dtime >= 0.4 then
					if mcl_title and mcl_title.set then
						mcl_title.set(player, "actionbar", {
							text = S("Spear cocked. Release RMB to throw."),
							stay = 20,
						})
					end
				end
				spear_held_times[player] = time + dtime
			end
		end
	end)

	controls.register_on_release(function(player, key)
		if key ~= "RMB" then return end
		local wielditem = player:get_wielded_item()
		local name = wielditem:get_name()
		local creative = core.is_creative_enabled(player:get_player_name())

		if core.get_item_group(name, "spear") > 0 and (spear_held_times[player] or 0) >= 0.4 then
			local spear_type = name:match("mcl_spears:(%w+)_spear")
			if spear_type and SPEAR_TYPES[spear_type] then
				local item = wielditem:take_item()
				local pos = mcl_util.target_eye_pos(player)
				local yaw = player:get_look_horizontal()
				local pitch = player:get_look_vertical()

				if mcl_spears.shoot_spear(spear_type, item, player, pos, yaw, pitch, nil) then
					if not creative then
						player:set_wielded_item(wielditem)
					end
				end
			end
		end
		spear_held_times[player] = -math.huge
	end)
end