local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local Json = require("json")
local Math = require("optmath")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local QUEUE_KEY = "blesync_queue"
local PAGES_KEY = "blesync_sync_every_pages"

-- An ATT value is capped at 512 bytes: book metadata is cut so the payload stays under it.
local function clip(s, n)
    if not s or #s <= n then return s or "" end
    return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", ""))
end

local BLESync = WidgetContainer:extend{
    name = "blesync",
    is_doc_only = true,
}

function BLESync:init()
    -- Same id as kosync/cwasync, so CWA sees one device whichever path the progress takes.
    self.device_id = G_reader_settings:readSetting("device_id")
    self.pages_since_sync = 0
    self.watch_task = function() self:watchSync() end
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

-- Makes "Sync now" assignable to a gesture, like kosync's push/pull.
function BLESync:onDispatcherRegisterActions()
    Dispatcher:registerAction("blesync_sync_now", { category = "none", event = "BLESyncNow", title = _("BLE sync: sync now"), reader = true })
end

function BLESync:syncEveryPages()
    return G_reader_settings:readSetting(PAGES_KEY, 20)
end

function BLESync:onBLESyncNow()
    self:captureProgress()
    if self:sync(true) then
        UIManager:show(InfoMessage:new{ text = _("Sync started (about 1 min)."), timeout = 3 })
    else
        UIManager:show(InfoMessage:new{ text = _("Nothing to sync."), timeout = 3 })
    end
    return true
end

-- blesync.sh runs detached: poll for the status it writes when done.
-- Automatic syncs only report failures, so reading isn't interrupted every N pages.
function BLESync:watchSync()
    local path = self.path .. "/status.txt"
    local f = io.open(path, "r")
    if not f then
        self.watch_tries = self.watch_tries + 1
        if self.watch_tries < 36 then
            UIManager:scheduleIn(5, self.watch_task)
        end
        return
    end
    local status = f:read("*l")
    f:close()
    os.remove(path)
    self:applyResults()
    if status == "OK" then
        if self.watch_notify then
            UIManager:show(InfoMessage:new{ text = "Synchronisé à " .. os.date("%H:%M"), timeout = 3 })
        end
    else
        UIManager:show(InfoMessage:new{ text = "iPhone introuvable : progression gardée, nouvel essai plus tard.", timeout = 5 })
    end
end

-- Same digest as cwasync, otherwise CWA would not match the book.
function BLESync:getDocumentDigest()
    local digest = self.ui.doc_settings:readSetting("partial_md5_checksum")
    if digest and digest ~= "" then
        return digest
    end
    local ok, result = pcall(util.partialMD5, self.ui.document.file)
    if ok and result and result ~= "" then
        return result
    end
end

function BLESync:captureProgress()
    local digest = self:getDocumentDigest()
    if not digest then
        logger.warn("BLESync: no digest for", self.ui.document.file)
        return
    end
    local reader = self.ui.document.info.has_pages and self.ui.paging or self.ui.rolling
    local props = self.ui.doc_props or {}
    local queue = G_reader_settings:readSetting(QUEUE_KEY, {})
    -- Keyed by digest: only the latest progress per book is kept.
    queue[digest] = {
        document = digest,
        progress = reader:getLastProgress(),
        percentage = Math.roundPercent(reader:getLastPercent()),
        device = Device.model,
        device_id = self.device_id,
        captured_at = os.time(),
        title = clip(props.display_title or props.title or self.ui.document.file:match("([^/]+)$"), 80),
        author = clip(((props.authors or ""):gsub("\n", ", ")), 50),
    }
    G_reader_settings:saveSetting(QUEUE_KEY, queue)
end

-- Drops entries the script delivered, unless they were captured again since.
function BLESync:applyResults()
    local path = self.path .. "/result.txt"
    local f = io.open(path, "r")
    if not f then return end
    local queue = G_reader_settings:readSetting(QUEUE_KEY, {})
    for line in f:lines() do
        local doc, captured_at = line:match("^OK (%S+) (%d+)")
        if doc and queue[doc] and queue[doc].captured_at == tonumber(captured_at) then
            queue[doc] = nil
        end
    end
    f:close()
    os.remove(path)
    G_reader_settings:saveSetting(QUEUE_KEY, queue)
