
local HTTPPORT = 8089

projectJson = "{}"
gDbgTimer = 0
gCmd = ""
args = { title = "none", album = "none", artist = "none" }

function dbg(strDebugText)
   if (g_dbgprint) then print(strDebugText) end
   if (g_dbglog or g_dbgprint) then
      C4:DebugLog("\r\nWeb Event: " .. strDebugText)
   end
end

function OnDriverDestroyed()
   if (gDbgTimer ~= 0) then gDbgTimer = C4:KillTimer(gDbgTimer) end
   if (gInitTimer ~= nil and gInitTimer ~= 0) then gInitTimer = C4:KillTimer(gInitTimer) end
   C4:DestroyServer()
end

function OnPropertyChanged(strProperty)
   local prop = Properties[strProperty]

   if (strProperty == "Debug Mode") then
      if (gDbgTimer > 0) then gDbgTimer = C4:KillTimer(gDbgTimer) end
      g_dbgprint, g_dbglog = (prop:find("Print") ~= nil), (prop:find("Log") ~= nil)
      if (prop == "Off") then
         return
      end
      gDbgTimer = C4:AddTimer(300, "MINUTES")
      dbg("Debug Timer set to 300 Minutes")
      return
   end
end

function ExecuteCommand(strCommand, tParams)
   tParams = tParams or {}
   dbg("ExecuteCommand: " .. strCommand)
   for k,v in pairs(tParams) do dbg("" .. k .. ":" .. v) end
end

function OnTimerExpired(idTimer)
   if (idTimer == gDbgTimer) then
      dbg("Turning Debug Mode Off (timer expired)")
      C4:UpdateProperty("Debug Mode", "Off")
      OnPropertyChanged("Debug Mode")
      gDbgTimer = C4:KillTimer(gDbgTimer)
   end
   if (idTimer == gInitTimer) then
      MyDriverInit()
      gInitTimer = C4:KillTimer(gInitTimer)
   end
end

function MyDriverInit()
   if (gInitialized ~= nil) then return end
   gInitialized = true
   dbg("MyDriverInit()")
   C4:CreateServer(HTTPPORT)
   C4:AddVariable("COMMAND", "", "STRING")
   dbg("Initialization Complete.")
end

function OnDriverLateInit()
   RefreshProjectData()
   MyDriverInit()
end

function RefreshProjectData()
   local function get(data,name)
      return data:match("<"..name..">(.-)</"..name..">")
   end

   local projectInfo = C4:GetProjectItems()
   projectInfo = get(projectInfo,"itemdata")
   if (projectInfo == nil) then
      projectJson = "{}"
      return
   end
   projectInfo = "<itemdata>"..projectInfo.."</itemdata>"
   projectInfo = C4:ParseXml(projectInfo)

   local project = {}
   if (projectInfo and projectInfo["ChildNodes"]) then
      for i,v in pairs(projectInfo["ChildNodes"]) do
         project[v["Name"]] = v.Value
      end
   end
   projectJson = C4:JsonEncode(project)
end

function ParseStatus()
   local _, _, url = string.find(gRecvBuf, "GET /(.*) HTTP")
   url = url or ""
   gCmd = url
   if (string.len(url) > 0) then
      dbg("GET URL: [" .. url .. "]")
      C4:SetVariable("COMMAND", url)
      C4:FireEvent("Command Received")
   else
      dbg("No Command Received.")
      gCmd = "None"
   end
end

function GetHeaders(ContentType,msg)
   return "HTTP/1.1 200 OK\r\nContent-Length: " .. msg:len() .. "\r\nContent-Type: "..ContentType.."\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n\r\n"
end

function SendResponse(nHandle, contentType, msg)
   local headers = GetHeaders(contentType, msg)
   C4:ServerSend(nHandle, headers .. msg)
   C4:ServerCloseClient(nHandle)
end

function GetWebFile(url, content_type, nHandle)
   local fullUrl = C4:GetControllerNetworkAddress() .. "/c4z/Metadata_Webserver/www/" .. url
   dbg("GetWebFile URL: " .. fullUrl)
   C4:urlGet(fullUrl, {}, false,
      function(ticketId, strData, responseCode, tHeaders, strError)
         if (strError == nil and strData ~= nil) then
            local headers = GetHeaders(content_type, strData)
            C4:ServerSend(nHandle, headers .. strData)
            C4:ServerCloseClient(nHandle)
         else
            local err = "GetWebFile failed for " .. url .. ": " .. tostring(strError)
            dbg(err)
            SendResponse(nHandle, "text/plain", err)
         end
      end
   )
end

function GetProperty(name, defaultValue)
   local value = Properties[name]
   if (value == nil or value == "") then return defaultValue end
   return value
end

function NormalizeProfile(profile)
   local map = {
      ["Auto"] = "auto",
      ["Portrait Small"] = "portrait-small",
      ["Portrait Large"] = "portrait-large",
      ["Landscape Small"] = "landscape-small",
      ["Landscape Large"] = "landscape-large"
   }
   return map[profile] or "auto"
end

