-- Your DoTs (Dots.lua), learned from your own casts and the UNIT_COMBAT hits on the
-- mob, never from the combat log (closed) or the mob's auras (secret).
local stub = require("stub")

local COR = 172      -- Corruption: 40 Shadow over 12 sec (4 ticks of 10)
local REND = 772     -- Rend: Physical bleed, 25 over 15 sec, 3 sec ticks
local AGONY = 980    -- Bane of Agony: 96 over 24 sec, 2 sec ticks, back-loaded
local RIP = 1079
local CLAW = 1082
local RAKE = 1822    -- Rake: a Physical hit, then a bleed
local SIPHON = 18265 -- Siphon Life: a second Shadow DoT, 15 every 3 sec for 30
local IMMOLATE = 348 -- an 11 Fire hit, then 20 Fire over 15 sec (5 ticks of 4)

local SPELLS = {
    [COR] = { name = "Corruption", desc = "Corrupts the target, causing 40 Shadow damage over 12 sec." },
    [REND] = { name = "Rend", desc = "Wounds the target causing them to bleed for 25 damage over 15 sec." },
    [AGONY] = { name = "Bane of Agony", desc = "Curses the target with agony, causing 96 Shadow damage over 24 sec." },
    [RIP] = { name = "Rip", desc = "Finishing move that causes damage over time.  Damage increases per combo point:\n   1 point : 42 damage over 12 sec.\n   2 points: 66 damage over 12 sec.\n   3 points: 90 damage over 12 sec.\n   4 points: 114 damage over 12 sec.\n   5 points: 138 damage over 12 sec." },
    [RAKE] = { name = "Rake", desc = "Rake the target for 19 damage and an additional 39 damage over 9 sec.  Awards 1 combo point." },
    [SIPHON] = { name = "Siphon Life", desc = "Transfers 15 health from the target to the caster every 3 sec.  Lasts 30 sec." },
    [IMMOLATE] = { name = "Immolate", desc = "Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec." },
    [CLAW] = { name = "Claw", desc = "Claw the enemy, causing 27 additional damage.  Awards 1 combo point." },
    [686] = { name = "Shadow Bolt", desc = "Sends a shadowy bolt at the enemy, causing 13 to 18 Shadow damage." },
    [139] = { name = "Renew", desc = "Heals the target of 45 damage over 15 sec." },
    [5740] = { name = "Rain of Fire", desc = "Calls down a fiery rain to burn enemies in the area of effect for 240 Fire damage over 8 sec." },
}

local SHADOW, PHYSICAL = 32, 1
local n = 0

local function world()
    local DUI = stub.Load{ before = function()
        stub.units.player = { name = "Me", isPlayer = true, class = "WARLOCK", guid = "Player-1" }
        stub.units.target = { name = "Kobold", reaction = 2, guid = "Creature-1", health = 300, maxHealth = 300 }
        stub.spells = SPELLS
    end }
    DUI.Dots.Want("unitframes", true)
    DUI.Dots.Forget()
    return DUI, DUI.Dots
end

local function cast(id)
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", guid, id)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
end

local function hit(amount, school, flag, unit)
    stub.FireEvent("UNIT_COMBAT", unit or "target", "WOUND", flag or "", amount, school)
end

local function tick(dt) stub.Advance(dt); stub.RunTickers() end
-- A hit with a secret amount, as every hit on a mob is in a fight on Forever.
local function secretHit(school) stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", stub.Secret(9), school) end

T.test("dots: the description gives total, school, duration, interval", function()
    local _, Dots = world()
    local total, school, dur = Dots.Parse(SPELLS[COR].desc)
    T.eq(total, 40); T.eq(school, SHADOW); T.eq(dur, 12)
    T.eq((Dots.Parse(SPELLS[RIP].desc, 3)), 90, "a finisher by combo points")
    T.eq((Dots.Parse(SPELLS[RIP].desc, 9)), 138, "points past the table take the top entry")
    T.isnil(Dots.Parse(SPELLS[686].desc), "a direct hit is no DoT")
    T.isnil(Dots.Parse(SPELLS[139].desc), "a heal over time is no DoT")
    T.eq((Dots.Parse("Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec.")), 150)
end)

-- A French client: its own tooltip wording, and its own names for the spells
-- the lists go by (Rain of Fire is an area, never a DoT on the mob).
local FRENCH = {
    [COR] = { name = "Corruption", desc = "Corrompt la cible et lui inflige 40 points de dégâts d'Ombre en 12 sec." },
    [REND] = { name = "Pourfendre", desc = "Blesse la cible. Elle saigne et perd 25 points de vie en 15 sec." },
    [RIP] = { name = "Déchirure", desc = "Coup de grâce qui inflige des dégâts sur la durée. La durée dépend du nombre de points de combo :\n   1 point : 42 points de dégâts en 12 secondes\n   3 points : 90 points de dégâts en 12 secondes\n   5 points : 138 points de dégâts en 12 secondes" },
    [CLAW] = { name = "Griffe", desc = "Griffe l'ennemi et lui inflige 27 points de dégâts supplémentaires. Vous gagnez 1 point de combo." },
    [686] = { name = "Trait de l'ombre", desc = "Envoie un trait d'ombre sur l'ennemi et lui inflige 13 à 18 points de dégâts d'Ombre." },
    [139] = { name = "Rénovation", desc = "Rend 45 points de vie à la cible en 15 sec." },
    [5740] = { name = "Pluie de feu", desc = "Invoque une pluie de feu qui brûle les ennemis dans la zone d'effet et inflige 240 points de dégâts de Feu en 8 sec." },
    [8921] = { name = "Eclat lunaire", desc = "Brûle l'ennemi et lui inflige 9 à 12 points de dégâts des Arcanes, puis 12 points de dégâts des Arcanes supplémentaires en 9 sec." },
    [348] = { name = "Immolation", desc = "Brûle l'ennemi et lui inflige 11 points de dégâts de feu, puis 20 points supplémentaires de dégâts de feu en 15 sec." },
    [14914] = { name = "Flammes sacrées", desc = "Consume l'ennemi et lui inflige 84 à 104 points de dégâts du Sacré et 30 points de dégâts du Sacré supplémentaires en 10 sec." },
    [15407] = { name = "Fouet mental", desc = "Inflige 75 points de dégâts d\226\128\153ombre en 3 sec." },
    [18265] = { name = "Siphon de vie", desc = "Transfère 15 points de vie de la cible vers le lanceur de sorts toutes les 3 sec. Dure 30 sec." },
    [3034] = { name = "Morsure de vipère", desc = "Mord la cible et lui draine 616 points de mana en 8 sec. Une seule technique de Morsure ou de Piqûre peut être active sur la cible par chasseur." },
}

T.test("dots: a French client reads its own tooltips and spell names", function()
    local _, Dots = world()
    stub.spells = FRENCH
    Dots.UseLocale("frFR")
    local total, school, dur = Dots.Parse(FRENCH[COR].desc)
    T.eq(total, 40); T.eq(school, SHADOW); T.eq(dur, 12)
    total, school, dur = Dots.Parse(FRENCH[REND].desc)
    T.eq(total, 25); T.eq(school, PHYSICAL, "a bleed is physical"); T.eq(dur, 15)
    T.eq((Dots.Parse(FRENCH[RIP].desc, 3)), 90, "a finisher by combo points")
    T.isnil(Dots.Parse(FRENCH[686].desc), "a direct hit is no DoT")
    T.isnil(Dots.Parse(FRENCH[139].desc), "a heal over time is no DoT")
    T.eq(select(2, Dots.Parse(FRENCH[8921].desc)), 64, "Arcane")
    T.eq((Dots.Parse(FRENCH[8921].desc)), 12, "the periodic part, not the hit")
    T.eq(select(2, Dots.Parse(FRENCH[348].desc)), 4, "Fire, with the word before it")
    T.eq((Dots.Parse(FRENCH[348].desc)), 20)
    T.eq(select(2, Dots.Parse(FRENCH[14914].desc)), 2, "Holy")
    T.eq(select(2, Dots.Parse(FRENCH[15407].desc)), SHADOW, "the curly apostrophe")
    T.eq((Dots.Parse(FRENCH[18265].desc)), 150, "a drain by its ticks")
    T.isnil(Dots.Parse(FRENCH[3034].desc), "Viper Sting drains mana, not health")
    cast(3034)
    T.isnil(Dots.Left("target"), "so nothing is drawn on the health bar")
    Dots.Forget()
    cast(COR)
    T.eq(Dots.Left("target"), 40, "the cast shows")
    Dots.Forget()
    cast(5740)
    T.isnil(Dots.Left("target"), "Pluie de feu is found by its id: an area, never on the mob")
    cast(CLAW)
    cast(RIP)
    T.eq(Dots.Left("target"), 42, "Griffe gave a point, Déchirure spends it")
    Dots.UseLocale("enUS")
    stub.spells = SPELLS
end)

