----------------------------------------------------------------------------------------------------
-- Blacklist Reborn: data layer
--
-- Entries live in BlackListedPlayers[GetRealmName()] as an array, exactly as before, so existing
-- saved variables load untouched. Each entry may carry an optional "realm" field; nil means the
-- player's own realm. A runtime key -> entry map (BlackList.index) backs every lookup so events do
-- not have to walk the whole list.
----------------------------------------------------------------------------------------------------

-- Runtime lookup map, rebuilt whenever the list changes. Never saved.
BlackList.index = {};

-- Returns the array of entries for the current realm, creating it if needed.
function BlackList:GetList()

	local realm = GetRealmName();

	if (not BlackListedPlayers) then BlackListedPlayers = {}; end
	if (not BlackListedPlayers[realm]) then BlackListedPlayers[realm] = {}; end

	return BlackListedPlayers[realm];

end

-- Capitalises a name the way the game displays it. Left alone for locales where that makes no sense.
function BlackList:NormalizeName(name)

	if (not name or name == "") then return nil; end

	local locale = GetLocale();
	if ((locale == "zhTW") or (locale == "zhCN") or (locale == "koKR")) then
		return name;
	end

	-- Step over one (possibly multi-byte) leading character before upper/lowering.
	local _, len = string.find(name, "[%z\1-\127\194-\244][\128-\191]*");
	if (not len) then return name; end

	return string.upper(string.sub(name, 1, len)) .. string.lower(string.sub(name, len + 1));

end

-- Splits "Name-Realm" into its parts. A realm equal to our own is folded back to nil.
function BlackList:SplitName(name, realm)

	if (not name or name == "") then return nil, nil; end

	if (not realm) then
		local n, r = string.match(name, "^([^%-]+)%-(.+)$");
		if (n) then
			name = n;
			realm = r;
		end
	end

	if (realm == "" or realm == GetRealmName()) then realm = nil; end

	return self:NormalizeName(name), realm;

end

-- The map key for a name/realm pair. Realm-less entries key on the name alone.
function BlackList:GetKey(name, realm)

	if (not name or name == "") then return nil; end

	if (realm and realm ~= "" and realm ~= GetRealmName()) then
		return string.lower(name) .. "-" .. string.lower(realm);
	end

	return string.lower(name);

end

-- Rebuilds the lookup map from the stored array.
function BlackList:RebuildIndex()

	local list = self:GetList();

	self.index = {};

	for i = 1, table.getn(list) do
		local player = list[i];
		local key = self:GetKey(player["name"], player["realm"]);
		if (key) then
			player["listIndex"] = i;
			self.index[key] = player;
		end
	end

end

-- Finds an entry. A bare name matches the same-realm entry first; failing that, it matches a
-- realm-qualified entry only when exactly one realm carries that name.
function BlackList:GetPlayer(name, realm)

	name, realm = self:SplitName(name, realm);

	local key = self:GetKey(name, realm);
	if (not key) then return nil; end

	local player = self.index[key];
	if (player) then return player; end

	if (realm) then return nil; end

	-- Bare name: accept a realm-qualified entry when it is unambiguous.
	local prefix = key .. "-";
	local match;
	for otherKey, other in pairs(self.index) do
		if (string.sub(otherKey, 1, string.len(prefix)) == prefix) then
			if (match) then return nil; end
			match = other;
		end
	end

	return match;

end

-- True when the player is blacklisted and flagged to warn.
function BlackList:ShouldWarn(name, realm)

	local player = self:GetPlayer(name, realm);
	return (player and player["warn"]) and player or nil;

end

-- "Name" or "Name (Realm)" for display.
function BlackList:FormatName(name, realm)

	if (realm and realm ~= "" and realm ~= GetRealmName()) then
		return name .. " (" .. realm .. ")";
	end

	return name;

end

function BlackList:FormatPlayer(player)

	return self:FormatName(player["name"], player["realm"]);

end

