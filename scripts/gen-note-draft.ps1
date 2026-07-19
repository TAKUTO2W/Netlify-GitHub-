# ===================================================
# CARJAM note用下書き自動生成
# 毎週金曜の朝、直近2週間のイベントまとめ記事の下書きを
# note-drafts\ に生成してメモ帳で開く（投稿は手動コピペ）。
# daily-run.ps1 から毎朝呼ばれる。テストは -Force で曜日ゲートを無視。
# ===================================================
param([switch]$Force)

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

# ---- 金曜ゲート ----
if (-not $Force -and (Get-Date).DayOfWeek -ne 'Friday') {
    exit 0
}

# ---- イベント読み込み ----
$events = @()
$raw = Get-Content "$PROJECT_ROOT\data\new-events.js" -Raw -Encoding UTF8
if ($raw -match 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') {
    $events += @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_ })
}
$events += @((Get-Content "$PROJECT_ROOT\data\legacy-events.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })

$today = (Get-Date).Date
$until = $today.AddDays(13)
$jpDow = @("日","月","火","水","木","金","土")

$selected = @()
$seen = @{}
foreach ($e in $events) {
    if (-not ($e.date -and $e.name)) { continue }
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($e.date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
    if ($d -lt $today -or $d -gt $until) { continue }
    if ($seen.ContainsKey($e.name)) { continue }
    # 明らかにイベントでないゴミデータを除外（収集元の誤爆対策）
    if ($e.name.Length -gt 40 -or $e.name -match '掲示板|募集・無料掲載|個展') { continue }
    $seen[$e.name] = $true
    $selected += ,([PSCustomObject]@{ date = $d; name = $e.name; pref = $e.prefecture; venue = $e.venue })
}
$selected = @($selected | Sort-Object date, pref)

if ($selected.Count -eq 0) {
    Write-Log "note下書き: 対象期間にイベントがないためスキップ"
    exit 0
}

# ---- 下書き組み立て ----
$sb = New-Object System.Text.StringBuilder
$titleRange = "{0}/{1}〜{2}/{3}" -f $today.Month, $today.Day, $until.Month, $until.Day
[void]$sb.AppendLine("■アイキャッチ画像（noteの「画像をアップロード」でこれを選ぶ）")
[void]$sb.AppendLine("$PROJECT_ROOT\images\note-eyecatch.jpg")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("■タイトル案（1行目をコピー）")
[void]$sb.AppendLine("【$titleRange】今週末〜来週の全国カーイベントまとめ")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("■本文（ここから下を全部コピー。※変なイベント名があれば削ってから投稿）")
[void]$sb.AppendLine("----------------------------------------")
[void]$sb.AppendLine("こんにちは。日本全国のカーイベント情報を集約しているサイト「CARJAM」です。")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("直近2週間に開催予定のカーイベントを、CARJAM掲載データからまとめて紹介します。")
[void]$sb.AppendLine("")

$byDate = $selected | Group-Object { $_.date.ToString("yyyy-MM-dd") }
foreach ($g in $byDate) {
    $d = $g.Group[0].date
    [void]$sb.AppendLine(("## {0}/{1}（{2}）" -f $d.Month, $d.Day, $jpDow[[int]$d.DayOfWeek]))
    $shown = @($g.Group | Select-Object -First 6)
    foreach ($e in $shown) {
        $place = if ($e.pref -and $e.pref -ne "未定") { $e.pref } else { "" }
        if ($e.venue -and $e.venue -ne "未定") {
            $place = if ($place) { "$place・$($e.venue)" } else { $e.venue }
        }
        if ($place) { [void]$sb.AppendLine("・$($e.name)（$place）") }
        else        { [void]$sb.AppendLine("・$($e.name)") }
    }
    $rest = $g.Group.Count - $shown.Count
    if ($rest -gt 0) { [void]$sb.AppendLine("ほか $rest 件") }
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine("## 全国190件以上を掲載中")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("ここに載せたのは一部です。CARJAMでは全国のカーイベントを都道府県・カテゴリ・日付で検索できます。毎朝9時に自動更新しているので、お出かけ前にチェックしてみてください。")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("CARJAM: https://carjam-usdm.netlify.app")
[void]$sb.AppendLine("X: https://x.com/carjam_usdm （2日に1回、直近イベントを発信中）")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("※開催情報は変更される場合があります。お出かけ前に各イベントの公式情報をご確認ください。")

# ---- 出力 ----
$outDir = "$PROJECT_ROOT\note-drafts"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = "$outDir\note-draft-$($today.ToString('yyyy-MM-dd')).txt"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8Bom)
Write-Log "note下書き: 生成完了 $outPath（イベント$($selected.Count)件）"

# 金曜の朝にメモ帳で自動的に開く（コピペのリマインダー）
Start-Process notepad.exe -ArgumentList $outPath
