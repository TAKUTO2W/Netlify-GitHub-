# ===================================================
# coscam(cos-cam.work) の都道府県を、カレンダーページから取り直して修正する
# （2026-07-20 の事故対応・一度きりの想定）
#
# 【原因】check-events.ps1 が、月ブロックの先頭から当該イベントまでのテキスト全部を
# 都道府県判定に渡していた。判定関数は「都道府県リストの並び順で最初に一致したもの」を
# 返す作りだったため、**その月の別のイベントの県**を拾っていた。
# 17件中10件（59%）が誤り。恵那峡ワンダーランド→山形県、DCM in NUMAZU→宮城県 など。
# 朝に直した北海道バグ（ナビメニューを拾う）と同じ構造の問題。
#
# 【正しい取り方】このカレンダーは「日付 / 曜日 / 都道府県 / イベント名」の順に並ぶので、
# イベントリンクの**直前**に出てくる県が正しい。範囲を絞り、いちばん近いものを採る。
#
#   .\fix-coscam-prefecture.ps1          … ドライラン
#   .\fix-coscam-prefecture.ps1 -Apply   … 適用（.bak を残す）
# ===================================================
param([switch]$Apply)

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib-event-detail.ps1"

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

# ---- カレンダーページから eventid → 都道府県 の対応表を作る ----
Write-Host "cos-cam.work のカレンダーを取得中..."
$res  = Invoke-WebRequest -Uri "https://cos-cam.work/?page_id=969" -UseBasicParsing -TimeoutSec 30
$html = $res.Content

$map = @{}
foreach ($mb in [regex]::Matches($html, '(?s)id="(\d{4})(\d{2})"[^>]*>(.*?)(?=id="\d{6}"|</body|$)', 'IgnoreCase')) {
    $mbContent = $mb.Groups[3].Value
    foreach ($ev in [regex]::Matches($mbContent, 'href="[^"]*eventid=(\d+)[^"]*"[^>]*>([^<]{3,60})</a>', 'IgnoreCase')) {
        $evid = $ev.Groups[1].Value
        $before = $mbContent.Substring(0, [Math]::Min($ev.Index + $ev.Length, $mbContent.Length))
        $plain  = ($before -replace '<[^>]+>',' ' -replace '\s+',' ')
        $pref   = Get-PrefectureNearest $plain $PREF_NAMES 300
        if ($pref) { $map[$evid] = $pref }
    }
}
Write-Host "カレンダーから $($map.Count) 件の都道府県を取得しました`n"

# ---- 既存データを突き合わせる ----
$neFile = "$PROJECT_ROOT\data\new-events.js"
$raw = Get-Content $neFile -Raw -Encoding UTF8
if ($raw -notmatch 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') { throw "new-events.js を解析できません" }
$newEvents = @($Matches[1] | ConvertFrom-Json | ForEach-Object { $_ })

$changes = @()
$notFound = 0
foreach ($e in $newEvents) {
    if ($e.source -ne 'coscam') { continue }
    if ($e.url -notmatch 'eventid=(\d+)') { continue }
    $evid = $Matches[1]
    if (-not $map.ContainsKey($evid)) { $notFound++; continue }
    $new = $map[$evid]
    if ($new -eq $e.prefecture) { continue }
    $changes += ,([PSCustomObject]@{ name = $e.name; before = $e.prefecture; after = $new })
    $e.prefecture = $new
    $e.region = if ($REGION_MAP.ContainsKey($new)) { $REGION_MAP[$new] } else { "その他" }
}

Write-Host "=== 修正 $(@($changes).Count) 件（カレンダーに無く照合できず: $notFound 件）==="
$changes | ForEach-Object {
    $nm = if ($_.name.Length -gt 34) { $_.name.Substring(0,34) + '…' } else { $_.name }
    "  {0,-36} {1,-6} → {2}" -f $nm, $_.before, $_.after
}

if (-not $Apply) {
    Write-Host "`n※ ドライランです。書き換えていません。-Apply で適用します。"
    exit 0
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $neFile "$neFile.bak-$stamp" -Force
$header = "// 自動更新される。scripts/check-events.ps1 が書き換える"
$body = "window.NEW_EVENTS = " + ($newEvents | ConvertTo-Json -Depth 5 -Compress) + ";"
[IO.File]::WriteAllText($neFile, "$header`n$body`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`n書き換えました。バックアップ: new-events.js.bak-$stamp"
