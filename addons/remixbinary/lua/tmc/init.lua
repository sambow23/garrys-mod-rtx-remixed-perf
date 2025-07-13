if SERVER then
	return
end

local NOTIFICATION_PATH = "tmc/notification.json"
local SOUND_PATH = "tmc/notification.mp3"
local DEFAULT_NOTIFICATION = {
	["unlocked"] = "Remix Menu Opened",
	["locked"] = "Remix Menu Closed",
}
local WHITE = Color(255, 255, 255, 255)

-- Remix UI states
local UI_STATE_NONE = 0
local UI_STATE_BASIC = 1
local UI_STATE_ADVANCED = 2
local previousRtxUiState = UI_STATE_NONE

surface.CreateFont("tmc_NotifyFont", {
	font = "Arial",
	size = 24,
	weight = 50,
	shadow = true,
})

local notificationsEnabled = CreateClientConVar(
	"tmc_notifications",
	"1",
	true,
	false,
	"Enable or disable notifications when Remix UI state changes",
	0,
	1
)

local blockEntityMenu = CreateClientConVar(
	"tmc_blockentitymenu",
	"0",
	true,
	false,
	"Disable context options pop-up when right-clicking on an entity",
	0,
	1
)

local enabled = false
local debounce = false
local worldPanel = vgui.GetWorldPanel()
local hudPanel = GetHUDPanel()

local playPing
do
	sound.Add({
		sound = SOUND_PATH,
		name = "tmc_notificationSound",
		channel = CHAN_STATIC,
		level = SNDLVL_NONE,
		volume = 1,
		pitch = 100,
	})
	function playPing()
		surface.PlaySound(SOUND_PATH)
	end
end

-- detours EnableScreenClicker so even if another addon disables screen clicking, this addon's state still keeps it enabled
gui.tmc_EnableScreenClickerInternal = gui.EnableScreenClicker
function gui.EnableScreenClicker(bool, ...)
	return gui.tmc_EnableScreenClickerInternal(bool or enabled, ...)
end

-- detours OpenEntityMenu to control opening the entity menu by ConVar if the cursor is free
properties.tmc_OpenEntityMenuInternal = properties.OpenEntityMenu
function properties.OpenEntityMenu(ent, tr, ...)
	if blockEntityMenu:GetBool() and enabled then
		return
	end

	return properties.tmc_OpenEntityMenuInternal(ent, tr, ...)
end

---Get custom cursor text from a json file located in the path.
---Called everytime we want to notify. Hence, live updates are possible.
---@param path string
---@return TMCData
local function getCustomText(path)
	if not file.Exists("tmc", "DATA") then
		file.CreateDir("tmc")
	end
	if not file.Exists(path, "DATA") then
		file.Write(path, util.TableToJSON(DEFAULT_NOTIFICATION, true))
	end

	local data = file.Read(path, "DATA")
	return data and util.JSONToTable(data)
end

---Tell the user that they have locked or unlocked their cursor
---@param text string
---@param lifetime number
---@param debounceTime number
local function notify(text, lifetime, debounceTime)
	if debounce then
		return
	end
	playPing()
	local notifyPanel = vgui.Create("DNotify")
	local scrW, scrH = ScrW(), ScrH()
	local xSize, ySize = scrW * 0.25, scrH * 0.1
	local screenX, screenY = scrW / 2 - xSize / 2, scrH / 2 - 80
	notifyPanel:SetSize(xSize, ySize)
	notifyPanel:SetPos(screenX, screenY)
	local lbl = vgui.Create("DLabel", notifyPanel)
	lbl:Dock(FILL)
	lbl:SetText(text)
	lbl:SetFont("tmc_NotifyFont")
	lbl:SetColor(WHITE)
	lbl:SetContentAlignment(5)
	lbl:SetWorldClicker(true)
	notifyPanel:AddItem(lbl, lifetime)
	notifyPanel:MoveTo(screenX, screenY - 30, lifetime, 0, 2)
	notifyPanel:SetWorldClicker(true)
	debounce = true
	timer.Simple(debounceTime, function()
		debounce = false
	end)
	timer.Simple(lifetime + 1, function()
		notifyPanel:Remove()
	end)
end

-- Add this Think hook to monitor the Remix UI state
hook.Add("Think", "TMC_MonitorRemixUI", function()
    -- Check if the GetRemixUIState function exists (from our module)
    if not GetRemixUIState then return end
    
    -- Get the current UI state
    local rtxUiState = GetRemixUIState()
    
    -- Only process if the state has changed
    if rtxUiState ~= previousRtxUiState then
        local isRtxUiActive = rtxUiState ~= UI_STATE_NONE
        previousRtxUiState = rtxUiState
        
        -- Update cursor visibility based on Remix UI state
        enabled = isRtxUiActive
        gui.EnableScreenClicker(enabled)
        worldPanel:SetWorldClicker(enabled)
        hudPanel:SetWorldClicker(enabled)
        
        -- Update input blocking
        if enabled then
            -- Block input when Remix UI is active
            hook.Add("CreateMove", "TMC_BlockAttacks", function(cmd)
                cmd:RemoveKey(IN_ATTACK)
                cmd:RemoveKey(IN_ATTACK2)
                return true
            end)

            hook.Add("StartCommand", "TMC_BlockInput", function(ply, cmd)
                if ply == LocalPlayer() then
                    cmd:ClearMovement()
                    cmd:ClearButtons()
                end
            end)

            hook.Add("InputMouseApply", "TMC_BlockMouseInput", function()
                return true
            end)
            
            if notificationsEnabled:GetBool() then
                local customText = getCustomText(NOTIFICATION_PATH)
                notify(customText.unlocked, 1, 0.5)
            end
        else
            -- Unblock input when Remix UI is closed
            hook.Remove("CreateMove", "TMC_BlockAttacks")
            hook.Remove("StartCommand", "TMC_BlockInput")
            hook.Remove("InputMouseApply", "TMC_BlockMouseInput")
            
            if notificationsEnabled:GetBool() then
                local customText = getCustomText(NOTIFICATION_PATH)
                notify(customText.locked, 1, 0.5)
            end
        end
    end
end)

-- Add a debug command to display current UI state
concommand.Add("rtx_ui_state", function()
    if GetRemixUIState then
        local rtxUiState = GetRemixUIState()
        local stateNames = {
            [UI_STATE_NONE] = "None (UI not visible)",
            [UI_STATE_BASIC] = "Basic UI",
            [UI_STATE_ADVANCED] = "Advanced UI"
        }
        
        print("Current RTX UI state:", rtxUiState, stateNames[rtxUiState] or "Unknown")
        print("TMC cursor enabled:", enabled)
    else
        print("GetRemixUIState function not available")
    end
end)