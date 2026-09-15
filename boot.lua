--[[
  boot.lua — ONE-TIME WORK. Layers, fonts, binds, physics, and the state
  main.lua's definitions read and write. Never reloads.
]]

game = layer_new('game')
ui = layer_new('ui')

font_register('big', 'assets/monogram.ttf', 72, 'rough')
font_register('mid', 'assets/monogram.ttf', 40, 'rough')
font_register('small', 'assets/monogram.ttf', 22, 'rough')

bind('capture', 'mouse:1')
bind('reset', 'key:r')
bind('quit', 'key:escape')

rng = random_create(os.time())

physics_init()
physics_set_gravity(0, 0)
physics_register_tag('unit')
physics_register_tag('wall')
physics_enable_collision('unit', 'unit')
physics_enable_collision('unit', 'wall')

world_reset()
