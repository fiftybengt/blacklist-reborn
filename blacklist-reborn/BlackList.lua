----------------------------------------------------------------------------------------------------
-- Blacklist Reborn: core
--
-- Keeps a per-realm list of players and notifies you about them in exactly two situations:
--   * a blacklisted player invites you to a group
--   * you join, or are joined into, a party or raid that contains one
--
-- It never filters chat and never declines an invite for you.
----------------------------------------------------------------------------------------------------

BlackList = {};

BlackListedPlayers = {};

local BL_DEFAULTS = {
	Sound  = true,
	Center = true,
	Chat   = true,
};

-- Menus that get the Black List panel. RAID is the one the raid frames actually use
-- (Blizzard_RaidUI opens "RAID", not "RAID_PLAYER").
local BL_MENUS = {
	["PLAYER"] = true,
	["PARTY"] = true,
	["RAID_PLAYER"] = true,
	["RAID"] = true,
	["CHAT_ROSTER"] = true,
	["FRIEND"] = true,
	["FRIEND_OFFLINE"] = true,
};

-- Invites from the same player inside this many seconds only produce one notice.
local BL_INVITE_THROTTLE = 10;

local inviteWarned = {};

----------------------------------------------------------------------------------------------------
-- Load / events
----------------------------------------------------------------------------------------------------

function BlackList:OnLoad(frame)

	self.frame = frame;
	self.session = {};

	frame:RegisterEvent("VARIABLES_LOADED");
	frame:RegisterEvent("PLAYER_ENTERING_WORLD");
	frame:RegisterEvent("PARTY_INVITE_REQUEST");
	frame:RegisterEvent("PARTY_MEMBERS_CHANGED");
	frame:RegisterEvent("RAID_ROSTER_UPDATE");

	self:HookUnitPopups();
	self:RegisterSlashCmds();

end

function BlackList:RegisterEvent(event)

	if (self.frame) then self.frame:RegisterEvent(event); end

end

function BlackList:UnregisterEvent(event)

	if (self.frame) then self.frame:UnregisterEvent(event); end

end

