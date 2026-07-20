# ===================================================
# 既存イベントの「会場・説明文」を、収集元の詳細ページから取得し直して補完する
#
# 【背景】2026-07-20 時点で自動収集206件のうち、会場が入っているのは11%、説明文は0%。
# 収集元の詳細ページには会場・住所・主催・時間・料金が載っていたのに、
# check-events.ps1 が venue="" と決め打ちしていて最初から取りに行っていなかった。
#
# 【方針】
#  - 収集元の説明文は**そのままコピーしない**（著作権＋重複コンテンツ）。
#    抽出した事実だけを使って自前の文章を組み立てる（lib-event-detail.ps1 参照）
#  - 会場・住所から都道府県が確定できる場合は、そちらを正とする（推測より実データ）
#  - 取れなかった項目は空のまま。**推測で埋めない**
#
#   .\enrich-event-details.ps1              … ドライラン（変更内容を表示するだけ）
#   .\enrich-event-details.ps1 -Apply       … 実際に書き換える（.bak を残す）
#   .\enrich-event-details.ps1 -Limit 20    … 先頭20件だけ試す（動作確認用）
# ===================================================
param(
    [switch]$Apply,
    [int]$Limit = 0
)

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib-event-detail.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

$REGION_MAP = @{
    "北海道"="北海道"
    "青森県"="東北";"岩手県"="東北";"宮城県"="東北";"秋田県"="東北";"山形県"="東北";"福島県"="東北"
    "茨城県"="関東";"栃木県"="関東";"群馬県"="関東";"埼玉県"="関東";"千葉県"="関東";"東京都"="関東";"神奈川県"="関東"
    "新潟県"="中部";"富山県"="中部";"石川県"="中部";"福井県"="中部";"山梨県"="中部";"長野県"="中部";"岐阜県"="中部";"静岡県"="中部";"愛知県"="中部"
    "三重県"="近畿";"滋賀県"="近畿";"京都府"="近畿";"大阪府"="近畿";"兵庫県"="近畿";"奈良県"="近畿";"和歌山県"="近畿"
    "鳥取県"="中国";"島根県"="中国";"岡山県"="中国";"広島県"="中国";"山口県"="中国"
    "徳島県"="四国";"香川県"="四国";"愛媛県"="四国";"高知県"="四国"
    "福岡県"="九州";"佐賀県"="九州";"長崎県"="九州";"熊本県"="九州";"大分県"="九州";"宮崎県"="九州";"鹿児島県"="九州";"沖縄県"="九州"
}

$jpDow = @("日","月","火","水","木","金","土")

# ---- 読み込み ----
$neFile = "$PROJECT_ROOT\data\new-events.js"
$raw = Get-Content $neFile -Raw -Encoding UTF8
if ($raw -notmatch 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') { throw "new-events.js を解析できません" }
$newEvents = @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_ })

# 補完が必要なもの（会場が無い、または説明文が無い）だけを対象にする
function Missing($v) { -not $v -or "$v".Trim() -eq '' -or "$v" -eq '未定' }
$targets = @($newEvents | Where-Object { (Missing $_.venue) -or (Missing $_.description) })
if ($Limit -gt 0) { $targets = @($targets | Select-Object -First $Limit) }

Write-Host "対象: $(@($targets).Count) 件 / 全 $(@($newEvents).Count) 件"
Write-Host "取得には1件あたり約0.5秒かかります（相手サイトに負荷をかけないため）"
Write-Host ""

$stat = @{ venue=0; desc=0; pref=0; fail=0; skip=0 }
$changes = @()
$n = 0

foreach ($e in $targets) {
    $n++
    if ($n % 25 -eq 0) { Write-Host "  ... $n / $(@($targets).Count) 件処理" }

    if (-not $e.url -or $e.url -notmatch '^https?://') { $stat.skip++; continue }

    try {
        $res = Invoke-WebRequest -Uri $e.url -UseBasicParsing -TimeoutSec 15
        $f = Get-EventDetailFields $res.Content
    } catch {
        $stat.fail++
        Start-Sleep -Milliseconds 300
        continue
    }

    $before = [PSCustomObject]@{ venue=$e.venue; description=$e.description; prefecture=$e.prefecture }
    $touched = $false

    # 会場
    if ((Missing $e.venue) -and $f.venue) {
        $e.venue = $f.venue
        $stat.venue++
        $touched = $true
    }

    # 都道府県: 会場・住所に県名があればそれを正とする（推測より実データが強い）
    $pFromPlace = Get-PrefectureFromPlace "$($f.venue) $($f.address)" $PREF_NAMES
    if ($pFromPlace -and $pFromPlace -ne $e.prefecture) {
        $e.prefecture = $pFromPlace
        $e.region = if ($REGION_MAP.ContainsKey($pFromPlace)) { $REGION_MAP[$pFromPlace] } else { "その他" }
        $stat.pref++
        $touched = $true
    }

    # 説明文: 抽出した事実から自前で組み立てる（収集元の文章はコピーしない）
    if (Missing $e.description) {
        $desc = New-EventDescription $e $f $jpDow
        if ($desc) { $e.description = $desc; $stat.desc++; $touched = $true }
    }

    if ($touched) {
        $changes += ,([PSCustomObject]@{
            name = $e.name
            venueBefore = $before.venue; venueAfter = $e.venue
            prefBefore  = $before.prefecture; prefAfter = $e.prefecture
            descLen = if ($e.description) { $e.description.Length } else { 0 }
        })
    }

    Start-Sleep -Milliseconds 500
}

# ---- 結果 ----
Write-Host ""
Write-Host "=========== 補完結果 ==========="
Write-Host "会場を埋めた      : $($stat.venue) 件"
Write-Host "説明文を作った    : $($stat.desc) 件"
Write-Host "都道府県を訂正    : $($stat.pref) 件"
Write-Host "ページ取得に失敗  : $($stat.fail) 件"
Write-Host "URLが無くスキップ : $($stat.skip) 件"

$after = @($newEvents | Where-Object { -not (Missing $_.venue) }).Count
$afterD = @($newEvents | Where-Object { -not (Missing $_.description) }).Count
Write-Host ""
Write-Host "会場のカバー  : $after / $(@($newEvents).Count)"
Write-Host "説明文のカバー: $afterD / $(@($newEvents).Count)"

Write-Host ""
Write-Host "--- 変更サンプル（先頭12件）---"
$changes | Select-Object -First 12 | ForEach-Object {
    $nm = if ($_.name.Length -gt 28) { $_.name.Substring(0,28) + '…' } else { $_.name }
    "{0,-30} 会場:{1,-24} 県:{2}→{3} 説明{4}字" -f $nm, ($(if($_.venueAfter){$_.venueAfter}else{'(取れず)'})), $_.prefBefore, $_.prefAfter, $_.descLen
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "※ ドライランです。書き換えていません。実行するには -Apply を付けてください。"
    exit 0
}

# ---- 書き戻し ----
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $neFile "$neFile.bak-$stamp" -Force
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$header = "// 自動更新される。scripts/check-events.ps1 が書き換える"
$body = "window.NEW_EVENTS = " + ($newEvents | ConvertTo-Json -Depth 5 -Compress) + ";"
[IO.File]::WriteAllText($neFile, "$header`n$body`n", $utf8NoBom)

Write-Log "enrich-event-details: 会場$($stat.venue)件 / 説明文$($stat.desc)件 / 都道府県$($stat.pref)件を補完"
Write-Host ""
Write-Host "書き換えました。バックアップ: new-events.js.bak-$stamp"
