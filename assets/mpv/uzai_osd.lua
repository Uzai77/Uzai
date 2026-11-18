-- Uzai-Anzeige über dem Video (mpv liegt vorn, Uzai steuert über die IPC-Pipe).
-- Zeichnet Uzais Player-Leiste mit ASS: Kanal, Titel, Als Nächstes, Fortschritt mit
-- SponsorBlock-Abschnitten, Zeiten, Tastenhinweise, Uhr, Hinweise, Spulen, Pause, Laden,
-- Endkarte. Uzai schickt nur, was mpv nicht selbst weiß (Titel, Kanal, Hinweise, Tasten);
-- Zeit, Pause und Puffer liest das Skript direkt aus mpv.
--
-- Nachrichten (script-message-to uzai_osd …):
--   meta <json>          { title, channel, info, hue, next, segments=[[s,e],…], hints=[[taste,text],…],
--                          accent="RRGGBB", clock24=true, pip=false, txt={…} }
--                        txt: die festen Texte der Leiste in der Sprache der Oberfläche (Video.osd_texts);
--                        fehlt einer, steht der deutsche da.
--                        pip = true: Bild in Bild – nur ein feiner Fortschritt unten, Pause und
--                        Laden groß in der Mitte (das Fenster ist klein, alles andere wäre Gekritzel).
--                        live = true: Live-Stream (Twitch) – „LIVE“ statt der Zeiten, kein „Endet um“.
--   show [sekunden]      Leiste zeigen (bei jeder Eingabe)
--   hide                 Leiste ausblenden
--   notice <text> [s]    Hinweis oben in der Mitte
--   seek <text>          Spulen-Blase („+10 s“) über dem Fortschritt
--   volume <0…130>       Lautstärke kurz anzeigen
--   endcard <titel> <s>  Endkarte mit Countdown (s < 0: angehalten, ohne Countdown)
--   endcard_hide
--   swipe <1|-1>         Shorts blättern: eine dunkle Fläche gleitet aus der Richtung herein, deckt
--                        den Wechsel ab und gibt das neue Video frei, sobald es läuft
--   covered <true|false> Ein Menü von Uzai liegt über dem Video (Guide, Optionen): nichts zeichnen,
--                        das Video bleibt hinter dem Menü zu sehen, ohne Titel und Balken

local mp = require 'mp'
local utils = require 'mp.utils'
local assdraw = require 'mp.assdraw'

local W, H = 1920, 1080
local GUTTER = 96
local ov = mp.create_osd_overlay("ass-events")
ov.res_x = W
ov.res_y = H

local meta = { title = "", channel = "", info = "", hue = 0.6, next = "", segments = {}, hints = {}, accent = "F0C36A", clock24 = true, pip = false }
local st = { pos = 0, dur = 0, pause = false, cache = false, seeking = false, buffered = 0, speed = 1, idle = true, eof = false }
local show_until = 0
local notice = { text = "", untilt = 0 }
local seekb = { text = "", untilt = 0 }
local vol = { value = -1, untilt = 0 }
local endc = { title = "", deadline = 0, total = 0, active = false }
local spin = 0
local last_ass = ""
local covered = false

local function now() return mp.get_time() end

-- Fester Text in der Sprache der Oberfläche (meta.txt), sonst der deutsche.
local function T(key, de)
	local t = type(meta.txt) == "table" and meta.txt[key] or nil
	return (type(t) == "string" and t ~= "") and t or de
end

-- Einen Wert für %s bzw. %d einsetzen (ohne string.format: eine Übersetzung ohne Platzhalter bricht nichts).
local function put(pattern, value)
	return (pattern:gsub("%%[sd]", function() return tostring(value) end, 1))
end

-- Farben: ASS will &HBBGGRR&. Eingabe "RRGGBB".
local function bgr(hex)
	hex = tostring(hex or "FFFFFF"):gsub("#", "")
	if #hex < 6 then hex = "FFFFFF" end
	return hex:sub(5, 6) .. hex:sub(3, 4) .. hex:sub(1, 2)
end