-- Spanish and Portuguese clients, worded as the classic tooltips on Wowhead
-- (the Spanish Corruption line is also the one a player reported).
local SPANISH = {
    [COR] = { name = "Corrupción", desc = "Corrompe al objetivo, causando 40 p. de daño de las Sombras durante 12 s." },
    [REND] = { name = "Desgarrar", desc = "Hiere al objetivo y lo hace sangrar con 25 p. de daño durante 15 s." },
    [RIP] = { name = "Destripar", desc = "Remate que inflige daño en el tiempo. El daño aumenta por cada punto de combo y con el poder de ataque:\n   1 punto: 42 de daño durante 12 s.\n   3 puntos: 90 de daño durante 12 s.\n   5 puntos: 138 de daño durante 12 s." },
    [CLAW] = { name = "Zarpa", desc = "Da un zarpazo al enemigo, causando 27 p. de daño extra. Otorga 1 p. de combo." },
    [686] = { name = "Descarga de las Sombras", desc = "Lanza un golpe de Sombras al enemigo causándole 13 al 18 p. de daño de las Sombras." },
    [139] = { name = "Renovar", desc = "Cura el objetivo en 45 p. de daño durante 15 s." },
    [348] = { name = "Inmolar", desc = "Quema al enemigo, que recibe 11 p. de daño de Fuego y 20 p. de daño de Fuego más durante 15 s." },
    [8921] = { name = "Fuegolunar", desc = "Quema al enemigo, causando 9 al 12 p. de daño Arcano y 12 p. de daño Arcano extra durante 9 s." },
    [14914] = { name = "Fuego Sagrado", desc = "Envuelve al enemigo en llamas Sagradas que causan 84 al 104 p. de daño Sagrado y 30 p. de daño Sagrado extra durante 10 s." },
    [1978] = { name = "Aguijón de serpiente", desc = "Aguijonea al enemigo causando 20 p. de daño de Naturaleza durante 15 s. Solo puede estar activo 1 aguijón por cazador." },
    [2823] = { name = "Veneno mortal", desc = "Cubre un arma con veneno que dura 30 min.\nCada golpe tiene un 30% de probabilidad de envenenar al enemigo, infligiendo 36 p. de daño de Naturaleza durante 12 s." },
    [18265] = { name = "Succionar vida", desc = "Transfiere 15 p. de salud del objetivo al taumaturgo cada 3 segundo durante 30 s." },
    [1943] = { name = "Ruptura", desc = "Golpe de remate que causa daño durante cierto tiempo, aumentado por tu poder de ataque. El daño aumenta con cada punto de combo:\n 1 punto  : 40 p. de daño durante 8 s\n   2 puntos: 60 p. de daño durante 10 s" },
}

local PORTUGUESE = {
    [COR] = { name = "Corrupção", desc = "Corrompe o alvo, causando 40 de dano de Sombra ao longo de 12 s." },
    [REND] = { name = "Dilacerar", desc = "Fere o alvo, fazendo-o sangrar. O sangramento causa 25 de dano ao longo de 15 s." },
    [RIP] = { name = "Rasgar", desc = "Golpe final que causa dano ao longo do tempo. O dano aumenta a cada ponto de combo e de acordo com o seu Poder de Ataque:\n   1 ponto: 42 de dano ao longo de 12 s.\n   3 pontos: 90 de dano ao longo de 12 s." },
    [CLAW] = { name = "Garra", desc = "Ataca o inimigo com as garras, causando mais 27 de dano. Concede 1 ponto de combo." },
    [139] = { name = "Renovar", desc = "Cura 45 pontos de vida do alvo ao longo de 15 s." },
    [8921] = { name = "Fogo Lunar", desc = "Queima o inimigo causando 9 para 12 de dano Arcano e mais 12 de dano Arcano ao longo de 9 s." },
    [348] = { name = "Imolação", desc = "Queima o inimigo, causando 11 de dano de Fogo e mais 20 de dano de Fogo ao longo de 15 s." },
    [2823] = { name = "Veneno Mortal", desc = "Cobre a arma com um veneno que dura 30 minutos.\nCada acerto tem 30% de chance de envenenar o inimigo, causando 36 de dano de Natureza ao longo de 12 s." },
    [18265] = { name = "Sifão de Vida", desc = "Transfere 15 pontos de vida do alvo para o lançador a cada 3 s. Dura 30 s." },
}

-- corruptionSchool: what the description alone says (Chinese names none; the
-- cast still gets Shadow from the spell itself).
local function readsItsOwn(locale, spells, corruptionSchool)
    local _, Dots = world()
    stub.spells = spells
    Dots.UseLocale(locale)
    local total, school, dur = Dots.Parse(spells[COR].desc)
    T.eq(total, 40, locale); T.eq(school, corruptionSchool or SHADOW, locale); T.eq(dur, 12, locale)
    total, school, dur = Dots.Parse(spells[REND].desc)
    T.eq(total, 25, locale); T.eq(school, PHYSICAL, "a bleed is physical"); T.eq(dur, 15, locale)
    T.eq((Dots.Parse(spells[RIP].desc, 3)), 90, "a finisher by combo points")
    T.isnil(Dots.Parse(spells[139].desc), "a heal over time is no DoT")
    T.isnil(Dots.Parse(spells[2823].desc), "a poison on the weapon is no DoT")
    T.eq((Dots.Parse(spells[8921].desc)), 12, "the periodic part, not the hit")
    T.eq(select(2, Dots.Parse(spells[8921].desc)), 64, "Arcane")
    T.eq((Dots.Parse(spells[348].desc)), 20)
    T.eq(select(2, Dots.Parse(spells[348].desc)), 4, "Fire")
    T.eq((Dots.Parse(spells[18265].desc)), 150, "a drain by its ticks")
    cast(COR)
    T.eq(Dots.Left("target"), 40, "the cast shows")
    tick(3); hit(10, SHADOW)
    T.eq(Dots.Left("target"), 30, "a Shadow tick takes its share off")
    Dots.Forget()
    cast(CLAW)
    cast(RIP)
    T.eq(Dots.Left("target"), 42, "the builder gave a point, the finisher spends it")
    Dots.UseLocale("enUS")
    stub.spells = SPELLS
end

T.test("dots: a Spanish client reads its own tooltips", function()
    readsItsOwn("esES", SPANISH)
    readsItsOwn("esMX", SPANISH)
    local _, Dots = world()
    Dots.UseLocale("esES")
    T.isnil(Dots.Parse(SPANISH[686].desc), "a direct hit is no DoT")
    T.eq(select(2, Dots.Parse(SPANISH[14914].desc)), 2, "Holy")
    T.eq(select(2, Dots.Parse(SPANISH[1978].desc)), 8, "Nature")
    T.eq((Dots.Parse(SPANISH[1943].desc, 2)), 60, "Rupture's own wording")
    T.eq((Dots.Parse("Corrompe al objetivo, causando 324 p. de daño de las Sombras durante 18 s.")), 324)
    Dots.UseLocale("enUS")
end)

T.test("dots: a Brazilian Portuguese client reads its own tooltips", function()
    readsItsOwn("ptBR", PORTUGUESE)
end)

