-- /kernel.lua
local serverUrl = "ws://atm10-wss.ndk.center/cc"  -- IP de tu Nest
local computerId = os.getComputerID()

local function connect()
  print("Conectando a "..serverUrl)
  local ws, err = http.websocket(serverUrl)
  if not ws then
    print("Error al conectar: "..tostring(err))
    sleep(3)
    return nil
  end

  -- Handshake inicial
  ws.send(textutils.serializeJSON({
    type = "hello",
    computerId = computerId,
  }))

  return ws
end

local ws = nil

-- Entorno seguro donde se ejecutan las llamadas
local env = {
  _G          = _G,
  os          = os,
  turtle      = turtle,
  redstone    = redstone,
  peripheral  = peripheral,
  gps         = gps,
  http        = http,
  -- añade lo que quieras exponer
  print       = print,
}

-- Si quieres permitir un "eval" remoto, puedes montar un módulo kernel
env.kernel = {}

function env.kernel.eval(code)
  local fn, err = load(code, "remote_eval", "t", env)
  if not fn then
    return nil, "load error: "..tostring(err)
  end

  local ok, res = pcall(fn)
  if not ok then
    return nil, "runtime error: "..tostring(res)
  end
  return res
end

local function handleCall(msg)
  local requestId = msg.requestId
  local lib = msg.lib
  local fnName = msg.fn
  local args = msg.args or {}

  local result, err

  local target = env[lib] or _G[lib]
  if not target then
    err = "lib no encontrada: "..tostring(lib)
  else
    local fn = target[fnName]
    if type(fn) ~= "function" then
      err = "fn no encontrada: "..tostring(lib).."."..tostring(fnName)
    else
      local returns = { pcall(fn, table.unpack(args)) }
      local okcall = table.remove(returns, 1)
      if not okcall then
        err = returns[1]
      else
        -- If the function returned multiple values, send them as an array.
        -- If only one value, send it directly to keep backward compatibility.
        if #returns > 1 then
          result = returns
        else
          result = returns[1]
        end
      end
    end
  end

  local reply = {
    type = "result",
    requestId = requestId,
  }

  if err then
    reply.ok = false
    reply.error = tostring(err)
  else
    reply.ok = true
    reply.result = result
  end

  ws.send(textutils.serializeJSON(reply))
end

local function run()
  while true do
    if not ws then
      ws = connect()
    end
    if ws then
      local event, url, msg = os.pullEvent()
      if event == "websocket_message" then
        local ok, data = pcall(textutils.unserializeJSON, msg)
        if ok and type(data) == "table" then
          if data.type == "call" then
            handleCall(data)
          else
            print("Mensaje desconocido:", data.type)
          end
        else
          print("Error parseando JSON recibido")
        end
      elseif event == "websocket_closed" then
        print("WebSocket cerrado, reconectando...")
        ws.close()
        ws = nil
        sleep(2)
      end
    else
      -- sin conexión, intenta cada cierto tiempo
      sleep(3)
    end
  end
end

run()
