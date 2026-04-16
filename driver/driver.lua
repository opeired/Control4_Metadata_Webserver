
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
   cfg["showLogo"] = (GetProperty("Show Logo", "Yes") == "Yes")
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

     local ip = C4:GetControllerNetworkAddress()
     local iconDeviceId = tonumber(args["medSrcDev"]) or tonumber(args["deviceid"])
     local fallbackDeviceId = tonumber(args["deviceid"])

     local function extractText(node)
        if node == nil then return "" end
        if node.Value ~= nil then return node.Value end
        if node["Value"] ~= nil then return node["Value"] end
        return ""
     end

     local function findChildByName(node, childName)
        if node == nil or node.ChildNodes == nil then return nil end
        for _,child in pairs(node.ChildNodes) do
           if child.Name == childName then
              return child
           end
        end
        return nil
     end

     local function getAttr(node, attrName)
        if node == nil then return nil end
        if node[attrName] ~= nil then return node[attrName] end
        if node.Attributes ~= nil then
           if node.Attributes[attrName] ~= nil then return node.Attributes[attrName] end
           for _,a in pairs(node.Attributes) do
              if type(a) == "table" and (a.Name == attrName or a.name == attrName) then
                 return a.Value or a.value
              end
           end
        end
        return nil
     end

     local function controllerToHttp(url)
        if url == nil or url == "" then return "" end
        local prefix,path = url:match("(.+)://(.+)")
        if prefix == "controller" and path ~= nil then
           return "http://" .. ip .. "/" .. path
        end
        return url
     end

     local function pickBestIconFromGroup(iconGroupNode)
        if iconGroupNode == nil or iconGroupNode.ChildNodes == nil then return "" end
        local bestUrl = ""
        local bestWidth = -1
        for _,iconNode in pairs(iconGroupNode.ChildNodes) do
           if iconNode.Name == "Icon" then
              local width = tonumber(getAttr(iconNode, "width")) or 0
              local url = extractText(iconNode)
              if url ~= "" and width > bestWidth then
                 bestWidth = width
                 bestUrl = url
              end
           end
        end
        return controllerToHttp(bestUrl)
     end

     local function extractDisplayIconUrl(targetDeviceId)
        if (targetDeviceId == nil) then return "" end
        local ok, deviceInfoXml = pcall(C4.GetDeviceData, C4, targetDeviceId)
        if (not ok or deviceInfoXml == nil or deviceInfoXml == "") then return "" end

        dbg("==== ICON SOURCE XML START (" .. tostring(targetDeviceId) .. ") ====")
        dbg(deviceInfoXml)
        dbg("==== ICON SOURCE XML END (" .. tostring(targetDeviceId) .. ") ====")

        deviceInfoXml = "<data>"..deviceInfoXml.."</data>"
        local deviceInfo = C4:ParseXml(deviceInfoXml)
        if (deviceInfo == nil or deviceInfo.ChildNodes == nil) then return "" end

        -- First try Media Service UI icon groups
        local capabilities = findChildByName(deviceInfo, "capabilities")
        if capabilities ~= nil and capabilities.ChildNodes ~= nil then
           local uiNode = findChildByName(capabilities, "UI")
           if uiNode ~= nil then
              local iconGroupId = ""
              local deviceIconNode = findChildByName(uiNode, "DeviceIcon")
              local brandingIconNode = findChildByName(uiNode, "BrandingIcon")
              iconGroupId = extractText(deviceIconNode)
              if iconGroupId == "" then
                 iconGroupId = extractText(brandingIconNode)
              end

              local iconsNode = findChildByName(uiNode, "Icons")
              if iconsNode ~= nil and iconsNode.ChildNodes ~= nil and iconGroupId ~= "" then
                 for _,groupNode in pairs(iconsNode.ChildNodes) do
                    if groupNode.Name == "IconGroup" and tostring(getAttr(groupNode, "id") or "") == tostring(iconGroupId) then
                       local picked = pickBestIconFromGroup(groupNode)
                       if picked ~= "" then
                          return picked
                       end
                    end
                 end
              end
           end

           -- Fallback to older navigator_display_option/display_icons path
           local navNode = findChildByName(capabilities, "navigator_display_option")
           if navNode ~= nil and navNode.ChildNodes ~= nil then
              local displayIconsNode = findChildByName(navNode, "display_icons")
              if displayIconsNode ~= nil and displayIconsNode.ChildNodes ~= nil and displayIconsNode.ChildNodes[1] ~= nil then
                 local oldUrl = extractText(displayIconsNode.ChildNodes[1])
                 oldUrl = controllerToHttp(oldUrl)
                 if oldUrl ~= "" then
                    local prefix,path = oldUrl:match("(.+)://(.+)")
                    if prefix == nil then
                       return oldUrl
                    end
                 end
              end
           end
        end

        return ""
     end

     deviceIconUrl = extractDisplayIconUrl(iconDeviceId)
     if (deviceIconUrl == "" and fallbackDeviceId ~= iconDeviceId) then
        deviceIconUrl = extractDisplayIconUrl(fallbackDeviceId)
     end

     args["devicename"] = C4:ListGetDeviceName(args["deviceid"]) or ""
     args["medSrcDevName"] = C4:ListGetDeviceName(args["medSrcDev"]) or ""
     args["deviceicon"] = deviceIconUrl
     args["displayicon"] = deviceIconUrl

     if (args["img"] == nil) then
        if deviceIconUrl ~= "" then
           args["img"] = deviceIconUrl
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