function BlackList:HandleEvent(event, arg1)

	if (event == "VARIABLES_LOADED") then
		self:InitConfig();
		self:MigrateDB();

	elseif (event == "PLAYER_ENTERING_WORLD") then
		self:InsertUI();
		self:CheckGroup();

	elseif (event == "PARTY_INVITE_REQUEST") then
		self:OnInvite(arg1);

	elseif (event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE") then
		self:CheckGroup();

	elseif (event == "GUILD_ROSTER_UPDATE") then
		self:OnGuildRoster();
	end

end

-- Saved variables are applied after this file runs, so defaults are merged at VARIABLES_LOADED
-- rather than at load time, and over a fresh table so the defaults are never mutated.
function BlackList:InitConfig()

	if (type(BlackListConfig) ~= "table") then BlackListConfig = {}; end

	for key, value in pairs(BL_DEFAULTS) do
		if (BlackListConfig[key] == nil) then BlackListConfig[key] = value; end
	end

	-- Retired: chat blocking, auto-decline and the guild officer tools are gone.
	BlackListConfig.Ignore = nil;
	BlackListConfig.Ban = nil;
	BlackListConfig.Kick = nil;
	BlackListConfig.Rank = nil;

end

----------------------------------------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------------------------------------

-- A blacklisted player invited you. Notify only; the invite popup is left alone.
function BlackList:OnInvite(inviter)

	if (not inviter or inviter == "") then return; end

	local player = self:ShouldWarn(inviter);
	if (not player) then return; end

	local key = self:GetKey(player["name"], player["realm"]);
	local now = GetTime();

	if (inviteWarned[key] and now < inviteWarned[key] + BL_INVITE_THROTTLE) then return; end
	inviteWarned[key] = now;

	local who = self:FormatPlayer(player);

	self:AddSound();
	self:AddErrorMessage(format(BL_NOTIFY_INVITE, who), "red", 8);
	self:AddMessage(format(BL_NOTIFY_INVITE, who), "red");
	self:ReportReason(player);

end

-- Called on every roster change. Notifies once per blacklisted player per stay in the group:
-- joining a group with three of them gives one line, and only a newly arriving one speaks again.
function BlackList:CheckGroup()

	local members = self:GetGroupMembers();

	if (not members or table.getn(members) == 0) then
		self.session = {};
		return;
	end

	local present = {};
	local arrivals = {};

	for i = 1, table.getn(members) do
		local member = members[i];
		local player = self:ShouldWarn(member.name, member.realm);

		if (player) then
			local key = self:GetKey(player["name"], player["realm"]);
			present[key] = true;

			if (not self.session[key]) then
				self.session[key] = true;
				table.insert(arrivals, player);
			end
		end
	end

	-- Forget anyone who has left, so rejoining warns again.
	for key in pairs(self.session) do
		if (not present[key]) then self.session[key] = nil; end
	end

	if (table.getn(arrivals) > 0) then
		self:NotifyGroup(arrivals);
	end

end

function BlackList:NotifyGroup(players)

	local names = {};
	for i = 1, table.getn(players) do
		table.insert(names, self:FormatPlayer(players[i]));
	end

	local joined = table.concat(names, ", ");
	local msg;

	if (table.getn(names) == 1) then
		msg = format(BL_NOTIFY_GROUP_ONE, joined);
	else
		msg = format(BL_NOTIFY_GROUP_MANY, table.getn(names), joined);
	end

	self:AddSound();
	self:AddErrorMessage(msg, "red", 8);
	self:AddMessage(msg, "red");

	for i = 1, table.getn(players) do
		self:ReportReason(players[i]);
	end

end

function BlackList:ReportReason(player)

	local reason = player["reason"];
	if (not reason or reason == "") then return; end

	self:AddMessage("   " .. self:FormatPlayer(player) .. ": " .. reason, "yellow");

end

----------------------------------------------------------------------------------------------------
-- Right-click menus
--
-- Nothing here writes to Blizzard's menu tables. UnitPopup_HideButtons checks issecure() and hides
-- Target, Main Tank and Main Assist once addon code has written to UnitPopupMenus, UnitPopupButtons
-- or UnitPopupShown, and protected actions picked from a tainted menu are blocked with an "addon
-- blocked" error. Earlier versions inserted their entries into those tables, which is what broke
-- Target from the friends list, chat names and the guild roster.
--
-- The Black List actions live in a small panel of our own attached under the menu instead. The only
-- links to Blizzard's code are hooksecurefunc and HookScript, which run after the original and leave
-- it untainted.
----------------------------------------------------------------------------------------------------

local BL_MENU_ROW_HEIGHT = 16;
local BL_MENU_ACTIONS = { "AddToBl", "GInv", "FInv" };

-- Who the menu being built right now is about. Set by the UnitPopup_ShowMenu hook and picked up
-- when the menu list is shown in the same frame.
local menuTarget = nil;

local function BL_MenuLabel(action)

	if (action == "AddToBl") then return BL_MENU_BLACKLIST; end
	if (action == "GInv") then return BL_MENU_GUILD_INVITE; end

	return BL_MENU_ADD_FRIEND;

end

-- Unit-based menus (party, raid and target frames) resolve through the unit so cross-realm players
-- keep their realm; name-based menus (friends list, chat roster) carry it in dropdownMenu.server.
local function BL_ResolveMenuTarget(dropdownMenu, unit)

	local name, realm;

	if (unit) then
		if (not UnitIsPlayer(unit) or UnitIsUnit(unit, "player")) then return nil; end
		name, realm = UnitName(unit);
	elseif (dropdownMenu) then
		name, realm = dropdownMenu.name, dropdownMenu.server;
	end

	if (not name or name == "" or name == UNKNOWNOBJECT) then return nil; end

	if (BlackList:GetKey(name, realm) == BlackList:GetKey(UnitName("player"))) then return nil; end

	return name, realm;

end

local function BL_UnitPopup_ShowMenu(dropdownMenu, which, unit)

	-- Submenus such as loot method are built at level 2; leave the level 1 target alone.
	if (UIDROPDOWNMENU_MENU_LEVEL ~= 1) then return; end

	menuTarget = nil;

	if (not BL_MENUS[which]) then return; end

	local name, realm = BL_ResolveMenuTarget(dropdownMenu, unit);
	if (not name) then return; end

	menuTarget = { frame = dropdownMenu, name = name, realm = realm, time = GetTime() };

end

-- The list can be re-anchored after it is shown when it would run off the screen, so the panel is
-- placed a frame later: below the menu, or above it when there is no room below.
local function BL_MenuPanel_Place(panel)

	panel:SetScript("OnUpdate", nil);

	local list = panel:GetParent();
	local bottom = list:GetBottom();

	panel:ClearAllPoints();

	if (bottom and bottom < panel:GetHeight() + 8) then
		panel:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, -2);
	else
		panel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, 2);
	end

