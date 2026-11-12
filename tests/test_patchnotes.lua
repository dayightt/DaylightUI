local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- Patch notes: the data, the "seen" state, the page and the sidebar glow.

T.test("the notes are well formed", function()
    local DUI = stub.Load()
    local errs = DUI.Notes.Validate(DUI.PatchNotes)
    T.eq(#errs, 0, table.concat(errs, "; "))
end)

T.test("bad notes are reported", function()
    local DUI = stub.Load()
    local errs = DUI.Notes.Validate({
        { version = "1.0", date = "30/09", fixed = { { "Area" } } },
        { version = "Unreleased" },
        { version = "1.0" },
    })
    T.eq(#errs, 4, table.concat(errs, "; "))
end)

T.test("the newest release matches the .toc version", function()
    local DUI = stub.Load()
    local f = assert(io.open("DaylightUI.toc", "r"))
    local toc = f:read("*a")
    f:close()
    T.eq(DUI.Notes.Latest(), string.match(toc, "## Version:%s*(%S+)"))
end)

T.test("Latest skips Unreleased", function()
    local DUI = stub.Load()
    DUI.PatchNotes = { { version = "Unreleased" }, { version = "2.0" }, { version = "1.0" } }
    T.eq(DUI.Notes.Latest(), "2.0")
    DUI.PatchNotes = { { version = "Unreleased" } }
    T.isnil(DUI.Notes.Latest())
    T.falsy(DUI.Notes.IsNew())
end)

T.test("a first install counts as fresh; an earlier session's table does not", function()
    local DUI = stub.Load()
    T.eq(DUI.DB.fresh, true)
    local saved = _G.DaylightUIDB
    DUI = stub.Load({ before = function() _G.DaylightUIDB = saved end })
    T.eq(DUI.DB.fresh, false)
end)

T.test("a first install has read the notes already", function()
    local DUI = stub.Load()
    DUI.Notes.OnLogin()
    T.eq(DUI.DB.Root().notesSeen, DUI.Notes.Latest())
    T.falsy(DUI.Notes.IsNew())
end)

T.test("an existing install sees new notes until they are marked seen", function()
    local DUI = stub.Load()
    DUI.DB.fresh = false
    DUI.DB.Root().notesSeen = nil   -- Load() already ran the login as a fresh install
    DUI.Notes.OnLogin()
    T.isnil(DUI.DB.Root().notesSeen)
    T.truthy(DUI.Notes.IsNew())
    DUI.Notes.MarkSeen()
    T.falsy(DUI.Notes.IsNew())
    DUI.DB.Root().notesSeen = "0.0.1"
    T.truthy(DUI.Notes.IsNew(), "an older version seen")
end)

local SAMPLE = {
    { version = "Unreleased" },
    { version = "2.0", date = "2026-10-01", summary = "Big one.",
      new = { { "Buffs", "A thing" } }, fixed = { { "Chat", "Another thing" }, { "Bags", "A third" } } },
    { version = "1.0", date = "2026-09-01", fixed = { { "Core", "Old fix" } } },
}

T.test("Unreleased is left out until it has lines", function()
    local DUI = stub.Load()
    DUI.PatchNotes = SAMPLE
    T.eq(#DUI.Notes.Shown(), 2)
    SAMPLE[1].new = { { "Core", "Soon" } }
    T.eq(#DUI.Notes.Shown(), 3)
    SAMPLE[1].new = nil
end)

T.test("the page draws one card per version in the Appearance font", function()
    local DUI = stub.Load()
    DUI.PatchNotes = SAMPLE
    DUI.Style.FONT = "Fonts\\picked.ttf"
    DUI.OptionsPanel.Show("patchnotes")
    local row = DUI.Notes.row
    T.eq(row.cards[1].title:GetText(), "DaylightUI 2.0")
    T.eq(row.cards[1].date:GetText(), "2026-10-01")
    T.eq((row.cards[1].title:GetFont()), "Fonts\\picked.ttf")
    T.eq((row.cards[1].pieces[2].text:GetFont()), "Fonts\\picked.ttf")
    T.truthy(string.find(row.cards[1].pieces[2].text:GetText(), "Buffs", 1, true))
    T.eq(row.cards[2].title:GetText(), "DaylightUI 1.0")
end)

T.test("the newest release is open, older ones fold and unfold", function()
    local DUI = stub.Load()
    DUI.PatchNotes = SAMPLE
    DUI.OptionsPanel.Show("patchnotes")
    local row = DUI.Notes.row
    T.truthy(DUI.Notes.IsOpen("2.0"))
    T.falsy(DUI.Notes.IsOpen("1.0"))
    local folded = row.cards[2]:GetHeight()
    row.cards[2].head:Click()
    T.truthy(DUI.Notes.IsOpen("1.0"))
    T.truthy(row.cards[2]:GetHeight() > folded, "taller when open")
end)

T.test("/dui notes opens the page and marks it read", function()
    local DUI = stub.Load()
    DUI.DB.Root().notesSeen = "0.0.1"
    DUI.RunCommand("notes")
    T.eq(DUI.OptionsPanel.Current(), "patchnotes")
    T.falsy(DUI.Notes.IsNew())
end)

T.test("the Patch Notes button glows until the page is opened", function()
    local DUI = stub.Load()
    DUI.DB.Root().notesSeen = "0.0.1"
    local Panel = DUI.OptionsPanel
    Panel.Show("home")
    local b = Panel.NavButton("patchnotes")
    T.truthy(b.tag:IsShown(), "NEW tag shown")
    T.eq(b.tag:GetText(), "NEW")
    T.truthy(b.bar:IsShown(), "pill shown while not selected")
    T.truthy(b.pulse:IsPlaying(), "pulsing")
    -- Stepped by the motion kit, never an alpha animation group.
    for _ = 1, 10 do stub.RunOnUpdate(DUI.Motion.Driver(), 1 / 30) end
    T.truthy(b.bar:GetAlpha() < 1, "the bar breathes")
    Panel.ShowSection("patchnotes")
    T.falsy(b.tag:IsShown(), "tag gone once read")
    T.falsy(b.pulse:IsPlaying(), "pulse stopped")
    Panel.Show("home")
    T.falsy(b.bar:IsShown(), "no pill afterwards")
end)

T.test("sections without a badge get no glow", function()
    local DUI = stub.Load()
    DUI.OptionsPanel.Show("home")
    T.isnil(DUI.OptionsPanel.NavButton("core").tag)
end)

T.test("the changelog is rendered from the notes", function()
    local CL = dofile("tools/changelog.lua")
    local text = CL.Render({
        { version = "Unreleased", fixed = { { "Chat", "A fix" } } },
        { version = "1.0", date = "2026-09-01", summary = "First.",
          fixed = { { "Core", "B" } }, new = { { "Bags", "A" } } },
    })
    T.eq(text, table.concat({
        "# DaylightUI 1.0", "", "First.", "", "## New", "- Bags: A", "", "## Fixed", "- Core: B", "",
    }, "\n"))
    T.eq(#CL.Load("PatchNotes.lua"), #stub.Load().PatchNotes)
end)
