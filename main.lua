--[[
  capture — an abstract sketch of one verb: a rectangle follows the mouse,
  shapes move around, click captures whatever is inside.

  DEFINITIONS ONLY (reloads on save). One-time work lives in boot.lua.
  Drive it:
    anchor drive start .
    anchor drive eval  . 'engine_step(60) return #entities'
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

-- palette -------------------------------------------------------------------
BG        = color(18, 18, 26)
GRID      = color(28, 28, 40)
CREAM     = color(240, 232, 214)
DIM       = color(120, 116, 130)
PALETTE   = {
  color(255, 107, 107), color(255, 190, 87), color(120, 220, 140),
  color(96, 186, 255), color(200, 120, 255), color(255, 140, 200),
}

-- tuning --------------------------------------------------------------------
ENTITY_COUNT   = 16
BOX_W, BOX_H   = 132, 84
BOX_FOLLOW     = 22        -- how fast the box catches the mouse (higher = tighter)
STARTLE_RADIUS = 70        -- shapes this close to the box edge flinch on a click
HITSTOP        = 0.10      -- seconds of near-freeze on a hit
HITSTOP_SLOW   = 0.12
TRAIL_LEN      = 9

-- helpers -------------------------------------------------------------------
function approach(a, b, k, dt) return a + (b - a)*(1 - math.exp(-k*dt)) end
function rgba_alpha(c, a) return color(c.r, c.g, c.b, math.floor(a*255)) end
function rf(a, b) return random_float(a, b, rng) end
function ri(a, b) return random_int(a, b, rng) end

-- world ---------------------------------------------------------------------
function world_reset()
  entities, particles, rings, popups = {}, {}, {}, {}
  respawn_queue = {}
  total, best = 0, 0
  slow, slow_t = 1, 0
  trauma = 0
  box = {x = width/2, y = height/2, tilt = 0, flash = 0, s = spring_new()}
  spring_add(box.s, 'scale', 1, 9, 0.35)
  spring_add(box.s, 'thick', 2, 7, 0.4)
  total_s = spring_new()
  spring_add(total_s, 'scale', 1, 6, 0.5)
  for i = 1, ENTITY_COUNT do entity_spawn(true) end
end

KINDS = {'circle', 'square', 'tri'}
MOVES = {'drift', 'dart', 'orbit', 'bounce'}

function entity_spawn(anywhere)
  local e = {
    kind = random_choice(KINDS, rng), move = random_choice(MOVES, rng),
    color = random_choice(PALETTE, rng), r = rf(8, 15),
    x = 0, y = 0, vx = 0, vy = 0, angle = rf(0, math.pi*2), spin = rf(-1.5, 1.5),
    phase = rf(0, 100), speed = rf(40, 90), t = 0, trail = {}, alive = true,
    s = spring_new(), born = 0,
  }
  spring_add(e.s, 'scale', 0.01, 7, 0.5)
  spring_set_target(e.s, 'scale', 1)
  if anywhere then
    e.x, e.y = rf(40, width - 40), rf(40, height - 40)
  else
    local side = ri(1, 4)
    if side == 1 then e.x, e.y = -20, rf(30, height - 30)
    elseif side == 2 then e.x, e.y = width + 20, rf(30, height - 30)
    elseif side == 3 then e.x, e.y = rf(30, width - 30), -20
    else e.x, e.y = rf(30, width - 30), height + 20 end
  end
  local a = math.angle_to_point(e.x, e.y, width/2 + rf(-100, 100), height/2 + rf(-60, 60))
  e.vx, e.vy = math.cos(a)*e.speed, math.sin(a)*e.speed
  if e.move == 'orbit' then
    e.ox, e.oy = e.x, e.y
    e.orad = rf(30, 70)
    e.ospeed = rf(1.2, 2.6)*random_sign(0.5, rng)
    e.ovx, e.ovy = rf(-25, 25), rf(-25, 25)
  elseif e.move == 'dart' then
    e.wait = rf(0.4, 1.4)
  end
  entities[#entities + 1] = e
  return e
end

function entity_update(e, dt)
  e.t = e.t + dt
  if e.move == 'drift' then
    local wob = math.sin(e.t*1.7 + e.phase)*1.4 + math.sin(e.t*0.6 + e.phase*2)*0.8
    local a = math.angle(e.vx, e.vy) + wob*dt
    e.vx, e.vy = math.cos(a)*e.speed, math.sin(a)*e.speed
  elseif e.move == 'dart' then
    e.wait = e.wait - dt
    if e.wait <= 0 then
      local a = rf(0, math.pi*2)
      local burst = rf(260, 420)
      e.vx, e.vy = math.cos(a)*burst, math.sin(a)*burst
      e.wait = rf(0.7, 1.8)
      spring_pull(e.s, 'scale', 0.45)
    end
    e.vx, e.vy = e.vx*(1 - math.min(1, 6*dt)), e.vy*(1 - math.min(1, 6*dt))
  elseif e.move == 'orbit' then
    e.ox, e.oy = e.ox + e.ovx*dt, e.oy + e.ovy*dt
    if e.ox < 30 or e.ox > width - 30 then e.ovx = -e.ovx end
    if e.oy < 30 or e.oy > height - 30 then e.ovy = -e.ovy end
    local tx = e.ox + math.cos(e.t*e.ospeed + e.phase)*e.orad
    local ty = e.oy + math.sin(e.t*e.ospeed + e.phase)*e.orad
    e.vx, e.vy = (tx - e.x)/dt*0.6, (ty - e.y)/dt*0.6
  end
  -- startle impulses decay back onto the base motion
  if e.kx then
    e.x, e.y = e.x + e.kx*dt, e.y + e.ky*dt
    e.kx, e.ky = e.kx*(1 - math.min(1, 5*dt)), e.ky*(1 - math.min(1, 5*dt))
    if math.abs(e.kx) + math.abs(e.ky) < 2 then e.kx, e.ky = nil, nil end
  end
  e.x, e.y = e.x + e.vx*dt, e.y + e.vy*dt
  -- walls: bounce with a squash, orbiters just get their anchor bounced above
  if e.move ~= 'orbit' then
    if e.x < e.r then e.x, e.vx = e.r, math.abs(e.vx) spring_pull(e.s, 'scale', 0.25)
    elseif e.x > width - e.r then e.x, e.vx = width - e.r, -math.abs(e.vx) spring_pull(e.s, 'scale', 0.25) end
    if e.y < e.r then e.y, e.vy = e.r, math.abs(e.vy) spring_pull(e.s, 'scale', 0.25)
    elseif e.y > height - e.r then e.y, e.vy = height - e.r, -math.abs(e.vy) spring_pull(e.s, 'scale', 0.25) end
  end
  e.angle = e.angle + e.spin*dt
  spring_update(e.s, dt)
  table.insert(e.trail, 1, {e.x, e.y})
  if #e.trail > TRAIL_LEN then table.remove(e.trail) end
end

function entity_draw(e)
  local sc = e.s.scale.x
  local speed = math.length(e.vx, e.vy)
  local stretch = math.clamp(speed/600, 0, 0.35)
  local ma = math.angle(e.vx, e.vy)
  -- trail
  for i, p in ipairs(e.trail) do
    local f = 1 - i/(#e.trail + 1)
    layer_circle(game, p[1], p[2], e.r*0.35*f*sc, rgba_alpha(e.color, 0.18*f))
  end
  layer_push(game, e.x, e.y, ma, sc*(1 + stretch), sc*(1 - stretch))
  layer_push(game, 0, 0, e.angle - ma, 1, 1)
  if e.kind == 'circle' then
    layer_circle(game, 0, 0, e.r, e.color)
    layer_circle(game, 0, 0, e.r*0.45, rgba_alpha(BG, 0.55))
  elseif e.kind == 'square' then
    layer_rectangle(game, -e.r, -e.r, e.r*2, e.r*2, e.color)
    layer_rectangle_line(game, -e.r*0.5, -e.r*0.5, e.r, e.r, rgba_alpha(BG, 0.55), 2)
  else
    local r = e.r*1.25
    layer_polygon(game, {0, -r, r*0.87, r*0.5, -r*0.87, r*0.5}, e.color)
    layer_circle(game, 0, r*0.1, r*0.28, rgba_alpha(BG, 0.55))
  end
  layer_pop(game)
  layer_pop(game)
end

-- the box -------------------------------------------------------------------
function box_update(dt)
  local mx, my = mouse_position()
  local px, py = box.x, box.y
  box.x = approach(box.x, mx, BOX_FOLLOW, dt)
  box.y = approach(box.y, my, BOX_FOLLOW, dt)
  local vx = (box.x - px)/math.max(dt, 0.0001)
  box.tilt = approach(box.tilt, math.clamp(vx/2600, -0.12, 0.12), 12, dt)
  box.flash = math.max(0, box.flash - dt*7)
  spring_update(box.s, dt)
end

function box_contains(e)
  local hw, hh = BOX_W/2, BOX_H/2
  return e.x > box.x - hw and e.x < box.x + hw and e.y > box.y - hh and e.y < box.y + hh
end

function box_edge_distance(e)
  local dx = math.max(math.abs(e.x - box.x) - BOX_W/2, 0)
  local dy = math.max(math.abs(e.y - box.y) - BOX_H/2, 0)
  return math.length(dx, dy)
end

function box_draw()
  local sc = box.s.scale.x
  local thick = box.s.thick.x
  local hw, hh = BOX_W/2, BOX_H/2
  layer_push(game, box.x, box.y, box.tilt, sc, sc)
  if box.flash > 0 then layer_rectangle(game, -hw, -hh, BOX_W, BOX_H, rgba_alpha(CREAM, box.flash*0.55)) end
  layer_rectangle(game, -hw, -hh, BOX_W, BOX_H, rgba_alpha(CREAM, 0.06))
  layer_rectangle_line(game, -hw, -hh, BOX_W, BOX_H, CREAM, thick)
  -- corner ticks
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
  for _, e in ipairs(entities) do
    if e.alive and box_contains(e) then caught[#caught + 1] = e end
  end
  local n = #caught
  box.flash = 1
  if n == 0 then
    -- a miss still answers the hand: a dull dip and a few grey motes
    spring_pull(box.s, 'scale', -0.06)
    for i = 1, 6 do particle_spawn(box.x + rf(-BOX_W/2, BOX_W/2), box.y + rf(-BOX_H/2, BOX_H/2), DIM, 40, 2) end
    return
  end
  spring_pull(box.s, 'scale', -0.16 - 0.03*n)
  spring_pull(box.s, 'thick', 3 + n)
  slow, slow_t = HITSTOP_SLOW, HITSTOP + 0.02*n
  trauma = math.min(1, trauma + 0.18 + 0.1*n)
  for _, e in ipairs(caught) do
    e.alive = false
    e.dying = 0
    spring_pull(e.s, 'scale', 0.9)
    for i = 1, 10 + ri(0, 8) do particle_spawn(e.x, e.y, e.color, 180 + 40*n, 4) end
    rings[#rings + 1] = {x = e.x, y = e.y, r = e.r, t = 0, color = e.color}
    respawn_queue[#respawn_queue + 1] = rf(1.2, 2.6)
  end
  rings[#rings + 1] = {x = box.x, y = box.y, r = BOX_H/2, t = 0, color = CREAM, box = true}
  -- neighbours flinch away from the box
  for _, e in ipairs(entities) do
    if e.alive then
      local d = box_edge_distance(e)
      if d < STARTLE_RADIUS then
        local a = math.angle_to_point(box.x, box.y, e.x, e.y)
        local k = (1 - d/STARTLE_RADIUS)*260
        e.kx, e.ky = (e.kx or 0) + math.cos(a)*k, (e.ky or 0) + math.sin(a)*k
        spring_pull(e.s, 'scale', 0.3)
      end
    end
  end
  total = total + n
  if n > best then best = n end
  spring_pull(total_s, 'scale', 0.25 + 0.1*n)
  popups[#popups + 1] = {x = box.x, y = box.y - BOX_H/2 - 8, t = 0, n = n, s = spring_new()}
  spring_add(popups[#popups].s, 'scale', 0.2, 8, 0.4)
  spring_set_target(popups[#popups].s, 'scale', 1)
end

function particle_spawn(x, y, col, speed, size)
  local a = rf(0, math.pi*2)
  local v = rf(speed*0.3, speed)
  particles[#particles + 1] = {
    x = x, y = y, vx = math.cos(a)*v, vy = math.sin(a)*v, life = 0, max = rf(0.35, 0.8),
    color = col, size = rf(size*0.5, size), square = random_bool(0.5, rng),
  }
end

-- update / draw -------------------------------------------------------------
function update(dt)
  sync_engine_globals()
  if input_pressed('quit') then engine_quit() end
  if input_pressed('reset') then world_reset() end

  -- hitstop: the world slows, the box does not
  if slow_t > 0 then slow_t = slow_t - dt if slow_t <= 0 then slow = HITSTOP_SLOW end
  else slow = approach(slow, 1, 14, dt) end
  local wdt = dt*slow

  box_update(dt)
  if input_pressed('capture') then capture() end

  for i = #entities, 1, -1 do
    local e = entities[i]
    if e.alive then entity_update(e, wdt)
    else
      e.dying = e.dying + dt
      spring_update(e.s, dt)
      if e.dying > 0.08 then spring_set_target(e.s, 'scale', 0) end
      if e.dying > 0.4 then table.remove(entities, i) end
    end
  end
  for i = #respawn_queue, 1, -1 do
    respawn_queue[i] = respawn_queue[i] - dt
    if respawn_queue[i] <= 0 then table.remove(respawn_queue, i) entity_spawn(false) end
  end
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.life = p.life + wdt
    p.x, p.y = p.x + p.vx*wdt, p.y + p.vy*wdt
    p.vx, p.vy = p.vx*(1 - math.min(1, 4*wdt)), p.vy*(1 - math.min(1, 4*wdt))
    if p.life > p.max then table.remove(particles, i) end
  end
  for i = #rings, 1, -1 do
    rings[i].t = rings[i].t + dt
    if rings[i].t > 0.45 then table.remove(rings, i) end
  end
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.t = p.t + dt
    spring_update(p.s, dt)
    if p.t > 0.9 then table.remove(popups, i) end
  end
  spring_update(total_s, dt)
  trauma = math.max(0, trauma - dt*2.2)
  process_destroy_queue()
end

function draw()
  local sh = trauma*trauma*7
  local ox, oy = rf(-sh, sh), rf(-sh, sh)
  layer_rectangle(game, 0, 0, width, height, BG)
  for gx = 0, width, 40 do for gy = 0, height, 40 do layer_circle(game, gx, gy, 1, GRID) end end
  layer_push(game, ox, oy, 0, 1, 1)
  for _, r in ipairs(rings) do
    local f = r.t/0.45
    local rad = r.r + (r.box and 90 or 40)*math.quad_out(f)
    layer_circle_line(game, r.x, r.y, rad, rgba_alpha(r.color, (1 - f)*0.9), (r.box and 3 or 2)*(1 - f) + 0.5)
  end
  for _, e in ipairs(entities) do entity_draw(e) end
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
