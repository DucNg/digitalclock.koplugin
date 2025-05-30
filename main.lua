local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")
local C_ = _.pgettext
local CenterContainer = require("ui/widget/container/centercontainer")
local datetime = require("frontend/datetime")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local Input = Device.input
local InputContainer = require("ui/widget/container/inputcontainer")
local logger = require("logger")
local PluginShare = require("pluginshare")
local Screen = Device.screen
local T = require("ffi/util").template
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local PLUGIN_ROOT = "plugins/digitalclock.koplugin/"

local DigitalClock = InputContainer:new{
    name = "DigitalClock",
    is_doc_only = false,
    dimen = Screen:getSize(),
}

function DigitalClock:onDispatcherRegisterActions()
    Dispatcher:registerAction("digital_clock", {category="none", event="ShowDigitalClock", title=_("Digital clock"), general=true,})
end

function DigitalClock:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)

    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end
end

function DigitalClock:_getDateString()
    local wday  = os.date("%a")
    local month = os.date("%B")
    local day   = os.date("%d")
    local year  = os.date("%Y")

    -- @translators Use the following placeholders in the desired order: %1 name of day, %2 name of month, %3 day, %4 year
    return T(C_("Date string", "%1 %2 %3 %4"),
        datetime.shortDayOfWeekToLongTranslation[wday], datetime.longMonthTranslation[month], day, year)
end

function DigitalClock:_getFileName()
    local supported_files = {"png", "svg", "jpg", "jpeg"}

    for _, extension in ipairs(supported_files) do
        local filename = PLUGIN_ROOT .. "image." .. extension

        logger.dbg("trying to open " .. filename)

        local f=io.open(filename,"r")
        if f~=nil then io.close(f)
            return filename
        end
    end

    return "resources/koreader.svg"
end

function DigitalClock:_pauseAutoSuspend()
    if Device:isCervantes() or Device:isKobo() then
        PluginShare.pause_auto_suspend = true
    elseif Device:isKindle() then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1")
    else
        logger.warn("pause suspend not supported on this device")
    end
end

function DigitalClock:_startAutoSuspend()
    if Device:isCervantes() or Device:isKobo() then
        PluginShare.pause_auto_suspend = false
    elseif Device:isKindle() then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
    else
        logger.warn("pause suspend not supported on this device")
    end
end

function DigitalClock:_getNextDateRefreshInSeconds()
    return (24 - tonumber(os.date("%H"))) * 3600
end

function DigitalClock:addToMainMenu(menu_items)
    menu_items.digital_clock = {
        text = _("Digital clock"),
        sorting_hint = "more_tools",
        callback = function()
            DigitalClock:showClock()
        end
    }
end

function DigitalClock:showClock()
    logger.dbg("Showing clock")

    self.time_widget = TextWidget:new{
        text = datetime.secondsToHour(os.time()),
        face = Font:getFace("cfont", 170)
    }

    self.separator = VerticalSpan:new{width = 130}

    self.date_widget = TextWidget:new{
        text = self:_getDateString(),
        face = Font:getFace("cfont", 40)
    }

    self.image_widget = ImageWidget:new{
        file = DigitalClock:_getFileName(),
        alpha = true
    }

    self.vertical_container = VerticalGroup:new{
        self.time_widget,
        self.date_widget,
        self.separator,
        self.image_widget
    }

    self.centered_container = CenterContainer:new{
        self.vertical_container,
        dimen = self.dimen
    }

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        self.centered_container
    }

    local time_widget_height = self.time_widget:getSize().h
    local date_widget_height = self.date_widget:getSize().h

    self.time_dimen = Geom:new{
        x = 0,
        y = 100,
        w = self.dimen.w,
        h = time_widget_height,
    }

    self.date_dimen = Geom:new{
        x = 0,
        y = 100 + time_widget_height,
        w = self.dimen.w,
        h = date_widget_height,
    }

    self.powerd = Device:getPowerDevice()

    UIManager:show(self, "full")

    self:_pauseAutoSuspend()
    self:setupAutoRefreshTime()
end

function DigitalClock:setupAutoRefreshTime()
    -- Setup refresh functions
    self.autoRefreshTime = function()
        -- Update clock
        logger.dbg("updating clock...", os.time())
        self.time_widget:setText(datetime.secondsToHour(os.time()))
        self.vertical_container:free()

        UIManager:setDirty(self, "partial", self.time_dimen)

        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
    end

    self.autoRefreshDate = function()
        -- Update date
        logger.dbg("updating date...")
        self.date_widget:setText(self:_getDateString())
        self.vertical_container:free()

        UIManager:setDirty(self, "partial", self.date_dimen)

        UIManager:scheduleIn(self:_getNextDateRefreshInSeconds(), self.autoRefreshDate)
    end

    self.autoCheckBatteryLevel = function()
        -- Check battery level
        logger.dbg("checking battery level...")

        if self.bat_info_msg then
            self.bat_info_msg:onTapClose()
        end

        if Device:hasBattery() then
            local main_batt_lvl = self.powerd:getCapacity()

            if Device:hasAuxBattery() and self.powerd:isAuxBatteryConnected() then
                local aux_batt_lvl = self.powerd:getAuxCapacity()
                is_charging = self.powerd:isAuxCharging()

                -- Sum both batteries for the actual text
                batt_lvl = (main_batt_lvl + aux_batt_lvl) / 2
            else
                is_charging = self.powerd:isCharging()
                batt_lvl = main_batt_lvl
            end

            if not is_charging and batt_lvl < 20 then
                self.bat_info_msg = InfoMessage:new{
                    text = T("Please recharge your device. Battery level: %1%", batt_lvl)
                }
                UIManager:show(self.bat_info_msg)
            end

            UIManager:scheduleIn(2 * 3600, self.autoCheckBatteryLevel)
        end
    end

    -- Unschedule refresh functions
    self.onCloseWidget = function()
        UIManager:unschedule(self.autoRefreshTime)
        UIManager:unschedule(self.autoRefreshDate)
        UIManager:unschedule(self.autoCheckBatteryLevel)
    end
    self.onSuspend = function()
        UIManager:unschedule(self.autoRefreshTime)
        UIManager:unschedule(self.autoRefreshDate)
        UIManager:unschedule(self.autoCheckBatteryLevel)
    end
    self.onResume = function()
        self.autoRefreshTime()
        self.autoRefreshDate()
        self.autoCheckBatteryLevel()
    end

    -- Schedule run refresh functions
    -- Refresh time every minute
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
    -- Refresh date every day
    UIManager:scheduleIn(self:_getNextDateRefreshInSeconds(), self.autoRefreshDate)
    -- Check battery level every 2h
    UIManager:scheduleIn(2 * 3600, self.autoCheckBatteryLevel)
end


function DigitalClock:onTapClose()
    self:_startAutoSuspend()
    UIManager:close(self)
end
DigitalClock.onAnyKeyPressed = DigitalClock.onTapClose

return DigitalClock
