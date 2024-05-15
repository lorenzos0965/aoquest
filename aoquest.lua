-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = "tm1jYBC0F2gTZ0EuUQKq5q_esxITDFkAG6QEpLbpI9I"
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end
-- Determines proximity between two points.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Evaluates if it's beneficial to attack or better to move to a safer position.
function shouldAttack(player, state, energyThreshold)
    -- Consider attacking if the player has more energy than the opponent and above the threshold.
    return player.energy > energyThreshold and player.energy > state.energy
end

-- Determines the safest direction to move away from an attacker.
function findSafeDirection(player, attacker)
    local directions = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local safestDirection = "Up" -- Default direction
    local maxDistance = 0

    for _, direction in ipairs(directions) do
        local dx, dy = unpack(directionMap[direction])
        local new_x, new_y = player.x + dx, player.y + dy
        local distance = (new_x - attacker.x)^2 + (new_y - attacker.y)^2
        if distance > maxDistance then
            maxDistance = distance
            safestDirection = direction
        end
    end

    return safestDirection
end

-- Strategically decides on the next move based on proximity, energy, and health.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local energyThreshold = 20 -- Set a threshold for when to consider attacking.

  for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 3) then
          if shouldAttack(player, state, energyThreshold) then
              targetInRange = true
              break
          end
      end
  end

  if targetInRange then
    print("Player in range and conditions favorable. Attacking.")
    ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy)})
  elseif player.health < 50 then
    print("Low health detected. Seeking health boost.")
    -- Logic to seek health boost or avoid combat.
    local safeDirection = findSafeDirection(player, attacker) -- Assuming 'attacker' is known.
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = safeDirection})
  else
    print("No player in range or conditions not favorable. Moving strategically.")
    -- Logic for strategic movement, considering the positions of other players.
    local safeDirection = findSafeDirection(player, attacker) -- Assuming 'attacker' is known.
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = safeDirection})
  end
end

-- Add a handler to react to being attacked.
Handlers.add(
  "ReactToAttack",
  Handlers.utils.hasMatchingTag("Action", "PlayerAttacked"),
  function (msg)
    if msg.Target == ao.id then
      print("Under attack! Taking evasive action.")
      local attacker = -- Logic to identify the attacker based on the message.
      local safeDirection = findSafeDirection(LatestGameState.Players[ao.id], attacker)
      ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = safeDirection})
    end
  end
)

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local player = LatestGameState.Players[ao.id]
      
      -- Check if player's energy is available and sufficient.
      if player.energy == nil then
        print("Unable to read energy. Skipping attack.")
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif player.energy <= 0 then
        print("Player has insufficient energy. Skipping attack.")
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        -- Return attack with all available energy.
        print("Returning attack with available energy.")
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy)})
      end
      
      InAction = false
      -- Signal the game process that the bot is ready for the next tick.
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)




