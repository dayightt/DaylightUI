-- Gender, plus the Spanish adjustments that are not dictionary lines.
-- esES.lua fills L before modules copy strings such as L["Head"].
-- The character's sex is only known after entering the world. Chat
-- channel letters and bag-search aliases live in other addons, which
-- load after this core, so they are applied on PLAYER_LOGIN.

local _, DUI = ...
if DUI.LOCALE ~= "esES" and DUI.LOCALE ~= "esMX" then return end
local L = DUI.L

local GENDER = {
    ["Rested"] = { "Descansado", "Descansada" },
    ["Fully rested. Go spend it!"] = { "Totalmente descansado. ¡Ve a gastarlo!", "Totalmente descansada. ¡Ve a gastarlo!" },
    ["Ready when you are"] = { "Listo cuando tú lo estés", "Lista cuando tú lo estés" },
    ["%s away. Your character is getting stiff."] = {
        "%s ausente. Tu personaje se está poniendo rígido.",
        "%s ausente. Tu personaje se está poniendo rígida.",
    },
    ["DPS/Tank made calm for questing: your action bars and your own frame fade a while after a fight (back under the mouse, in a fight or when you're hurt), the damage meter starts folded (one click on the panel's tab brings it out), the minimap is a little smaller and the XP bar shows its percent. Nothing fades in dungeons, raids, battlegrounds or arenas (General > Appearance, Fade only in the open world). Choose it above to use it. If the profile you're on has moved action bars, offers to bring them along."] = {
        "DPS/Tanque sosegado para las misiones: tus barras de acción y tu propio marco se desvanecen un rato después de un combate (vuelven bajo el ratón, en combate o cuando estás herido), el medidor de daño empieza plegado (un clic en la pestaña del panel lo hace aparecer), el minimapa es un poco más pequeño y la barra de PE muestra su porcentaje. Nada se desvanece en mazmorras, bandas, campos de batalla o arenas (General > Apariencia, Desvanecer solo en mundo abierto). Elígelo arriba para usarlo. Si el perfil actual tiene barras de acción movidas, ofrece llevarlas consigo.",
        "DPS/Tanque sosegado para las misiones: tus barras de acción y tu propio marco se desvanecen un rato después de un combate (vuelven bajo el ratón, en combate o cuando estás herida), el medidor de daño empieza plegado (un clic en la pestaña del panel lo hace aparecer), el minimapa es un poco más pequeño y la barra de PE muestra su porcentaje. Nada se desvanece en mazmorras, bandas, campos de batalla o arenas (General > Apariencia, Desvanecer solo en mundo abierto). Elígelo arriba para usarlo. Si el perfil actual tiene barras de acción movidas, ofrece llevarlas consigo.",
    },
    ["DPS/Tank with your party and raid as square tiles under you (you included, missing health on them, dispels easy to see), and your frame and your target's raised a little. Everything it sets is on the Party and Raid pages; move any of them in unlock mode. Choose it above to use it. If the profile you're on has moved action bars, offers to bring them along."] = {
        "DPS/Tanque con tu grupo y tu banda como casillas cuadradas debajo de ti (tú incluido, con la salud perdida en ellas y las disipaciones bien visibles), y tu marco y el de tu objetivo un poco elevados. Todo lo que ajusta está en las secciones Grupo y Banda; mueve cualquiera de ellos en modo de desbloqueo. Elígelo arriba para usarlo. Si el perfil actual tiene barras de acción movidas, ofrece llevarlas consigo.",
        "DPS/Tanque con tu grupo y tu banda como casillas cuadradas debajo de ti (tú incluida, con la salud perdida en ellas y las disipaciones bien visibles), y tu marco y el de tu objetivo un poco elevados. Todo lo que ajusta está en las secciones Grupo y Banda; mueve cualquiera de ellos en modo de desbloqueo. Elígelo arriba para usarlo. Si el perfil actual tiene barras de acción movidas, ofrece llevarlas consigo.",
    },
}

local function applyGender()
    local sex = UnitSex and UnitSex("player")
    if sex ~= 2 and sex ~= 3 then return end
    local female = sex == 3
    for key, forms in pairs(GENDER) do
        L[key] = female and forms[2] or forms[1]
    end
end

local HINT_PARTS = {
    { "^Click: (.+)$", "Clic: %s" },
    { "^Shift%-click: (.+)$", "Mayús-clic: %s" },
    { "^Ctrl%-click: (.+)$", "Ctrl-clic: %s" },
    { "^Alt%-click: (.+)$", "Alt + clic: %s" },
}
local MENU_FULL = { ["Show on map"] = "Mostrar en el mapa" }