-- German, Russian, Chinese and Korean, from the same classic tooltips (Rend,
-- Rip and Corruption's numbers set to the ones above). German, Chinese and
-- Korean name the duration before the damage.
local GERMAN = {
    [COR] = { name = "Verderbnis", desc = "Verdirbt das Ziel und verursacht 12 Sek. lang 40 Punkt(e) Schattenschaden." },
    [REND] = { name = "Verwunden", desc = "Verwundet das Ziel, lässt es 15 Sek. lang bluten und fügt damit 25 Punkt(e) Schaden zu." },
    [RIP] = { name = "Zerfetzen", desc = "Finishing-Move, der Schaden im Lauf der Zeit verursacht. Der Schaden erhöht sich pro Combopunkt sowie durch Eure Angriffskraft:\n   1 Punkt: 42 Schaden im Verlauf von 12 Sek.\n   3 Punkte: 90 Schaden im Verlauf von 12 Sek." },
    [CLAW] = { name = "Klaue", desc = "Den Feind mit Klauen beharken und ihm so zusätzlich 27 Punkt(e) Schaden zufügen. Gewährt 1 Combopunkt." },
    [139] = { name = "Erneuerung", desc = "Heilt das Ziel 15 Sek. lang um 45 Schadenspunkt(e)." },
    [2823] = { name = "Tödliches Gift", desc = "Überzieht eine Waffe mit Gift, das 30 Minuten lang wirkt.\nBei jedem Schlag besteht eine Chance von 30%, den Gegner 12 Sek. lang für 36 Punkt(e) Naturschaden zu vergiften." },
    [8921] = { name = "Mondfeuer", desc = "Verbrennt den Feind und fügt ihm 9 bis 12 Punkt(e) Arkanschaden sowie 9 Sek. lang 12 Punkt(e) zusätzlichen Arkanschaden zu." },
    [348] = { name = "Feuerbrand", desc = "Verbrennt den Gegner und fügt ihm 11 Feuerschaden sowie im Verlauf von 15 Sek. insgesamt 20 zusätzlichen Feuerschaden zu." },
    [18265] = { name = "Lebensentzug", desc = "Überträgt alle 3 Sek. 15 Punkt(e) Gesundheit vom Ziel auf den Zaubernden. Hält 30 Sek. lang an." },
    [1822] = { name = "Krallenhieb", desc = "Attackiert das Ziel mit Krallen, fügt 19 Punkt(e) Schaden sowie 39 Punkt(e) zusätzlichen Schaden im Verlauf von 9 Sek. zu. Gewährt 1 Combopunkt." },
    [116] = { name = "Frostblitz", desc = "Schleudert einen Frostblitz auf den Gegner, der 18 bis 20 Frostschaden verursacht und 5 Sek. lang das Bewegungstempo um 40% verringert." },
    [1943] = { name = "Blutung", desc = "Finishing-Move, der Schaden im Lauf der Zeit verursacht, erhöht durch Angriffskraft. Hält pro Combopunkt länger an:\n   1 Punkt: 40 Schaden über 8 Sekunden.\n   2 Punkte: 60 Schaden über 10 Sekunden." },
}

local RUSSIAN = {
    [COR] = { name = "Порча", desc = "Порча цели с нанесением ей 40 ед. урона от темной магии за 12 сек." },
    [REND] = { name = "Кровопускание", desc = "Наносит цели кровоточащую рану, из-за которой она теряет 25 ед. здоровья за 15 сек." },
    [RIP] = { name = "Разорвать", desc = "Завершающий прием, наносящий урон в течение некоторого времени. Урон увеличивается за счет длины серии и силы атаки:\n  1 прием: 42 ед. урона за 12 сек.\n  3 приема: 90 ед. урона за 12 сек." },
    [CLAW] = { name = "Когти", desc = "Наносит противнику дополнительно 27 ед. урона. Длина серии приемов увеличивается на 1." },
    [139] = { name = "Обновление", desc = "Излечение цели на 45 ед. в течение 15 сек." },
    [2823] = { name = "Смертельный яд", desc = "Смазать оружие ядом, действующим в течение 30 мин.\nКаждый удар с вероятностью 30% отравляет противника ядом, наносящим 36 ед. урона от сил природы в течение 12 сек." },
    [8921] = { name = "Лунный огонь", desc = "Обжигает противника, нанося ему 9 в 12 ед. урона от тайной магии и 12 дополнительного урона от тайной магии в течение 9 сек." },
    [348] = { name = "Жертвенный огонь", desc = "Наносит противнику 11 ед. урона от огня сразу и еще 20 ед. урона от огня за 15 сек." },
    [18265] = { name = "Вытягивание жизни", desc = "Передача 15 ед. здоровья от цели к заклинателю раз в 3 сек. Время действия – 30 сек." },
    [AGONY] = { name = "Проклятие агонии", desc = "Проклинает цель, вводит ее в состояние агонии и наносит ей в течение 24 сек. постепенно нарастающий урон. Общая величина урона - 84. Каждый чернокнижник может наложить только одно заклинание проклятия на каждую цель." },
    [1822] = { name = "Глубокая рана", desc = "Наносит противнику глубокую рану. Противник теряет 19 и дополнительно 39 здоровья за 9 сек. в результате кровотечения. Длина серии приемов увеличивается на 1." },
    [14914] = { name = "Священный огонь", desc = "Навлечение на противника священного пламени, которое наносит 84 в 104 ед. урона от светлой магии и дополнительно 30 ед. урона от светлой магии в течение 10 сек." },
}

local CHINESE = {
    [COR] = { name = "腐蚀术", desc = "腐蚀目标，在12秒内造成累计40点伤害。" },
    [REND] = { name = "撕裂", desc = "使目标的伤口不断流血，在15秒内造成累计25点伤害。" },
    [RIP] = { name = "撕扯", desc = "终结技，使目标在一段时间内受到持续伤害。伤害将根据连击点数和攻击强度决定：\n1点：12秒内42点伤害。\n3点：12秒内90点伤害。" },
    [CLAW] = { name = "爪击", desc = "用爪攻击敌人，对其造成27点额外伤害。奖励1个连击点数。" },
    [139] = { name = "恢复", desc = "治疗目标，在15秒内恢复总计45点生命值。" },
    [2823] = { name = "致命毒药", desc = "给一件武器浸毒，效果持续30分钟。\n每次攻击都有30%的几率令敌人中毒，在12秒内对其造成36点自然伤害，对单一目标最多可以叠加5次。" },
    [8921] = { name = "月火术", desc = "灼烧敌人，对其造成9至12点伤害，并在9秒内造成额外的12点奥术伤害。" },
    [348] = { name = "献祭", desc = "灼烧敌人，对其造成11点火焰伤害，并在15秒内造成额外的20点火焰伤害。" },
    [18265] = { name = "生命虹吸", desc = "每3秒将目标的15点生命值转移给施法者，持续30秒。" },
    [14914] = { name = "神圣之火", desc = "神圣的烈焰吞噬敌人，对其造成84至104点神圣伤害，并在10秒内造成30点额外的神圣伤害。" },
    [1943] = { name = "割裂", desc = "终结技，使目标在一段时间内受到持续的伤害。根据连击点数决定持续时间，该伤害会受到攻击强度的加成影响：\n 1点：40伤害，持续8秒\n 2点：60伤害，持续10秒" },
}

local KOREAN = {
    [COR] = { name = "부패", desc = "대상을 부패시켜 12초에 걸쳐 총 40의 암흑 피해를 입힙니다." },
    [REND] = { name = "분쇄", desc = "적에게 깊은 상처를 입혀 출혈을 일으킵니다. 15초에 걸쳐 총 25의 피해를 입힙니다." },
    [RIP] = { name = "도려내기", desc = "마무리 일격을 시도하여 적에게 지속적인 피해를 입힙니다. 연계 점수와 전투력에 따라 피해가 증가합니다:\n  연계 점수 1점: 12초에 걸쳐 42의 피해\n  연계 점수 3점: 12초에 걸쳐 90의 피해" },
    [CLAW] = { name = "할퀴기", desc = "적을 발톱으로 할퀴어 27의 추가 피해를 입힙니다. 1의 연계 포인트가 주어집니다." },
    [139] = { name = "소생", desc = "15초에 걸쳐 대상의 생명력을 총 45만큼 회복시킵니다." },
    [2823] = { name = "맹독", desc = "무기에 30분 동안 유지되는 독을 바릅니다.\n매 공격 시 30%의 확률로 적을 중독시켜 12초에 걸쳐 36의 자연 피해를 입힙니다." },
    [8921] = { name = "달빛 섬광", desc = "적을 불태워 9 에서 12의 비전 피해를 입히고 9초에 걸쳐 총 12의 비전 피해를 입힙니다." },
    [348] = { name = "제물", desc = "적을 불태워 11의 화염 피해를 입히고 추가로 15초에 걸쳐 총 20의 화염 피해를 입힙니다." },
    [18265] = { name = "생명력 착취", desc = "대상으로부터 매 3초마다 15의 생명력을 흡수합니다. 30초 동안 지속됩니다." },
    [1943] = { name = "파열", desc = "마무리 일격을 시도하여 적에게 지속적인 피해를 입힙니다. 입히는 피해는 전투력에 따라 증가하며 연계 포인트 당 지속 시간이 달라집니다:\n  1 포인트: 8초에 걸쳐 40의 피해\n  2 포인트: 10초에 걸쳐 60의 피해" },
}

T.test("dots: a German client reads its own tooltips", function()
    readsItsOwn("deDE", GERMAN)
    local _, Dots = world()
    Dots.UseLocale("deDE")
    T.eq((Dots.Parse(GERMAN[1822].desc)), 39, "Rake's bleed, worded the other way round")
    T.isnil(Dots.Parse(GERMAN[116].desc), "a slow after a hit is no DoT")
    T.eq((Dots.Parse(GERMAN[1943].desc, 2)), 60, "Rupture's own wording")
    Dots.UseLocale("enUS")
end)

T.test("dots: a Russian client reads its own tooltips", function()
    readsItsOwn("ruRU", RUSSIAN)
    local _, Dots = world()
    Dots.UseLocale("ruRU")
    T.eq((Dots.Parse(RUSSIAN[AGONY].desc)), 84, "Curse of Agony names its total last")
    T.eq((Dots.Parse(RUSSIAN[1822].desc)), 39, "Rake's bleed")
    T.eq(select(2, Dots.Parse(RUSSIAN[14914].desc)), 2, "Holy")
    Dots.UseLocale("enUS")
end)

T.test("dots: a Chinese client reads its own tooltips", function()
    readsItsOwn("zhCN", CHINESE, PHYSICAL)
    local _, Dots = world()
    Dots.UseLocale("zhCN")
    T.eq(select(2, Dots.Parse(CHINESE[14914].desc)), 2, "Holy, inside the words")
    T.eq((Dots.Parse(CHINESE[1943].desc, 2)), 60, "Rupture lists its points the other way")
    Dots.UseLocale("enUS")
end)

T.test("dots: a Korean client reads its own tooltips", function()
    readsItsOwn("koKR", KOREAN)
    local _, Dots = world()
    Dots.UseLocale("koKR")
    T.eq((Dots.Parse(KOREAN[1943].desc, 2)), 60, "Rupture's own wording")
    Dots.UseLocale("enUS")
end)

-- The game's own name for a school counts too, so a language with none of
-- the hand-made words still finds it.
T.test("dots: the game's own school names count", function()
    local _, Dots = world()
    local was = _G.STRING_SCHOOL_SHADOW
    _G.STRING_SCHOOL_SHADOW = "Ombra"
    T.eq(select(2, Dots.Parse("Causes 40 Ombra damage over 12 sec.")), SHADOW)
    _G.STRING_SCHOOL_SHADOW = was
end)

-- The game writes big numbers grouped ("1,214 Shadow damage"), so a pattern
-- starting after the comma read 214 and Shadow Word: Pain at 1,214 showed
-- a sliver, while Devouring Plague at 904 looked right.
T.test("dots: a description's grouped thousands read whole", function()
    local _, Dots = world()
    stub.spells[589] = { name = "Shadow Word: Pain", desc = "A word of darkness that causes 1,214 Shadow damage over 24 sec." }
    T.eq((Dots.Parse(stub.spells[589].desc)), 1214, "English comma")
    T.eq((Dots.Parse("Transfers 1,015 health from the target to the caster every 3 sec.  Lasts 30 sec.")), 10150, "a drain")
    T.eq((Dots.Parse("Causes 1,234,567 Shadow damage over 12 sec.")), 1234567, "two commas")
    T.eq(Dots.Upfront("Burns the enemy for 1,011 Fire damage and then an additional 2,020 Fire damage over 15 sec."), 1011, "the upfront hit")
    cast(589)
    T.eq(Dots.Left("target"), 1214, "the whole DoT shows at the cast")
    tick(3); secretHit(SHADOW)
    T.eq(Dots.Left("target"), 1062, "7 of 8 ticks left after the first, not a sliver")
    local cases = {
        { "deDE", "Verursacht 24 Sek. lang 1.214 Punkt(e) Schattenschaden." },
        { "frFR", "Inflige 1\194\160214 points de dégâts d'Ombre en 24 sec." },
        { "frFR", "Inflige 1\226\128\175214 points de dégâts d'Ombre en 24 sec." },
        { "ruRU", "Наносит цели 1 214 ед. урона от темной магии за 24 сек." },
        { "esES", "Causa 1.214 p. de daño de las Sombras durante 24 s." },
        { "ptBR", "Causa 1.214 de dano de Sombra ao longo de 24 s." },
        { "zhCN", "在24秒内造成累计1,214点暗影伤害。" },
        { "koKR", "24초에 걸쳐 총 1,214의 암흑 피해를 입힙니다." },
    }
    for _, c in ipairs(cases) do
        Dots.UseLocale(c[1])
        T.eq((Dots.Parse(c[2])), 1214, c[1] .. " groups its thousands its own way")
    end
    Dots.UseLocale("deDE")
    T.eq(select(3, Dots.Parse("Verursacht 7,5 Sek. lang 40 Punkt(e) Schattenschaden.")), 7.5, "a decimal comma")
    Dots.UseLocale("enUS")
end)

-- A size learned next to a misread description ("1,950" read as 950) is
-- twice too big once the description reads whole, so older saved sizes go.
T.test("dots: sizes learned while thousands were misread are dropped", function()
    local DUI, Dots = world()
    stub.spells[589] = { name = "Shadow Word: Pain", desc = "A word of darkness that causes 1,950 Shadow damage over 24 sec." }
    DUI.DB.Character().dots = { v = 2, ticks = { [589] = 2.05 }, weights = { [589] = 8 } }
    cast(589)
    T.eq(Dots.Left("target"), 1950, "the description's own size, not 2.05 times it")
end)

T.test("dots: a cast shows its whole damage, each tick takes its share off", function()
    local _, Dots = world()
    T.isnil(Dots.Left("target"))
    cast(COR)
    T.eq(Dots.Left("target"), 40)
    tick(3); hit(10, SHADOW)
    T.eq(Dots.Left("target"), 30)
    tick(3); hit(10, SHADOW)
    T.eq(Dots.Left("target"), 20)
end)

T.test("dots: real tick sizes replace the description's and are kept per character", function()
    local DUI, Dots = world()
    cast(COR)
    tick(3); hit(14, SHADOW)
    T.eq(Dots.Left("target"), 42, "3 ticks left at the 14 seen")
    T.isnil(DUI.DB.Character().dots.ticks[COR], "one tick alone isn't kept: it may have been a white hit")
    tick(3); hit(14, SHADOW)
    T.eq(DUI.DB.Character().dots.ticks[COR], 1.4, "two that agree are, as their size next to the description's")
    Dots.Forget()
    cast(COR)
    T.eq(Dots.Left("target"), 56, "the next cast starts from the learned 14 x 4")
end)

-- On Forever a spell keeps one id at every level, and its description grows
-- with level and spell power. A tick size learned at level 10 must not shrink
-- the same spell at level 47 (Shadow Word: Pain, 5 a tick then, 151 now).
T.test("dots: a size learned at a lower level doesn't shrink the spell once it grows", function()
    local DUI, Dots = world()
    stub.spells[589] = { name = "Shadow Word: Pain", desc = "A word of darkness that causes 30 Shadow damage over 18 sec." }
    cast(589)                        -- 6 ticks of 5
    tick(3); hit(5, SHADOW)
    tick(3); hit(5, SHADOW)
    T.truthy(DUI.DB.Character().dots.ticks[589], "learned from two that agree")
    Dots.Forget()
    stub.spells[589].desc = "A word of darkness that causes 1214 Shadow damage over 24 sec."
    cast(589)                        -- 8 ticks of about 151
    T.eq(Dots.Left("target"), 1214, "the whole new damage shows")
    tick(3); secretHit(SHADOW)
    T.eq(Dots.Left("target"), 1062, "a tick in a fight takes one share off, not the rest")
    stub.spells[589] = nil
end)

T.test("dots: a white hit off the rhythm is not a tick", function()
    local _, Dots = world()
    cast(REND)                       -- 25 over 15 sec: 5 ticks of 5
    tick(1.5); hit(5, PHYSICAL)      -- a melee swing between ticks
    T.eq(Dots.Left("target"), 25)
    tick(1.5); hit(5, PHYSICAL)      -- the real first tick, on the 3 sec rhythm
    T.eq(Dots.Left("target"), 20)
end)

T.test("dots: another school is never a tick", function()
    local _, Dots = world()
    cast(COR)
    tick(3); hit(10, 4)              -- a Fire hit right on the rhythm
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: a crit tick isn't learned as the normal size", function()
    local DUI, Dots = world()
    cast(COR)
    tick(3); hit(10, SHADOW)
    tick(3); hit(10, SHADOW)
    tick(3); hit(19, SHADOW, "CRITICAL")
    T.eq(Dots.Left("target"), 10)
    T.eq(DUI.DB.Character().dots.ticks[COR], 1, "the description's own size")
end)

T.test("dots: a dodge right after the cast takes the DoT back", function()
    local _, Dots = world()
    cast(REND)
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, PHYSICAL)
    T.isnil(Dots.Left("target"))
end)

