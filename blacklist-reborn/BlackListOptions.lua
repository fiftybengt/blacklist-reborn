----------------------------------------------------------------------------------------------------
-- Blacklist Reborn: options panel
----------------------------------------------------------------------------------------------------

BlackListOptions = {};

-- Label and tooltip per option frame. Keyed by frame name so BL_TooltipOn can find them without
-- another pile of global strings.
BL_OPTION_TEXT = {
	["SoundCheckButton"] = {
		label = "Play Sound",
		text = "Play a sound with the notification.",
	},
	["CenterCheckButton"] = {
		label = "Warn at Center",
		text = "Show the notification in the middle of the screen as well as in chat.",
	},
	["ChatCheckButton"] = {
		label = "Show in Chat",
		text = "Print the notification, and the reason you blacklisted the player, to your chat frame. "
			.. "Output you asked for with /bl is always printed.",
	},
};

function BlackListOptions:Handler()

	if (BlackListOptionsFrame:IsShown()) then
		BlackListOptionsFrame:Hide();
	else
		BlackListOptionsFrame:Show();
	end

end

function BlackListOptions:CheckButton_OnShow(checkButton, key)

	checkButton = checkButton or this;

	local text = BL_OPTION_TEXT[checkButton:GetName()];
	if (text) then
		getglobal(checkButton:GetName() .. "Text"):SetText(text.label);
	end

	checkButton:SetChecked(BlackListConfig and BlackListConfig[key]);

end

function BlackListOptions:CheckButton_OnClick(checkButton, key)

	checkButton = checkButton or this;

	if (not BlackListConfig) then return; end

	BlackListConfig[key] = checkButton:GetChecked() and true or false;

end
