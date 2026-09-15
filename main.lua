--[[
  capture — an abstract sketch of one verb: a box follows the mouse, seekers
  drift and settle into groups on a closed board, click captures whatever is
  inside the box.

  DEFINITIONS ONLY (reloads on save). One-time work lives in boot.lua.
  Drive it:
    anchor drive start .
    anchor drive eval  . 'engine_step(60) return #units'
    anchor drive stop  .
]]

require('anchor')({
  width  = 640,
  height = 360,
  scale  = 2,
  title  = 'capture',
  filter = 'smooth',
  boot   = {'boot.lua'},
})

-- palette (SNKRX) -----------------------------------------------------------
BG       = color(34, 40, 46)
GRID     = color(42, 49, 56)
WALL     = color(52, 60, 68)
CREAM    = color(240, 232, 214)
DIM      = color(120, 126, 134)
SEEKER   = color(216, 70, 84)

-- tuning --------------------------------------------------------------------
UNIT_COUNT     = 20
UNIT_W, UNIT_H = 14, 6
WALL_T         = 10          -- wall thickness; the board is closed
BOX_W, BOX_H   = 120, 76
BOX_FOLLOW     = 22
SPOT_COUNT     = 4           -- gathering spots on the board
GROUP_CHANCE   = 70          -- percent: a unit picks a spot (group) vs its own place (alone)
UNIT_SPEED     = 34          -- max speed while travelling
UNIT_FORCE     = 60          -- steering force cap
SETTLE_RADIUS  = 26          -- arrive slow radius
STARTLE_RADIUS = 60
HITSTOP        = 0.10
HITSTOP_SLOW   = 0.12

-- helpers -------------------------------------------------------------------
function approach(a, b, k, dt) return a + (b - a)*(1 - math.exp(-k*dt)) end
function rgba_alpha(c, a) return color(c.r, c.g, c.b, math.floor(a*255)) end
function rf(a, b) return random_float(a, b, rng) end
function ri(a, b) return random_int(a, b, rng) end

-- world ---------------------------------------------------------------------
function world_reset()
  if units then for _, u in ipairs(units) do u.collider:destroy() end end
  if walls then for _, w in ipairs(walls) do w.collider:destroy() end end
  units, walls, spots, particles, rings, popups, respawn_queue = {}, {}, {}, {}, {}, {}, {}
  total, best = 0, 0
  slow, slow_t, trauma = 1, 0, 0
  box = {x = width/2, y = height/2, tilt = 0, flash = 0, s = spring_new()}
  spring_add(box.s, 'scale', 1, 9, 0.35)
  spring_add(box.s, 'thick', 2, 7, 0.4)
  total_s = spring_new()
  spring_add(total_s, 'scale', 1, 6, 0.5)
  wall_add(width/2, WALL_T/2, width, WALL_T)
  wall_add(width/2, height - WALL_T/2, width, WALL_T)
  wall_add(WALL_T/2, height/2, WALL_T, height)
  wall_add(width - WALL_T/2, height/2, WALL_T, height)
  for i = 1, SPOT_COUNT do spots[i] = spot_new() end
  for i = 1, UNIT_COUNT do unit_spawn(true) end
end

