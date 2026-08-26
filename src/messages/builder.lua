local Builder = {}

local function element(text, options)
  local out = { type = "text", text = text }
  for key, value in pairs(options or {}) do out[key] = value end
  return out
end

function Builder.build(event, channel_name)
  if type(event) ~= "table" or type(event.kind) ~= "string" then return nil end
  if event.kind ~= "text_message" then
    local messages = {
      deleted_message = "🗑 Message deleted",
      clear_chat = "🧹 Chat cleared",
      user_banned = "🚫 User banned: " .. tostring(event.author or "?"),
      subscription = "⭐ New subscription: " .. tostring(event.author or "?"),
      gift = "🎁 " .. tostring(event.author or "?") .. " gifted " .. tostring(event.count or 1) .. " subscriptions"
    }
    return { system = true, message_text = "🟢 KICK " .. (messages[event.kind] or "Event") }
  end
  local author, body = tostring(event.author or "[?]"), tostring(event.text or "")
  local badge_text = #event.badges > 0 and ("[" .. table.concat(event.badges, "][") .. "] ") or ""
  return {
    id = event.id ~= "" and ("kick-chat-" .. event.id) or nil,
    message_text = "🟢 KICK " .. author .. ": " .. body,
    display_name = author, login_name = author, system = false,
    elements = {
      element("🟢", { style = "ChatMediumBold" }),
      element("KICK", { color = "#53FC18", style = "ChatMediumBold" }),
      { type = "timestamp" },
      element("(" .. channel_name .. ")", { color = "system", style = "Tiny" }),
      element(badge_text .. author .. ":", { color = event.author_color or "green", style = "ChatMediumBold" }),
      element(body)
    }
  }
end

return Builder
