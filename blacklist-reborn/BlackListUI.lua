----------------------------------------------------------------------------------------------------
-- Blacklist Reborn: user interface
----------------------------------------------------------------------------------------------------

local SelectedIndex = 1;
local settingReason = false;

BLACKLISTS_TO_DISPLAY = 17;
FRIENDS_FRAME_BL_HEIGHT = 16;

BL_CLASSES = { "", "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior", "Death Knight" };
BL_RACES = { "", "Human", "Dwarf", "Night Elf", "Gnome", "Draenei", "Orc", "Undead", "Tauren", "Troll", "Blood Elf" };

----------------------------------------------------------------------------------------------------
-- Strings. Prefixed so they cannot clash with Blizzard's global strings or another addon.
----------------------------------------------------------------------------------------------------

-- Addon identity. The version comes from the TOC so it is only set in one place.
BL_ADDON_NAME              = "Blacklist Reborn";
BL_ADDON_FOLDER            = "blacklist-reborn";

local tocVersion = GetAddOnMetadata and GetAddOnMetadata(BL_ADDON_FOLDER, "Version");
BL_ADDON_VERSION           = tocVersion or "";
BL_PREFIX                  = BL_ADDON_NAME .. ": ";

BL_PLAYER_NOT_FOUND        = "Player not found.";
BL_ALREADY_BLACKLISTED     = "is already on your blacklist.";
BL_ADDED_TO_BLACKLIST      = "added to your blacklist.";
BL_REMOVED_FROM_BLACKLIST  = "removed from your blacklist.";
BL_CANNOT_BLACKLIST_SELF   = "You cannot add yourself to your blacklist.";
BL_ENTER_NAME              = "Enter the name of the player to add to your blacklist:";

BL_TAB_TITLE               = "Blacklist";
BL_WINDOW_TITLE            = BL_ADDON_NAME;
BL_ADD_PLAYER              = "Add Player";
BL_REMOVE_PLAYER           = "Remove Player";
BL_OPTIONS                 = "Options";
BL_LIST_GROUP              = "List Group";
BL_WARN_GROUP              = "Warn Group";

BL_DETAILS_OF              = "Blacklist details for";
BL_BLACK_LISTED            = "Blacklisted:";
BL_WARN_ME                 = "Warn Me";
BL_REASON                  = "Blacklisted for:";
BL_UNKNOWN_LEVEL_CLASS     = "Unknown Level, Class";
BL_UNKNOWN_LEVEL           = "Unknown Level %s";
BL_UNKNOWN_CLASS           = "Level %s Unknown Class";
BL_LEVEL_CLASS             = "Level %s %s";
BL_UNKNOWN_RACE            = "Unknown Race";

BL_MENU_BLACKLIST          = "Add to Blacklist";
BL_MENU_GUILD_INVITE       = "Guild Invite";
BL_MENU_ADD_FRIEND         = "Add to Friends";

BL_NOTIFY_INVITE           = BL_PREFIX .. "%s just invited you to a group.";
BL_NOTIFY_GROUP_ONE        = BL_PREFIX .. "%s is in your group.";
BL_NOTIFY_GROUP_MANY       = BL_PREFIX .. "%d blacklisted players in your group: %s";

BL_SCOPE_PARTY             = "your party";
BL_SCOPE_RAID              = "your raid";
BL_SCOPE_GUILD             = "your guild";

BL_LIST_HEADER             = BL_PREFIX .. "%d in %s";
BL_LIST_NONE               = BL_PREFIX .. "nobody in %s is on your blacklist.";
BL_WARN_PREFIX             = "On my blacklist: ";
BL_WARN_SENT               = BL_PREFIX .. "announced %d player(s) to %s.";
BL_GUILD_ROSTER_PENDING    = BL_PREFIX .. "fetching the guild roster, one moment...";

BL_ERR_NO_GROUP            = BL_PREFIX .. "you are not in a party or raid.";
BL_ERR_NO_PARTY            = BL_PREFIX .. "you are not in a party.";
BL_ERR_NO_RAID             = BL_PREFIX .. "you are not in a raid.";
BL_ERR_NO_GUILD            = BL_PREFIX .. "you are not in a guild.";
BL_ERR_UNKNOWN             = BL_PREFIX .. "unknown command '%s'.";
BL_DEPRECATED_REMOVE       = BL_PREFIX .. "this command now lives at /bl remove.";

BL_EDIT_NONE               = "(none)";
BL_COUNT_NONE              = "Nobody is on your blacklist.";
BL_COUNT_ONE               = "1 player on your blacklist";
BL_COUNT_MANY              = "%d players on your blacklist";

BL_OPT_NOTIFY_HEADER       = "Notify me when a blacklisted player";
BL_OPT_HINT                = "...invites me to a group, or is in a group I join.\nType /bl help for the full command list.";