-- A cat's white swing can miss in the same instant Rip lands. A finisher that
-- lands spends its combo points (the game sends a power event for them); one
-- that misses keeps them.
local function comboMoved() stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS") end

T.test("dots: a swing missing as Rip lands doesn't take Rip back", function()
    local _, Dots = world()
    cast(CLAW); hit(27, PHYSICAL)
    tick(1)
    cast(RIP); comboMoved()
    stub.FireEvent("UNIT_COMBAT", "target", "MISS", "", 0, PHYSICAL)
    T.eq(Dots.Left("target"), 42, "its points were spent: it landed")
end)

T.test("dots: Rip comes back when its points are spent after the swing's miss", function()
    local _, Dots = world()
    cast(CLAW); hit(27, PHYSICAL)
    tick(1)
    cast(RIP)
    stub.FireEvent("UNIT_COMBAT", "target", "MISS", "", 0, PHYSICAL)
    T.isnil(Dots.Left("target"), "dropped until it's known")
    comboMoved()
    T.eq(Dots.Left("target"), 42, "restored")
end)

T.test("dots: a Rip that really misses stays gone", function()
    local _, Dots = world()
    cast(CLAW); hit(27, PHYSICAL)
    tick(1)
    cast(RIP)
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, PHYSICAL)
    tick(1)
    comboMoved() -- a later change (a new builder) says nothing about Rip
    T.isnil(Dots.Left("target"))