end

local function BL_MenuPanelButton_OnClick(button)

	local target = BlackListMenuPanel.target;

	CloseDropDownMenus();

	if (not target) then return; end

	if (button.action == "AddToBl") then
		BlackList:AddPlayer(target.name, nil, nil, target.realm);
		return;
	end

	local fullName = target.name;
	if (target.realm and target.realm ~= "" and target.realm ~= GetRealmName()) then
		fullName = target.name .. "-" .. target.realm;
	end

	if (button.action == "GInv") then
		GuildInvite(fullName);
	elseif (button.action == "FInv") then
		AddFriend(fullName);
	end

end

local function BL_MenuList_OnShow(list)

	local panel = BlackListMenuPanel;
	local target = menuTarget;

	-- The panel is a child of the list, so hide it first or it reappears on unrelated menus.
	panel:Hide();
	panel.target = nil;

	if (not target or target.frame ~= UIDROPDOWNMENU_OPEN_MENU or target.time ~= GetTime()) then
		return;
	end

	local width = list:GetWidth() or 0;

	for i = 1, table.getn(panel.buttons) do
		local button = panel.buttons[i];
		button:SetText(BL_MenuLabel(button.action));

		local needed = (button:GetTextWidth() or 0) + 32;
		if (needed > width) then width = needed; end
	end

	panel.target = target;
	panel:SetWidth(width);
	panel:ClearAllPoints();
	panel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, 2);
	panel:SetScript("OnUpdate", BL_MenuPanel_Place);
	panel:Show();

end

local function BL_MenuList_OnHide()

	menuTarget = nil;
	BlackListMenuPanel:Hide();
	BlackListMenuPanel.target = nil;

end

function BlackList:HookUnitPopups()

	local list = DropDownList1;
	local panel = CreateFrame("Frame", "BlackListMenuPanel", list);

	panel:Hide();
	panel:EnableMouse(true);
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 4 },
	});
	panel:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b);
	panel:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b);
	panel:SetHeight(table.getn(BL_MENU_ACTIONS) * BL_MENU_ROW_HEIGHT + 20);
	panel.buttons = {};

	for i = 1, table.getn(BL_MENU_ACTIONS) do
		local button = CreateFrame("Button", "BlackListMenuPanelButton" .. i, panel);
		local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmallLeft");

		text:SetPoint("LEFT", button, "LEFT", 0, 0);
		button:SetFontString(text);
		button:SetHeight(BL_MENU_ROW_HEIGHT);
		button:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -10 - (i - 1) * BL_MENU_ROW_HEIGHT);
		button:SetPoint("RIGHT", panel, "RIGHT", -16, 0);
		button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
		button:SetScript("OnClick", BL_MenuPanelButton_OnClick);
		button.action = BL_MENU_ACTIONS[i];

		panel.buttons[i] = button;
	end

	list:HookScript("OnShow", BL_MenuList_OnShow);
	list:HookScript("OnHide", BL_MenuList_OnHide);

	hooksecurefunc("UnitPopup_ShowMenu", BL_UnitPopup_ShowMenu);

end

----------------------------------------------------------------------------------------------------
-- Public helper kept for the XML button and the name-entry dialog
----------------------------------------------------------------------------------------------------

function BlackListPlayer(player, reason, realm)

	BlackList:AddPlayer(player, nil, reason, realm);

end

----------------------------------------------------------------------------------------------------
-- Options panel tooltips
----------------------------------------------------------------------------------------------------

function BL_TooltipOn(self)

	self = self or this;
	if (not self) then return; end

	local text = BL_OPTION_TEXT and BL_OPTION_TEXT[self:GetName()];
	if (not text) then return; end

	GameTooltip:ClearLines();
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT");
	GameTooltip:AddLine(text.label, 1, 1, 1, 1);
	GameTooltip:AddLine(text.text, nil, nil, nil, 1, 1);
	GameTooltip:Show();

end

function BL_TooltipOff()

	GameTooltip:Hide();

end
