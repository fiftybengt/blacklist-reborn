----------------------------------------------------------------------------------------------------
-- Blacklist Reborn: slash commands
--
--   /bl                       toggle the Black List window
--   /bl help                  command list
--   /bl add [name] [reason]   blacklist a name, or your target if omitted
--   /bl remove [name]         remove a name, or your target / the selected row
--   /bl list                  blacklisted members of your current group (raid if in a raid)
--   /bl list -g               blacklisted members of your guild
--   /bl warn [-p|-r|-g]       announce them; no flag means raid if in a raid, else party
--   /bl reason on|off         include the blacklist reason in /bl warn (saved, default off)
--   /bl show | /bl options    open the window / the options panel
--
-- Flags always take a dash. /bl -p, /bl -r and /bl -g are shorthand for /bl warn -p|-r|-g.
----------------------------------------------------------------------------------------------------

-- SendChatMessage is capped at 255 characters and bursts get throttled, so announcements are
-- queued and drained slowly, one player per line.
local BL_CHAT_MAX = 255;
local BL_CHAT_INTERVAL = 0.3;

-- Most players announced by one /bl warn; the rest are summed up in a final line.
local BL_MAX_WARN_PLAYERS = 10;

local queue = {};
local queueElapsed = 0;
local queueFrame;

local function BL_DrainQueue(self, elapsed)

	queueElapsed = queueElapsed + elapsed;
	if (queueElapsed < BL_CHAT_INTERVAL) then return; end
	queueElapsed = 0;

	local entry = table.remove(queue, 1);
	if (not entry) then
		self:Hide();
		return;
	end

	SendChatMessage(entry.text, entry.channel);

end

local function BL_Announce(lines, channel)

	for i = 1, table.getn(lines) do
		table.insert(queue, { text = lines[i], channel = channel });
	end

	if (not queueFrame) then
		queueFrame = CreateFrame("Frame", "BlackListChatQueueFrame", UIParent);
		queueFrame:SetScript("OnUpdate", BL_DrainQueue);
	end

	queueElapsed = BL_CHAT_INTERVAL;
	queueFrame:Show();

end

-- Cuts a line to the chat limit: max characters minus 2, then "..". Backs off to a whole UTF-8
-- character so a name or reason in another alphabet is never split mid-character.
local function BL_FitChatLine(line)

	if (string.len(line) <= BL_CHAT_MAX) then return line; end

	local cut = BL_CHAT_MAX - 2;
	local nextByte = string.byte(line, cut + 1);

	while (cut > 0 and nextByte and nextByte >= 128 and nextByte <= 191) do
		cut = cut - 1;
		nextByte = string.byte(line, cut + 1);
	end

	return string.sub(line, 1, cut) .. "..";

end

-- "Name blacklisted at 2026-09-13", plus " for <reason>" when reasons are switched on.
local function BL_DescribePlayer(player, withReason)

	local name = BlackList:FormatPlayer(player);
	local when = player["added"] and date("%Y-%m-%d", player["added"]) or BL_UNKNOWN_DATE;

	local reason = withReason and player["reason"] or "";
	reason = string.gsub(reason, "%s+", " ");
	reason = string.gsub(reason, "^%s*(.-)%s*$", "%1");
	-- A bare "|" starts an escape sequence in chat and gets the message rejected.
	reason = string.gsub(reason, "|", "/");

	if (reason == "") then
		return BL_FitChatLine(format(BL_WARN_LINE, name, when));
	end

	return BL_FitChatLine(format(BL_WARN_LINE_REASON, name, when, reason));

end

----------------------------------------------------------------------------------------------------
-- Argument parsing
----------------------------------------------------------------------------------------------------