end)

T.test("dots: Rake on a mob immune to bleeds leaves no DoT", function()
    local _, Dots = world()
    cast(RAKE)
    hit(19, PHYSICAL) -- the upfront hit lands
    stub.FireEvent("UNIT_COMBAT", "target", "IMMUNE", "", 0, PHYSICAL)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: an immune bleed reported before the cast event leaves no DoT", function()
    local _, Dots = world()
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", guid, RAKE)
    stub.FireEvent("UNIT_COMBAT", "target", "IMMUNE", "", 0, PHYSICAL)
    hit(19, PHYSICAL)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, RAKE)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: after Rake's hit lands, a swing's dodge is someone else's", function()
    local _, Dots = world()
    cast(RAKE)
    hit(19, PHYSICAL)
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, PHYSICAL)
    T.eq(Dots.Left("target"), 39)
end)

T.test("dots: two Shadow DoTs ticking the same amount at once both count", function()
    local _, Dots = world()
    cast(COR); cast(SIPHON)
    tick(3)
    hit(10, SHADOW); hit(10, SHADOW)
    T.eq(Dots.Left("target"), 30 + 9 * 10, "each took one tick (Siphon Life's seen at 10)")
end)

T.test("dots: one secret hit reported for target and plate feeds only one DoT", function()
    local _, Dots = world()
    stub.units.nameplate1 = stub.units.target
    cast(COR)
    tick(0.2); cast(SIPHON)
    tick(2.8)
    stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", stub.Secret(9), SHADOW)
    stub.FireEvent("UNIT_COMBAT", "nameplate1", "WOUND", "", stub.Secret(9), SHADOW)
    T.eq(Dots.Left("target"), 30 + 150, "Siphon Life's own tick is still to come")
end)

-- Where the client hides mobs' GUIDs (a restricted map), each mob is told
-- apart by its nameplate: the game's plate frame keeps its unit token.
local function hiddenGUIDs()
    stub.SetRestriction("Map", true)
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        stub.CheckPlateUnit(unit)
        for i = 1, 3 do
            local token = "nameplate" .. i
            if stub.units[token] and stub.units[token] == stub.units[unit] then return { unitToken = token } end
        end
    end }
end

T.test("dots: with GUIDs hidden, DoTs follow each mob's nameplate", function()
    local _, Dots = world()
    hiddenGUIDs()
    stub.units.nameplate1 = stub.units.target
    stub.units.nameplate2 = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    cast(COR)
    T.eq(Dots.Left("nameplate1"), 40, "the plate shows it")
    stub.units.target = stub.units.nameplate2
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    cast(COR)
    T.eq(Dots.Left("nameplate1"), 40, "tab-dotting keeps the first mob's")
    T.eq(Dots.Left("target"), 40)
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.isnil(Dots.Left("nameplate1"), "the token can go to another mob now")
    stub.SetRestriction("Map", false)
    _G.C_NamePlate = nil
end)

T.test("dots: with GUIDs hidden and no plate, only the target is tracked", function()
    local _, Dots = world()
    hiddenGUIDs()
    cast(COR)
    T.eq(Dots.Left("target"), 40)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.isnil(Dots.Left("target"))
    stub.SetRestriction("Map", false)
    _G.C_NamePlate = nil
end)

T.test("dots: with GUIDs hidden, a hit on your target's target asks no plate", function()
    local _, Dots = world()
    hiddenGUIDs()
    stub.units.targettarget = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    cast(COR)
    tick(3)
    T.noerror(function()
        stub.FireEvent("UNIT_COMBAT", "targettarget", "WOUND", "", stub.Secret(9), SHADOW)
    end)
    T.isnil(Dots.KeyOf("targettarget"), "a chained token can't be told apart")
    stub.units.targettarget = nil
    stub.SetRestriction("Map", false)
    _G.C_NamePlate = nil
end)

T.test("dots: a recast that misses keeps the one still running", function()
    local _, Dots = world()
    cast(COR)
    tick(3); hit(10, SHADOW)
    cast(COR)
    stub.FireEvent("UNIT_COMBAT", "target", "RESIST", "", 0, SHADOW)
    T.eq(Dots.Left("target"), 30)
end)

T.test("dots: a DoT that never ticks is dropped after three missed ticks", function()
    local _, Dots = world()
    cast(COR)
    tick(6.5)
    T.truthy(Dots.Left("target"), "two missed ticks keep it: finding the rhythm takes two")
    tick(3)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: the last tick is waited for even when it lands late, and ends it at once", function()
    local _, Dots = world()
    cast(COR)                        -- 4 ticks of 10, every 3 sec
    for _ = 1, 3 do tick(3); hit(10, SHADOW) end
    tick(3.8)
    T.eq(Dots.Left("target"), 10, "0.8 s past its time, the last tick still counts")
    tick(0.1); hit(10, SHADOW)
    T.isnil(Dots.Left("target"), "it landed: gone with it")
end)

T.test("dots: a last tick that never comes lets go half an interval on", function()
    local _, Dots = world()
    cast(COR)
    for _ = 1, 3 do tick(3); hit(10, SHADOW) end
    tick(4.6)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a tick that passes unseen redraws by the clock", function()
    local DUI, Dots = world()
    cast(COR)
    tick(3); hit(10, SHADOW)
    local fired = 0
    DUI.On("DotsChanged", function() fired = fired + 1 end)
    tick(3.5)                        -- the second tick never arrived
    T.eq(Dots.Left("target"), 20)
    T.truthy(fired > 0, "the shade shrinks with it")
end)