end

function BLESync:sync(notify_success)
    self.pages_since_sync = 0
    self:applyResults()
    local lines = {}
    for _digest, e in pairs(G_reader_settings:readSetting(QUEUE_KEY, {})) do
        -- Fixed key order: blesync.sh appends sent_at and parses document/captured_at with sed.
        table.insert(lines, string.format('{"v":1,"document":%s,"progress":%s,"percentage":%s,"device":%s,"device_id":%s,"title":%s,"author":%s,"captured_at":%d}',
            Json.encode(e.document), Json.encode(e.progress), tostring(e.percentage),
            Json.encode(e.device), Json.encode(e.device_id or ""), Json.encode(e.title or ""), Json.encode(e.author or ""), e.captured_at))
    end
    G_reader_settings:flush()
    if #lines == 0 then return false end
    local f = io.open(self.path .. "/outbox.jsonl", "w")
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    os.remove(self.path .. "/status.txt")
    os.execute(string.format("sh %q %q >/dev/null 2>&1 &", self.path .. "/blesync.sh", self.path))
    UIManager:unschedule(self.watch_task)
    -- A manual sync keeps its success message even if an automatic one fires meanwhile.
    self.watch_notify = notify_success or (self.watch_tries ~= nil and self.watch_tries < 36 and self.watch_notify)
    self.watch_tries = 0
    UIManager:scheduleIn(5, self.watch_task)
    return true
end

function BLESync:onPageUpdate()
    self:captureProgress()
    self.pages_since_sync = self.pages_since_sync + 1
    local every = self:syncEveryPages()
    -- 0 disables page-based sync: only close, resume and manual sync remain.
    if every > 0 and self.pages_since_sync >= every then
        self:sync()
    end
end

function BLESync:onCloseDocument()
    self:captureProgress()
    self:sync()
end

-- Nothing survives sleep on this device: only make sure the queue is on disk.
function BLESync:onSuspend()
    self:captureProgress()
    G_reader_settings:flush()
end

function BLESync:onResume()
    UIManager:scheduleIn(5, function() self:sync() end)
end

function BLESync:addToMainMenu(menu_items)
    menu_items.blesync = {
        text = _("BLE sync"),
        sub_item_table = {
            {
                text = _("Sync now"),
                callback = function() self:onBLESyncNow() end,
            },
            {
                text_func = function()
                    local every = self:syncEveryPages()
                    return every > 0 and string.format(_("Sync every %d pages"), every) or _("Sync every N pages: off")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
                        title_text = _("Sync every N pages"),
                        info_text = _("0 = only on close, wake-up and manual sync."),
                        value = self:syncEveryPages(),
                        value_min = 0,
                        value_max = 500,
                        value_step = 5,
                        value_hold_step = 50,
                        default_value = 20,
                        callback = function(spin)
                            G_reader_settings:saveSetting(PAGES_KEY, spin.value)
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
            },
            {
                text = _("Show queue and last sync"),
                callback = function()
                    self:captureProgress()
                    self:applyResults()
                    local lines = {}
                    for _digest, e in pairs(G_reader_settings:readSetting(QUEUE_KEY, {})) do
                        table.insert(lines, string.format("%s\n%.2f%% · %s\n%s",
                            e.title or "?", e.percentage * 100, os.date("%d/%m %H:%M", e.captured_at), e.document))
                    end
                    local log = io.open(self.path .. "/sync.log", "r")
                    local last = log and log:read("*a") or _("never")
                    if log then log:close() end
                    UIManager:show(InfoMessage:new{
                        text = (#lines > 0 and table.concat(lines, "\n\n") or _("Queue is empty."))
                            .. "\n\n— " .. _("Last sync") .. " —\n" .. last,
                    })
                end,
            },
        },
    }
end

return BLESync