-- Splits "add Bob ninja looted -x" into verb, a flag set and the remaining free text.
local function BL_Parse(args)

	local words = {};
	for word in string.gmatch(args or "", "%S+") do
		table.insert(words, word);
	end

	local verb, flags, rest = nil, {}, {};

	for i = 1, table.getn(words) do
		local word = words[i];

		if (string.sub(word, 1, 1) == "-") then
			flags[string.lower(string.sub(word, 2))] = true;
		elseif (not verb) then
			verb = string.lower(word);
		else
			table.insert(rest, word);
		end
	end

	return verb, flags, table.concat(rest, " ");

end

-- Which chat channel a set of flags asks for, if any.
local function BL_FlagChannel(flags)

	if (flags["g"] or flags["guild"]) then return "GUILD"; end
	if (flags["r"] or flags["raid"]) then return "RAID"; end
	if (flags["p"] or flags["party"]) then return "PARTY"; end

	return nil;

end

----------------------------------------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------------------------------------

function BlackList:PrintHelp()

	self:AddMessage(BL_HELP_HEADER, "yellow", true);

	for i = 1, table.getn(BL_HELP_LINES) do
		self:AddMessage("  " .. BL_HELP_LINES[i], "white", true);
	end

end

-- Collects the blacklisted players in the requested scope.
-- scope is "group" or "guild"; returns the match list plus a label for messages.
function BlackList:CollectMatches(scope)

	if (scope == "guild") then
		return self:FilterBlackListed(self:GetGuildMembers()), BL_SCOPE_GUILD;
	end

	local channel = self:GetGroupChannel();
	local label = (channel == "RAID") and BL_SCOPE_RAID or BL_SCOPE_PARTY;

	return self:FilterBlackListed(self:GetGroupMembers()), label;

end

function BlackList:ListMatches(scope)

	if (scope == "guild") then
		if (not IsInGuild()) then
			self:AddMessage(BL_ERR_NO_GUILD, "red", true);
			return;
		end

		local ready = self:RequestGuildRoster(function() BlackList:PrintMatches("guild"); end);
		if (not ready) then
			self:AddMessage(BL_GUILD_ROSTER_PENDING, "yellow", true);
			return;
		end

		self:PrintMatches("guild");
		return;
	end

	if (not self:IsInGroup()) then
		self:AddMessage(BL_ERR_NO_GROUP, "red", true);
		return;
	end

	self:PrintMatches("group");

end

function BlackList:PrintMatches(scope)

	local matches, label = self:CollectMatches(scope);
	local count = table.getn(matches);

	if (count == 0) then
		self:AddMessage(format(BL_LIST_NONE, label), "yellow", true);
		return;
	end

	self:AddMessage(format(BL_LIST_HEADER, count, label), "red", true);

	for i = 1, count do
		local player = matches[i].player;
		local line = "  " .. self:FormatPlayer(player);

		if (player["reason"] and player["reason"] ~= "") then
			line = line .. " - " .. player["reason"];
		end

		self:AddMessage(line, "yellow", true);
	end

end

function BlackList:WarnGroup(flags)

	local channel = BL_FlagChannel(flags);

	if (not channel) then
		channel = self:GetGroupChannel();

		if (not channel) then
			self:AddMessage(BL_ERR_NO_GROUP, "red", true);
			return;
		end
	end

	if (channel == "GUILD") then
		if (not IsInGuild()) then
			self:AddMessage(BL_ERR_NO_GUILD, "red", true);
			return;
		end

		local ready = self:RequestGuildRoster(function() BlackList:SendWarning("GUILD", "guild"); end);
		if (not ready) then
			self:AddMessage(BL_GUILD_ROSTER_PENDING, "yellow", true);
			return;
		end

		self:SendWarning("GUILD", "guild");
		return;
	end

	if (channel == "RAID" and not self:IsInRaid()) then
		self:AddMessage(BL_ERR_NO_RAID, "red", true);
		return;
	end

	if (channel == "PARTY" and GetNumPartyMembers() == 0) then
		self:AddMessage(BL_ERR_NO_PARTY, "red", true);
		return;
	end

	self:SendWarning(channel, "group");

end