----------------------------------------------------------------------------------------------------
-- Adding and removing
----------------------------------------------------------------------------------------------------

-- Blacklists a player. "target" pulls the name, level, class and race off the current target.
function BlackList:AddPlayer(player, warn, reason, realm)

	local name, level, class, race, raceEn;

	if (player == "" or player == nil) then
		return;
	elseif (player == "target") then
		if (UnitIsPlayer("target") and not UnitIsUnit("target", "player")) then
			name, realm = UnitName("target");
			level = UnitLevel("target") .. "";
			class = UnitClass("target");
			-- Keep both: the first return is localised and shown, the second is the locale-free
			-- token the faction lookup needs.
			race, raceEn = UnitRace("target");
		else
			self:ShowNameDialog();
			return;
		end
	else
		name = player;
		level = "";
		class = "";
		race = "";
	end

	name, realm = self:SplitName(name, realm);
	if (not name) then return; end

	if (self:GetKey(name, realm) == self:GetKey(UnitName("player"))) then
		self:AddMessage(BL_CANNOT_BLACKLIST_SELF, "yellow");
		return;
	end

	if (self.index[self:GetKey(name, realm)]) then
		self:AddMessage(self:FormatName(name, realm) .. " " .. BL_ALREADY_BLACKLISTED, "yellow");
		return;
	end

	if (warn == nil) then warn = true; end
	if (reason == nil) then reason = ""; end

	local entry = {
		["name"] = name,
		["realm"] = realm,
		["warn"] = warn,
		["reason"] = reason,
		["added"] = time(),
		["level"] = level or "",
		["class"] = class or "",
		["race"] = race or "",
		["raceEn"] = raceEn,
	};

	table.insert(self:GetList(), entry);
	self:Sort();

	self:AddMessage(self:FormatName(name, realm) .. " " .. BL_ADDED_TO_BLACKLIST, "yellow");

	self:UpdateUI();

	-- A player added while you are already grouped with them should still produce a notice.
	self:CheckGroup();

end

-- Removes a player. "target" uses the current target; nil falls back to the selected row.
function BlackList:RemovePlayer(player, realm)

	local name;

	if (player == "target") then
		name, realm = UnitName("target");
	else
		name = player;
	end

	local entry;

	if (name and name ~= "") then
		entry = self:GetPlayer(name, realm);
	else
		entry = self:GetPlayerByIndex(self:GetSelectedBlackList());
	end

	if (not entry) then
		self:AddMessage(BL_PLAYER_NOT_FOUND, "yellow");
		return;
	end

	local list = self:GetList();
	for i = 1, table.getn(list) do
		if (list[i] == entry) then
			table.remove(list, i);
			break;
		end
	end

	self:RebuildIndex();

	self:AddMessage(self:FormatPlayer(entry) .. " " .. BL_REMOVED_FROM_BLACKLIST, "yellow");

	self:UpdateUI();

end

-- Updates the details of the entry at the given index. Only non-nil fields are written.
function BlackList:UpdateDetails(index, warn, reason, level, class, race, raceEn)

	local player = self:GetPlayerByIndex(index);
	if (not player) then return; end

	if (warn ~= nil) then player["warn"] = warn; end
	if (reason ~= nil) then player["reason"] = reason; end
	if (level ~= nil) then player["level"] = level; end
	if (class ~= nil) then player["class"] = class; end
	if (race ~= nil) then player["race"] = race; end
	if (raceEn ~= nil) then player["raceEn"] = raceEn; end

end

----------------------------------------------------------------------------------------------------
-- List accessors
----------------------------------------------------------------------------------------------------

function BlackList:GetNumBlackLists()

	return table.getn(self:GetList());

end

function BlackList:GetPlayerByIndex(index)

	local list = self:GetList();

	if (not index or index < 1 or index > table.getn(list)) then
		return nil;
	end

	return list[index];

end

function BlackList:GetNameByIndex(index)

	local player = self:GetPlayerByIndex(index);
	if (not player) then return nil; end

	return self:FormatPlayer(player);