local function hsv_hex(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b
	i = i % 6
	if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
	elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
	return string.format("%02X%02X%02X", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Deckkraft 0…1 → ASS-Alpha (&H00& deckend, &HFF& unsichtbar).
local function alpha(a)
	a = math.max(0, math.min(1, a))
	return string.format("%02X", math.floor((1 - a) * 255 + 0.5))
end

local function esc(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\239\187\159"):gsub("{", "\\{"):gsub("}", "\\}"):gsub("\n", " ")
	return s
end

-- Zeichenbreiten von Uzai Sans (aus den Schriftdateien, in em): r normal, m mittel, b fett.
local WIDTHS = {
	r = { [32]=0.260, [33]=0.240, [34]=0.338, [35]=0.699, [36]=0.560, [37]=0.747, [38]=0.686, [39]=0.174, [40]=0.222, [41]=0.222, [42]=0.398, [43]=0.560, [44]=0.240, [45]=0.327, [46]=0.240, [47]=0.418, [48]=0.560, [49]=0.560, [50]=0.560, [51]=0.560, [52]=0.560, [53]=0.560, [54]=0.560, [55]=0.560, [56]=0.560, [57]=0.560, [58]=0.240, [59]=0.240, [60]=0.560, [61]=0.560, [62]=0.560, [63]=0.516, [64]=0.874, [65]=0.637, [66]=0.601, [67]=0.704, [68]=0.682, [69]=0.585, [70]=0.565, [71]=0.731, [72]=0.678, [73]=0.246, [74]=0.552, [75]=0.634, [76]=0.495, [77]=0.839, [78]=0.676, [79]=0.748, [80]=0.554, [81]=0.774, [82]=0.598, [83]=0.564, [84]=0.587, [85]=0.656, [86]=0.656, [87]=0.957, [88]=0.641, [89]=0.602, [90]=0.582, [91]=0.258, [92]=0.448, [93]=0.258, [94]=0.552, [95]=0.405, [96]=0.292, [97]=0.540, [98]=0.587, [99]=0.518, [100]=0.587, [101]=0.540, [102]=0.335, [103]=0.514, [104]=0.547, [105]=0.226, [106]=0.226, [107]=0.532, [108]=0.265, [109]=0.828, [110]=0.547, [111]=0.577, [112]=0.587, [113]=0.587, [114]=0.407, [115]=0.470, [116]=0.346, [117]=0.547, [118]=0.521, [119]=0.748, [120]=0.520, [121]=0.521, [122]=0.472, [123]=0.239, [124]=0.258, [125]=0.239, [126]=0.560, [228]=0.540, [246]=0.577, [252]=0.547, [196]=0.637, [214]=0.748, [220]=0.656, [223]=0.634, [233]=0.540, [232]=0.540, [225]=0.540, [224]=0.540, [237]=0.226, [243]=0.577, [250]=0.547, [241]=0.547, [231]=0.518, [8222]=0.387, [8220]=0.436, [8221]=0.438, [8218]=0.288, [8216]=0.263, [8217]=0.263, [8211]=0.412, [8212]=1.058, [8230]=0.668, [183]=0.334, [8364]=0.560, [176]=0.418, [215]=0.560 },
	m = { [32]=0.260, [33]=0.244, [34]=0.347, [35]=0.697, [36]=0.560, [37]=0.743, [38]=0.691, [39]=0.180, [40]=0.240, [41]=0.240, [42]=0.398, [43]=0.560, [44]=0.240, [45]=0.327, [46]=0.240, [47]=0.419, [48]=0.560, [49]=0.560, [50]=0.560, [51]=0.560, [52]=0.560, [53]=0.560, [54]=0.560, [55]=0.560, [56]=0.560, [57]=0.560, [58]=0.240, [59]=0.240, [60]=0.560, [61]=0.560, [62]=0.560, [63]=0.516, [64]=0.874, [65]=0.649, [66]=0.604, [67]=0.706, [68]=0.679, [69]=0.583, [70]=0.563, [71]=0.732, [72]=0.683, [73]=0.252, [74]=0.553, [75]=0.644, [76]=0.498, [77]=0.845, [78]=0.680, [79]=0.748, [80]=0.557, [81]=0.778, [82]=0.603, [83]=0.568, [84]=0.586, [85]=0.656, [86]=0.661, [87]=0.964, [88]=0.651, [89]=0.610, [90]=0.590, [91]=0.272, [92]=0.454, [93]=0.272, [94]=0.577, [95]=0.434, [96]=0.299, [97]=0.542, [98]=0.583, [99]=0.519, [100]=0.583, [101]=0.540, [102]=0.339, [103]=0.517, [104]=0.553, [105]=0.232, [106]=0.232, [107]=0.541, [108]=0.269, [109]=0.833, [110]=0.553, [111]=0.575, [112]=0.583, [113]=0.583, [114]=0.413, [115]=0.471, [116]=0.353, [117]=0.553, [118]=0.526, [119]=0.750, [120]=0.527, [121]=0.526, [122]=0.472, [123]=0.254, [124]=0.262, [125]=0.254, [126]=0.560, [228]=0.542, [246]=0.575, [252]=0.553, [196]=0.649, [214]=0.748, [220]=0.656, [223]=0.640, [233]=0.540, [232]=0.540, [225]=0.542, [224]=0.542, [237]=0.232, [243]=0.575, [250]=0.553, [241]=0.553, [231]=0.519, [8222]=0.404, [8220]=0.445, [8221]=0.446, [8218]=0.287, [8216]=0.265, [8217]=0.265, [8211]=0.417, [8212]=1.058, [8230]=0.676, [183]=0.325, [8364]=0.560, [176]=0.419, [215]=0.560 },
	b = { [32]=0.260, [33]=0.252, [34]=0.366, [35]=0.694, [36]=0.560, [37]=0.735, [38]=0.700, [39]=0.193, [40]=0.277, [41]=0.277, [42]=0.399, [43]=0.560, [44]=0.240, [45]=0.327, [46]=0.240, [47]=0.420, [48]=0.560, [49]=0.560, [50]=0.560, [51]=0.560, [52]=0.560, [53]=0.560, [54]=0.560, [55]=0.560, [56]=0.560, [57]=0.560, [58]=0.240, [59]=0.240, [60]=0.560, [61]=0.560, [62]=0.560, [63]=0.515, [64]=0.873, [65]=0.674, [66]=0.611, [67]=0.709, [68]=0.674, [69]=0.578, [70]=0.558, [71]=0.735, [72]=0.693, [73]=0.263, [74]=0.556, [75]=0.663, [76]=0.504, [77]=0.856, [78]=0.689, [79]=0.747, [80]=0.562, [81]=0.785, [82]=0.612, [83]=0.575, [84]=0.584, [85]=0.657, [86]=0.672, [87]=0.979, [88]=0.670, [89]=0.625, [90]=0.605, [91]=0.299, [92]=0.467, [93]=0.299, [94]=0.627, [95]=0.493, [96]=0.312, [97]=0.546, [98]=0.574, [99]=0.522, [100]=0.574, [101]=0.541, [102]=0.348, [103]=0.522, [104]=0.564, [105]=0.245, [106]=0.245, [107]=0.560, [108]=0.278, [109]=0.843, [110]=0.564, [111]=0.572, [112]=0.574, [113]=0.574, [114]=0.426, [115]=0.472, [116]=0.367, [117]=0.564, [118]=0.535, [119]=0.755, [120]=0.542, [121]=0.535, [122]=0.471, [123]=0.283, [124]=0.271, [125]=0.283, [126]=0.560, [228]=0.546, [246]=0.572, [252]=0.564, [196]=0.674, [214]=0.747, [220]=0.657, [223]=0.651, [233]=0.541, [232]=0.541, [225]=0.546, [224]=0.546, [237]=0.245, [243]=0.572, [250]=0.564, [241]=0.564, [231]=0.522, [8222]=0.437, [8220]=0.462, [8221]=0.463, [8218]=0.285, [8216]=0.270, [8217]=0.270, [8211]=0.428, [8212]=1.058, [8230]=0.692, [183]=0.308, [8364]=0.560, [176]=0.422, [215]=0.560 },
}

local function codepoints(s)
	local i, n = 1, #s
	return function()
		if i > n then return nil end
		local c = s:byte(i)
		local cp, len
		if c < 0x80 then cp, len = c, 1
		elseif c < 0xE0 then cp, len = (c % 0x20) * 0x40 + (s:byte(i + 1) or 0) % 0x40, 2
		elseif c < 0xF0 then cp, len = ((c % 0x10) * 0x40 + (s:byte(i + 1) or 0) % 0x40) * 0x40 + (s:byte(i + 2) or 0) % 0x40, 3
		else cp, len = 0x10000, 4 end
		i = i + len
		return cp
	end
end

-- Breite eines Textes in Pixeln (für Umbruch und rechtsbündige Blöcke).
local function text_w(s, px, weight)
	local tbl = WIDTHS[weight or "m"] or WIDTHS.m
	local w = 0
	for cp in codepoints(tostring(s or "")) do
		w = w + (tbl[cp] or (cp >= 0x2E80 and 1.0 or 0.56))
	end
	return w * px
end

-- Zeilen umbrechen (Wortgrenzen), höchstens n Zeilen, sonst mit „…“.
local function wrap(s, px, maxw, n, weight)
	local lines, cur = {}, ""
	for word in tostring(s or ""):gmatch("%S+") do
		local try = cur == "" and word or (cur .. " " .. word)
		if text_w(try, px, weight) <= maxw or cur == "" then
			cur = try
		else
			table.insert(lines, cur)
			cur = word
		end
	end
	if cur ~= "" then table.insert(lines, cur) end
	if #lines > n then
		local keep = {}
		for i = 1, n do keep[i] = lines[i] end
		local last = keep[n]
		while #last > 1 and text_w(last .. " …", px, weight) > maxw do
			last = last:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
		end
		keep[n] = last:gsub("%s+$", "") .. " …"
		lines = keep
	end
	return lines
end

local function ftime(t)
	t = math.max(0, math.floor(t or 0))
	local h, m, s = math.floor(t / 3600), math.floor(t / 60) % 60, t % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%d:%02d", m, s)
end

local function clock_text(t)
	local d = os.date("*t", t)
	if meta.clock24 ~= false then return string.format("%02d:%02d", d.hour, d.min) end
	local h = d.hour % 12
	if h == 0 then h = 12 end
	return string.format("%d:%02d %s", h, d.min, d.hour >= 12 and "PM" or "AM")
end

-- --- Zeichnen ---------------------------------------------------------------------------------

local function ev(a, tags)
	a:new_event()
	a:append("{\\an7\\pos(0,0)\\bord0\\shad0\\blur0" .. (tags or "") .. "}")
end

local function rect(a, x0, y0, x1, y1, col, al, r, tags)
	ev(a, "\\1c&H" .. col .. "&\\1a&H" .. al .. "&" .. (tags or ""))
	a:draw_start()
	if r and r > 0 then a:round_rect_cw(x0, y0, x1, y1, r) else a:rect_cw(x0, y0, x1, y1) end
	a:draw_stop()
end

local function circle(a, cx, cy, r, col, al, tags)
	rect(a, cx - r, cy - r, cx + r, cy + r, col, al, r, tags)
end

local function text(a, x, y, s, font, px, col, al, an, tags)
	a:new_event()
	a:append(string.format("{\\an%d\\pos(%d,%d)\\bord0\\shad0\\fn%s\\fs%d\\1c&H%s&\\1a&H%s&%s}%s",
		an or 7, math.floor(x + 0.5), math.floor(y + 0.5), font, math.floor(px + 0.5), col, al, tags or "", esc(s)))
end

-- Weicher Verlauf (ASS kennt keine Verläufe): mehrere weich gezeichnete Flächen übereinander,
-- jede etwas tiefer beginnend. Unten summiert sich die Deckkraft auf „op“.
local function shade(a, y_top, op, from_top)
	local n = 8
	local p = 1 - (1 - op) ^ (1 / n)
	for i = 0, n - 1 do
		local k = i / n
		if from_top then
			rect(a, -80, -260, W + 80, y_top * (1 - k * 0.92), "000000", alpha(p), 0, "\\blur34")
		else
			rect(a, -80, y_top + (H - y_top) * k * 0.92, W + 80, H + 260, "000000", alpha(p), 0, "\\blur34")
		end
	end
end

local WHITE, INK = "FFFFFF", "E7EFF3"       -- INK: warmes Weiß (BGR von F3EFE7)
local MUTED = "C3C9CC"

local function glyph_w(key)
	if key == "ud" or key == "mn" then return 30 end
	return (#key > 1) and 44 or 30
end

local function tri(a, x0, y0, x1, y1, x2, y2, col, al)
	ev(a, "\\1c&H" .. col .. "&\\1a&H" .. al .. "&")
	a:draw_start()
	a:move_to(x0, y0)
	a:line_to(x1, y1)
	a:line_to(x2, y2)
	a:draw_stop()
end

local function draw_glyph(a, x, y, key)
	-- Taste als kleine dunkle Scheibe mit Zeichen (wie Uzais Hinweisleiste).
	local w = glyph_w(key)
	rect(a, x, y, x + w, y + 30, "FFFFFF", alpha(0.15), 15)
	if key == "ud" then
		-- Steuerkreuz hoch/runter (Lautstärke): zwei Spitzen, die Schrift hat keine Pfeile.
		local cx, cy = x + w / 2, y + 15
		tri(a, cx, cy - 11, cx + 6, cy - 2, cx - 6, cy - 2, INK, "00")
		tri(a, cx, cy + 11, cx - 6, cy + 2, cx + 6, cy + 2, INK, "00")
		return w
	end
	if key == "mn" then
		-- Start-/Options-Taste (≡): drei kurze Striche.
		local cx, cy = x + w / 2, y + 15
		for i = -1, 1 do rect(a, cx - 7, cy + i * 5 - 1, cx + 7, cy + i * 5 + 1, INK, "00", 1) end
		return w
	end
	text(a, x + w / 2, y + 15, key, "Uzai Sans Bold", (#key > 1) and 14 or 16, INK, "00", 5)
	return w
end

local function draw_hints(a, y)
	local items = meta.hints or {}
	if #items == 0 then return end
	-- Von rechts nach links aufbauen, damit der Block rechtsbündig mit dem Rand abschließt.
	local x = W - GUTTER
	for i = #items, 1, -1 do
		local key, label = tostring(items[i][1] or ""), tostring(items[i][2] or "")
		x = x - text_w(label, 20, "m")
		text(a, x, y + 15, label, "Uzai Sans Medium", 20, MUTED, "10", 4)
		x = x - 10 - glyph_w(key)
		draw_glyph(a, x, y, key)
		x = x - 28
	end
end

local function bar_rect()
	return 210, 912, W - 210, 918
end

local function draw_bar(a)
	local x0, y0, x1, y1 = bar_rect()
	if meta.live then
		-- Live (Twitch, meta.live): kein Spulen – ein ruhiger, voller Balken und „LIVE“ statt der Zeiten.
		local cy = (y0 + y1) / 2
		rect(a, x0, y0, x1, y1, "FFFFFF", alpha(0.34), 3)
		rect(a, GUTTER, cy - 17, GUTTER + 84, cy + 17, "4848E0", "00", 9)
		text(a, GUTTER + 42, cy, "LIVE", "Uzai Sans Bold", 20, WHITE, "00", 5, "\\fsp1.5")
		return
	end
	local dur = st.dur > 0 and st.dur or 0
	local k = dur > 0 and math.max(0, math.min(1, st.pos / dur)) or 0
	local kb = dur > 0 and math.max(k, math.min(1, st.buffered / dur)) or 0
	rect(a, x0, y0, x1, y1, "FFFFFF", alpha(0.22), 3)
	if kb > k then rect(a, x0, y0, x0 + (x1 - x0) * kb, y1, "FFFFFF", alpha(0.34), 3) end
	-- SponsorBlock-Abschnitte: hell, damit sie nicht wie ein zweiter Füllstand wirken.
	if dur > 0 then
		for _, sg in ipairs(meta.segments or {}) do
			local s0, s1 = tonumber(sg[1]) or 0, tonumber(sg[2]) or 0
			if s1 > s0 then
				rect(a, x0 + (x1 - x0) * (s0 / dur), y0, x0 + (x1 - x0) * math.min(1, s1 / dur), y1, "FFFFFF", alpha(0.62), 2)
			end
		end
	end
	local xk = x0 + (x1 - x0) * k
	if k > 0 then rect(a, x0, y0, xk, y1, INK, "00", 3) end
	circle(a, xk, (y0 + y1) / 2, 15, "000000", alpha(0.35), "\\blur4")
	circle(a, xk, (y0 + y1) / 2, 11, INK, "00")
	text(a, GUTTER, (y0 + y1) / 2, ftime(st.pos), "Uzai Sans Medium", 24, INK, "00", 4)
	text(a, W - GUTTER, (y0 + y1) / 2, dur > 0 and ftime(dur) or "–:––", "Uzai Sans Medium", 24, MUTED, "00", 6)
	-- Spulen-Blase über dem Knopf: Zeit und Sprung in Gold.
	if seekb.untilt > now() and seekb.text ~= "" then
		local t1, t2 = ftime(st.pos), seekb.text
		local bw = text_w(t1, 22, "b") + text_w(t2, 20, "b") + 58
		local bx = math.max(x0 - 20, math.min(x1 - bw + 20, xk - bw / 2))
		local by = y0 - 58
		rect(a, bx, by, bx + bw, by + 42, "1E1D1C", alpha(0.94), 21)
		text(a, bx + 22, by + 21, t1, "Uzai Sans Bold", 22, INK, "00", 4)
		text(a, bx + 22 + text_w(t1, 22, "b") + 14, by + 21, t2, "Uzai Sans Bold", 20, bgr(meta.accent), "00", 4)
	end
end

local function draw_info(a)
	-- Kanal · Aufrufe · Alter
	local y = 676
	local x = GUTTER
	if meta.channel ~= "" then
		circle(a, x + 16, y + 16, 16, bgr(hsv_hex(tonumber(meta.hue) or 0.6, 0.45, 0.62)), "00")
		local initial = meta.channel:match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
		text(a, x + 16, y + 16, initial:upper(), "Uzai Sans Bold", 16, WHITE, "00", 5)
		x = x + 46
	end
	local line = ""
	if meta.channel ~= "" then line = "{\\fnUzai Sans Medium\\1c&H" .. INK .. "&}" .. esc(meta.channel) end
	if meta.info ~= "" then
		line = line .. "{\\fnUzai Sans\\1c&H" .. MUTED .. "&}" .. (meta.channel ~= "" and "   ·   " or "") .. esc(meta.info)
	end
	if line ~= "" then
		a:new_event()
		a:append(string.format("{\\an4\\pos(%d,%d)\\bord0\\shad0\\fs24}", x, y + 16) .. line)
	end
	-- Titel groß, höchstens zwei Zeilen.
	local lines = wrap(meta.title, 54, 1180, 2, "b")
	local ty = 714
	for i, l in ipairs(lines) do
		text(a, GUTTER, ty + (i - 1) * 62, l, "Uzai Sans Bold", 54, WHITE, "00", 7)
	end
	-- Als Nächstes (rechts, ohne Bild): kleine Überschrift, Titel in zwei Zeilen.
	if meta.next and meta.next ~= "" then
		local nx = W - GUTTER
		text(a, nx, 742, T("next", "ALS NÄCHSTES"), "Uzai Sans Bold", 16, bgr(meta.accent), "00", 9, "\\fsp1.5")
		local nl = wrap(meta.next, 24, 470, 2, "m")
		for i, l in ipairs(nl) do
			text(a, nx, 770 + (i - 1) * 31, l, "Uzai Sans Medium", 24, INK, "00", 9)
		end
	end
end

local function draw_head(a, osc_k)
	-- Oben rechts: Uhr und „Endet um …“ bzw. „Pausiert“.
	local t = os.time()
	text(a, W - GUTTER, 52, clock_text(t), "Uzai Sans Bold", 34, INK, alpha(osc_k), 9)
	local sub = ""
	if st.pause then sub = T("paused", "Pausiert")
	elseif meta.live then sub = T("live", "Live")
	elseif st.dur > 0 then sub = put(T("ends", "Endet um %s"), clock_text(t + math.max(0, st.dur - st.pos) / math.max(0.1, st.speed))) end
	if sub ~= "" then text(a, W - GUTTER, 92, sub, "Uzai Sans Medium", 20, MUTED, alpha(osc_k * 0.9), 9) end
end

local function draw_notice(a)
	if notice.untilt <= now() or notice.text == "" then return end
	local left = notice.untilt - now()
	local k = math.min(1, left / 0.35)
	local w = text_w(notice.text, 22, "m") + 60
	local x = (W - w) / 2
	rect(a, x, 40, x + w, 88, "222120", alpha(0.94 * k), 24)
	text(a, W / 2, 64, notice.text, "Uzai Sans Medium", 22, INK, alpha(k), 5)
end

local function draw_volume(a)
	if vol.untilt <= now() or vol.value < 0 then return end
	local k = math.min(1, (vol.untilt - now()) / 0.35)
	local x, y = W - GUTTER - 320, 140
	rect(a, x, y, x + 320, y + 56, "222120", alpha(0.94 * k), 28)
	text(a, x + 28, y + 28, T("volume", "Lautstärke"), "Uzai Sans Medium", 20, MUTED, alpha(k), 4)
	local bx0, bx1 = x + 150, x + 260
	rect(a, bx0, y + 25, bx1, y + 31, "FFFFFF", alpha(0.22 * k), 3)
	rect(a, bx0, y + 25, bx0 + (bx1 - bx0) * math.min(1, vol.value / 130), y + 31, INK, alpha(k), 3)
	text(a, x + 296, y + 28, tostring(vol.value), "Uzai Sans Bold", 20, INK, alpha(k), 6)
end

local function draw_center(a)
	local cx, cy = W / 2, H / 2
	if st.cache or st.seeking or (st.idle and not st.pause and not st.eof) then
		-- Laden: zwölf Punkte im Kreis, der hellste läuft herum.
		for i = 0, 11 do
			local ang = (i / 12) * 2 * math.pi + spin
			local d = (12 - i) / 12
			circle(a, cx + math.cos(ang) * 34, cy + math.sin(ang) * 34, 5, INK, alpha(0.15 + 0.85 * d * d))
		end
	elseif st.pause and not endc.active then
		circle(a, cx, cy, 58, "000000", alpha(0.5))
		rect(a, cx - 17, cy - 22, cx - 5, cy + 22, INK, "00", 3)
		rect(a, cx + 5, cy - 22, cx + 17, cy + 22, INK, "00", 3)
	end
end

local function draw_end(a)
	if not endc.active then return end
	local w, h = 980, 190
	local x, y = (W - w) / 2, H - 470
	rect(a, x, y, x + w, y + h, "1B1A19", alpha(0.95), 30, "")
	text(a, x + 44, y + 40, endc.title ~= "" and T("next", "ALS NÄCHSTES") or T("ended", "VIDEO ZU ENDE"), "Uzai Sans Bold", 16, bgr(meta.accent), "00", 7, "\\fsp1.5")
	local tl = wrap(endc.title ~= "" and endc.title or meta.title, 38, w - 88, 1, "b")
	text(a, x + 44, y + 68, tl[1] or "", "Uzai Sans Bold", 38, WHITE, "00", 7)
	local sub
	if endc.deadline > 0 then
		local left = math.max(0, math.ceil(endc.deadline - now()))
		sub = put(T("countdown", "Startet in %d s  ·  A jetzt  ·  B abbrechen"), left)
		local total = endc.total > 0 and endc.total or 8
		local k = 1 - math.max(0, math.min(1, (endc.deadline - now()) / total))
		rect(a, x + 44, y + h - 30, x + w - 44, y + h - 25, "FFFFFF", alpha(0.18), 3)
		rect(a, x + 44, y + h - 30, x + 44 + (w - 88) * k, y + h - 25, bgr(meta.accent), "00", 3)
	else
		sub = endc.title ~= "" and T("play", "A abspielen  ·  B beenden") or T("again", "A nochmal  ·  B beenden")
	end
	text(a, x + 44, y + 122, sub, "Uzai Sans Medium", 22, MUTED, "00", 7)
end

-- Bild in Bild: unten ein feiner Fortschritt über die ganze Breite, Pause und Laden groß.
local function render_pip(a)
	if meta.live then
		-- Live-Stream: kein Fortschritt, oben links groß „LIVE“ (das Fenster ist klein).
		rect(a, 60, 60, 300, 156, "4848E0", "00", 24)
		text(a, 180, 108, "LIVE", "Uzai Sans Bold", 56, WHITE, "00", 5, "\\fsp3")
	else
		local dur = st.dur > 0 and st.dur or 0
		local k = dur > 0 and math.max(0, math.min(1, st.pos / dur)) or 0
		rect(a, 0, H - 16, W, H, "FFFFFF", alpha(0.22), 0)
		if k > 0 then rect(a, 0, H - 16, W * k, H, bgr(meta.accent), "00", 0) end
	end
	local cx, cy = W / 2, H / 2
	if st.cache or st.seeking or (st.idle and not st.pause and not st.eof) then
		for i = 0, 11 do
			local ang = (i / 12) * 2 * math.pi + spin
			local d = (12 - i) / 12
			circle(a, cx + math.cos(ang) * 96, cy + math.sin(ang) * 96, 14, INK, alpha(0.15 + 0.85 * d * d))
		end
	elseif st.pause then
		circle(a, cx, cy, 150, "000000", alpha(0.5))
		rect(a, cx - 44, cy - 58, cx - 13, cy + 58, INK, "00", 8)
		rect(a, cx + 13, cy - 58, cx + 44, cy + 58, INK, "00", 8)
	end
	if notice.untilt > now() and notice.text ~= "" then
		local left = notice.untilt - now()
		local nk = math.min(1, left / 0.35)
		local w = text_w(notice.text, 64, "m") + 140
		local x = (W - w) / 2
		rect(a, x, 60, x + w, 196, "222120", alpha(0.94 * nk), 68)
		text(a, W / 2, 128, notice.text, "Uzai Sans Medium", 64, INK, alpha(nk), 5)
	end
end

-- Shorts blättern: Die Fläche gleitet wie das nächste Short im Feed herein (SW_IN) und deckt den
-- Wechsel ab – vorher stand das alte Bild still, dann kam kurz Schwarz. Sobald das neue Video
-- läuft, gleitet sie zur anderen Seite hinaus (SW_OUT); lädt es nicht, spätestens nach SW_MAX.
local swipe = { dir = 0, t0 = 0, out = 0, loaded = false }
local SW_IN, SW_OUT, SW_MAX = 0.16, 0.24, 8
local COVER = bgr("0F1115")
local function ease_out(k) return 1 - (1 - k) ^ 3 end

local function draw_swipe(a)
	if swipe.dir == 0 then return end
	local t = now()
	if swipe.out == 0 and t - swipe.t0 > SW_MAX then swipe.out = t end
	local y
	if swipe.out > 0 and t >= swipe.out then
		local k = math.min(1, (t - swipe.out) / SW_OUT)
		if k >= 1 then
			swipe.dir = 0
			return
		end
		y = -swipe.dir * H * ease_out(k)
	else
		y = swipe.dir * H * (1 - ease_out(math.min(1, (t - swipe.t0) / SW_IN)))
	end
	local y0, y1 = math.max(0, y), math.min(H, y + H)
	if y1 > y0 then rect(a, 0, y0, W, y1, COVER, "00") end
end

local function render()
	local t = now()
	if meta.pip then
		local ap = assdraw.ass_new()
		render_pip(ap)
		if ap.text ~= last_ass then
			last_ass = ap.text
			ov.data = ap.text
			ov:update()
		end
		return
	end
	-- Ein Menü von Uzai liegt darüber: nur das Video, nichts von der Leiste (das Gleiten beim
	-- Blättern ausgenommen, es deckt einen Wechsel ab).
	if covered and swipe.dir == 0 then
		if last_ass ~= "" then
			last_ass = ""
			ov.data = ""
			ov:update()
		end
		return
	end
	local osc = show_until > t or st.pause or endc.active
	local a = assdraw.ass_new()
	draw_swipe(a)
	if osc then
		local fade = st.pause and 1 or math.min(1, (show_until - t) / 0.4)
		if endc.active then fade = 1 end
		shade(a, 600, 0.84 * fade, false)
		shade(a, 190, 0.5 * fade, true)
		if not endc.active then
			draw_info(a)
		end
		draw_bar(a)
		draw_hints(a, 1000)
		draw_head(a, fade)
	end
	draw_center(a)
	draw_notice(a)
	draw_volume(a)
	draw_end(a)
	local out = a.text
	if out ~= last_ass then
		last_ass = out
		ov.data = out
		ov:update()
	end
end

-- --- Zustand aus mpv ---------------------------------------------------------------------------

local function num(v, d) return tonumber(v) or d end
mp.observe_property("time-pos", "number", function(_, v) st.pos = num(v, 0) end)
mp.observe_property("duration", "number", function(_, v) st.dur = num(v, 0) end)
mp.observe_property("pause", "bool", function(_, v) st.pause = v == true; render() end)
mp.observe_property("paused-for-cache", "bool", function(_, v) st.cache = v == true end)
mp.observe_property("seeking", "bool", function(_, v) st.seeking = v == true end)
mp.observe_property("core-idle", "bool", function(_, v) st.idle = v == true end)
mp.observe_property("eof-reached", "bool", function(_, v) st.eof = v == true end)
mp.observe_property("speed", "number", function(_, v) st.speed = num(v, 1) end)
mp.observe_property("demuxer-cache-time", "number", function(_, v) st.buffered = num(v, 0) end)

mp.register_script_message("meta", function(json)
	local m = utils.parse_json(json or "")
	if type(m) == "table" then
		for k, v in pairs(m) do meta[k] = v end
	end
	render()
end)
mp.register_script_message("show", function(sec)
	show_until = now() + num(sec, 3.5)
	render()
end)
mp.register_script_message("hide", function()
	show_until = 0
	render()
end)
mp.register_script_message("covered", function(v)
	covered = v == "true" or v == "yes"
	render()
end)
mp.register_script_message("notice", function(t, sec)
	notice.text = t or ""
	notice.untilt = now() + num(sec, 2.2)
	render()
end)
mp.register_script_message("seek", function(t)
	seekb.text = t or ""
	seekb.untilt = now() + 1.2
	show_until = math.max(show_until, now() + 3.5)
	render()
end)
mp.register_script_message("volume", function(v)
	vol.value = num(v, -1)
	vol.untilt = now() + 1.4
	render()
end)
mp.register_script_message("endcard", function(title, sec)
	local s = num(sec, -1)
	endc.active = true
	endc.title = title or ""
	endc.total = s > 0 and s or 0
	endc.deadline = s > 0 and (now() + s) or 0
	render()
end)
mp.register_script_message("endcard_hide", function()
	endc.active = false
	render()
end)

-- Während des Gleitens 60-mal pro Sekunde zeichnen (sonst zehnmal).
local fast
fast = mp.add_periodic_timer(1 / 60, function()
	render()
	if swipe.dir == 0 then fast:kill() end
end)
fast:kill()
mp.register_script_message("swipe", function(d)
	swipe.dir = num(d, 1) < 0 and -1 or 1
	swipe.t0 = now()
	swipe.out = 0
	swipe.loaded = false
	fast:resume()
end)
mp.register_event("file-loaded", function()
	if swipe.dir ~= 0 then swipe.loaded = true end
end)
mp.register_event("playback-restart", function()
	if swipe.dir ~= 0 and swipe.loaded and swipe.out == 0 then
		swipe.out = math.max(now(), swipe.t0 + SW_IN)
	end
end)

-- Laufend nachzeichnen, solange sich etwas bewegt (Zeit, Uhr, Laden, Countdown).
mp.add_periodic_timer(0.1, function()
	spin = (spin + 0.55) % (2 * math.pi)
	render()
end)
