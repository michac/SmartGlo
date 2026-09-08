-- Rule-driven glows on Cooldown Manager icons.
--
-- This build registers the command surface and nothing else: it reads no cooldown data,
-- creates no glow, and stores no settings. The loader frame exists only to hold the
-- PLAYER_LOGIN registration, because slash commands registered at file scope are
-- overwritten by any addon that loads later.

local function Say(msg)
  print("SmartGlo: " .. msg)
end

local COMMANDS = {
  status = function()
    Say("loaded. No rules yet -- this build only answers the command surface.")
  end,
}

--- Verb dispatch off a schema table. Matching only the leading word keeps a verb from
--- being found inside an argument, which a substring search does not.
local function Dispatch(msg)
  local verb = string.match(msg or "", "^(%a*)")
  local handler = COMMANDS[string.lower(verb)]
  if handler == nil then
    Say("status")
    return
  end
  handler()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  SLASH_SMARTGLO1 = "/sg"
  SlashCmdList.SMARTGLO = Dispatch
  Say("loaded -- /sg status")
end)
