# ===================================================
# 同じイベントが複数レコードになっているのを除去する
#
# 【背景】収集元を増やすと、同じイベントが別々のサイトから登録され、
# サイト上で同じカードが2〜3枚並ぶ。2026-07-21 に racry を全件取得に広げたら
# クロスソース重複が増えた（例: HARUNA SUBARU FES が fdesign/careventnavi/racry の3枚）。
#
# 【判定】イベント名（記号・空白を除いた正規化）＋開催日 が一致するものを重複とみなす。
# 残す1件は次のスコアで選ぶ:
#   - 手動登録（source が空。legacy/events-data.js 由来）… 最優先で残す
#   - 都道府県が実在（未定でない）／会場が実在／説明文がある … 情報が濃い方を残す
#   - 同点なら id が小さい方（古くて安定しているもの）を残す
# legacy-events.json のレコードは削除対象にしない（手動データは触らない）。
#
#   .\dedup-events.ps1                   … ドライラン
#   .\dedup-events.ps1 -Apply            … 実際に削除（.bak を残す）
#   .\dedup-events.ps1 -Apply -NoBackup  … daily-run から毎日呼ぶ用（.bak を作らない。
#                                           データは git 履歴が保持するため）
# ===================================================
param([switch]$Apply, [switch]$NoBackup)

. "$PSScriptRoot\config.ps1"

function Norm($s) {
    if (-not $s) { return "" }
    (($s -replace '[\s　\[\]【】（）()!！?？・、。〜~ー\-＆&]', '') -replace '&amp;','' -replace 'amp;','').ToLower()
}
function IsReal($v) { $v -and "$v".Trim() -ne '' -and "$v" -ne '未定' }

function Score($e) {
    $s = 0
    if (-not $e.source) { $s += 100 }             # 手動登録は最優先で残す
    if (IsReal $e.prefecture) { $s += 2 }
    if (IsReal $e.venue) { $s += 2 }
    if (IsReal $e.description) { $s += 1 }
    if ($e.description -and $e.description.Length -ge 40) { $s += 2 }
    return $s
}

# ---- 読み込み（new-events.js と legacy 両方を突き合わせるが、削除は new 側だけ） ----
$neFile = "$PROJECT_ROOT\data\new-events.js"
$raw = Get-Content $neFile -Raw -Encoding UTF8
if ($raw -notmatch 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') { throw "new-events.js を解析できません" }
$newEvents = @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_ })
$legacy    = @((Get-Content "$PROJECT_ROOT\data\legacy-events.json" -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })

# id → どのリスト由来かを覚えておく（legacy は削除しない）
$legacyIds = @{}; foreach ($e in $legacy) { $legacyIds[[string]$e.id] = $true }

$all = @($newEvents + $legacy)
$groups = $all | Group-Object { "$(Norm $_.name)|$($_.date)" } | Where-Object { $_.Count -gt 1 -and $_.Name -notmatch '^\|' }

$removeIds = @{}
$report = @()
foreach ($g in $groups) {
    # スコア降順・id昇順で並べ、先頭を残す
    $ranked = @($g.Group | Sort-Object @{Expression={ Score $_ }; Descending=$true}, @{Expression={ [int]$_.id }; Descending=$false})
    $keep = $ranked[0]
    foreach ($e in $ranked[1..($ranked.Count-1)]) {
        if ($legacyIds.ContainsKey([string]$e.id)) { continue }  # 手動データは消さない
        $removeIds[[string]$e.id] = $true
        $report += [PSCustomObject]@{
            name = $e.name; date = $e.date
            remove = "id=$($e.id) [$(if($e.source){$e.source}else{'手動'})]"
            keep   = "id=$($keep.id) [$(if($keep.source){$keep.source}else{'手動'})]"
        }
    }
}

Write-Host "重複グループ: $(@($groups).Count) 組 / 削除対象: $($removeIds.Count) 件`n"
$report | Sort-Object name | ForEach-Object {
    $nm = if ($_.name.Length -gt 34) { $_.name.Substring(0,34)+'…' } else { $_.name }
    "  削除 {0} ← 残す {1}  : {2}（{3}）" -f $_.remove, $_.keep, $nm, $_.date
}

if (-not $Apply) {
    Write-Host "`n※ ドライランです。-Apply で実際に削除します。"
    exit 0
}

$kept = @($newEvents | Where-Object { -not $removeIds.ContainsKey([string]$_.id) })
if (-not $NoBackup) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item $neFile "$neFile.bak-$stamp" -Force
}
[IO.File]::WriteAllText($neFile, "// 自動更新される。scripts/check-events.ps1 が書き換える`nwindow.NEW_EVENTS = " + ($kept | ConvertTo-Json -Depth 5 -Compress) + ";`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`n重複除去: $($newEvents.Count) → $($kept.Count) 件$(if($NoBackup){''}else{' / バックアップ: new-events.js.bak-'+$stamp})"
