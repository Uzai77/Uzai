"""Vorschau der Leiste in mpv ohne mpv: führt assets/mpv/uzai_osd.lua mit einem nachgebauten mpv
(lupa, LuaJIT) aus und zeichnet das Ergebnis mit libass (ffmpeg) auf ein Bild.

    pip install lupa imageio-ffmpeg
    curl -o assdraw.lua https://raw.githubusercontent.com/mpv-player/mpv/v0.39.0/player/lua/assdraw.lua
    python tools/osd_preview.py assets/mpv/uzai_osd.lua assdraw.lua bild.jpg assets/mpv/fonts \
        "$(python -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")" ausgabe/
"""
import json, subprocess, sys, os
try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.lua51 import LuaRuntime

lua_path, assdraw_path, bg, fonts, ffmpeg, out = sys.argv[1:7]
os.makedirs(out, exist_ok=True)
lua = LuaRuntime(unpack_returned_tuples=True)
state = {"t": 100.0, "data": "", "props": {}, "msgs": {}, "timers": []}

def to_lua(v):
    if isinstance(v, dict):
        t = lua.table()
        for k, x in v.items():
            t[k] = to_lua(x)
        return t
    if isinstance(v, list):
        t = lua.table()
        for i, x in enumerate(v):
            t[i + 1] = to_lua(x)
        return t
    return v

mp = lua.table()
def create_osd_overlay(fmt):
    ov = lua.table()
    ov.data = ""
    def update(self):
        state["data"] = self.data
    ov.update = update
    return ov
mp.create_osd_overlay = create_osd_overlay
mp.get_time = lambda: state["t"]
def observe(name, kind, cb):
    state["props"][name] = cb
mp.observe_property = observe
def reg(name, cb):
    state["msgs"][name] = cb
mp.register_script_message = reg
def timer(sec, cb):
    state["timers"].append(cb)
mp.add_periodic_timer = timer
utils = lua.table()
utils.parse_json = lambda s: to_lua(json.loads(s))
assdraw = lua.execute(open(assdraw_path, encoding="utf-8").read())
g = lua.globals()
g.__mp, g.__utils, g.__assdraw = mp, utils, assdraw
lua.execute("package.preload['mp'] = function() return __mp end; package.preload['mp.utils'] = function() return __utils end; package.preload['mp.assdraw'] = function() return __assdraw end")
lua.execute(open(lua_path, encoding="utf-8").read())

def prop(name, v):
    state["props"][name](name, v)
def msg(name, *args):
    state["msgs"][name](*args)
def tick():
    for cb in state["timers"]:
        cb()

def shot(name):
    tick()
    events = state["data"].split("\n") if state["data"] else []
    ass = ["[Script Info]", "ScriptType: v4.00+", "PlayResX: 1920", "PlayResY: 1080", "WrapStyle: 2", "", "[V4+ Styles]",
           "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
           "Style: Default,Uzai Sans,40,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1",
           "", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"]
    for e in events:
        ass.append("Dialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,," + e)
    p = os.path.join(out, name + ".ass")
    open(p, "w", encoding="utf-8").write("\n".join(ass) + "\n")
    png = os.path.join(out, name + ".png")
    r = subprocess.run([ffmpeg, "-v", "error", "-y", "-loop", "1", "-i", bg, "-vf",
                        "scale=1920:1080,ass=%s:fontsdir=%s" % (p, fonts), "-frames:v", "1", png], capture_output=True, text=True)
    print(name, "events:", len(events), r.stderr.strip()[:300])

# Zustand wie bei einem laufenden Video
for n, v in [("time-pos", 52.0), ("duration", 1532.0), ("pause", False), ("paused-for-cache", False), ("seeking", False),
             ("core-idle", False), ("eof-reached", False), ("speed", 1.0), ("demuxer-cache-time", 140.0)]:
    prop(n, v)
meta = {"title": "Ich habe 30 Jahre alte Konsolen auf dem Flohmarkt gekauft – und was dann passierte", "channel": "Speedrun Deutschland",
        "info": "512 Tsd. Aufrufe  ·  Gestern", "hue": 0.88, "next": "Final Fantasy X – kompletter Soundtrack, neu abgemischt",
        "segments": [[300, 330], [900, 960]], "accent": "F0C36A", "clock24": True,
        "hints": [["A", "Pause"], ["X", "Untertitel"], ["Y", "Optionen"], ["B", "Beenden"], ["LB", "Voriges"], ["RB", "Nächstes"]]}
msg("meta", json.dumps(meta))
msg("show", "4")
shot("01_leiste")
msg("seek", "+10 s")
state["t"] += 0.3
shot("02_spulen")
prop("pause", True)
msg("notice", "Sponsoren übersprungen", "3")
shot("03_pause")
prop("pause", False)
msg("hide")
state["t"] += 5
prop("paused-for-cache", True)
shot("04_laden")
prop("paused-for-cache", False)
msg("volume", "85")
shot("05_lautstaerke")
msg("endcard", "Final Fantasy X – kompletter Soundtrack, neu abgemischt", "8")
state["t"] += 3
shot("06_endkarte")
