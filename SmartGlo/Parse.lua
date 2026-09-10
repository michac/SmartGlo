-- Rule text, read in the game. The same grammar `wowkb.smartglo` reads, in Lua.
--
-- ⚠ The grammar now lives in TWO languages, which rule-language.md §7 said it would not.
-- What changed is that the config box is the only authoring surface a player has, and a box
-- that accepts nothing but an `SG1:` blob makes the addon unusable without a checkout. The
-- refusal STRINGS are what drift between the two copies, and the `attach` capture stream is
-- what catches that: a parse refusal is marked, so a wording the Python tool would not have
-- produced shows up in a log rather than in a support question.

local _, ns = ...

local Parse = {}
ns.Parse = Parse

local COMPARISONS = { [">="] = true, [">"] = true, ["<="] = true, ["<"] = true, ["=="] = true }
local PRIMARY = {
  mana = true, rage = true, focus = true, energy = true, runic_power = true,
  fury = true, pain = true, insanity = true, maelstrom = true,
}
local SECONDARY = {
  soul_shards = true, holy_power = true, combo_points = true, chi = true,
  arcane_charges = true, essence = true, runes = true,
}
--- Every readable call over one spell. `at_max_charges` and `no_charges` are BOOLEANS off
--- the CDM's own verdict flags, not charge counts -- a count stays refused, in both bowls.
local CALLS = {
  ready = true, aura = true, talent = true, at_max_charges = true, no_charges = true,
}

local BIND_FORMS = "<spell>.stacks >= <n> | <spell>.cooldown > <n>s "
  .. "| <spell>.cooldown outside <a>s..<b>s | health% < <n>"

-- ------------------------------------------------------------------- the lexer

