-- Small defensive JSON codec for the Chatterino sandbox.
local Json = {}

local function escape(value)
  return value:gsub('[%z\1-\31\\"]', function(ch)
    local map = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
    return map[ch] or string.format('\\u%04x', string.byte(ch))
  end)
end

local function is_array(value)
  local max, count = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    max, count = math.max(max, key), count + 1
  end
  return max == count
end

function Json.encode(value)
  local kind = type(value)
  if value == nil then return "null" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. escape(value) .. '"' end
  if kind ~= "table" then error("unsupported JSON type") end
  local out = {}
  if is_array(value) then
    for i = 1, #value do out[#out + 1] = Json.encode(value[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for key, item in pairs(value) do
    if type(key) == "string" then out[#out + 1] = Json.encode(key) .. ":" .. Json.encode(item) end
  end
  table.sort(out)
  return "{" .. table.concat(out, ",") .. "}"
end

function Json.decode(source)
  assert(type(source) == "string", "JSON input must be a string")
  local pos, length = 1, #source
  local parse_value
  local function skip() while pos <= length and source:sub(pos,pos):match("%s") do pos = pos + 1 end end
  local function parse_string()
    assert(source:sub(pos,pos) == '"', "expected string")
    pos = pos + 1
    local out = {}
    while pos <= length do
      local ch = source:sub(pos,pos); pos = pos + 1
      if ch == '"' then return table.concat(out) end
      if ch == "\\" then
        local esc = source:sub(pos,pos); pos = pos + 1
        local map = { ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
        if map[esc] then out[#out + 1] = map[esc]
        elseif esc == "u" then
          local hex = source:sub(pos,pos+3); assert(hex:match("^%x%x%x%x$"), "bad unicode escape"); pos = pos + 4
          local code = tonumber(hex, 16)
          if code >= 0xD800 and code <= 0xDBFF and source:sub(pos,pos+1) == "\\u" then
            local low = tonumber(source:sub(pos+2,pos+5), 16)
            if low and low >= 0xDC00 and low <= 0xDFFF then code = 0x10000 + (code-0xD800)*0x400 + low-0xDC00; pos = pos + 6 end
          end
          out[#out + 1] = utf8.char(code)
        else error("bad escape") end
      else out[#out + 1] = ch end
    end
    error("unterminated string")
  end
  local function parse_array()
    pos = pos + 1; local out = {}; skip()
    if source:sub(pos,pos) == "]" then pos = pos + 1; return out end
    while true do
      out[#out + 1] = parse_value(); skip()
      local ch = source:sub(pos,pos); pos = pos + 1
      if ch == "]" then return out end
      assert(ch == ",", "expected comma")
    end
  end
  local function parse_object()
    pos = pos + 1; local out = {}; skip()
    if source:sub(pos,pos) == "}" then pos = pos + 1; return out end
    while true do
      skip(); local key = parse_string(); skip(); assert(source:sub(pos,pos) == ":", "expected colon"); pos = pos + 1
      out[key] = parse_value(); skip(); local ch = source:sub(pos,pos); pos = pos + 1
      if ch == "}" then return out end
      assert(ch == ",", "expected comma")
    end
  end
  function parse_value()
    skip(); local ch = source:sub(pos,pos)
    if ch == '"' then return parse_string() end
    if ch == "{" then return parse_object() end
    if ch == "[" then return parse_array() end
    local tail = source:sub(pos)
    if tail:sub(1,4) == "true" then pos = pos + 4; return true end
    if tail:sub(1,5) == "false" then pos = pos + 5; return false end
    if tail:sub(1,4) == "null" then pos = pos + 4; return nil end
    local token = tail:match("^-?%d+%.?%d*[eE]?[+-]?%d*")
    assert(token and token ~= "", "invalid JSON value"); pos = pos + #token; return tonumber(token)
  end
  local result = parse_value(); skip(); assert(pos > length, "trailing JSON data"); return result
end

return Json
