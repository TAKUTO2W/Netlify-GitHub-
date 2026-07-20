# ===================================================
# CARJAM note 自動投稿
# gen-note-draft.ps1 が作った note-drafts\*.json を読んで note に下書きを作る。
#
#   .\post-to-note.ps1              … 最新のpendingを1件、下書き保存まで
#   .\post-to-note.ps1 -WhatIf      … 何もせず、何をするかだけ表示（安全確認用）
#   .\post-to-note.ps1 -Date 2026-07-24  … 日付を指定して処理
#   .\post-to-note.ps1 -Retry       … failed になったものを再試行
#
# 【重要】現時点では「下書き保存まで」しか行わない。公開は note の画面から手動。
#   note の公開APIは未特定のため（2026-07-20時点）。
#
# 【認証】config.ps1 に $NOTE_COOKIE を設定すること。値の取り方は README-note.md 参照。
#   note に公式APIは無く、これは非公式API。規約グレーで、note側の仕様変更で壊れうる。
# ===================================================
param(
    [string]$Date,
    [switch]$Retry,
    [switch]$WhatIf
)

. "$PSScriptRoot\config.ps1"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
function Save-Draft($obj, $path) {
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 5), $utf8Bom)
}

# ---- 前提チェック ----
if ([string]::IsNullOrWhiteSpace($NOTE_COOKIE)) {
    Write-Log "note投稿: 中止 — config.ps1 に `$NOTE_COOKIE がありません"
    exit 1
}

$outDir = "$PROJECT_ROOT\note-drafts"
if (-not (Test-Path $outDir)) {
    Write-Log "note投稿: 中止 — $outDir がありません"
    exit 1
}

# ---- 対象のJSONを選ぶ ----
# PS5.1 は1件ヒット時に配列にならないので @() で必ず配列化する（HANDOVER §8）
if ($Date) {
    $files = @(Get-ChildItem "$outDir\note-draft-$Date.json" -ErrorAction SilentlyContinue)
} else {
    $files = @(Get-ChildItem "$outDir\note-draft-*.json" -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
}

$wanted = if ($Retry) { @('pending','failed') } else { @('pending') }

$target = $null
foreach ($f in $files) {
    $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($wanted -contains $j.status) { $target = @{ file = $f.FullName; data = $j }; break }
    # 二重投稿防止: drafted/published は黙って飛ばす
}

if (-not $target) {
    Write-Log "note投稿: 対象なし（status=$($wanted -join '/') のJSONが見つからない）"
    exit 0
}

$j    = $target.data
$path = $target.file
Write-Log "note投稿: 対象 $path（$($j.date) / 本文$($j.bodyLength)文字 / status=$($j.status)）"

if ($WhatIf) {
    Write-Host ""
    Write-Host "=== -WhatIf: 実際には何も送信しません ==="
    Write-Host "ファイル : $path"
    Write-Host "タイトル : $($j.title)"
    Write-Host "本文文字数: $($j.bodyLength)"
    Write-Host "既存キー : $(if ($j.noteKey) { $j.noteKey } else { '（なし・新規作成する）' })"
    Write-Host "動作     : 下書き保存まで（公開はしない）"
    Write-Host ""
    exit 0
}

$headers = @{
    "Cookie"           = $NOTE_COOKIE
    "x-requested-with" = "XMLHttpRequest"
    "User-Agent"       = "Mozilla/5.0"
}

function Fail($msg) {
    $j.status    = "failed"
    $j.lastError = $msg
    Save-Draft $j $path
    Write-Log "note投稿: 失敗 — $msg"
    exit 1
}

# ---- 1) 下書きの器を作る（既に作ってあれば再利用＝空下書きの量産を防ぐ） ----
$noteKey = $j.noteKey
if (-not $noteKey) {
    # GET /notes/new は 302 を返し、Location に editor.note.com/notes/{key}/edit/ が入る。
    # このGETだけで note 側に空の下書きが1本できる（副作用あり）ので、
    # リダイレクトは追わず Location だけ読む。
    try {
        $r = Invoke-WebRequest -Uri "https://note.com/notes/new" -Headers $headers `
                -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop
        $loc = $r.Headers["Location"]
    } catch {
        $resp = $_.Exception.Response
        if ($resp -and [int]$resp.StatusCode -ge 300 -and [int]$resp.StatusCode -lt 400) {
            $loc = $resp.Headers["Location"]
        } else {
            Fail "下書きの作成に失敗: $($_.Exception.Message)"
        }
    }

    if ($loc -match '/notes/([^/]+)/edit') {
        $noteKey = $Matches[1]
    } else {
        # ログイン切れだと note.com/login に飛ばされる
        Fail "下書きキーを取得できない（Cookieが期限切れの可能性）。飛び先: $loc"
    }

    $j.noteKey = $noteKey
    Save-Draft $j $path
    Write-Log "note投稿: 下書きを作成 key=$noteKey"
}

# ---- 2) 記事キー → 数値ID（draft_save が要求するのは数値IDの方） ----
$noteId = $j.noteId
if (-not $noteId) {
    try {
        $meta = Invoke-RestMethod -Uri "https://note.com/api/v3/notes/$noteKey" -Headers $headers `
                    -UseBasicParsing -ErrorAction Stop
        $noteId = $meta.data.id
    } catch {
        Fail "数値IDの取得に失敗: $($_.Exception.Message)"
    }
    if (-not $noteId) { Fail "数値IDが空だった（key=$noteKey）" }
    $j.noteId = $noteId
    Save-Draft $j $path
    Write-Log "note投稿: 数値ID取得 id=$noteId"
}

# ---- 3) 本文を保存する ----
$payload = @{
    body         = $j.bodyHtml
    body_length  = $j.bodyLength
    name         = $j.title
    index        = $false
    is_lead_form = $false
} | ConvertTo-Json -Depth 3 -Compress

# PS5.1 の -Body に文字列を渡すと日本語が化けるのでバイト列で送る
$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$url   = "https://note.com/api/v1/text_notes/draft_save?id=$noteId&is_temp_saved=true"

try {
    $res = Invoke-WebRequest -Uri $url -Method POST -Headers $headers `
              -ContentType "application/json" -Body $bytes -UseBasicParsing -ErrorAction Stop
} catch {
    Fail "下書き保存に失敗: $($_.Exception.Message)"
}

if ($res.StatusCode -lt 200 -or $res.StatusCode -ge 300) {
    Fail "下書き保存が想定外の応答: HTTP $($res.StatusCode)"
}

# ---- 完了 ----
$j.status    = "drafted"
$j.postedAt  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$j.lastError = $null
Save-Draft $j $path

Write-Log "note投稿: 下書き保存 完了 https://editor.note.com/notes/$noteKey/edit/"
Write-Host ""
Write-Host "下書きを保存しました。内容を確認して、noteの画面から公開してください:"
Write-Host "  https://editor.note.com/notes/$noteKey/edit/"
Write-Host ""
Write-Host "※アイキャッチ画像は手動で設定してください: $($j.eyecatch)"