-- As recorded in a fight on Forever: action, flag and school are plain, and the
-- amount of every hit on a mob is secret.
local function wound(school, flag) stub.FireEvent("UNIT_COMBAT", "target", "WOUND", flag or "", stub.Secret(9), school) end

T.test("dots: with secret amounts a tick comes off the moment it lands, by school and time", function()
    local _, Dots = world()
    cast(REND)                       -- 25 over 15 sec: 5 ticks of 5
    for left = 20, 5, -5 do
        tick(3); wound(PHYSICAL)
        T.eq(Dots.Left("target"), left)
    end
    tick(3); wound(PHYSICAL)
    T.isnil(Dots.Left("target"), "gone with the last tick")
end)

T.test("dots: with secret amounts a DoT that keeps ticking is never dropped", function()
    local _, Dots = world()
    cast(COR)
    tick(3); wound(SHADOW)
    tick(3); wound(SHADOW)
    tick(3); wound(SHADOW)
    tick(2.9)
    T.eq(Dots.Left("target"), 10, "the last tick is still to come")
end)

T.test("dots: a blocked or glancing hit is a swing, never a bleed's tick", function()
    local _, Dots = world()
    cast(REND)
    tick(3); wound(PHYSICAL, "BLOCK_REDUCED")
    T.eq(Dots.Left("target"), 25)
    wound(PHYSICAL, "GLANCING")
    T.eq(Dots.Left("target"), 25)
    wound(PHYSICAL)
    T.eq(Dots.Left("target"), 20)
end)

T.test("dots: a swing just before a tick doesn't move the rhythm", function()
    local _, Dots = world()
    cast(REND)
    tick(2.6); wound(PHYSICAL)       -- taken for tick 1, since nothing tells them apart
    tick(0.4); wound(PHYSICAL)       -- the real one, so that slot is spent
    T.eq(Dots.Left("target"), 20)
    tick(3); wound(PHYSICAL)         -- 0.4 s off the swing, right on the DoT's rhythm
    T.eq(Dots.Left("target"), 15)
end)

T.test("dots: a hit of another school with a secret amount is no tick", function()
    local _, Dots = world()
    cast(COR)
    tick(3); wound(4)
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: with secret amounts a projectile DoT counts from its first tick", function()
    local _, Dots = world()
    stub.spells[1978] = { name = "Serpent Sting", desc = "Stings the target, causing 40 Nature damage over 15 sec." }
    cast(1978)                       -- 5 ticks of 8, the first 0.8 s late in flight
    tick(3.8); wound(8)
    T.eq(Dots.Left("target"), 32)
    tick(3); wound(8)
    tick(3); wound(8)
    tick(3); wound(8)
    tick(3); wound(8)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a DoT ends with its last tick", function()
    local _, Dots = world()
    cast(COR)
    for _ = 1, 4 do tick(3); hit(10, SHADOW) end
    tick(1)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: Agony ticks back-loaded (4 at half, 4 at one, 4 at one and a half)", function()
    local _, Dots = world()
    cast(AGONY)                      -- 96 over 24 sec: 12 ticks, average 8, every 2 sec
    T.eq(Dots.Left("target"), 96)
    for _ = 1, 4 do tick(2); hit(4, SHADOW) end
    T.eq(Dots.Left("target"), 80, "the light ticks went first")
end)

T.test("dots: Rip counts the combo points the builders gave", function()
    local _, Dots = world()
    stub.units.player.class = "DRUID"
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); hit(30, PHYSICAL)
    cast(RIP)
    T.eq(Dots.Left("target"), 90)
end)

-- Slice and Dice lasts by its points, secret in a fight: the Cooldown Manager asks
-- from the same cast event, before or after this file has heard it.
T.test("dots: a finisher's combo points can be asked from its own cast", function()
    local _, Dots = world()
    stub.combat = true
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); hit(30, PHYSICAL)
    T.eq(Dots.Combo(RIP), 2, "before the finisher: the count so far")
    cast(RIP)
    T.eq(Dots.Combo(RIP), 2, "just after: the points it used")
    stub.Advance(2)
    T.isnil(Dots.Combo(RIP), "later: spent, none counted")
    stub.combat = false
end)

T.test("dots: a builder that's dodged gives no point", function()
    local _, Dots = world()
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, PHYSICAL)
    stub.Advance(1)                  -- a global cooldown later
    cast(RIP)
    T.eq(Dots.Left("target"), 42, "one point counted")
end)

T.test("dots: a DoT goes on the mob it was sent at", function()
    local _, Dots = world()
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", guid, COR)
    stub.units.target = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, COR)
    T.isnil(Dots.Left("target"), "not on the new target")
    stub.units.nameplate1 = { name = "Kobold", reaction = 2, guid = "Creature-1" }
    T.eq(Dots.Left("nameplate1"), 40, "on the mob it was aimed at")
end)

T.test("dots: one hit reported for target and its plate counts once", function()
    local _, Dots = world()
    stub.units.nameplate1 = stub.units.target
    cast(COR)
    tick(3); hit(10, SHADOW, nil, "target"); hit(10, SHADOW, nil, "nameplate1")
    T.eq(Dots.Left("target"), 30)
end)