function GetRoomProfile(roomId)
   for i = 1, 8 do
      local enabled = GetProperty("Override " .. i .. " Enabled", "False")
      local id = GetProperty("Override " .. i .. " Room ID", "")
      local profile = GetProperty("Override " .. i .. " Profile", "Auto")
      if enabled == "True" and tostring(id) == tostring(roomId) then
         return profile
      end
   end
   return GetProperty("Default Profile", "Auto")
end

function GetConfigForRoom(roomId)
   local cfg = {}
   cfg["profile"] = NormalizeProfile(GetRoomProfile(roomId))
   cfg["burnInMode"] = GetProperty("Burn-In Mode", "Clock Corners")
   cfg["noMediaLayout"] = GetProperty("No-Media Layout", "Stacked")
   cfg["showWeather"] = (GetProperty("Show Weather", "Yes") == "Yes")
   cfg["weatherSource"] = GetProperty("Weather Source", "Weather.gov")
   cfg["roomId"] = tostring(roomId or "")
   return cfg
end

function GetRoomMedia(roomId)
  local args = {}
  local deviceIconUrl = ""
  local roomMediaXml = C4:GetVariable(tonumber(roomId),1031)
  local roomMedia = C4:ParseXml(roomMediaXml)
  if (roomMedia) then
     for i,v in pairs(roomMedia.ChildNodes) do
        args[v["Name"]] = v.Value or ""
     end

     local deviceInfoXml = C4:GetDeviceData(tonumber(args["deviceid"]))
     deviceInfoXml = "<data>"..deviceInfoXml.."</data>"
     local deviceInfo = C4:ParseXml(deviceInfoXml)
     local ip = C4:GetControllerNetworkAddress()

     for i1,v1 in pairs(deviceInfo.ChildNodes) do
      if(v1.Name == "capabilities") then
        for i2,v2 in pairs(deviceInfo.ChildNodes[i1].ChildNodes) do
           if (v2.Name == "navigator_display_option") then
             for i3,v3 in pairs(deviceInfo.ChildNodes[i1].ChildNodes[i2].ChildNodes) do
              if (v3.Name == "display_icons") then
                deviceIconUrl = deviceInfo.ChildNodes[i1].ChildNodes[i2].ChildNodes[i3].ChildNodes[1].Value
              end
             end
           end
        end
      end
     end

     args["devicename"] = C4:ListGetDeviceName(args["deviceid"]) or ""

     if (args["img"] == nil) then
      local prefix,path = deviceIconUrl:match("(.+)://(.+)")
      if path ~= nil then
         local basePath,fileName = path:match("(.+)/(.+)")
         local imgUrl = "http://"..ip.."/"..basePath.."/experience_1024.png"
         local imgUrlFallback = "http://"..ip.."/"..path
         args["img"] = imgUrl
         args["imgFallback"] = imgUrlFallback
      end
     else
      local imgUrl = C4:Base64Decode(args["img"])
      local prefix,path = imgUrl:match("(.+)://(.+)")
      if (prefix == "controller") then
        imgUrl = "http://"..ip.."/"..path
      end
      args["img"] = imgUrl
     end
  end
  return args
end

function SplitPath(path)
   local result = {}
   for token in string.gmatch(path, "[^/]+") do
      table.insert(result, token)
   end
   return result
end

function OnServerConnectionStatusChanged(nHandle, nPort, strStatus)
end

function OnServerDataIn(nHandle, strData)
   gRecvBuf = strData
   local ret, err = pcall(ParseStatus)
   if (ret ~= true) then
      local e = "Error Parsing return status: " .. err
      print(e)
      C4:ErrorLog(e)
      SendResponse(nHandle, "text/plain", e)
      gRecvBuf = ""
      return
   end
   gRecvBuf = ""

   local urlArgs = SplitPath(gCmd)

   if tonumber(gCmd) then
      GetWebFile("html/main.html", "text/html", nHandle)
   elseif (#urlArgs == 2 and urlArgs[2] == "json") then
      local roomId = urlArgs[1]
      SendResponse(nHandle, "application/json", C4:JsonEncode(GetRoomMedia(roomId)))
   elseif (#urlArgs == 2 and urlArgs[1] == "config") then
      local roomId = urlArgs[2]
      SendResponse(nHandle, "application/json", C4:JsonEncode(GetConfigForRoom(roomId)))
   elseif (gCmd == "project") then
      SendResponse(nHandle, "application/json", projectJson)
   elseif (urlArgs[1] == "png") then
      GetWebFile(gCmd, "image/png", nHandle)
   elseif (urlArgs[1] == "css") then
      GetWebFile(gCmd, "text/css", nHandle)
   elseif (urlArgs[1] == "js") then
      GetWebFile(gCmd, "application/javascript", nHandle)
   elseif (urlArgs[1] == "html") then
      GetWebFile(gCmd, "text/html", nHandle)
   else
      SendResponse(nHandle, "text/plain", "404")
   end
end

print("Driver Loaded..." .. os.date())
OnPropertyChanged("Debug Mode")
gInitTimer = C4:AddTimer(5, "SECONDS")
