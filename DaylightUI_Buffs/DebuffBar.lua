-- DebuffBar: what is on you, soonest first, bordered by dispel type. Same
-- machinery as the buff bar with its own settings scope; no categories.
-- Its first row sits on the info panel's bottom edge and slides with it.

local _, BL = ...

BL.DebuffBar = BL.CreateBar({ scope = "debuff", frameName = "DaylightUIDebuffs", label = "Debuffs", moverKey = "buffs.debuff",
    default = { "TOPRIGHT", BL.DEBUFF_ANCHOR, "TOPRIGHT", 0, 0 } })