-- Announces the blacklisted players in scope to a chat channel, one line each. Reasons are
-- included only when switched on with /bl reason on.
function BlackList:SendWarning(channel, scope)

	local matches, label = self:CollectMatches(scope);
	local count = table.getn(matches);

	if (count == 0) then
		self:AddMessage(format(BL_LIST_NONE, label), "yellow", true);
		return;
	end

	local withReason = BlackListConfig and BlackListConfig.WarnReason;
	local lines = {};

	for i = 1, math.min(count, BL_MAX_WARN_PLAYERS) do
		table.insert(lines, BL_DescribePlayer(matches[i].player, withReason));
	end

	if (count > BL_MAX_WARN_PLAYERS) then
		table.insert(lines, format(BL_WARN_MORE, count - BL_MAX_WARN_PLAYERS));
	end

	BL_Announce(lines, channel);

	self:AddMessage(format(BL_WARN_SENT, count, channel), "yellow", true);

end

-- /bl reason on | off, any case. With no argument, reports the current setting.
function BlackList:SetWarnReason(arg)

	if (not BlackListConfig) then return; end

	arg = string.lower(arg or "");

	if (arg == "on") then
		BlackListConfig.WarnReason = true;
		self:AddMessage(BL_REASON_NOW_ON, "yellow", true);
	elseif (arg == "off") then
		BlackListConfig.WarnReason = false;
		self:AddMessage(BL_REASON_NOW_OFF, "yellow", true);
	else
		local state = BlackListConfig.WarnReason and "ON" or "OFF";
		self:AddMessage(format(BL_REASON_USAGE, state), "yellow", true);
	end

end

----------------------------------------------------------------------------------------------------
-- Dispatch
----------------------------------------------------------------------------------------------------

function BlackList:HandleSlashCmd(args)

	local verb, flags, rest = BL_Parse(args);

	-- /bl -p, /bl -r, /bl -g are shorthand for /bl warn -x
	if (not verb) then
		if (BL_FlagChannel(flags)) then
			self:WarnGroup(flags);
		else
			self:ToggleTab();
		end
		return;
	end

	if (verb == "help" or verb == "?") then
		self:PrintHelp();

	elseif (verb == "show" or verb == "toggle") then
		self:ToggleTab();

	elseif (verb == "options" or verb == "config") then
		BlackListOptions:Handler();

	elseif (verb == "add") then
		if (rest == "") then
			self:AddPlayer("target");
		else
			local name, reason = string.match(rest, "^(%S+)%s+(.*)$");
			self:AddPlayer(name or rest, nil, reason);
		end

	elseif (verb == "remove" or verb == "rem" or verb == "del") then
		if (rest == "") then
			self:RemovePlayer("target");
		else
			self:RemovePlayer(rest);
		end

	elseif (verb == "list") then
		if (flags["g"] or flags["guild"]) then
			self:ListMatches("guild");
		else
			self:ListMatches("group");
		end

	elseif (verb == "warn") then
		self:WarnGroup(flags);

	elseif (verb == "reason") then
		self:SetWarnReason(rest);

	else
		self:AddMessage(format(BL_ERR_UNKNOWN, verb), "red", true);
		self:PrintHelp();
	end

end

function BlackList:RegisterSlashCmds()

	SlashCmdList["BlackList"] = function(args)
		BlackList:HandleSlashCmd(args);
	end;
	SLASH_BlackList1 = "/blacklist";
	SLASH_BlackList2 = "/bl";

	-- Kept so old macros keep working; both now point at /bl remove.
	SlashCmdList["RemoveBlackList"] = function(args)
		BlackList:AddMessage(BL_DEPRECATED_REMOVE, "yellow", true);
		if (args and args ~= "") then
			BlackList:RemovePlayer(args);
		else
			BlackList:RemovePlayer("target");
		end
	end;
	SLASH_RemoveBlackList1 = "/removeblacklist";
	SLASH_RemoveBlackList2 = "/removebl";

end
