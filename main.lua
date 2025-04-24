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
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
    else
        logger.warn("pause suspend not supported on this device")
    end
end

function DigitalClock:_startAutoSuspend()
    if Device:isCervantes() or Device:isKobo() then
        PluginShare.pause_auto_suspend = false
    elseif Device:isKindle() then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1")
    else
        logger.warn("pause suspend not supported on this device")
    end
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
        face = Font:getFace("cfont", 100)
    }

    self.separator = VerticalSpan:new{width = 200}

    self.date_widget = TextWidget:new{
        text = self:_getDateString(),
        face = Font:getFace("cfont")
    }

    self.image_widget = ImageWidget:new{
        file = DigitalClock:_getFileName(),
        alpha = true
    }

    self.vertical_container = VerticalGroup:new{
        self.time_widget,
        self.date_widget,
        self.separator,
        self.separator2,
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

    UIManager:show(self, "full")

    self:_pauseAutoSuspend()
    self:setupAutoRefreshTime()
end

function DigitalClock:setupAutoRefreshTime()
    if not self.autoRefreshTime then
        self.autoRefreshTime = function()
            -- Update clock
            logger.dbg("updating clock...")

            self.time_widget.text = datetime.secondsToHour(os.time())
            UIManager:setDirty(self.timewidget, "ui")

            UIManager:scheduleIn(60 - tonumber(os.date("%S")), self.autoRefreshTime)
        end
    end
    self.onCloseWidget = function()
        UIManager:unschedule(self.autoRefreshTime)
    end
    self.onSuspend = function()
        UIManager:unschedule(self.autoRefreshTime)
    end
    self.onResume = function()
        self.autoRefreshTime()
    end
    UIManager:scheduleIn(60 - tonumber(os.date("%S")), self.autoRefreshTime)
end


function DigitalClock:onTapClose()
    self:_startAutoSuspend()
    UIManager:close(self)
end
DigitalClock.onAnyKeyPressed = DigitalClock.onTapClose

return DigitalClock
