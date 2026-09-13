----------------------------------------------------------------------------------------------------
-- Blacklist Reborn: roster helpers
--
-- 3.3.5 has no GetNumGroupMembers/IsInRaid, and party and raid rosters are two separate APIs, so
-- everything that needs "who am I grouped with" goes through here.
----------------------------------------------------------------------------------------------------

-- "RAID" when in a raid, "PARTY" when in a party, nil when solo.
function BlackList:GetGroupChannel()

	if (GetNumRaidMembers() > 0) then return "RAID"; end
	if (GetNumPartyMembers() > 0) then return "PARTY"; end

	return nil;

end

function BlackList:IsInRaid()

	return GetNumRaidMembers() > 0;

end

function BlackList:IsInGroup()

	return (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0);

end

-- Everyone in your current group except you.
-- Returns { { name = , realm = , unit = , subgroup = }, ... }; empty when solo.
function BlackList:GetGroupMembers()

	local members = {};

	if (GetNumRaidMembers() > 0) then
		for i = 1, GetNumRaidMembers() do
			local unit = "raid" .. i;

			if (not UnitIsUnit(unit, "player")) then
				local name, realm = UnitName(unit);

				if (name and name ~= "" and name ~= UNKNOWNOBJECT) then
					local _, _, subgroup = GetRaidRosterInfo(i);
					table.insert(members, {
						name = name,
						realm = realm,
						unit = unit,
						subgroup = subgroup,
					});
				end
			end
		end

	elseif (GetNumPartyMembers() > 0) then
		for i = 1, GetNumPartyMembers() do
			local unit = "party" .. i;
			local name, realm = UnitName(unit);

			if (name and name ~= "" and name ~= UNKNOWNOBJECT) then
				table.insert(members, {
					name = name,
					realm = realm,
					unit = unit,
				});
			end
		end
	end

	return members;

end

-- Everyone in your guild. Requires the roster to have been fetched; see BlackList:RequestGuildRoster.
-- Returns { { name = , realm = , rank = , level = , class = , online = }, ... }.
function BlackList:GetGuildMembers()

	local members = {};

	if (not IsInGuild()) then return members; end

	for i = 1, GetNumGuildMembers() do
		local name, rank, rankIndex, level, class, zone, note, officernote, online = GetGuildRosterInfo(i);

		if (name and name ~= "") then
			local shortName, realm = self:SplitName(name);
			table.insert(members, {
				name = shortName or name,
				realm = realm,
				rank = rank,
				level = level,
				class = class,
				online = online,
			});
		end
	end

	return members;

end

-- The guild roster is only populated after the server answers GuildRoster(), and it only contains
-- offline members while the Guild tab's "Show Offline" box is ticked. Both are handled here: the
-- setting is flipped on if needed and put back exactly as it was once the data has been read.
-- Returns true when the roster is usable right now, false when the callback will run later.
function BlackList:RequestGuildRoster(callback)

	if (not IsInGuild()) then return false; end

	local showOffline = GetGuildRosterShowOffline();

	if (showOffline and GetNumGuildMembers() > 0) then
		GuildRoster();
		return true;
	end

	self.pendingGuildRoster = callback;
	self.restoreShowOffline = (not showOffline) or nil;

	self:RegisterEvent("GUILD_ROSTER_UPDATE");

	if (not showOffline) then
		SetGuildRosterShowOffline(true);
	end

	GuildRoster();

	return false;

end

function BlackList:OnGuildRoster()

	local callback = self.pendingGuildRoster;
	local restore = self.restoreShowOffline;

	self.pendingGuildRoster = nil;
	self.restoreShowOffline = nil;
	self:UnregisterEvent("GUILD_ROSTER_UPDATE");

	if (callback) then callback(); end

	-- Put the player's own Guild tab preference back. Safe now that we are no longer listening.
	if (restore) then
		SetGuildRosterShowOffline(false);
	end

end

-- Matches a roster list against the black list. Returns the matching entries plus, for each, the
-- roster record it came from.
function BlackList:FilterBlackListed(members)

	local matches = {};
	local seen = {};

	for i = 1, table.getn(members) do
		local member = members[i];
		local player = self:GetPlayer(member.name, member.realm);

		if (player) then
			local key = self:GetKey(player["name"], player["realm"]);

			if (not seen[key]) then
				seen[key] = true;
				table.insert(matches, { player = player, member = member });
			end
		end
	end

	return matches;

end
