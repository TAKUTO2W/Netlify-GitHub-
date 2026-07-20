# ===================================================
# CARJAM note用下書き自動生成
# 毎週金曜の朝、直近2週間のイベントまとめ記事の下書きを生成する。
#   - note-drafts\note-draft-YYYY-MM-DD.json … post-to-note.ps1 が読む正本
#   - note-drafts\note-draft-YYYY-MM-DD.txt  … 手動コピペ用のフォールバック
# daily-run.ps1 から毎朝呼ばれる。テストは -Force で曜日ゲートを無視。
#
# $NOTE_COOKIE が config.ps1 に設定されていれば自動投稿に任せてメモ帳は開かない。
# 未設定なら従来どおりメモ帳を開く（手動コピペ運用のまま）。
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

# ---- 本文をブロックの配列として組み立てる ----
# 1ブロック = 1段落。type は 'h2'（見出し）か 'p'（本文）。
# ここから .txt と .json(HTML) の両方を生成するので、本文の変更はここだけ直せばよい。
$blocks = @()
function Add-Block($type, $text) {
    $script:blocks += ,([PSCustomObject]@{ type = $type; text = $text })
}

$titleRange = "{0}/{1}〜{2}/{3}" -f $today.Month, $today.Day, $until.Month, $until.Day
$title = "【$titleRange】今週末〜来週の全国カーイベントまとめ"

Add-Block 'p' "こんにちは。日本全国のカーイベント情報を集約しているサイト「CARJAM」です。"
Add-Block 'p' "直近2週間に開催予定のカーイベントを、CARJAM掲載データからまとめて紹介します。"

$byDate = $selected | Group-Object { $_.date.ToString("yyyy-MM-dd") }
foreach ($g in $byDate) {
    $d = $g.Group[0].date
    Add-Block 'h2' ("{0}/{1}（{2}）" -f $d.Month, $d.Day, $jpDow[[int]$d.DayOfWeek])
    $shown = @($g.Group | Select-Object -First 6)
    foreach ($e in $shown) {
        $place = if ($e.pref -and $e.pref -ne "未定") { $e.pref } else { "" }
        if ($e.venue -and $e.venue -ne "未定") {
            $place = if ($place) { "$place・$($e.venue)" } else { $e.venue }
        }
        if ($place) { Add-Block 'p' "・$($e.name)（$place）" }
        else        { Add-Block 'p' "・$($e.name)" }
    }
    $rest = $g.Group.Count - $shown.Count
    if ($rest -gt 0) { Add-Block 'p' "ほか $rest 件" }
}

Add-Block 'h2' "全国190件以上を掲載中"
Add-Block 'p' "ここに載せたのは一部です。CARJAMでは全国のカーイベントを都道府県・カテゴリ・日付で検索できます。毎朝9時に自動更新しているので、お出かけ前にチェックしてみてください。"
Add-Block 'p' "CARJAM: https://carjam-usdm.netlify.app"
Add-Block 'p' "X: https://x.com/carjam_usdm （2日に1回、直近イベントを発信中）"
Add-Block 'p' "※開催情報は変更される場合があります。お出かけ前に各イベントの公式情報をご確認ください。"

# ---- HTML化（noteのエディタが吐く形に合わせる） ----
# note公式エディタは1段落ごとに <p name="{uuid}" id="{uuid}"> を付ける。
# 必須かは未検証だが、実物と同じ形にしておく方が安全。
function Escape-Html($s) {
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
}
$htmlSb = New-Object System.Text.StringBuilder
$textSb = New-Object System.Text.StringBuilder
$plainLen = 0
foreach ($b in $blocks) {
    $u = [guid]::NewGuid().ToString()
    $esc = Escape-Html $b.text
    if ($b.type -eq 'h2') {
        [void]$htmlSb.Append("<h2 name=""$u"" id=""$u"">$esc</h2>")
        [void]$textSb.AppendLine("## $($b.text)")
        [void]$textSb.AppendLine("")
    } else {
        [void]$htmlSb.Append("<p name=""$u"" id=""$u"">$esc</p>")
        [void]$textSb.AppendLine($b.text)
        [void]$textSb.AppendLine("")
    }
    $plainLen += $b.text.Length
}

$eyecatch = "$PROJECT_ROOT\images\note-eyecatch.jpg"

# ---- 出力 ----
$outDir = "$PROJECT_ROOT\note-drafts"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$stamp = $today.ToString('yyyy-MM-dd')
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

# JSON（post-to-note.ps1 が読む正本）
# status: pending → drafted → published。失敗時は failed。
# 既にあるファイルは上書きしない（投稿済みフラグを消さないため）。
$jsonPath = "$outDir\note-draft-$stamp.json"
if (Test-Path $jsonPath) {
    Write-Log "note下書き: $jsonPath は既にあるためJSONは再生成しない（投稿状態を保持）"
} else {
    $payload = [PSCustomObject]@{
        date       = $stamp
        title      = $title
        bodyHtml   = $htmlSb.ToString()
        bodyLength = $plainLen
        eyecatch   = $eyecatch
        eventCount = $selected.Count
        status     = "pending"
        noteKey    = $null
        noteId     = $null
        postedAt   = $null
        lastError  = $null
    }
    [IO.File]::WriteAllText($jsonPath, ($payload | ConvertTo-Json -Depth 5), $utf8Bom)
    # $plainLen文字 と書くと「plainLen文字」という変数名として解釈される（PS は日本語の変数名も許す）
    Write-Log "note下書き: JSON生成 $jsonPath（イベント$($selected.Count)件 / 本文$($plainLen)文字）"
}

# TXT（手動コピペ用のフォールバック。JSONが壊れても人力で投稿できるように残す）
$txtSb = New-Object System.Text.StringBuilder
[void]$txtSb.AppendLine("■アイキャッチ画像（noteの「画像をアップロード」でこれを選ぶ）")
[void]$txtSb.AppendLine($eyecatch)
[void]$txtSb.AppendLine("")
[void]$txtSb.AppendLine("■タイトル案（1行目をコピー）")
[void]$txtSb.AppendLine($title)
[void]$txtSb.AppendLine("")
[void]$txtSb.AppendLine("■本文（ここから下を全部コピー。※変なイベント名があれば削ってから投稿）")
[void]$txtSb.AppendLine("----------------------------------------")
[void]$txtSb.Append($textSb.ToString())
$txtPath = "$outDir\note-draft-$stamp.txt"
[IO.File]::WriteAllText($txtPath, $txtSb.ToString(), $utf8Bom)

# 自動投稿が設定済みならメモ帳は開かない（post-to-note.ps1 に任せる）
if ([string]::IsNullOrWhiteSpace($NOTE_COOKIE)) {
    Write-Log "note下書き: NOTE_COOKIE未設定のため手動コピペ運用（メモ帳を開く）"
    Start-Process notepad.exe -ArgumentList $txtPath
}