function wall_add(x, y, w, h)
  local wall = {x = x, y = y, w = w, h = h}
  wall.collider = collider(wall, 'wall', 'static', 'box', w, h)
  wall.collider:set_position(x, y)
  walls[#walls + 1] = wall
end

-- gathering spots drift slowly and occasionally jump somewhere new
function spot_new()
  return {x = rf(70, width - 70), y = rf(60, height - 60), t = rf(6, 14), vx = rf(-4, 4), vy = rf(-4, 4)}
end

function spots_update(dt)
  for i, s in ipairs(spots) do
    s.t = s.t - dt
    s.x, s.y = math.clamp(s.x + s.vx*dt, 60, width - 60), math.clamp(s.y + s.vy*dt, 50, height - 50)
    if s.t <= 0 then
      spots[i] = spot_new()
      for _, u in ipairs(units) do if u.spot == s then unit_pick_target(u) end end
    end
  end
end

-- units ---------------------------------------------------------------------
function unit_spawn(anywhere)
  local u = {r = 0, alive = true, s = spring_new(), settled = 0, idle_t = rf(0, 10)}
  if anywhere then
    u.x, u.y = rf(40, width - 40), rf(40, height - 40)
  else
    -- come in along a wall, just inside the board
    local side = ri(1, 4)
    if side == 1 then u.x, u.y = WALL_T + 12, rf(40, height - 40)
    elseif side == 2 then u.x, u.y = width - WALL_T - 12, rf(40, height - 40)
    elseif side == 3 then u.x, u.y = rf(40, width - 40), WALL_T + 12
    else u.x, u.y = rf(40, width - 40), height - WALL_T - 12 end
  end
  spring_add(u.s, 'scale', 0.01, 7, 0.5)
  spring_set_target(u.s, 'scale', 1)
  u.collider = collider(u, 'unit', 'dynamic', 'box', UNIT_W, UNIT_H)
  u.collider:set_position(u.x, u.y)
  u.collider:set_linear_damping(4)
  u.collider:set_angular_damping(6)
  u.collider:set_friction(0.3)
  u.collider:set_restitution(0.15)
  unit_pick_target(u)
  units[#units + 1] = u
  return u
end

-- a unit either joins a spot (with its own offset so groups spread out a
-- little) or picks a place of its own; it reconsiders every few seconds
function unit_pick_target(u)
  if random_bool(GROUP_CHANCE, rng) then
    u.spot = random_choice(spots, rng)
    local a, d = rf(0, math.pi*2), rf(4, 22)
    u.ox, u.oy = math.cos(a)*d, math.sin(a)*d
  else
    u.spot = nil
    u.tx, u.ty = rf(50, width - 50), rf(45, height - 45)
  end
  u.retarget = rf(5, 12)
end

function unit_target(u)
  if u.spot then return u.spot.x + u.ox, u.spot.y + u.oy end
  return u.tx, u.ty
end

function unit_update(u, dt)
  u.collider:sync()
  u.retarget = u.retarget - dt
  if u.retarget <= 0 then unit_pick_target(u) end
  local tx, ty = unit_target(u)
  local d = math.distance(u.x, u.y, tx, ty)
  if d > 6 then
    local fx, fy = u.collider:steering_arrive(tx, ty, SETTLE_RADIUS, UNIT_SPEED, UNIT_FORCE)
    u.collider:apply_force(fx, fy)
    u.settled = 0
  else
    u.settled = u.settled + dt
  end
  -- face the way it moves; when still, a slow idle wobble
  local vx, vy = u.collider:get_velocity()
  if math.length(vx, vy) > 4 then
    u.r = math.lerp_angle_dt(0.99, 0.12, dt, u.r, math.angle(vx, vy))
  else
    u.idle_t = u.idle_t + dt
    u.r = u.r + math.sin(u.idle_t*1.3)*0.15*dt
  end
  u.collider:set_angle(u.r)
  spring_update(u.s, dt)
end

function unit_draw(u)
  local sc = u.s.scale.x
  local stretch = 0
  if u.alive then
    local vx, vy = u.collider:get_velocity()
    stretch = math.clamp(math.length(vx, vy)/300, 0, 0.25)
  end
  layer_push(game, u.x, u.y, u.r, sc*(1 + stretch), sc*(1 - stretch))
  layer_rounded_rectangle(game, -UNIT_W/2, -UNIT_H/2, UNIT_W, UNIT_H, 3, SEEKER)
  layer_pop(game)
end

-- the box -------------------------------------------------------------------
function box_update(dt)
  local mx, my = mouse_position()
  local px = box.x
  box.x = approach(box.x, mx, BOX_FOLLOW, dt)
  box.y = approach(box.y, my, BOX_FOLLOW, dt)
  local vx = (box.x - px)/math.max(dt, 0.0001)
  box.tilt = approach(box.tilt, math.clamp(vx/2600, -0.12, 0.12), 12, dt)
  box.flash = math.max(0, box.flash - dt*7)
  spring_update(box.s, dt)
end

function box_contains(u)
  return math.abs(u.x - box.x) < BOX_W/2 and math.abs(u.y - box.y) < BOX_H/2
end

function box_edge_distance(u)
  local dx = math.max(math.abs(u.x - box.x) - BOX_W/2, 0)
  local dy = math.max(math.abs(u.y - box.y) - BOX_H/2, 0)
  return math.length(dx, dy)
end

function box_draw()
  local sc, thick = box.s.scale.x, box.s.thick.x
  local hw, hh = BOX_W/2, BOX_H/2
  layer_push(game, box.x, box.y, box.tilt, sc, sc)
  if box.flash > 0 then layer_rectangle(game, -hw, -hh, BOX_W, BOX_H, rgba_alpha(CREAM, box.flash*0.55)) end
  layer_rectangle(game, -hw, -hh, BOX_W, BOX_H, rgba_alpha(CREAM, 0.05))
  layer_rectangle_line(game, -hw, -hh, BOX_W, BOX_H, CREAM, thick)
  local t = 10
  for _, c in ipairs({{-1, -1}, {1, -1}, {-1, 1}, {1, 1}}) do
    local cx, cy = c[1]*hw, c[2]*hh
    layer_line(game, cx, cy, cx - c[1]*t, cy, thick + 1.5, CREAM)
    layer_line(game, cx, cy, cx, cy - c[2]*t, thick + 1.5, CREAM)
  end
  layer_pop(game)
end

-- the click -----------------------------------------------------------------
function capture()
  local caught = {}
  for _, u in ipairs(units) do if u.alive and box_contains(u) then caught[#caught + 1] = u end end
  local n = #caught
  box.flash = 1
  if n == 0 then
    spring_pull(box.s, 'scale', -0.06)
    for i = 1, 6 do particle_spawn(box.x + rf(-BOX_W/2, BOX_W/2), box.y + rf(-BOX_H/2, BOX_H/2), DIM, 40, 2) end
    return
  end
  spring_pull(box.s, 'scale', -0.16 - 0.03*n)
  spring_pull(box.s, 'thick', 3 + n)
  slow, slow_t = HITSTOP_SLOW, HITSTOP + 0.02*n
  trauma = math.min(1, trauma + 0.18 + 0.1*n)
  for _, u in ipairs(caught) do
    u.alive = false
    u.dying = 0
    u.collider:destroy()
    spring_pull(u.s, 'scale', 0.9)
    for i = 1, 8 + ri(0, 6) do particle_spawn(u.x, u.y, SEEKER, 160 + 30*n, 3.5) end
    rings[#rings + 1] = {x = u.x, y = u.y, r = 6, t = 0, color = SEEKER}
    respawn_queue[#respawn_queue + 1] = rf(1.5, 3)
  end
  rings[#rings + 1] = {x = box.x, y = box.y, r = BOX_H/2, t = 0, color = CREAM, box = true}
  -- neighbours are shoved away from the box
  for _, u in ipairs(units) do
    if u.alive then
      local d = box_edge_distance(u)
      if d < STARTLE_RADIUS then
        local a = math.angle_to_point(box.x, box.y, u.x, u.y)
        local k = (1 - d/STARTLE_RADIUS)*u.collider:get_mass()*90
        u.collider:apply_impulse(math.cos(a)*k, math.sin(a)*k)
        spring_pull(u.s, 'scale', 0.3)
      end
    end
  end
  total = total + n
  if n > best then best = n end
  spring_pull(total_s, 'scale', 0.25 + 0.1*n)
  local p = {x = box.x, y = box.y - BOX_H/2 - 8, t = 0, n = n, s = spring_new()}
  spring_add(p.s, 'scale', 0.2, 8, 0.4)
  spring_set_target(p.s, 'scale', 1)
  popups[#popups + 1] = p
end

function particle_spawn(x, y, col, speed, size)
  local a = rf(0, math.pi*2)
  local v = rf(speed*0.3, speed)
  particles[#particles + 1] = {
    x = x, y = y, vx = math.cos(a)*v, vy = math.sin(a)*v, life = 0, max = rf(0.35, 0.8),
    color = col, size = rf(size*0.5, size), square = random_bool(50, rng),
  }
end

-- update / draw -------------------------------------------------------------
function update(dt)
  sync_engine_globals()
  if input_pressed('quit') then engine_quit() end
  if input_pressed('reset') then world_reset() end

  -- hitstop: the world (physics included, via the engine's time scale) slows,
  -- the box and the UI run on the unscaled step
  local rdt = unscaled_dt or dt
  if slow_t > 0 then slow_t = slow_t - rdt
  else slow = approach(slow, 1, 14, rdt) end
  set_time_scale(slow)
  local wdt = dt

  box_update(rdt)
  if input_pressed('capture') then capture() end
  spots_update(wdt)

  for i = #units, 1, -1 do
    local u = units[i]
    if u.alive then unit_update(u, wdt)
    else
      u.dying = u.dying + rdt
      spring_update(u.s, rdt)
      if u.dying > 0.08 then spring_set_target(u.s, 'scale', 0) end
      if u.dying > 0.4 then table.remove(units, i) end
    end
  end
  for i = #respawn_queue, 1, -1 do
    respawn_queue[i] = respawn_queue[i] - rdt
    if respawn_queue[i] <= 0 then table.remove(respawn_queue, i) unit_spawn(false) end
  end
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.life = p.life + wdt
    p.x, p.y = p.x + p.vx*wdt, p.y + p.vy*wdt
    p.vx, p.vy = p.vx*(1 - math.min(1, 4*wdt)), p.vy*(1 - math.min(1, 4*wdt))
    if p.life > p.max then table.remove(particles, i) end
  end
  for i = #rings, 1, -1 do
    rings[i].t = rings[i].t + rdt
    if rings[i].t > 0.45 then table.remove(rings, i) end
  end
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.t = p.t + rdt
    spring_update(p.s, rdt)
    if p.t > 0.9 then table.remove(popups, i) end
  end
  spring_update(total_s, rdt)
  trauma = math.max(0, trauma - rdt*2.2)
  process_destroy_queue()
end

function draw()
  local sh = trauma*trauma*7
  local ox, oy = rf(-sh, sh), rf(-sh, sh)
  layer_rectangle(game, 0, 0, width, height, BG)
  for gx = 0, width, 40 do for gy = 0, height, 40 do layer_circle(game, gx, gy, 1, GRID) end end
  layer_push(game, ox, oy, 0, 1, 1)
  for _, w in ipairs(walls) do layer_rectangle(game, w.x - w.w/2, w.y - w.h/2, w.w, w.h, WALL) end
  for _, r in ipairs(rings) do
    local f = r.t/0.45
    local rad = r.r + (r.box and 90 or 34)*math.quad_out(f)
    layer_circle_line(game, r.x, r.y, rad, rgba_alpha(r.color, (1 - f)*0.9), (r.box and 3 or 2)*(1 - f) + 0.5)
  end
  for _, u in ipairs(units) do unit_draw(u) end
  for _, p in ipairs(particles) do
    local f = 1 - p.life/p.max
    if p.square then layer_rectangle(game, p.x - p.size*f/2, p.y - p.size*f/2, p.size*f, p.size*f, p.color)
    else layer_circle(game, p.x, p.y, p.size*f*0.6, p.color) end
  end
  box_draw()
  layer_pop(game)

  for _, p in ipairs(popups) do
    local f = p.t/0.9
    local sc = p.s.scale.x
    local font = p.n >= 3 and 'big' or 'mid'
    layer_push(ui, p.x, p.y - 30*math.quad_out(f), 0, sc, sc)
    layer_text(ui, '+' .. p.n, fonts[font], -12*(#tostring(p.n)), -20, rgba_alpha(CREAM, 1 - math.quad_in(f)))
    layer_pop(ui)
  end
  layer_push(ui, 24, 20, 0, total_s.scale.x, total_s.scale.x)
  layer_text(ui, tostring(total), fonts['big'], 0, 0, CREAM)
  layer_pop(ui)
  layer_text(ui, 'best ' .. best, fonts['small'], 24, 74, DIM)
  layer_text(ui, 'click  capture     R  reset     Esc  quit', fonts['small'], 24, height - 34, DIM)

  layer_render(game) layer_draw(game)
  layer_render(ui) layer_draw(ui)
end

require('boot')
