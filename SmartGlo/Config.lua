-- One dialog: a subject dropdown built from live item frames, a detail pane, and a text box
-- that is also the import/export surface.

local _, ns = ...

local Config = {}

local WIDTH, HEIGHT = 480, 380
local dialog
local selected

--- The dropdown is built by ENUMERATING live item frames, so a subject with no frame cannot
--- be offered; the paste box is where a frameless subject can still arrive.
local function Subjects()
  local out, seen = {}, {}
  for _, viewer in ipairs({ EssentialCooldownViewer, UtilityCooldownViewer,
                            BuffIconCooldownViewer, BuffBarCooldownViewer }) do
    if viewer ~= nil and viewer.itemFramePool ~= nil then
      for item in viewer.itemFramePool:EnumerateActive() do
        local ok, id = pcall(item.GetCooldownID, item)
        if ok and type(id) == "number" and type(C_CooldownViewer) == "table" then
          local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
          if okInfo and type(info) == "table" then
            local spell = info.overrideSpellID
            if type(spell) ~= "number" or spell == 0 then spell = info.spellID end
            if type(spell) == "number" and not seen[spell] then
              seen[spell] = true
              out[#out + 1] = spell
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return ns.SpellLabel(a) < ns.SpellLabel(b) end)
  return out
end

--- The box shows RULE TEXT, not a wire string, because the box is the only place a rule can
--- be written by hand. A wire string pasted in still applies -- `Read` takes either.
local function RulesText(subject)
  local glows = ns.Store.ForSubject(subject)
  if #glows == 0 then return "" end
  return ns.Parse.Render(glows)
end

--- One door for whatever is in the box. `SG1:` is the wire prefix and nothing else may start
--- with it, so the sniff is exact rather than a guess about the content.
local function Read(text)
  local glows, why
  if string.match(text or "", "^%s*SG1:") then
    glows, why = ns.Wire.Decode((string.match(text, "^%s*(.-)%s*$")))
  else
    glows, why = ns.Parse.Text(text)
  end
  -- The refusal STRING is the payload: the same input refused differently here and by
  -- `wowkb.smartglo` is the two grammars having drifted, and there is no other detector.
  if glows == nil then ns.log:Mark("refused: %s", ns.Capture.Safe(why)) end
  return glows, why
end

