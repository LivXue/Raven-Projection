-- Animate the Raven mascot at idle and accept live state updates over the local HTTP API.
local function start_app()
  local APP_KEY = "RAVEN_DISPLAY_APP"
  local previous = rawget(_G, APP_KEY)
  if previous and previous.stop then previous.stop() end

  local APP = {
    version = "0.2.0",
    status = "idle",
    progress = nil,
    updates = 0,
    updated_ms = millis(),
    routes = {},
    stopped = false,
    animation_running = false,
    animation_ticks = 0,
    animation_phase = 0,
    pose = { x = 52, y = 0 },
  }
  _G[APP_KEY] = APP

  local codec = rawget(_G, "sjson") or rawget(_G, "json")
  local BASE = app.route_base()
  local DIRECTORY = "/sd/apps/raven_display"
  local MAIN = LV_PART_MAIN | LV_STATE_DEFAULT
  local IDLE_PERIOD_MS = 4800
  local IDLE_TICK_MS = 50
  local STATES = {
    idle = { label = "Ready", color = 0xE4B86D },
    thinking = { label = "Thinking", color = 0xFFD27F },
    working = { label = "Working", color = 0x91E6B7 },
    waiting = { label = "Waiting", color = 0xDDA8FF },
    error = { label = "Error", color = 0xFF8C91 },
    offline = { label = "Offline", color = 0x999CA5 },
  }

  local root = lv_scr_act()
  lv_obj_clean(root)

  local function panel(parent, x, y, width, height, color)
    local object = lv_obj_create(parent)
    lv_obj_set_pos(object, x, y)
    lv_obj_set_size(object, width, height)
    lv_obj_set_style_bg_color(object, color, MAIN)
    lv_obj_set_style_bg_opa(object, 255, MAIN)
    lv_obj_set_style_border_width(object, 0, MAIN)
    lv_obj_set_style_radius(object, 0, MAIN)
    lv_obj_set_style_pad_all(object, 0, MAIN)
    lv_obj_clear_flag(object, LV_OBJ_FLAG_SCROLLABLE)
    return object
  end

  APP.panel = panel(root, 0, 0, 320, 240, 0x000000)
  APP.portrait = lv_img_create(APP.panel)
  lv_img_set_src(APP.portrait, "S:/apps/raven_display/raven.png")
  lv_obj_set_pos(APP.portrait, 52, 0)

  local function sparkle(x, y, size)
    local object = panel(APP.panel, x, y, size + 1, size + 1, 0x000000)
    lv_obj_set_style_bg_opa(object, 0, MAIN)
    local center = math.floor(size / 2)
    local outline = lv_line_create(object)
    lv_line_set_points(outline, {
      center, 0, center + 1, center - 1, size, center,
      center + 1, center + 1, center, size,
      center - 1, center + 1, 0, center,
      center - 1, center - 1, center, 0,
    })
    lv_obj_set_style_line_color(outline, 0xEAC17C, MAIN)
    lv_obj_set_style_line_width(outline, 1, MAIN)
    panel(object, center, center, 1, 1, 0xFFF0CB)
    lv_obj_set_style_opa(object, 0, MAIN)
    return { object = object, y = y }
  end
  APP.sparkles = { sparkle(43, 66, 12), sparkle(270, 94, 10), sparkle(49, 172, 8) }

  APP.status_bar = lv_canvas_create(APP.panel, 320, 20, CANVAS_FMT_TRUE_COLOR)
  lv_obj_set_pos(APP.status_bar, 0, 220)

  APP.dot = panel(APP.panel, 88, 225, 6, 6, STATES.idle.color)
  lv_obj_set_style_radius(APP.dot, 3, MAIN)

  local function round(value)
    return math.floor(value + 0.5)
  end

  local function apply_pose(x, y)
    if APP.pose.x ~= x or APP.pose.y ~= y then
      lv_obj_set_pos(APP.portrait, x, y)
    end
    APP.pose.x, APP.pose.y = x, y
  end

  local function render_idle(phase_ms)
    APP.animation_phase = phase_ms % IDLE_PERIOD_MS
    local phase = APP.animation_phase * math.pi * 2 / IDLE_PERIOD_MS
    local breath = (1 - math.cos(phase)) / 2
    apply_pose(52 + round(2 * math.sin(phase)), round(-4 * breath))
    for index, star in ipairs(APP.sparkles) do
      local glow = math.max(0, math.sin(phase - (index - 1) * math.pi * 2 / 3)) ^ 3
      lv_obj_set_style_opa(star.object, round(230 * glow), MAIN)
      lv_obj_set_y(star.object, star.y - round(2 * glow))
    end
    lv_obj_set_style_opa(APP.dot, 175 + round(80 * breath), MAIN)
  end

  local function reset_pose()
    apply_pose(52, 0)
    for _, star in ipairs(APP.sparkles) do lv_obj_set_style_opa(star.object, 0, MAIN) end
    lv_obj_set_style_opa(APP.dot, 255, MAIN)
    APP.animation_phase = 0
  end

  local function sync_animation()
    local should_run = APP.status == "idle" and not APP.stopped
    if should_run == APP.animation_running then return end
    APP.animation_running = should_run
    if should_run then
      APP.animation_started_ms = millis()
      render_idle(0)
      local started = APP.animation_timer:alarm(IDLE_TICK_MS, tmr.ALARM_AUTO, function()
        if APP.stopped or not APP.animation_running then return end
        if app.exiting() then APP.stop() return end
        APP.animation_ticks = APP.animation_ticks + 1
        local rendered, animation_error = pcall(render_idle, millis() - APP.animation_started_ms)
        if not rendered then
          APP.animation_running = false
          APP.animation_error = tostring(animation_error)
          APP.animation_timer:stop()
          file.putcontents(DIRECTORY .. "/last_error.txt", APP.animation_error)
        end
      end)
      if started == false then error("Cannot start the idle animation timer") end
    else
      APP.animation_timer:stop()
      reset_pose()
    end
  end

  local function render_state()
    local state = STATES[APP.status]
    local label = state.label
    if APP.progress ~= nil then label = label .. "  " .. tostring(APP.progress) .. "%" end
    lv_canvas_begin(APP.status_bar)
    lv_canvas_fill_bg(APP.status_bar, 0x000000, 255)
    lv_canvas_draw_text(APP.status_bar, 12, 1, 76, "RAVEN", {
      font_handle = LV_FONT_MONTSERRAT_12, color = 0xF2D298, letter_space = 1,
    })
    lv_canvas_draw_text(APP.status_bar, 102, 1, 208, label, {
      font_handle = LV_FONT_MONTSERRAT_12, color = state.color,
    })
    lv_canvas_end(APP.status_bar)
    lv_obj_set_style_bg_color(APP.dot, state.color, MAIN)
    sync_animation()
  end

  local function state_payload()
    return {
      ok = true,
      app = "raven_display",
      api_version = 1,
      version = APP.version,
      status = APP.status,
      progress = APP.progress,
      updates = APP.updates,
      updated_ms = APP.updated_ms,
      route_base = BASE,
      screen = { width = 320, height = 240 },
      portrait = {
        width = lv_obj_get_width(APP.portrait),
        height = lv_obj_get_height(APP.portrait),
      },
      animation = {
        name = "raven_idle",
        running = APP.animation_running,
        period_ms = IDLE_PERIOD_MS,
        tick_ms = IDLE_TICK_MS,
        ticks = APP.animation_ticks,
        phase_ms = APP.animation_phase,
        x = APP.pose.x,
        y = APP.pose.y,
        error = APP.animation_error,
      },
    }
  end

  local function respond(status, value)
    return {
      status = status,
      type = "application/json; charset=utf-8",
      headers = { ["cache-control"] = "no-store", ["connection"] = "close" },
      body = codec.encode(value),
    }
  end

  local function update_state(request)
    local chunks, size = {}, 0
    while true do
      local chunk = request.getbody()
      if not chunk or #chunk == 0 then break end
      size = size + #chunk
      if size > 1024 then
        return respond("413 Payload Too Large", { ok = false, error = "Maximum body size is 1024 bytes" })
      end
      chunks[#chunks + 1] = chunk
    end
    local decoded, value = pcall(codec.decode, table.concat(chunks))
    if not decoded or type(value) ~= "table" then
      return respond("400 Bad Request", { ok = false, error = "Expected a JSON object" })
    end
    if type(value.status) ~= "string" or not STATES[value.status] then
      return respond("400 Bad Request", { ok = false, error = "Unknown status" })
    end
    for field in pairs(value) do
      if field ~= "status" and field ~= "progress" then
        return respond("400 Bad Request", { ok = false, error = "Unknown field: " .. tostring(field) })
      end
    end
    local progress = value.progress
    if progress ~= nil and (type(progress) ~= "number" or progress ~= progress or
        progress < 0 or progress > 100 or progress ~= math.floor(progress)) then
      return respond("400 Bad Request", { ok = false, error = "Progress must be an integer from 0 to 100" })
    end
    APP.status = value.status
    APP.progress = progress
    APP.updates = APP.updates + 1
    APP.updated_ms = millis()
    render_state()
    return respond("200 OK", state_payload())
  end

  local function save_snapshot(request)
    if not lv_snapshot_take or not lv_snapshot_save_to_png then
      return respond("501 Not Implemented", { ok = false, error = "Firmware does not support snapshots" })
    end
    local phase_ms
    local query = request.query or ""
    if query ~= "" then
      phase_ms = tonumber(query:match("^phase_ms=(%d+)$"))
      if not phase_ms or phase_ms >= IDLE_PERIOD_MS then
        return respond("400 Bad Request", { ok = false, error = "phase_ms must be from 0 to 4799" })
      end
      if not APP.animation_running then
        return respond("409 Conflict", { ok = false, error = "Phase capture requires idle state" })
      end
      render_idle(phase_ms)
    end
    local captured, snapshot, capture_error = pcall(lv_snapshot_take, APP.panel)
    if phase_ms then render_idle(millis() - APP.animation_started_ms) end
    if not captured then
      return respond("500 Internal Server Error", { ok = false, error = tostring(snapshot) })
    end
    if not snapshot then
      return respond("500 Internal Server Error", { ok = false, error = tostring(capture_error) })
    end
    local path = DIRECTORY .. "/snapshot.png"
    local called, saved, save_error = pcall(lv_snapshot_save_to_png, snapshot, path)
    lv_snapshot_free(snapshot)
    if not called or not saved then
      return respond("500 Internal Server Error", { ok = false, error = tostring(save_error or saved) })
    end
    return respond("200 OK", { ok = true, path = path, width = 320, height = 240, phase_ms = phase_ms })
  end

  local function register(method, suffix, handler)
    local route = BASE .. suffix
    local err = httpd.dynamic(method, route, handler)
    if err then error("Cannot register " .. route .. ": " .. tostring(err)) end
    APP.routes[#APP.routes + 1] = { method = method, route = route }
  end

  function APP.stop()
    if APP.stopped then return end
    APP.stopped = true
    APP.animation_running = false
    if APP.animation_timer then
      APP.animation_timer:stop()
      APP.animation_timer:unregister()
      APP.animation_timer = nil
    end
    key.off(key.HOME)
    for _, route in ipairs(APP.routes) do
      pcall(httpd.unregister, route.method, route.route)
    end
    APP.routes = {}
    if APP.panel then pcall(lv_obj_del, APP.panel) end
    APP.panel = nil
    if rawget(_G, APP_KEY) == APP then _G[APP_KEY] = nil end
  end
  APP.shutdown = APP.stop

  httpd.start({ webroot = DIRECTORY, auto_index = httpd.INDEX_NONE, max_handlers = 8 })
  register(httpd.GET, "", function() return respond("200 OK", state_payload()) end)
  register(httpd.GET, "/", function() return respond("200 OK", state_payload()) end)
  register(httpd.GET, "/api/state", function() return respond("200 OK", state_payload()) end)
  register(httpd.POST, "/api/state", update_state)
  register(httpd.POST, "/api/snapshot", save_snapshot)

  key.on(key.HOME, function(event)
    if event == key.SHORT then
      APP.stop()
      app.exit()
    end
  end)

  APP.animation_timer = tmr.create()
  render_state()

  print("[Raven] Ready at " .. BASE .. "/api/state")
end

local ok, failure = xpcall(start_app, function(message)
  return debug and debug.traceback and debug.traceback(tostring(message), 2) or tostring(message)
end)
if ok then
  file.putcontents("/sd/apps/raven_display/last_error.txt", "")
else
  local failed_app = rawget(_G, "RAVEN_DISPLAY_APP")
  if failed_app and failed_app.stop then pcall(failed_app.stop) end
  file.putcontents("/sd/apps/raven_display/last_error.txt", tostring(failure))
  error(failure)
end
