# ===================================================
# CARJAM note用 記事生成（切り口を変えて書く）
#
# 同じイベントデータでも切り口を変えることで、サイト本体・はてなブログと
# 重複コンテンツにならないようにする。方針は Obsidian の
# Decisions/2026-07-20-note-cadence-and-angles.md 参照。
#
#   .\gen-note-article.ps1 -Angle region -Value 北海道
#   .\gen-note-article.ps1 -Angle genre  -Value カーミーティング
#   .\gen-note-article.ps1 -Angle month  -Value 2026-09
#   .\gen-note-article.ps1 -Angle newest
#   .\gen-note-article.ps1 -Angle region -Value 北海道 -Preview   ← 保存せず画面表示だけ
#
# 出力: note-drafts\note-article-{angle}-{value}-YYYY-MM-DD.json
#       （post-to-note.ps1 が読む形式。gen-note-draft.ps1 と同じスキーマ）
# ===================================================
param(
    [ValidateSet('region','genre','month','newest')]
    [string]$Angle = 'region',
    [string]$Value,
    [switch]$Preview
)

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

# ---- イベント読み込み（サイトをスクレイピングせず、収集済みデータを直接読む） ----
$events = @()
$raw = Get-Content "$PROJECT_ROOT\data\new-events.js" -Raw -Encoding UTF8
if ($raw -match 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') {
    $events += @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_ })
}
$events += @((Get-Content "$PROJECT_ROOT\data\legacy-events.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })

$today = (Get-Date).Date
$all = @()
$seen = @{}
foreach ($e in $events) {
    if (-not ($e.date -and $e.name)) { continue }
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($e.date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
    if ($d -lt $today) { continue }
    if ($seen.ContainsKey($e.name)) { continue }
    # 明らかにイベントでないゴミデータを除外（収集元の誤爆対策）
    if ($e.name.Length -gt 40 -or $e.name -match '掲示板|募集・無料掲載|個展') { continue }
    $seen[$e.name] = $true
    $all += ,([PSCustomObject]@{
        date = $d; name = $e.name
        pref = $e.prefecture; venue = $e.venue; cat = $e.category
    })
}
$all = @($all | Sort-Object date)

# ---- 切り口ごとに対象を絞る ----
switch ($Angle) {
    'region' {
        if (-not $Value) { throw "-Angle region には -Value 都道府県名 が必要です" }
        $selected = @($all | Where-Object { $_.pref -eq $Value })
        $themeLabel = $Value
        $themeDesc  = "$Value で開催されるカーイベント"
    }
    'genre' {
        if (-not $Value) { throw "-Angle genre には -Value カテゴリ名 が必要です" }
        $selected = @($all | Where-Object { $_.cat -eq $Value })
        $themeLabel = $Value
        $themeDesc  = "「$Value」ジャンルのカーイベント"
    }
    'month' {
        if (-not $Value) { throw "-Angle month には -Value yyyy-MM が必要です" }
        $selected = @($all | Where-Object { $_.date.ToString("yyyy-MM") -eq $Value })
        $themeLabel = ([datetime]::ParseExact("$Value-01","yyyy-MM-dd",$null)).ToString("yyyy年M月")
        $themeDesc  = "$themeLabel に開催されるカーイベント"
    }
    'newest' {
        $selected = @($all | Where-Object { $_.date -le $today.AddDays(30) })
        $themeLabel = "直近1ヶ月"
        $themeDesc  = "これから1ヶ月以内に開催されるカーイベント"
    }
}

# 会場・都道府県が「未定」のものは記事に載せない（読者に不親切なため）
$selected = @($selected | Where-Object { $_.pref -and $_.pref -ne "未定" })

if ($selected.Count -lt 3) {
    Write-Log "note記事生成: 対象が$($selected.Count)件しかないためスキップ（$Angle / $Value）"
    exit 0
}

# ---- Claude に渡すイベント一覧を組み立てる ----
$jpDow = @("日","月","火","水","木","金","土")
$lines = @()
foreach ($e in $selected) {
    $place = if ($e.venue -and $e.venue -ne "未定") { "$($e.pref)・$($e.venue)" } else { $e.pref }
    $lines += ("{0}（{1}） / {2} / {3} / {4}" -f $e.date.ToString("yyyy年M月d日"), $jpDow[[int]$e.date.DayOfWeek], $e.name, $place, $e.cat)
}
$eventList = $lines -join "`n"

$prompt = @"
あなたは日本全国のカーイベント情報サイト「CARJAM」の編集者です。
note に載せる読み物記事を1本書いてください。

## 今回のテーマ
$themeDesc

## 使えるデータ（CARJAM掲載イベント $($selected.Count)件）
$eventList

## 絶対に守ること
- **上のデータに書かれていないことを書かない。** 開催時間・料金・出展車種・会場の詳細・
  主催者名・過去の開催実績などは、データに無い限り一切書かないこと。推測も禁止。
- イベント名・日付・場所は、上のデータから一字一句そのまま使うこと。
- 「〜だそうです」「〜のようです」といった伝聞でごまかさない。知らないことは書かない。

## 書き方
- 単なる一覧ではなく、**読み物**にすること。テーマならではの切り口・季節感・
  「どれに行くか迷っている人」への実用的な視点を入れる。
- 全体で1200〜1800字程度。
- 見出し（section）は3〜5個。イベントをグルーピングして意味のある見出しを付ける
  （例: 日程順、エリア別、初心者向け/コア向け など。テーマに合う切り方を選ぶ）。
- 各 section の paragraphs には、そのグループのイベントを紹介する文章を入れる。
  イベント名は「・」で始まる箇条書きの行にしてよい。
- 文体は丁寧語。親しみやすく、でも大げさな煽りはしない。
- 読者は「今週末どこか行きたいな」と思っている車好き。

## タイトル
- 32文字以内。テーマと件数が一目で分かるもの。
- 【】で囲った短いラベルを先頭に付けてよい（例:【北海道】）。
"@

# Anthropic の structured output は、object 型ごとに additionalProperties=false が必須。
# 無いと 400 invalid_request_error になる。
$schema = @{
    type = "object"
    additionalProperties = $false
    properties = @{
        title    = @{ type = "string" }
        lead     = @{ type = "string" }
        sections = @{
            type = "array"
            items = @{
                type = "object"
                additionalProperties = $false
                properties = @{
                    heading    = @{ type = "string" }
                    paragraphs = @{ type = "array"; items = @{ type = "string" } }
                }
                required = @("heading","paragraphs")
            }
        }
        closing = @{ type = "string" }
        tags    = @{ type = "array"; items = @{ type = "string" } }
    }
    required = @("title","lead","sections","closing","tags")
}

$body = @{
    model      = "claude-opus-4-8"
    max_tokens = 8000
    messages   = @(@{ role = "user"; content = $prompt })
    output_config = @{ format = @{ type = "json_schema"; schema = $schema } }
} | ConvertTo-Json -Depth 20

$headers = @{
    "x-api-key"         = $CLAUDE_API_KEY
    "anthropic-version" = "2023-06-01"
    "content-type"      = "application/json"
}

Write-Log "note記事生成: Claude呼び出し（$Angle / $Value / 対象$($selected.Count)件）"
$res  = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" -Method POST -Headers $headers `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 300 -UseBasicParsing
$json = [System.Text.Encoding]::UTF8.GetString($res.RawContentStream.ToArray()) | ConvertFrom-Json

if ($json.stop_reason -ne "end_turn") {
    Write-Log "note記事生成: 中断 stop_reason=$($json.stop_reason)"
    exit 1
}
$article = ($json.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1).text | ConvertFrom-Json

# ---- note用HTMLに組み立てる ----
function Escape-Html($s) { $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }

$htmlSb  = New-Object System.Text.StringBuilder
$plainSb = New-Object System.Text.StringBuilder
$plainLen = 0
function Add-Html($tag, $text) {
    $u = [guid]::NewGuid().ToString()
    [void]$script:htmlSb.Append("<$tag name=""$u"" id=""$u"">$(Escape-Html $text)</$tag>")
    if ($tag -eq 'h2') { [void]$script:plainSb.AppendLine("## $text") } else { [void]$script:plainSb.AppendLine($text) }
    [void]$script:plainSb.AppendLine("")
    $script:plainLen += $text.Length
}

Add-Html 'p' $article.lead
foreach ($s in $article.sections) {
    Add-Html 'h2' $s.heading
    foreach ($p in $s.paragraphs) { if ($p) { Add-Html 'p' $p } }
}
Add-Html 'h2' "CARJAMについて"
Add-Html 'p' $article.closing
Add-Html 'p' "CARJAM: https://carjam-usdm.netlify.app"
Add-Html 'p' "X: https://x.com/carjam_usdm （2日に1回、直近イベントを発信中）"
Add-Html 'p' "※開催情報は変更される場合があります。お出かけ前に各イベントの公式情報をご確認ください。"

# ---- 出力 ----
if ($Preview) {
    Write-Host ""
    Write-Host "==================== タイトル ===================="
    Write-Host $article.title
    Write-Host ""
    Write-Host "==================== 本文（$plainLen 文字）===================="
    Write-Host $plainSb.ToString()
    Write-Host "==================== タグ ===================="
    Write-Host ($article.tags -join " / ")
    Write-Host ""
    Write-Host "[tokens in=$($json.usage.input_tokens) out=$($json.usage.output_tokens)]"
    exit 0
}

$outDir = "$PROJECT_ROOT\note-drafts"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$slug = if ($Value) { ($Value -replace '[^\w\-]','') } else { $Angle }
$outPath = "$outDir\note-article-$Angle-$slug-$($today.ToString('yyyy-MM-dd')).json"

$payload = [PSCustomObject]@{
    date       = $today.ToString('yyyy-MM-dd')
    angle      = $Angle
    angleValue = $Value
    title      = $article.title
    bodyHtml   = $htmlSb.ToString()
    bodyLength = $plainLen
    eyecatch   = "$PROJECT_ROOT\images\note-eyecatch.jpg"
    eventCount = $selected.Count
    tags       = @($article.tags)
    status     = "pending"
    noteKey    = $null
    noteId     = $null
    postedAt   = $null
    lastError  = $null
}
[IO.File]::WriteAllText($outPath, ($payload | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($true)))
Write-Log "note記事生成: 完了 $outPath（$($article.title) / $($plainLen)文字 / tokens out=$($json.usage.output_tokens)）"