local function Detail(subject)
  if subject == nil then
    return "Pick a subject. The list is built from the icons the Cooldown Manager has laid "
      .. "out right now, so everything in it has a frame."
  end
  local glows = ns.Store.ForSubject(subject)
  if #glows == 0 then
    return ns.SpellLabel(subject) .. "\n\nNo rules on this subject."
  end
  local lines = { ns.SpellLabel(subject), "" }
  for _, glow in ipairs(glows) do
    local verdict = ns.Rules.Evaluate(ns.Rules.Gate(glow))
    lines[#lines + 1] = ("[%s] %s"):format(verdict, glow.name or "(unnamed)")
    if glow.when ~= nil then
      lines[#lines + 1] = "      when   " .. ns.Rules.Describe(glow.when)
    end
    if glow.bind ~= nil then
      lines[#lines + 1] = ("      bind   %s -- %s"):format(
        ns.Rules.DescribeBind(glow.bind), ns.Count.Describe(subject))
    end
  end
  return table.concat(lines, "\n")
end

local function Refresh()
  if dialog == nil then return end
  dialog.detail:SetText(Detail(selected))
  dialog.edit:SetText(RulesText(selected))
  if selected == nil then
    dialog.dropdown:SetDefaultText("Pick a Cooldown Manager icon")
  else
    dialog.dropdown:SetDefaultText(ns.SpellLabel(selected))
  end
  dialog.dropdown:GenerateMenu()
end

local function Apply()
  local text = dialog.edit:GetText()
  if selected == nil then
    local glows, err = Read(text)
    if glows == nil then
      dialog.status:SetText("|cffff6060" .. tostring(err) .. "|r")
      return
    end
    local ok, errs = ns.Store.Replace(glows)
    if ok == nil then
      dialog.status:SetText("|cffff6060" .. errs[1] .. "|r")
      return
    end
    ns.Attach.Refresh()
    dialog.status:SetText(("|cff60ff60Applied %d glows.|r"):format(#glows))
    return
  end
  if string.match(text or "", "^%s*$") then
    local ok, errs = ns.Store.SetForSubject(selected, {})
    if ok == nil then
      dialog.status:SetText("|cffff6060" .. errs[1] .. "|r")
      return
    end
    dialog.status:SetText("|cff60ff60Cleared.|r")
    Refresh()
    return
  end
  local glows, err = Read(text)
  if glows == nil then
    dialog.status:SetText("|cffff6060" .. tostring(err) .. "|r")
    return
  end
  local ok, errs = ns.Store.SetForSubject(selected, glows)
  if ok == nil then
    dialog.status:SetText("|cffff6060" .. errs[1] .. "|r")
    return
  end
  ns.Attach.Refresh()
  dialog.status:SetText("|cff60ff60Applied.|r")
  Refresh()
end

local function Button(parent, label, point, x, y, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(96, 22)
  b:SetPoint(point, x, y)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function Build()
  local f = CreateFrame("Frame", "SmartGloConfig", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("Smart Glo")

  local dropdown = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
  dropdown:SetPoint("TOPLEFT", 14, -32)
  dropdown:SetSize(260, 24)
  dropdown:SetupMenu(function(_, root)
    local subjects = Subjects()
    if #subjects == 0 then
      root:CreateButton("No Cooldown Manager icons are laid out", function() end)
      return
    end
    for _, spell in ipairs(subjects) do
      root:CreateRadio(ns.SpellLabel(spell),
        function() return selected == spell end,
        function()
          selected = spell
          Refresh()
        end)
    end
  end)
  f.dropdown = dropdown

  local detail = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  detail:SetPoint("TOPLEFT", 16, -66)
  detail:SetWidth(WIDTH - 32)
  detail:SetJustifyH("LEFT")
  detail:SetJustifyV("TOP")
  detail:SetHeight(120)
  f.detail = detail

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -194)
  scroll:SetSize(WIDTH - 52, 110)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(WIDTH - 52)
  edit:SetMaxLetters(0)
  edit:SetMaxBytes(0)
  edit:SetScript("OnEscapePressed", edit.ClearFocus)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  status:SetPoint("BOTTOMLEFT", 16, 40)
  status:SetText("")
  f.status = status

  Button(f, "Apply", "BOTTOMRIGHT", -16, 12, Apply)
  Button(f, "Copy", "BOTTOMRIGHT", -116, 12, function()
    edit:SetFocus()
    edit:HighlightText()
    status:SetText("Selected -- Ctrl+C to copy.")
  end)
  Button(f, "Revert", "BOTTOMLEFT", 16, 12, function()
    Refresh()
    status:SetText("Reverted to what is applied.")
  end)
  Button(f, "Close", "BOTTOMLEFT", 116, 12, function() f:Hide() end)

  return f
end

--- The dialog's box is this addon's only copy surface: WoW has no clipboard API, so anything
--- a person has to move out of the game lands in a multiline EditBox, preselected for Ctrl+C.
--- Reading it out of the chat frame means picking our lines out of everyone else's.
function Config.ShowText(blurb, body)
  if dialog == nil then dialog = Build() end
  dialog:Show()
  selected = nil
  dialog.detail:SetText(blurb)
  dialog.edit:SetText(body)
  dialog.edit:SetFocus()
  dialog.edit:HighlightText()
  dialog.status:SetText("Selected -- Ctrl+C to copy.")
end

function Config.Toggle()
  if dialog == nil then dialog = Build() end
  if dialog:IsShown() then
    dialog:Hide()
    return
  end
  if selected == nil then
    local subjects = Subjects()
    selected = subjects[1]
  end
  dialog:Show()
  Refresh()
end

ns.RegisterCommand{
  name = "config",
  desc = "open the rule dialog",
  handler = Config.Toggle,
}

ns.RegisterCommand{
  name = "export",
  args = "[text]",
  desc = "print every applied rule -- as a share string, or as rule text",
  handler = function(rest)
    local all = ns.Store.All()
    if #all == 0 then
      ns.Print("no rules applied, so there is nothing to export.")
      return
    end
    local plain = string.match(rest or "", "^%s*text%s*$") ~= nil
    local body, blurb
    if plain then
      body = ns.Parse.Render(all)
      blurb = "Every applied rule, as text. Edit it and press Apply, or Ctrl+C to copy."
    else
      local err
      body, err = ns.Wire.Encode(all)
      if body == nil then
        ns.Printf("could not encode: %s", tostring(err))
        return
      end
      blurb = "Every applied rule, as one share string. Ctrl+C to copy. "
        .. "`/sg export text` gives the editable form."
    end
    Config.ShowText(blurb, body)
  end,
}

ns.RegisterCommand{
  name = "import",
  desc = "open the box to paste a whole rule set into",
  handler = function()
    if dialog == nil then dialog = Build() end
    dialog:Show()
    selected = nil
    dialog.detail:SetText("Paste a whole rule set -- rule text or an SG1: string -- then press Apply.")
    dialog.edit:SetText("")
    dialog.edit:SetFocus()
    dialog.status:SetText("")
  end,
}
