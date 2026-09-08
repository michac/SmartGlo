-- The exchange format: `SG1:` + base64(deflate(json envelope)), decodable in Python alone.

local _, ns = ...

local Wire = {}
ns.Wire = Wire

Wire.PREFIX = "SG1:"

--- Adler-32, so the Python side is `zlib.adler32` and needs no bit library here.
local function Checksum(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + string.byte(s, i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

Wire.Checksum = Checksum

local function api()
  if type(C_EncodingUtil) ~= "table" then return nil, "C_EncodingUtil is absent" end
  return C_EncodingUtil
end

--- Every call gets its own pcall: these RAISE on bad input rather than returning nothing,
--- and a decoder that returns a value is not evidence the input was well-formed.
function Wire.Encode(ast)
  local util, absent = api()
  if util == nil then return nil, absent end

  local okJson, json = pcall(util.SerializeJSON, ast)
  if not okJson then return nil, "SerializeJSON refused: " .. tostring(json) end

  local envelope = { c = Checksum(json), j = json }
  local okEnv, encoded = pcall(util.SerializeJSON, envelope)
  if not okEnv then return nil, "SerializeJSON refused the envelope: " .. tostring(encoded) end

  local okZip, packed = pcall(util.CompressString, encoded, Enum.CompressionMethod.Deflate)
  if not okZip then return nil, "CompressString refused: " .. tostring(packed) end

  local ok64, text = pcall(util.EncodeBase64, packed, Enum.Base64Variant.Standard)
  if not ok64 then return nil, "EncodeBase64 refused: " .. tostring(text) end

  return Wire.PREFIX .. text
end

function Wire.Decode(text)
  local util, absent = api()
  if util == nil then return nil, absent end
  if type(text) ~= "string" then return nil, "not a string" end

  local body = string.match(text, "^%s*" .. Wire.PREFIX .. "(%S+)%s*$")
  if body == nil then return nil, "does not start with " .. Wire.PREFIX end

  local ok64, packed = pcall(util.DecodeBase64, body, Enum.Base64Variant.Standard)
  if not ok64 then return nil, "DecodeBase64 refused: " .. tostring(packed) end

  local okZip, encoded = pcall(util.DecompressString, packed, Enum.CompressionMethod.Deflate)
  if not okZip then return nil, "DecompressString refused: " .. tostring(encoded) end

  local okEnv, envelope = pcall(util.DeserializeJSON, encoded)
  if not okEnv then return nil, "DeserializeJSON refused the envelope: " .. tostring(envelope) end
  if type(envelope) ~= "table" or type(envelope.j) ~= "string" or type(envelope.c) ~= "number" then
    return nil, "the payload is not a SmartGlo envelope"
  end
  if Checksum(envelope.j) ~= envelope.c then
    return nil, "checksum mismatch -- the string was truncated or edited"
  end

  local okAst, ast = pcall(util.DeserializeJSON, envelope.j)
  if not okAst then return nil, "DeserializeJSON refused: " .. tostring(ast) end
  if type(ast) ~= "table" then return nil, "the payload is not a rule set" end
  return ast
end
