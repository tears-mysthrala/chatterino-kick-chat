local Events = {}

local function text_runs(content)
  return { { type = "text", text = tostring(content or "") } }
end

local function badges(sender)
  local out = {}
  local identity = type(sender) == "table" and sender.identity or nil
  for _, badge in ipairs(type(identity) == "table" and identity.badges or {}) do
    if type(badge) == "table" and type(badge.type) == "string" then out[#out + 1] = badge.type end
  end
  return out
end

function Events.normalize(event_name, data)
  if type(data) ~= "table" then return nil end
  if event_name == "App\\Events\\ChatMessageEvent" then
    local sender = type(data.sender) == "table" and data.sender or {}
    return {
      kind = "text_message", id = tostring(data.id or ""), author = tostring(sender.username or "[?]"),
      author_color = type(sender.identity) == "table" and sender.identity.color or nil,
      badges = badges(sender), runs = text_runs(data.content), text = tostring(data.content or ""),
      created_at = data.created_at
    }
  end
  if event_name == "App\\Events\\MessageDeletedEvent" then
    local message = type(data.message) == "table" and data.message or {}
    return { kind = "deleted_message", target_message_id = tostring(message.id or data.id or "") }
  end
  if event_name == "App\\Events\\ChatroomClearEvent" then return { kind = "clear_chat" } end
  if event_name == "App\\Events\\UserBannedEvent" then
    local user = type(data.user) == "table" and data.user or {}
    return { kind = "user_banned", author = tostring(user.username or data.username or "?") }
  end
  if event_name == "App\\Events\\SubscriptionEvent" then
    local user = type(data.user) == "table" and data.user or {}
    return { kind = "subscription", author = tostring(user.username or data.username or "?") }
  end
  if event_name == "GiftedSubscriptionsEvent" then
    return { kind = "gift", author = tostring(data.gifter_username or "?"), count = tonumber(data.gifted_total) or 1 }
  end
  return nil
end

return Events
