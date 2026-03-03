diff --git a/HealerManaTracker.lua b/HealerManaTracker.lua
index be62eaadba69af82fa1fcd8a1586b6d52d1e8e4d..2279e22b2fae1325fa3da259d18ed374122e7749 100644
--- a/HealerManaTracker.lua
+++ b/HealerManaTracker.lua
@@ -461,73 +461,92 @@ local function createConfigPanel()
     local xSlider = createSlider(configPanel, "X position", 0, 2000, 1, function()
         return HMTDB.point.x
     end, function(v)
         HMTDB.point.x = v
         applyLayout()
     end, -380)
 
     local ySlider = createSlider(configPanel, "Y position", 0, 2000, 1, function()
         return HMTDB.point.y
     end, function(v)
         HMTDB.point.y = v
         applyLayout()
     end, -450)
 
     configPanel:SetScript("OnShow", function()
         syncDropdown()
         xSlider:SetValue(HMTDB.point.x)
         ySlider:SetValue(HMTDB.point.y)
     end)
 
     createClassColorButtons(configPanel)
 end
 
 SLASH_HMT1 = "/hmt"
 SLASH_HMT2 = "/healermana"
+
+local function printHelp()
+    print("HealerManaTracker commands:")
+    print("  /hmt - Open/close the settings window")
+    print("  /hmt unlock - Unlock tracker so you can drag it")
+    print("  /hmt lock - Lock tracker in place")
+    print("  /hmt help - Show this help text")
+end
+
 SlashCmdList.HMT = function(msg)
     msg = string.lower((msg or ""):gsub("^%s+", ""))
 
+    if msg == "help" or msg == "?" then
+        printHelp()
+        return
+    end
+
     if msg == "unlock" then
         HMTDB.unlocked = true
         applyLayout()
         print("HealerManaTracker: tracker unlocked.")
         return
     end
 
     if msg == "lock" then
         HMTDB.unlocked = false
         applyLayout()
         print("HealerManaTracker: tracker locked.")
         return
     end
 
     createConfigPanel()
     if configPanel:IsShown() then
         configPanel:Hide()
     else
         configPanel:Show()
     end
+
+    if msg ~= "" then
+        print(string.format("HealerManaTracker: unknown command '%s'.", msg))
+        printHelp()
+    end
 end
 
 frame:RegisterEvent("ADDON_LOADED")
 frame:RegisterEvent("PLAYER_ENTERING_WORLD")
 frame:RegisterEvent("GROUP_ROSTER_UPDATE")
 frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
 frame:RegisterEvent("UNIT_POWER_UPDATE")
 frame:RegisterEvent("UNIT_AURA")
 frame:RegisterEvent("UNIT_FLAGS")
 
 frame:SetScript("OnEvent", function(_, event, arg1)
     if event == "ADDON_LOADED" and arg1 == addonName then
         initDB()
         applyLayout()
         updateDisplay()
         return
     end
 
     if not HMTDB then
         return
     end
 
     if event == "UNIT_POWER_UPDATE" or event == "UNIT_AURA" or event == "UNIT_FLAGS" then
         if arg1 and not UnitInParty(arg1) and not UnitInRaid(arg1) and arg1 ~= "player" then
             return
