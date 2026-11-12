local _, ns = ...

-- The settings window that /peckish opens. Game code: it builds plain frames,
-- holds a draft of the settings while the window is open and hands the draft
-- to ns.applySettings (Init.lua) on Accept. Close, the close box and Escape
-- just hide it; the next open rebuilds the draft from the saved settings.
-- See PRD.md and docs/superpowers/specs/2026-11-10-settings-window-design.md.

local Core = ns.Core

local Options = {}
ns.Options = Options

local FRAME_NAME = "FeelingPeckishOptionsFrame"
local WIDTH, HEIGHT = 300, 380
local SLIDER_X, SLIDER_WIDTH = 30, 240

local frame -- built on the first Toggle()
local draft -- the settings being edited; rebuilt on every OnShow
local controls = {} -- setting key -> { set = fn(value), enable = fn(on) }

local function setLabelEnabled(label, on)
	local shade = on and 1 or 0.5
	label:SetTextColor(shade, shade, shade)
end

-- Grey out the reminder controls the draft makes meaningless.
local function refreshStates()
	local states = Core.controlStates(draft)
	controls.reminderInterval.enable(states.interval)
	controls.reminderCount.enable(states.count)
	controls.remindUntilFed.enable(states.untilFed)
end

local function addHeader(text, y)
	local header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetPoint("TOPLEFT", 16, y)
	header:SetText(text)
end

local function addCheck(key, text, x, y)
	local box = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint("TOPLEFT", x, y)
	local label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", box, "RIGHT", 2, 1)
	label:SetText(text)
	box:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0)
	box:SetScript("OnClick", function(self)
		draft[key] = self:GetChecked() and true or false
		refreshStates()
	end)
	controls[key] = {
		set = function(value)
			box:SetChecked(value)
		end,
		enable = function(on)
			if on then
				box:Enable()
			else
				box:Disable()
			end
			setLabelEnabled(label, on)
		end,
	}
end

-- A plain horizontal slider (no template) with its name and current value
-- on a line above it. Range and step come from Core.NUMBER_SPECS[key];
-- format turns a value into the text shown.
local function addSlider(key, text, format, y)
	local spec = Core.NUMBER_SPECS[key]
	local name = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	name:SetPoint("TOPLEFT", SLIDER_X, y)
	name:SetText(text)
	local value = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	value:SetPoint("LEFT", name, "RIGHT", 8, 0)

	local slider = CreateFrame("Slider", nil, frame)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(SLIDER_WIDTH, 17)
	slider:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:GetThumbTexture():SetSize(32, 32)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0, 0, 0, 0.6)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(6)
	slider:SetMinMaxValues(spec.min, spec.max)
	slider:SetValueStep(spec.step)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	-- Set after the range, so the clamp from the initial value of 0 does not
	-- reach the draft.
	slider:SetScript("OnValueChanged", function(_, v)
		v = Core.snap(spec, v)
		draft[key] = v
		value:SetText(format(v))
	end)

	controls[key] = {
		set = function(v)
			slider:SetValue(v)
			-- SetValue does not fire OnValueChanged when the value is unchanged.
			value:SetText(format(v))
		end,
		enable = function(on)
			-- Mouse stays enabled so a greyed slider swallows clicks (no window drag).
			if on then
				slider:Enable()
			else
				slider:Disable()
			end
			slider:SetAlpha(on and 1 or 0.4)
			setLabelEnabled(name, on)
			setLabelEnabled(value, on)
		end,
	}
end

local function addButton(text, point, relativeTo, relativePoint, x, y, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(90, 22)
	button:SetPoint(point, relativeTo, relativePoint, x, y)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function onShow()
	local settings = ns.getSettings()
	draft = {}
	for key in pairs(Core.DEFAULTS) do
		draft[key] = settings[key]
	end
	for key, control in pairs(controls) do
		control.set(draft[key])
	end
	refreshStates()
end

local function build()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
	frame:Hide()
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)
	table.insert(UISpecialFrames, FRAME_NAME) -- Escape closes it

	local title = frame.TitleText
	if not title then
		title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -5)
	end
	title:SetText("FeelingPeckish")

	addCheck("enabled", "Snack alerts on", 14, -32)
	addHeader("Stay quiet while", -66)
	addCheck("quietWhenDead", "Dead or a ghost", 22, -82)
	addCheck("quietWhenResting", "Resting (city or inn)", 22, -108)
	addHeader("Reminders", -142)
	addCheck("remindersOn", "Send reminders", 22, -158)
	addSlider("reminderInterval", "Every", Core.formatInterval, -192)
	addSlider("reminderCount", "How many", tostring, -240)
	addCheck("remindUntilFed", "Keep reminding until I eat", 22, -288)

	local close = addButton("Close", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12, function()
		frame:Hide()
	end)
	addButton("Accept", "RIGHT", close, "LEFT", -6, 0, function()
		ns.applySettings(draft)
		frame:Hide()
	end)

	frame:SetScript("OnShow", onShow)
end

function Options.Toggle()
	if not frame then
		build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

-- /peckish on|off ran: keep the open window's box (and draft) in step.
function Options.SyncEnabled(enabled)
	if frame and frame:IsShown() and draft then
		draft.enabled = enabled
		controls.enabled.set(enabled)
	end
end