local function translateShown(text)
    if type(text) ~= "string" then return text end
    if MENU_FULL[text] then return MENU_FULL[text] end
    local got = L[text]
    if type(got) == "string" and got ~= text then return got end
    for i = 1, #HINT_PARTS do
        local rest = text:match(HINT_PARTS[i][1])
        if rest then
            local word = L[rest]
            if type(word) == "string" and word ~= rest then
                return HINT_PARTS[i][2]:format(word)
            end
        end
    end
    local name, tail = text:match("^(.-) (%(.+%))$")
    if name then
        local word = L[name]
        if type(word) == "string" and word ~= name then return word .. " " .. tail end
    end
    return text
end

local function watchText(fs)
    if not fs or fs.__duiEs then return fs end
    fs.__duiEs = true
    local set = fs.SetText
    function fs:SetText(text, ...)
        return set(self, translateShown(text), ...)
    end
    return fs
end

local function installHooks()
    if DUI.__duiEsHooks then return end
    DUI.__duiEsHooks = true
    local tips = DUI.Tips
    if tips and type(tips.Hint) == "function" then
        local hint = tips.Hint
        tips.Hint = function(text) return hint(translateShown(text)) end
    end
    local widgets = DUI.Widgets
    if widgets and type(widgets.OpenMenu) == "function" then
        local openMenu = widgets.OpenMenu
        widgets.OpenMenu = function(owner, keys, values, ...)
            if type(values) == "table" then
                local copy = {}
                for k, v in pairs(values) do copy[k] = translateShown(v) end
                values = copy
            end
            return openMenu(owner, keys, values, ...)
        end
    end
    local style = DUI.Style
    if style and type(style.Text) == "function" then
        local text = style.Text
        style.Text = function(...) return watchText(text(...)) end
    end
    if widgets and type(widgets.Font) == "function" then
        local font = widgets.Font
        widgets.Font = function(...) return watchText(font(...)) end
    end
end

local function moduleNs(name)
    local mod = type(DUI.GetModule) == "function" and DUI:GetModule(name)
    return mod and mod.ns
end

