# Probe für Bild in Bild (UzPip und Befehl „pip“ in helper/uzai-helper.ps1): C# 5 übersetzbar
# (Warnungen als Fehler), „front“ meldet nur, wer vorn liegt (Fenster, Prozess, Prozess des
# Spielfensters) – nur Zahlen hinein und heraus, keine Tasten, kein Fokuswechsel, nichts umgestellt.
# Fenster von Windows gibt es hier nicht; was Uzai mit der Antwort macht, prüft
# tests/logic_bild_in_bild.gd (Pip.unser_vorn).
#   pwsh -NoProfile -File tests/pip_cs.ps1 helper/uzai-helper.ps1   → „Ergebnis: alles ok“
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$fails = 0
function Check($cond, $what) {
    if ($cond) { "  ok   $what" } else { $script:fails++; "  FAIL $what" }
}

"Quelltext"
$code = [regex]::Match($src, "(?s)\n\`$script:PipSrc = @'\n(.*?)\n'@").Groups[1].Value
Check ($code.Length -gt 2000) ("UzPip-Block gefunden (" + $code.Length + " Zeichen)")
$cmd = [regex]::Match($src, "(?s)\nfunction Pip-Call\(\`$a\) \{(.*?)\n\}\n").Groups[1].Value
Check ($cmd.Length -gt 500) "Befehl „pip“ gefunden"
try {
    Add-Type -TypeDefinition $code -CompilerOptions @('-langversion:5', '-warnaserror') -ErrorAction Stop
    Check $true "UzPip übersetzt (C# 5, Warnungen als Fehler)"
} catch { Check $false ("UzPip: " + $_.Exception.Message) }

"Wer liegt vorn (front)"
$m = [UzPip].GetMethod('Front')
Check ($null -ne $m -and $m.ReturnType -eq [string] -and $m.GetParameters().Count -eq 1 -and $m.GetParameters()[0].ParameterType -eq [long]) "UzPip.Front(long) → Text"
$front = [regex]::Match($code, "(?s)public static string Front\(long gameHwnd\) \{(.*?)\n    \}").Groups[1].Value
Check ($front.Contains('GetForegroundWindow()') -and $front.Contains('GetWindowThreadProcessId(fg, out fp)') -and $front.Contains('IsWindow(g)')) "liest Vordergrund und Prozess, Spielfenster nur, wenn es eins ist"
foreach ($bad in @('SetForegroundWindow', 'SetWindowPos', 'ShowWindow', 'SetWindowLongPtr', 'SendInput', 'keybd_event', 'AttachThreadInput')) {
    Check (-not $front.Contains($bad)) "front stellt nichts um ($bad)"
}
$op = [regex]::Match($cmd, "(?s)'front' \{(.*?)\n        \}").Groups[1].Value
Check ($op.Contains('[long]$a.game') -and $op.Contains('[UzPip]::Front($g)') -and $op.Contains('ForEach-Object { [long]$_ }')) "Befehl: nur Zahlen hinein (Spielfenster) und heraus"
Check ($op.Contains('fg_hwnd = $f[0]') -and $op.Contains('fg_pid = $f[1]') -and $op.Contains('game_pid = $f[2]')) "Antwort { fg_hwnd, fg_pid, game_pid } wie Pip.unser_vorn sie liest"
Check ($cmd.Contains("default { throw")) "unbekannte op: Fehler statt Raten"

""
"Ergebnis: " + $(if ($fails -eq 0) { "alles ok" } else { "$fails Fehler" })
