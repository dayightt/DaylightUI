-- Writes CHANGELOG.md from PatchNotes.lua. Run from the repo root:
--   luajit tools/changelog.lua
-- Loaded by the tests too (dofile), which use Render and Load.

local M = {}

local KINDS = { { "new", "New" }, { "changed", "Changed" }, { "fixed", "Fixed" } }

function M.Render(notes)
    local out = {}
    local function add(s) out[#out + 1] = s end
    -- Unreleased lines aren't in the build being uploaded, so leave them out.
    for _, v in ipairs(notes) do
        if v.version == "Unreleased" then goto continue end
        if #out > 0 then add("") end
        add("# DaylightUI " .. v.version)
        if v.summary then
            add("")
            add(v.summary)
        end
        for _, kind in ipairs(KINDS) do
            local lines = v[kind[1]]
            if lines and #lines > 0 then
                add("")
                add("## " .. kind[2])
                for _, line in ipairs(lines) do add("- " .. line[1] .. ": " .. line[2]) end
            end
        end
        ::continue::
    end
    return table.concat(out, "\n") .. "\n"
end

-- PatchNotes.lua expects the addon's (name, table) arguments.
function M.Load(path)
    local chunk = assert(loadfile(path or "PatchNotes.lua"))
    local DUI = {}
    chunk("DaylightUI", DUI)
    return DUI.PatchNotes
end

if arg and type(arg[0]) == "string" and string.match(arg[0], "changelog%.lua$") then
    local f = assert(io.open("CHANGELOG.md", "wb"))
    f:write(M.Render(M.Load()))
    f:close()
    print("CHANGELOG.md written")
end

return M