--- Kinds: number · name (dots included, so `warlock.demonology.demonbolt` is one token)
--- · cmp · punct. Whitespace and `--` comments are dropped.
local function Lex(text)
  local out, pos = {}, 1
  while pos <= #text do
    local skip = string.match(text, "^%s+", pos) or string.match(text, "^%-%-[^\n]*", pos)
    if skip ~= nil then
      pos = pos + #skip
    else
      local tok = string.match(text, "^%d+", pos)
      local kind = "number"
      if tok == nil then
        tok, kind = string.match(text, "^[A-Za-z_][A-Za-z_0-9%.]*", pos), "name"
      end
      if tok == nil then
        tok, kind = string.match(text, "^[<>=]=", pos), "cmp"
      end
      if tok == nil then
        tok, kind = string.match(text, "^[<>]", pos), "cmp"
      end
      if tok == nil then
        tok, kind = string.match(text, "^[%(%)]", pos), "punct"
      end
      if tok == nil then
        return nil, ("cannot read %q"):format(string.sub(text, pos, pos + 19))
      end
      out[#out + 1] = { kind = kind, text = tok }
      pos = pos + #tok
    end
  end
  out[#out + 1] = { kind = "end", text = "" }
  return out
end

-- ------------------------------------------------------ the expression parser

--- A hand-rolled recursive descent with one error channel: every production returns
--- `node` or `nil, why`, and a `nil` is propagated rather than turned into a default.
local Expression

local function Take(p)
  local tok = p.tokens[p.i]
  p.i = p.i + 1
  return tok
end

local function Peek(p)
  return p.tokens[p.i]
end

local function Expect(p, value)
  local tok = Take(p)
  if tok.text ~= value then
    return nil, ("expected %q, found %q"):format(value, tok.text)
  end
  return true
end

local function Primary(p)
  local tok = Take(p)
  if tok.text == "(" then
    local node, why = Expression(p)
    if node == nil then return nil, why end
    local ok, closeWhy = Expect(p, ")")
    if not ok then return nil, closeWhy end
    return node
  end
  if tok.kind ~= "name" then
    return nil, ("expected a term, found %q"):format(tok.text)
  end
  if CALLS[tok.text] then
    local ok, why = Expect(p, "(")
    if not ok then return nil, why end
    local ref = Take(p)
    if ref.kind ~= "name" and ref.kind ~= "number" then
      return nil, ("%s() takes a spell name or id, found %q"):format(tok.text, ref.text)
    end
    local closed, closeWhy = Expect(p, ")")
    if not closed then return nil, closeWhy end
    -- The term picks the namespace: `aura()` reads a tracked row, everything else reads
    -- something the spec learns, and the same word can be both.
    local kind = tok.text == "aura" and "aura" or "ability"
    local spell, resolveWhy = ns.Names.Resolve(ref.text, p.scope, kind)
    if spell == nil then return nil, resolveWhy end
    return { t = tok.text, spell = spell }
  end
  if tok.text == "health" then
    return nil, "health is never readable -- UnitHealth is unconditionally secret. It "
      .. "belongs in `bind` as `health% < <n>`, not in `when`"
  end
  -- `soul_shards.after_cast` is one lexer token, so the suffix comes off before the name is
  -- looked up. Stripping it first is also what lets `mana.after_cast` earn the primary
  -- refusal rather than the useless "unknown term".
  local power, projected = tok.text, false
  local base = string.match(power, "^(.+)%.after_cast$")
  if base ~= nil then power, projected = base, true end
  if PRIMARY[power] then
    return nil, ("%s is a primary resource, which is never readable -- it belongs in `bind` "
      .. "as a percent, not in `when`"):format(power)
  end
  if string.match(power, "%.stacks$") or string.match(power, "%.cooldown$") then
    return nil, ("%s is a sealed term and belongs in `bind`, not in `when`"):format(power)
  end
  if not SECONDARY[power] then
    return nil, ("unknown term %q"):format(tok.text)
  end
  local cmp = Take(p)
  if cmp.kind ~= "cmp" or not COMPARISONS[cmp.text] then
    return nil, ("expected a comparison after %s, found %q"):format(tok.text, cmp.text)
  end
  local value = Take(p)
  if value.kind ~= "number" then
    return nil, ("expected a number after %s, found %q"):format(cmp.text, value.text)
  end
  local node = { t = "resource", power = power, cmp = cmp.text, value = tonumber(value.text) }
  if projected then node.projected = true end
  return node
end

local function Unary(p)
  if Peek(p).text == "not" then
    Take(p)
    local node, why = Unary(p)
    if node == nil then return nil, why end
    return { t = "not", term = node }
  end
  return Primary(p)
end

local function Conjunction(p)
  local node, why = Unary(p)
  if node == nil then return nil, why end
  while Peek(p).text == "and" do
    Take(p)
    local right, rightWhy = Unary(p)
    if right == nil then return nil, rightWhy end
    node = { t = "and", terms = { node, right } }
  end
  return node
end

function Expression(p)
  local node, why = Conjunction(p)
  if node == nil then return nil, why end
  while Peek(p).text == "or" do
    Take(p)
    local right, rightWhy = Conjunction(p)
    if right == nil then return nil, rightWhy end
    node = { t = "or", terms = { node, right } }
  end
  return node
end

local function ParseWhen(text, scope)
  local tokens, why = Lex(text)
  if tokens == nil then return nil, why end
  local p = { tokens = tokens, i = 1, scope = scope }
  local node, nodeWhy = Expression(p)
  if node == nil then return nil, nodeWhy end
  if Peek(p).kind ~= "end" then
    return nil, ("trailing %q"):format(Peek(p).text)
  end
  return node
end

-- ------------------------------------------------------------------ the bind

--- The only tail a bind takes, and the author's answer to §6.4's absence case.
local function Absent(rest)
  rest = string.match(rest or "", "^%s*(.-)%s*$")
  if rest == "" then return nil end
  local word = string.match(rest, "^absent%s+(dark)$") or string.match(rest, "^absent%s+(show)$")
  if word == nil then
    return nil, ("trailing %q; the only tail a bind takes is `absent dark` or `absent show`")
      :format(rest)
  end
  return word
end

local function ParseBind(text, scope)
  local ref, n = string.match(text, "^(.-)%.stacks%s*>=%s*(%d+)$")
  if ref == nil then
    ref, n = string.match(text, "^count%(%s*(.-)%s*%)%s*>=%s*(%d+)$")
  end
  if ref ~= nil then
    local aura, why = ns.Names.Resolve(ref, scope)
    if aura == nil then return nil, why end
    return { family = "count", aura = aura, threshold = tonumber(n) }
  end

  local lo, hi, rest
  ref, lo, hi, rest = string.match(text,
    "^(.-)%.cooldown%s+outside%s+([%d%.]+)s%s*%.%.%s*([%d%.]+)s(.*)$")
  if ref ~= nil then
    local spell, why = ns.Names.Resolve(ref, scope)
    if spell == nil then return nil, why end
    local absent, absentWhy = Absent(rest)
    if absent == nil and absentWhy ~= nil then return nil, absentWhy end
    if tonumber(hi) <= tonumber(lo) then
      return nil, ("outside %ss..%ss is empty; the second bound must be larger"):format(lo, hi)
    end
    return { family = "duration", spell = spell, cmp = "outside",
      lo = tonumber(lo), hi = tonumber(hi), absent = absent }
  end

  local cmp
  ref, cmp, n, rest = string.match(text, "^(.-)%.cooldown%s*([<>]=?)%s*([%d%.]+)s(.*)$")
  if ref ~= nil then
    local spell, why = ns.Names.Resolve(ref, scope)
    if spell == nil then return nil, why end
    local absent, absentWhy = Absent(rest)
    if absent == nil and absentWhy ~= nil then return nil, absentWhy end
    return { family = "duration", spell = spell, cmp = cmp,
      seconds = tonumber(n), absent = absent }
  end

  local pct
  cmp, pct = string.match(text, "^health%%%s*([<>]=?)%s*([%d%.]+)$")
  if cmp ~= nil then
    local value = tonumber(pct)
    if value == nil or value <= 0 or value >= 100 then
      return nil, ("health%% %s %s never changes; the threshold has to sit strictly "
        .. "between 0 and 100"):format(cmp, pct)
    end
    return { family = "health", cmp = cmp, percent = value }
  end

  local head = string.match(text, "^(%S+)") or text
  local bare = string.match(head, "^([^%.]+)")
  if SECONDARY[bare] then
    return nil, ("%s is a secondary resource and reads plain -- it belongs in `when`, "
      .. "not `bind`"):format(bare)
  end
  return nil, ("cannot read the bind %q; the forms are %s"):format(text, BIND_FORMS)
end

-- ------------------------------------------------------------------ the lines

--- Surface text -> the glow list the store takes. Returns nil plus one refusal naming its
--- line; the caller has a display path for it and must never fall back to a partial list.
function Parse.Text(text)
  local glows, current, scope = {}, nil, nil
  local lineno = 0
  for raw in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
    lineno = lineno + 1
    local line = string.match(string.gsub(raw, "%-%-.*$", ""), "^%s*(.-)%s*$")
    if line ~= "" then
      local head, rest = string.match(line, "^(%S+)%s*(.-)%s*$")
      local why
      if head == "spec" then
        scope, why = ns.Names.Scope(rest)
      elseif head == "glow" then
        current = { name = (string.gsub(rest, '^"(.*)"$', "%1")) }
        glows[#glows + 1] = current
      elseif current == nil then
        why = ("%q outside any glow"):format(head)
      elseif head == "on" then
        local subject, subjectWhy = ns.Names.Resolve(string.match(rest, "^(%S*)"), scope)
        current.subject, why = subject, subjectWhy
      elseif head == "when" or head == "show" then
        current.when, why = ParseWhen(rest, scope)
      elseif head == "bind" or head == "count" then
        current.bind, why = ParseBind(rest, scope)
      elseif head == "color" then
        current.color = string.lower(string.match(rest, "^(%S*)"))
      else
        why = ("unknown keyword %q"):format(head)
      end
      if why ~= nil then
        return nil, ("line %d: %s"):format(lineno, why)
      end
    end
  end
  return glows
end

-- ----------------------------------------------------------------- rendering

local function Scope(glows)
  -- Which spec's names to print bare. The subject a rule names is the strongest signal
  -- available in the rule itself, so the first subject that any spec claims wins.
  for _, glow in ipairs(glows) do
    local key = ns.Names.SpecOf(glow.subject)
    if key ~= nil then return key end
  end
  return nil
end

--- The glow list as text a player can edit and re-apply. Names are printed bare inside the
--- scope the `spec` line declares, so what comes out is what may be typed back in.
function Parse.Render(glows)
  local scope = Scope(glows)
  local lines = {}
  if scope ~= nil then
    lines[#lines + 1] = "spec " .. scope
    lines[#lines + 1] = ""
  end
  for _, glow in ipairs(glows) do
    lines[#lines + 1] = ('glow "%s"'):format(glow.name or "")
    lines[#lines + 1] = "  on     " .. ns.Names.Write(glow.subject, scope)
    if glow.when ~= nil then
      lines[#lines + 1] = "  when   " .. ns.Rules.Describe(glow.when)
    end
    if glow.bind ~= nil then
      lines[#lines + 1] = "  bind   " .. ns.Rules.DescribeBind(glow.bind)
    end
    if glow.color ~= nil then
      lines[#lines + 1] = "  color  " .. glow.color
    end
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end