local function patchModules()
    local quests = moduleNs("Quests")
    if type(quests) == "table" then
        local data = quests.Data
        if type(data) == "table" then
            if type(data.READY) == "string" then data.READY = translateShown(data.READY) end
            if type(data.AUTO) == "string" then data.AUTO = translateShown(data.AUTO) end
            if type(data.Quest) == "function" and not data.__duiEs then
                data.__duiEs = true
                local quest = data.Quest
                function data.Quest(...)
                    local q = quest(...)
                    if type(q) == "table" and type(q.turnIn) == "string" then
                        q.turnIn = translateShown(q.turnIn)
                    end
                    return q
                end
            end
        end
        local layout = quests.Layout
        if type(layout) == "table" and type(layout.FAILED) == "string" then
            layout.FAILED = translateShown(layout.FAILED)
        end
    end
    local bags = moduleNs("Bags")
    local categories = type(bags) == "table" and bags.Categories
    if type(categories) == "table" and type(categories.BUILTIN) == "table" then
        for _, group in ipairs(categories.BUILTIN) do
            if type(group.name) == "string" then group.name = translateShown(group.name) end
        end
    end
    local search = type(bags) == "table" and bags.Search
    if type(search) == "table" then
        local words = search.KEYWORDS
        if type(words) == "table" then
            local alias = {
                equipo = "gear", arma = "weapon", armadura = "armor",
                consumible = "consumable", comida = "food", bebida = "drink",
                pocion = "potion", ["poción"] = "potion",
                componente = "reagent", oficio = "tradegoods", receta = "recipe",
                llave = "key", recipiente = "container", bolsa = "bag",
                mision = "quest", ["misión"] = "quest", chatarra = "junk",
                ligado = "soulbound", conjunto = "set", bloqueado = "locked",
            }
            for es, en in pairs(alias) do
                if words[en] and not words[es] then words[es] = words[en] end
            end
        end
        local quality = search.QUALITY
        if type(quality) == "table" and type(words) == "table" then
            local names = { pobre = "poor", comun = "common", ["común"] = "common",
                inusual = "uncommon", raro = "rare", epico = "epic", ["épico"] = "epic",
                legendario = "legendary" }
            for es, en in pairs(names) do
                if quality[en] ~= nil then
                    quality[es] = quality[en]
                    if words[en] and not words[es] then words[es] = words[en] end
                end
            end
        end
        if type(search.FIELDS) == "table" then
            search.FIELDS.calidad = search.FIELDS.calidad or "quality"
            search.FIELDS.nivel = search.FIELDS.nivel or "itemLevel"
        end
        if type(search.HELP) == "string" then search.HELP = translateShown(search.HELP) end
    end
    local info = moduleNs("InfoPanel")
    local texts = type(info) == "table" and info.DataTexts
    if type(texts) == "table" and type(texts.GEAR) == "table" then
        for _, piece in ipairs(texts.GEAR) do
            if type(piece[2]) == "string" then piece[2] = translateShown(piece[2]) end
        end
    end
    if type(texts) == "table" and type(texts.CHANNELS) == "table" then
        for _, channel in pairs(texts.CHANNELS) do
            if type(channel) == "table" and type(channel.name) == "string" then
                channel.name = translateShown(channel.name)
            end
        end
    end
    local chat = moduleNs("Chat")
    local tags = type(chat) == "table" and chat.Tags
    if type(tags) == "table" then
        local channel = {
            General = "G", Comercio = "C",
            Trade = "C",
            LocalDefense = "DL", Defensalocal = "DL",
            LookingForGroup = "BG", Buscargrupo = "BG",
            WorldDefense = "DM", Defensamundial = "DM", Defensaglobal = "DM",
            GuildRecruitment = "RH", Reclutamiento = "RH",
            NewcomerChat = "Nv", Novatos = "Nv",
            Services = "Sv", Servicios = "Sv",
            ["Trade(Services)"] = "Sv", ["Comercio(Servicios)"] = "Sv",
            ["Trade(Local)"] = "CL", ["Comercio(Local)"] = "CL",
        }
        if type(tags.CHANNELS) == "table" then
            for key, letter in pairs(channel) do tags.CHANNELS[key] = letter end
        end
        local kind = { general = "G", trade = "C", lfg = "BG", defense = "DL",
            ["ch:trade (services)"] = "Sv", ["ch:trade (local)"] = "CL" }
        if type(tags.KIND_TAGS) == "table" then
            for key, letter in pairs(kind) do tags.KIND_TAGS[key] = letter end
        end
        local chatTags = { say = "D", yell = "Gr", whisper = "Su", bnet = "Su", party = "Gp",
            instance = "E", raid = "B", warning = "AB", guild = "H", officer = "O" }
        if type(tags.CHAT_TAGS) == "table" then
            for key, letter in pairs(chatTags) do tags.CHAT_TAGS[key] = letter end
        end
        local types = { GUILD = "H", OFFICER = "O", PARTY = "Gp", RAID = "B", INSTANCE_CHAT = "E" }
        if type(tags.TYPES) == "table" then
            for key, letter in pairs(types) do tags.TYPES[key] = letter end
        end
        local leaders = { CHAT_MSG_PARTY_LEADER = "GpL", CHAT_MSG_RAID_LEADER = "BL",
            CHAT_MSG_INSTANCE_CHAT_LEADER = "EL" }
        if type(tags.LEADERS) == "table" then
            for key, letter in pairs(leaders) do tags.LEADERS[key] = letter end
        end
        local speech = { S = "D", Y = "Gr", W = "Su", To = "A", RW = "AB" }
        if type(tags.SPEECH) == "table" then
            for _, row in pairs(tags.SPEECH) do
                if type(row) == "table" and speech[row[2]] then row[2] = speech[row[2]] end
            end
        end
    end
    local kinds = type(chat) == "table" and chat.Kinds
    if type(kinds) == "table" and type(kinds.CHANNELS) == "table" then
        local extra = {
            comercio = "trade", ["defensa local"] = "defense", ["buscar grupo"] = "lfg",
            ["defensa mundial"] = "defense", ["defensa global"] = "defense",
            servicios = "ch:trade (services)", novatos = "general",
        }
        for key, kind in pairs(extra) do kinds.CHANNELS[key] = kind end
    end
    local stats = DUI.Char and DUI.Char.Stats
    if type(stats) == "table" then
        if type(stats.LABEL) == "table" then
            for key, name in pairs(stats.LABEL) do
                if type(name) == "string" then stats.LABEL[key] = translateShown(name) end
            end
        end
        if type(stats.ROWS) == "table" then
            for _, rows in pairs(stats.ROWS) do
                if type(rows) == "table" then
                    for _, row in pairs(rows) do
                        if type(row) == "table" then
                            if type(row.label) == "string" then row.label = translateShown(row.label) end
                            if type(row.fmt) == "string" then row.fmt = translateShown(row.fmt) end
                        end
                    end
                end
            end
        end
    end
    local strip = DUI.SampleStrip
    if type(strip) == "table" then
        for _, field in ipairs({ "HINT", "DESIGN_HINT", "TIP", "DESIGN_EMPTY", "ALL", "ADD", "DESIGN_TIP" }) do
            local value = strip[field]
            if type(value) == "string" then strip[field] = translateShown(value) end
        end
    end
end

installHooks()
applyGender()
patchModules()

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_LOGIN")
watch:SetScript("OnEvent", function(self)
    applyGender()
    patchModules()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