T.test("dots: skipped spells (area, heals) are never tracked", function()
    local _, Dots = world()
    cast(5740); cast(139); cast(686)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: secret payloads are skipped, never compared", function()
    local _, Dots = world()
    cast(COR)
    stub.Advance(3)
    T.noerror(function()
        stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", stub.Secret(10), stub.Secret(SHADOW))
        stub.FireEvent("UNIT_COMBAT", stub.Secret("target"), stub.Secret("WOUND"), "", 10, SHADOW)
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", stub.Secret("x"), stub.Secret(COR))
    end)
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: a secret target GUID still tracks the target", function()
    local _, Dots = world()
    stub.units.target.guid = stub.Secret("Creature-1")
    cast(COR)
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: DotsChanged fires on a cast and a tick, the ticker stops with nothing tracked", function()
    local DUI, Dots = world()
    -- Other parts of the core keep tickers of their own (the fade engine's).
    local function live()
        local c = 0
        for _, t in ipairs(stub.tickers) do if not t.cancelled then c = c + 1 end end
        return c
    end
    local before = live()
    local fired = 0
    DUI.On("DotsChanged", function() fired = fired + 1 end)
    cast(COR)
    T.eq(fired, 1)
    T.eq(live(), before + 1, "a ticker while a DoT runs")
    tick(3); hit(10, SHADOW)
    T.eq(fired, 2)
    Dots.Forget()
    T.eq(live(), before, "no ticker of ours left running")
end)

-- Plates redraw only the mob whose DoTs changed (Nameplates' Manager).
T.test("dots: DotsChanged names the one mob that changed", function()
    local DUI, Dots = world()
    local got = {}
    DUI.On("DotsChanged", function(key) got[#got + 1] = key end)
    cast(COR)
    T.eq(got[1], stub.units.target.guid, "a cast: its mob")
    tick(3); hit(10, SHADOW)
    T.eq(got[2], stub.units.target.guid, "a tick: its mob")
    Dots.Forget()
    T.eq(#got, 2, "Forget: every mob (nil key)")
end)

T.test("dots: nothing tracked while nobody wants it", function()
    local _, Dots = world()
    Dots.Want("unitframes", false)
    cast(COR)
    T.isnil(Dots.Left("target"))
    Dots.Want("nameplates", true)
    cast(COR)
    T.eq(Dots.Left("target"), 40)
end)

-- The Does It Die addon's public API (DoesItDie.GetRemainingDamage and its
-- callback), standing in for the counting here when installed.
local function doesItDie(left)
    local api = { API_VERSION = 1, owners = {} }
    function api.GetRemainingDamage(unit) return left[unit] or 0, left[unit] and 1 or 0 end
    function api.RegisterCallback(owner, fn) api.owners[owner] = fn end
    function api.UnregisterCallback(owner) api.owners[owner] = nil end
    return api
end

T.test("dots: with Does It Die installed its numbers are shown and the tracker here rests", function()
    -- The switch lives on the Nameplates page, so that module is loaded.
    local DUI = stub.Load{ nameplates = true, before = function()
        stub.units.player = { name = "Me", isPlayer = true, class = "WARLOCK", guid = "Player-1" }
        stub.units.target = { name = "Kobold", reaction = 2, guid = "Creature-1", health = 300, maxHealth = 300 }
        stub.spells = SPELLS
    end }
    local Dots = DUI.Dots
    Dots.Want("unitframes", true)
    Dots.Forget()
    local api = doesItDie({ target = 77 })
    _G.DoesItDie = api
    stub.FireEvent("ADDON_LOADED", "DoesItDie")
    T.truthy(api.owners.DaylightUI, "it calls back when its numbers change")
    T.eq(Dots.Left("target"), 77)
    cast(COR)
    T.eq(Dots.Left("target"), 77, "a cast here counts nothing")
    local got = {}
    DUI.On("DotsChanged", function(key) got[#got + 1] = key or "all" end)
    api.owners.DaylightUI("DOTS_CHANGED", "target")
    T.eq(got[1], stub.units.target.guid, "its callback redraws that mob")
    T.eq(DUI:Get("Nameplates", "dotsDoesItDie"), true, "on by default")
    DUI:Set("Nameplates", "dotsDoesItDie", false)
    T.isnil(api.owners.DaylightUI, "switched off: let go of it")
    cast(COR)
    T.eq(Dots.Left("target"), 40, "Daylight UI counts again")
    _G.DoesItDie = nil
end)

T.test("dots: the Cooldown Manager keeps its combo count while Does It Die counts DoTs", function()
    local DUI, Dots = world()
    _G.DoesItDie = doesItDie({})
    stub.FireEvent("ADDON_LOADED", "DoesItDie")
    Dots.Want("cdm", true)
    cast(CLAW)
    cast(RIP)
    T.eq(Dots.Combo(RIP), 1, "the builder's point is still counted")
    T.isnil(Dots.Left("target"), "the DoT numbers are Does It Die's")
    _G.DoesItDie = nil
    stub.FireEvent("ADDON_LOADED", "DoesItDie")
    Dots.Want("cdm", false)
end)

-- ---------------------------------------------------------------------
-- Learning real tick sizes from the game's damage meter after a fight
-- ---------------------------------------------------------------------

-- A fight in which spell is cast and its next `ticks` ticks land (their
-- amounts secret, as in every fight), then the fight ends and the meter says
-- what the spell really dealt.
local FIRE = 4
-- The saved factor for Corruption, nil while none was learned.
local function learnedCor(DUI)
    local d = DUI.DB.Character().dots
    return d and d.ticks and d.ticks[COR]
end
local function fight(Dots, id, school, interval, ticks, meterTotal)
    stub.EnterCombat()
    cast(id)
    for _ = 1, ticks do
        tick(interval)
        stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", stub.Secret(9), school)
    end
    stub.meter.spells = { { spellID = id, totalAmount = meterTotal } }
    stub.LeaveCombat()
    stub.RunTimers()
    Dots.Forget()
end

T.test("dots: after a fight the meter teaches a DoT's real size", function()
    local _, Dots = world()
    fight(Dots, COR, SHADOW, 3, 4, 80) -- the meter says 80 where the tooltip said 40
    cast(COR)
    T.eq(Dots.Left("target"), 80, "the next cast starts from twice the tooltip")
end)

T.test("dots: the upfront hit is split off before learning", function()
    local _, Dots = world()
    -- 11 upfront + 5 ticks of 4 = 31 by the tooltip; the meter's 62 is twice that.
    fight(Dots, IMMOLATE, FIRE, 3, 5, 62)
    cast(IMMOLATE)
    T.eq(Dots.Left("target"), 40, "ticks of 8, not the hit folded into them")
end)

T.test("dots: what was learned is kept per character and grows with the spell", function()
    local DUI, Dots = world()
    fight(Dots, COR, SHADOW, 3, 4, 80)
    T.eq(learnedCor(DUI), 2, "kept as a factor of the tooltip's share")
end)

T.test("dots: a second fight blends in, a fight with one tick teaches nothing", function()
    local _, Dots = world()
    fight(Dots, COR, SHADOW, 3, 4, 80)  -- factor 2 over 4 ticks
    fight(Dots, COR, SHADOW, 3, 4, 40)  -- factor 1 over 4 ticks
    cast(COR)
    T.eq(Dots.Left("target"), 60, "halfway, by ticks seen")
    Dots.Forget()
    fight(Dots, COR, SHADOW, 3, 1, 500)
    cast(COR)
    T.eq(Dots.Left("target"), 60, "one tick is too little to judge")
end)

T.test("dots: the meter is skipped when it can't match what was counted", function()
    local DUI, Dots = world()
    fight(Dots, COR, SHADOW, 3, 4, 1000) -- 25 times the tooltip: someone else's damage got in
    T.isnil(learnedCor(DUI), "far off the tooltip")
    -- A cast that never ticked here (out of sight, or the mob died first).
    stub.EnterCombat()
    cast(COR); tick(3); secretHit(SHADOW); tick(3); secretHit(SHADOW)
    stub.units.target = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    cast(COR)
    stub.meter.spells = { { spellID = COR, totalAmount = 60 } }
    stub.LeaveCombat(); stub.RunTimers()
    T.isnil(learnedCor(DUI), "a cast whose ticks weren't seen")
    -- A cast at nothing that can be told apart.
    Dots.Forget()
    stub.EnterCombat()
    cast(COR); tick(3); secretHit(SHADOW); tick(3); secretHit(SHADOW)
    stub.units.target = nil
    cast(COR)
    stub.meter.spells = { { spellID = COR, totalAmount = 40 } }
    stub.LeaveCombat(); stub.RunTimers()
    T.isnil(learnedCor(DUI), "a cast the meter counted but nothing here did")
end)

T.test("dots: a mob that dies takes its DoTs with it", function()
    local _, Dots = world()
    stub.units.nameplate1 = stub.units.target
    cast(COR)
    stub.units.target.dead = true
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a DoT that ticks on out of sight isn't learned from", function()
    local DUI, Dots = world()
    stub.EnterCombat()
    cast(COR)
    tick(3); secretHit(SHADOW); tick(3); secretHit(SHADOW)
    stub.units.target = nil -- tabbed away, no plate: its last ticks land unseen
    tick(3); tick(3); tick(1)
    stub.meter.spells = { { spellID = COR, totalAmount = 80 } }
    stub.LeaveCombat(); stub.RunTimers()
    T.isnil(learnedCor(DUI))
end)

T.test("dots: the meter is read once it's no longer secret", function()
    local DUI, Dots = world()
    stub.EnterCombat()
    cast(COR)
    for _ = 1, 4 do tick(3); secretHit(SHADOW) end
    stub.meter.spells = { { spellID = COR, totalAmount = stub.Secret(80) } } -- still secret for a moment
    stub.LeaveCombat()
    stub.RunTimers()
    T.isnil(learnedCor(DUI))
    stub.meter.spells = { { spellID = COR, totalAmount = 80 } }
    stub.RunTimers()
    T.eq(learnedCor(DUI), 2)
end)

-- ---------------------------------------------------------------------
-- Drawing (DotsDraw.lua)
-- ---------------------------------------------------------------------

local function bar()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 20)
    local b = CreateFrame("StatusBar", nil, f)
    b:SetAllPoints(f)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    return f, b
end

T.test("dots draw: secret health and max go straight into the bars", function()
    local _, Dots = world()
    local f, b = bar()
    local veil, skull = Dots.NewVeil(b), Dots.NewSkull(f, 16)
    local hp, max = stub.Secret(25), stub.Secret(300)
    stub.units.target.health, stub.units.target.maxHealth = hp, max
    cast(COR)
    T.truthy(Dots.Paint("target", veil, skull))
    T.eq(veil.bar.__max, max); T.eq(veil.bar.__value, 40)
    T.eq(skull.bar.__max, hp); T.eq(skull.bar.__value, 40)
    T.truthy(veil:IsShown()); T.truthy(skull:IsShown())
end)

T.test("dots draw: no DoTs or a dead target shows nothing", function()
    local _, Dots = world()
    local f, b = bar()
    local veil, skull = Dots.NewVeil(b), Dots.NewSkull(f, 16)
    T.falsy(Dots.Paint("target", veil, skull))
    T.falsy(veil:IsShown()); T.falsy(skull:IsShown())
    cast(COR)
    stub.units.target.dead = true
    T.falsy(Dots.Paint("target", veil, skull))
    T.falsy(veil:IsShown())
end)

T.test("dots draw: the veil hangs off the fill's moving edge and grows back into it", function()
    local _, Dots = world()
    local _, b = bar()
    local veil = Dots.NewVeil(b)
    Dots.LayoutVeil(veil, b, false)
    local p, rel, rp = veil.bar:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, b:GetStatusBarTexture()); T.eq(rp, "TOPRIGHT")
    T.truthy(veil.bar:GetReverseFill(), "grows leftward from the fill's right edge")
    Dots.LayoutVeil(veil, b, true)
    p, rel, rp = veil.bar:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rp, "TOPLEFT")
    T.falsy(veil.bar:GetReverseFill())
    T.truthy(veil:DoesClipChildren(), "never past the bar's start when lethal")
end)

T.test("dots draw: an angled fill angles both ends of the veil, and its line leans", function()
    local DUI, Dots = world()
    local _, b = bar()
    DUI.Style.AngleFill(b, "right", 6)
    local veil = Dots.NewVeil(b)
    Dots.LayoutVeil(veil, b, false)
    local masks = veil.bar:GetStatusBarTexture().__masks or {}
    T.eq(#masks, 2, "the fill's edge plus the trail at the damage's end")
    T.eq(masks[1], DUI.Style.GetFillMask(b))
    local off = veil.edge.__vertexOffsets
    T.eq(off[1][1], 6); T.eq(off[3][1], 6)
    -- A square fill: no masks, and the line upright again.
    DUI.Style.AngleFill(b, nil, 0)
    Dots.LayoutVeil(veil, b, false)
    T.eq(#(veil.bar:GetStatusBarTexture().__masks or {}), 0)
    T.eq(veil.edge.__vertexOffsets[1][1], 0)
end)

T.test("dots draw: a flipped fill edge flips the veil's back end and its line", function()
    local DUI, Dots = world()
    local _, b = bar()
    -- The fill's edge leans under: its bottom corner is ahead (\ on the right).
    DUI.Style.AngleFill(b, "right", 6, true)
    local veil = Dots.NewVeil(b)
    Dots.LayoutVeil(veil, b, false)
    local masks = veil.bar:GetStatusBarTexture().__masks or {}
    T.eq(#masks, 2)
    T.eq(masks[1], DUI.Style.GetFillMask(b))
    -- The back end is the same line turned round: the left end's cut image.
    T.eq(masks[2].__texture, DUI.MEDIA .. "mask-slant-l.png", "the damage's end leans the fill's way")
    -- The line's bottom moves out along the cut, its top stays.
    local off = veil.edge.__vertexOffsets
    T.eq(off[1][1], 0); T.eq(off[3][1], 0)
    T.eq(off[2][1], 6); T.eq(off[4][1], 6)
    -- Back to the usual lean: top out again, bottom back.
    DUI.Style.AngleFill(b, "right", 6)
    Dots.LayoutVeil(veil, b, false)
    off = veil.edge.__vertexOffsets
    T.eq(off[1][1], 6); T.eq(off[2][1], 0)
end)

T.test("dots draw: the skull rides the end of a long bar in a small window", function()
    local _, Dots = world()
    local f = bar()
    local skull = Dots.NewSkull(f, 16)
    T.truthy(skull:DoesClipChildren())
    T.eq(skull.bar:GetWidth(), Dots.SKULL_BAR)
    local p, rel, rp = skull.icon:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, skull.bar:GetStatusBarTexture()); T.eq(rp, "RIGHT")
end)

T.test("dots draw: a sample shows plain numbers, lethal fills the skull", function()
    local _, Dots = world()
    local f, b = bar()
    local veil, skull = Dots.NewVeil(b), Dots.NewSkull(f, 16)
    Dots.PaintSample(veil, skull, 100, 24, true)
    T.eq(veil.bar.__max, 100); T.eq(veil.bar.__value, 24)
    T.eq(skull.bar.__value, 1); T.truthy(skull:IsShown())
    Dots.PaintSample(veil, skull, 100, 24, false)
    T.falsy(skull:IsShown())
end)

-- ---------------------------------------------------------------------
-- Edge cases
-- ---------------------------------------------------------------------

T.test("dots: a secret-GUID target's DoTs don't carry over to the next target", function()
    local _, Dots = world()
    stub.units.target.guid = stub.Secret("Player-A")    -- an enemy player in a battleground
    cast(COR)
    T.eq(Dots.Left("target"), 40)
    stub.units.target = { name = "Bee", reaction = 2, guid = stub.Secret("Player-B"), health = 10, maxHealth = 300 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.isnil(Dots.Left("target"), "no false veil or skull on the new target")
end)

T.test("dots: a cast with no target is kept nowhere", function()
    local _, Dots = world()
    stub.units.target = nil
    cast(COR)
    stub.units.target = { name = "Bee", reaction = 2, guid = stub.Secret("Player-B"), health = 10, maxHealth = 300 }
    T.isnil(Dots.Left("target"))
end)

T.test("dots: an on-rhythm white hit far bigger than a bleed's tick isn't taken or kept", function()
    local DUI, Dots = world()
    cast(REND)                       -- 5 a tick
    tick(3); hit(60, PHYSICAL)       -- a white hit right on the rhythm
    T.eq(Dots.Left("target"), 25)
    T.isnil(DUI.DB.Character().dots.ticks[REND])
end)

T.test("dots: hits on your group's tokens cost no GUID read", function()
    local _, Dots = world()
    cast(COR)
    local real, reads = UnitGUID, 0
    _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
    for i = 1, 10 do
        stub.FireEvent("UNIT_COMBAT", "raid" .. i, "WOUND", "", 100, PHYSICAL)
        stub.FireEvent("UNIT_COMBAT", "party1", "WOUND", "", 100, PHYSICAL)
        stub.FireEvent("UNIT_COMBAT", "player", "WOUND", "", 100, PHYSICAL)
    end
    _G.UnitGUID = real
    T.eq(reads, 0)
end)

T.test("dots: a mouseover cast goes on the mob it was cast at, not the target", function()
    local _, Dots = world()
    stub.units.mouseover = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "Gnoll", guid, COR)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, COR)
    T.isnil(Dots.Left("target"), "the target (Kobold) has nothing")
    T.eq(Dots.Left("mouseover"), 40)
end)

T.test("dots: hits on mobs aren't read while nothing is cast or tracked", function()
    local _, Dots = world()
    local real, reads = UnitGUID, 0
    local function hits()
        reads = 0
        _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
        for _ = 1, 10 do stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", 100, PHYSICAL) end
        _G.UnitGUID = real
        return reads
    end
    T.eq(hits(), 0, "nothing cast yet")
    cast(COR)
    T.truthy(hits() > 0, "a DoT running hears them")
    tick(3); hit(10, SHADOW); tick(3); hit(10, SHADOW); tick(3); hit(10, SHADOW); tick(3); hit(10, SHADOW)
    tick(1)
    T.isnil(Dots.Left("target"))
    T.eq(hits(), 0, "the DoT ran out: deaf again")
end)

-- A heal, a mount, a direct hit: nothing to learn from the hits after it.
T.test("dots: a cast that's no DoT, finisher or builder hears no hits", function()
    local _, Dots = world()
    local function live()
        local c = 0
        for _, t in ipairs(stub.tickers) do if not t.cancelled then c = c + 1 end end
        return c
    end
    local before = live()
    local real, reads = UnitGUID, 0
    -- Still being cast (sent, not yet succeeded): the hits around it.
    for i, id in ipairs({ 139, 686, 5740 }) do
        stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-other" .. i, id)
    end
    _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
    for _ = 1, 10 do stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", 100, PHYSICAL) end
    _G.UnitGUID = real
    T.eq(reads, 0, "no GUID read for the hits while a heal or a direct hit is cast")
    T.eq(live(), before, "no ticker for them")
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a failed or interrupted cast stops hearing at once", function()
    local _, Dots = world()
    local real, reads = UnitGUID, 0
    for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-x", COR)
        stub.FireEvent(event, "player", "Cast-x", COR)
        _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
        reads = 0
        for _ = 1, 10 do stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", 100, PHYSICAL) end
        _G.UnitGUID = real
        T.eq(reads, 0, event .. ": the send is dropped, no hits read")
    end
    T.isnil(Dots.Left("target"))
end)
