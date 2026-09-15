--[[
  boot.lua — ONE-TIME WORK. Layers, fonts, binds, and the state main.lua's
  definitions read and write. Never reloads.
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

world_reset()