end

function BlackList:GetIndexByName(name, realm)

	local player = self:GetPlayer(name, realm);
	if (not player) then return 0; end

	local list = self:GetList();
	for i = 1, table.getn(list) do
		if (list[i] == player) then return i; end
	end

	return 0;

end

----------------------------------------------------------------------------------------------------
-- Sorting
----------------------------------------------------------------------------------------------------

function BlackList:Sort()

	table.sort(self:GetList(), BlackList.Comparator);
	self:RebuildIndex();

end

-- Case-insensitive name sort, realm as the tie-breaker. Must return false for equal entries or
-- table.sort raises "invalid order function for sorting".
function BlackList.Comparator(a, b)

	local nameA = string.lower(a["name"] or "");
	local nameB = string.lower(b["name"] or "");

	if (nameA ~= nameB) then
		return nameA < nameB;
	end

	return string.lower(a["realm"] or "") < string.lower(b["realm"] or "");

end

----------------------------------------------------------------------------------------------------
-- Migration
----------------------------------------------------------------------------------------------------

-- Brings pre-4.0 saved data up to date: splits "Name-Realm", normalises capitalisation, fills in
-- missing fields and drops the retired per-player ignore flag.
function BlackList:MigrateDB()

	local list = self:GetList();

	for i = 1, table.getn(list) do
		local player = list[i];

		local name, realm = self:SplitName(player["name"], player["realm"]);
		player["name"] = name or player["name"];
		player["realm"] = realm;

		if (player["warn"] == nil) then player["warn"] = true; end
		if (player["reason"] == nil) then player["reason"] = ""; end
		if (player["added"] == nil) then player["added"] = time(); end
		if (player["level"] == nil) then player["level"] = ""; end
		if (player["class"] == nil) then player["class"] = ""; end
		if (player["race"] == nil) then player["race"] = ""; end

		player["ignore"] = nil;
	end

	self:Sort();

	BlackListConfig.dbVersion = 2;

end

----------------------------------------------------------------------------------------------------
-- Output helpers
----------------------------------------------------------------------------------------------------

local BL_COLORS = {
	["red"]    = { 1.0, 0.0, 0.0 },
	["yellow"] = { 1.0, 1.0, 0.0 },
	["white"]  = { 1.0, 1.0, 1.0 },
};

function BlackList:AddMessage(msg, color, force)

	if (not force and BlackListConfig and not BlackListConfig.Chat) then return; end

	local rgb = BL_COLORS[color] or BL_COLORS["white"];

	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage(msg, rgb[1], rgb[2], rgb[3]);
	end

end

function BlackList:AddErrorMessage(msg, color, timeout)

	if (BlackListConfig and not BlackListConfig.Center) then return; end

	local rgb = BL_COLORS[color] or BL_COLORS["white"];

	if (UIErrorsFrame) then
		UIErrorsFrame:AddMessage(msg, rgb[1], rgb[2], rgb[3], nil, timeout);
	end

end

function BlackList:AddSound()

	if (BlackListConfig and not BlackListConfig.Sound) then return; end

	PlaySound("PVPTHROUGHQUEUE");

end

----------------------------------------------------------------------------------------------------
-- Misc
----------------------------------------------------------------------------------------------------

-- Faction from a race. Uses the locale-independent race token when one is supplied, since
-- UnitRace()'s first return is localised.
function BL_GetFaction(race, returnText)

	local factions = { "Alliance", "Horde", "Unknown" };
	local faction = 3;

	if (race == "Human" or race == "Dwarf" or race == "NightElf" or race == "Night Elf"
			or race == "Gnome" or race == "Draenei") then
		faction = 1;
	elseif (race == "Orc" or race == "Scourge" or race == "Undead" or race == "Tauren"
			or race == "Troll" or race == "BloodElf" or race == "Blood Elf") then
		faction = 2;
	end

	if (returnText) then
		return factions[faction];
	end

	return faction;

end