BL_HELP_HEADER             = BL_ADDON_NAME .. (tocVersion and (" v" .. tocVersion) or "") .. " commands:";
BL_HELP_LINES = {
	"/bl - open the " .. BL_ADDON_NAME .. " window",
	"/bl add [name] [reason] - blacklist a name, or your target",
	"/bl remove [name] - remove a name, or your target",
	"/bl list - blacklisted players in your group",
	"/bl list -g - blacklisted players in your guild",
	"/bl warn - announce them to raid, or party",
	"/bl warn -p | -r | -g - announce to party / raid / guild",
	"/bl options - open the options panel",
};

BINDING_HEADER_BLACKLIST      = BL_ADDON_NAME;
BINDING_NAME_TOGGLE_BLACKLIST = "Toggle " .. BL_ADDON_NAME .. " Window";

----------------------------------------------------------------------------------------------------
-- Frame plumbing
----------------------------------------------------------------------------------------------------

-- Lets Escape close our windows. PLAYER_ENTERING_WORLD fires on every zone change, so this guards
-- itself.
--
-- The window is standalone. It used to be a tab inside the Friends frame, which meant writing to
-- FRIENDSFRAME_SUBFRAMES and FriendsTabHeader; that taints the Friends frame and, through it, the
-- right-click menus it opens. UISpecialFrames is safe: the game menu reads it through securecall.
function BlackList:InsertUI()

	if (self.uiInserted) then return; end
	self.uiInserted = true;

	table.insert(UISpecialFrames, "BlackListFrame");
	table.insert(UISpecialFrames, "BlackListOptionsFrame");
	table.insert(UISpecialFrames, "BlackListNameDialog");

end

function BlackList:ClickBlackList(button)

	button = button or this;

	self:SetSelectedBlackList(button:GetID());
	self:UpdateUI();
	self:ShowDetails();

end

function BlackList:SetSelectedBlackList(index)

	SelectedIndex = index;

end

function BlackList:GetSelectedBlackList()

	return SelectedIndex;

end

-- Opens the window in the Friends frame's place. HideUIPanel hands the work to Blizzard's secure
-- panel manager, so closing the Friends frame from here does not taint it.
function BlackList:ShowWindow()

	if (FriendsFrame and FriendsFrame:IsShown()) then
		HideUIPanel(FriendsFrame);
	end

	BlackListFrame:Show();

end

function BlackList:ToggleTab()

	if (BlackListFrame:IsShown()) then
		BlackListFrame:Hide();
	else
		self:ShowWindow();
	end

end

----------------------------------------------------------------------------------------------------
-- Details panel
----------------------------------------------------------------------------------------------------

function BlackList:ShowDetails()

	local player = self:GetPlayerByIndex(self:GetSelectedBlackList());
	if (not player) then
		getglobal("BlackListDetailsFrame"):Hide();
		return;
	end

	getglobal("BlackListDetailsName"):SetText(BL_DETAILS_OF .. " " .. self:FormatPlayer(player));

	local level;
	if (player["level"] == "" and player["class"] == "") then
		level = BL_UNKNOWN_LEVEL_CLASS;
	elseif (player["level"] == "") then
		level = format(BL_UNKNOWN_LEVEL, player["class"]);
	elseif (player["class"] == "") then
		level = format(BL_UNKNOWN_CLASS, player["level"]);
	else
		level = format(BL_LEVEL_CLASS, player["level"], player["class"]);
	end

	local race = player["race"];
	if (race == "" or race == nil) then race = BL_UNKNOWN_RACE; end

	getglobal("BlackListDetailsLevel"):SetText(level);
	getglobal("BlackListDetailsRace"):SetText(race);

	local faction = BL_GetFaction(player["raceEn"] or player["race"]);
	local insignia = getglobal("BlackListDetailsFactionInsignia");

	if (faction == 1) then
		insignia:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Factions.blp");
		insignia:SetTexCoord(0, 0.5, 0, 1);
	elseif (faction == 2) then
		insignia:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Factions.blp");
		insignia:SetTexCoord(0.5, 1, 0, 1);
	else
		insignia:SetTexture(0, 0, 0, 0);
	end

	local added = player["added"];
	if (added) then
		getglobal("BlackListDetailsBlackListedText"):SetText(date("%I:%M%p on %b %d, %Y", added));
	else
		getglobal("BlackListDetailsBlackListedText"):SetText("");
	end

	getglobal("BlackListDetailsFrameCheckButton1Text"):SetText("  " .. BL_WARN_ME);
	getglobal("BlackListDetailsFrameCheckButton1"):SetChecked(player["warn"]);

	-- SetText fires OnTextChanged, which would otherwise write this reason onto whichever row
	-- was selected a moment ago.
	settingReason = true;
	getglobal("BlackListDetailsFrameReasonTextBox"):SetText(player["reason"] or "");
	settingReason = false;

	getglobal("BlackListDetailsFrame"):Show();
	getglobal("BlackListEditDetailsFrame"):Hide();

end

function BlackList:SetWarnFlag(checkButton)

	checkButton = checkButton or this;

	self:UpdateDetails(self:GetSelectedBlackList(), checkButton:GetChecked() and true or false);

end

function BlackList:SetReason(editBox)

	if (settingReason) then return; end

	editBox = editBox or this;

	self:UpdateDetails(self:GetSelectedBlackList(), nil, editBox:GetText());

