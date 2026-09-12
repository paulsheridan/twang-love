-- Input state with PICO-8 style button semantics.
--
-- Held state is polled once per rendered frame from the keyboard and all
-- connected gamepads. Press edges are re-evaluated once per simulation
-- step, so a press landing on a rendered frame without a step is never
-- swallowed; presses also latch, so taps shorter than one rendered frame
-- still register. A held button repeats every 4 steps after 15 held
-- steps, like the PICO-8's btnp.

local Input = {}
Input.__index = Input

local BUTTONS = { "left", "right", "up", "down", "aim", "jump", "swap" }

local KEY_MAP = {
  left = "left", right = "right", up = "up", down = "down",
  z = "aim", x = "jump", c = "swap",
}

-- SDL gamepad layout: dpad/left stick moves, A/B jump, right bumper or
-- right trigger aims, X swaps arrow type.
local GAMEPAD_MAP = {
  dpleft = "left", dpright = "right", dpup = "up", dpdown = "down",
  a = "jump", b = "jump",
  rightshoulder = "aim", x = "swap",
}

function Input.new()
  local self = setmetatable({}, Input)
  self.held = {}
  self.hold_steps = {}
  self.edge = {}
  self.latched = {}
  for _, button in ipairs(BUTTONS) do
    self.held[button] = false
    self.hold_steps[button] = 0
    self.edge[button] = false
  end
  return self
end

-- Samples keyboard and gamepads; called once per rendered frame.
function Input:poll()
  local keys = {}
  for key, button in pairs(KEY_MAP) do
    keys[button] = love.keyboard.isDown(key)
  end
  local pad, dpad = self:poll_gamepads()
  self.held.left = keys.left or pad.left or false
  self.held.right = keys.right or pad.right or false
  self.held.up = keys.up or dpad.up or false
  self.held.down = keys.down or dpad.down or false
  self.held.aim = keys.aim or pad.aim or false
  self.held.jump = keys.jump or pad.jump or false
  self.held.swap = keys.swap or pad.swap or false
end

function Input:poll_gamepads()
  local pad, dpad = {}, {}
  for _, joystick in ipairs(love.joystick.getJoysticks()) do
    if joystick:isGamepad() then
      dpad.left = dpad.left or joystick:isGamepadDown("dpleft") or false
      dpad.right = dpad.right or joystick:isGamepadDown("dpright") or false
      dpad.up = dpad.up or joystick:isGamepadDown("dpup") or false
      dpad.down = dpad.down or joystick:isGamepadDown("dpdown") or false
      local x = joystick:getGamepadAxis("leftx") or 0
      local y = joystick:getGamepadAxis("lefty") or 0
      pad.left = pad.left or x < -0.5
      pad.right = pad.right or x > 0.5
      pad.up = pad.up or y < -0.5
      pad.down = pad.down or y > 0.5
      if joystick:isGamepadDown("rightshoulder") then pad.aim = true end
      local trigger = joystick:getGamepadAxis("triggerright")
      if trigger and trigger > 0.4 then pad.aim = true end
      if joystick:isGamepadDown("a") or joystick:isGamepadDown("b") then pad.jump = true end
      if joystick:isGamepadDown("x") then pad.swap = true end
    else
      -- Raw-fallback controllers: buttons 14-17 act as a dpad.
      if joystick:isDown(14) then pad.left = true; dpad.left = true end
      if joystick:isDown(15) then pad.right = true; dpad.right = true end
      if joystick:isDown(16) then pad.up = true; dpad.up = true end
      if joystick:isDown(17) then pad.down = true; dpad.down = true end
      if joystick:isDown(10) or joystick:isDown(11) then pad.aim = true end
      if joystick:isDown(12) or joystick:isDown(13) then pad.jump = true end
      if joystick:isDown(18) then pad.swap = true end
    end
  end
  return pad, dpad
end

-- Re-evaluates press edges; call once at the top of each simulation
-- step. Latched presses are consumed here.
function Input:step()
  for _, button in ipairs(BUTTONS) do
    self.hold_steps[button] = self.held[button]
      and self.hold_steps[button] + 1 or 0
    self.edge[button] = (self.held[button] and self.hold_steps[button] == 1)
      or (self.hold_steps[button] >= 16 and (self.hold_steps[button] - 16) % 4 == 0)
      or self.latched[button] or false
    self.latched[button] = false
  end
end

-- True while `button` is held.
function Input:down(button)
  return self.held[button]
end

-- True on the press step of `button` (or on a repeat).
function Input:pressed(button)
  return self.edge[button]
end

-- Latches a keyboard press.
function Input:latch_key(key, isrepeat)
  if isrepeat then return end
  local button = KEY_MAP[key]
  if button then self.latched[button] = true end
end

-- Latches an SDL gamepad button press.
function Input:latch_gamepad(button)
  local button = GAMEPAD_MAP[button]
  if button then self.latched[button] = true end
end

-- Clears all input state; used when the window loses focus so no button
-- stays stuck down.
function Input:reset()
  for _, button in ipairs(BUTTONS) do
    self.held[button] = false
    self.hold_steps[button] = 0
    self.edge[button] = false
    self.latched[button] = false
  end
end

-- Left-stick direction of the first connected gamepad, if pushed past the
-- deadzone; used for analog bow aiming. Returns nil when idle.
function Input:aim_stick()
  for _, joystick in ipairs(love.joystick.getJoysticks()) do
    if joystick:isGamepad() then
      local x = joystick:getGamepadAxis("leftx") or 0
      local y = joystick:getGamepadAxis("lefty") or 0
      if x * x + y * y > 0.09 then  -- deadzone 0.3, squared
        return x, y
      end
    end
  end
  return nil
end

return Input