end

----------------------------------------------------------------------------------------------------
-- Edit sub-panel
----------------------------------------------------------------------------------------------------

local editClass, editRace = 1, 1;

-- UnitRace's locale-free second return, mapped onto the names in BL_RACES.
local BL_RACE_TOKENS = {
	["Human"] = "Human", ["Dwarf"] = "Dwarf", ["NightElf"] = "Night Elf", ["Gnome"] = "Gnome",
	["Draenei"] = "Draenei", ["Orc"] = "Orc", ["Scourge"] = "Undead", ["Tauren"] = "Tauren",
	["Troll"] = "Troll", ["BloodElf"] = "Blood Elf",
};

local function BL_IndexOf(list, value)

	for i = 1, table.getn(list) do
		if (list[i] == value) then return i; end
	end

	return 1;

end

local function BL_EditLabel(value)

	if (not value or value == "") then return BL_EDIT_NONE; end

	return value;

end

function BlackList:RefreshEditLabels()

	BlackListEditClassText:SetText(BL_EditLabel(BL_CLASSES[editClass]));
	BlackListEditRaceText:SetText(BL_EditLabel(BL_RACES[editRace]));

end

function BlackListEditDetailsFrame_Update()

	local player = BlackList:GetPlayerByIndex(BlackList:GetSelectedBlackList());
	if (not player) then return; end

	BlackListEditDetailsFrameLevel:SetText(player["level"] or "");

	editClass = BL_IndexOf(BL_CLASSES, player["class"]);

	local race = player["race"];
	if (player["raceEn"]) then
		race = BL_RACE_TOKENS[player["raceEn"]] or player["raceEn"];
	end
	editRace = BL_IndexOf(BL_RACES, race);

	BlackList:RefreshEditLabels();

end

-- Steps the class or race selection, wrapping at either end.
function BlackList:CycleEdit(field, delta)

	if (field == "class") then
		local count = table.getn(BL_CLASSES);
		editClass = (editClass - 1 + delta + count) % count + 1;
	else
		local count = table.getn(BL_RACES);
		editRace = (editRace - 1 + delta + count) % count + 1;
	end

	self:RefreshEditLabels();

end

function BlackListEditDetailsSaveButton_OnClick()

	local index = BlackList:GetSelectedBlackList();
	local level = BlackListEditDetailsFrameLevel:GetText();
	local class = BL_CLASSES[editClass];
	local race = BL_RACES[editRace];

	-- The race list is English, so it doubles as the faction token.
	BlackList:UpdateDetails(index, nil, nil, level, class, race, race);

	BlackListEditDetailsFrame:Hide();

	BlackList:ShowDetails();

end

----------------------------------------------------------------------------------------------------
-- Name entry dialog
----------------------------------------------------------------------------------------------------

function BlackList:ShowNameDialog()

	BlackListNameDialog:Show();

end

function BlackList:AcceptNameDialog()

	local name = string.gsub(BlackListNameDialogEditBox:GetText() or "", "^%s*(.-)%s*$", "%1");

	BlackListNameDialog:Hide();

	if (name ~= "") then
		BlackListPlayer(name);
	end

end

----------------------------------------------------------------------------------------------------
-- List refresh
----------------------------------------------------------------------------------------------------

function BL_Update()

	BlackList:UpdateUI();

end

function BlackList:UpdateUI()

	if (not BlackListFrame) then return; end

	local numBlackLists = self:GetNumBlackLists();
	local selectedBlackList = self:GetSelectedBlackList();

	if (numBlackLists > 0) then
		if (selectedBlackList == 0 or selectedBlackList > numBlackLists) then
			self:SetSelectedBlackList(1);
			selectedBlackList = 1;
		end

		BlackListRemovePlayerButton:Enable();
	else
		BlackListRemovePlayerButton:Disable();
	end

	if (numBlackLists == 0) then
		BlackListFrameCountText:SetText(BL_COUNT_NONE);
	elseif (numBlackLists == 1) then
		BlackListFrameCountText:SetText(BL_COUNT_ONE);
	else
		BlackListFrameCountText:SetText(format(BL_COUNT_MANY, numBlackLists));
	end

	local blacklistOffset = FauxScrollFrame_GetOffset(BlackListScrollFrame);

	for i = 1, BLACKLISTS_TO_DISPLAY do
		local blacklistIndex = i + blacklistOffset;
		local button = getglobal("BlackListRow" .. i);

		getglobal("BlackListRow" .. i .. "ButtonTextName"):SetText(self:GetNameByIndex(blacklistIndex));
		button:SetID(blacklistIndex);

		if (blacklistIndex == selectedBlackList) then
			button:LockHighlight();
		else
			button:UnlockHighlight();
		end

		if (blacklistIndex > numBlackLists) then
			button:Hide();
		else
			button:Show();
		end
	end

	FauxScrollFrame_Update(BlackListScrollFrame, numBlackLists, BLACKLISTS_TO_DISPLAY, FRIENDS_FRAME_BL_HEIGHT);

end
