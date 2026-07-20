# ===================================================
# 都道府県データの一括修正（2026-07-20 の事故対応・一度きりの想定）
#
# 【背景】check-events.ps1 が、ページ全体のテキストを都道府県推定に渡していた。
# 推定マップは [ordered] で北海道が先頭のため、サイトのナビメニューにある「北海道」を
# 拾って無関係なイベントが北海道になっていた。careventnavi は32件中19件が誤り。
#
# 【方針】誤った都道府県より「未定」の方がマシ。
#   - jmty     : URLのローマ字（https://jmty.jp/{pref}/…）から引き直す。最も確実
#   - その他   : イベント名（＋会場）から引き直す。取れなければ「未定」
#   - 対象は推定が壊れていた収集元のみ。名前・会場だけを見ていた7サイトは触らない
#
#   .\fix-prefecture-data.ps1          … ドライラン（変更内容を表示するだけ）
#   .\fix-prefecture-data.ps1 -Apply   … 実際に書き換える（.bak を残す）
# ===================================================
param([switch]$Apply)

. "$PSScriptRoot\config.ps1"

# check-events.ps1 の判定関数をそのまま使う（二重管理を避けるため読み込む）
# ※ check-events.ps1 は読み込むと収集まで走ってしまうので、必要な部分だけ再定義する
function Get-PrefectureFromName($name) {
    $map = [ordered]@{
        "北海道|ふらの|富良野|EZO|蝦夷|札幌|函館|旭川" = "北海道"
        "青森|弘前|八戸" = "青森県"
        "岩手|盛岡" = "岩手県"
        "宮城|仙台|SUGO|スポーツランドSUGO|スポーツランド菅生" = "宮城県"
        "秋田" = "秋田県"
        "山形|やまがた" = "山形県"
        "福島" = "福島県"
        "茨城|水戸|つくば|筑波サーキット|筑波" = "茨城県"
        "栃木|宇都宮|日光|もてぎ|ツインリンク|Twin Ring|ツインリンクもてぎ" = "栃木県"
        "群馬|前橋|高崎|伊勢崎" = "群馬県"
        "埼玉|さいたま|浦和|大宮" = "埼玉県"
        "千葉|幕張|柏|袖ヶ浦|茂原|袖ケ浦|SODEGAURA|幕張メッセ" = "千葉県"
        "東京|品川|渋谷|新宿|秋葉原|羽田|お台場|豊洲|有明|青海|東京ビッグサイト|東京国際展示場" = "東京都"
        "横浜|神奈川|川崎|湘南|箱根|大観山|厚木|相模|大黒PA|大黒ふ頭|みなとみらい|海老名" = "神奈川県"
        "新潟|国上|長岡|SORAIRO" = "新潟県"
        "富山" = "富山県"
        "金沢|石川|能登|北陸" = "石川県"
        "福井" = "福井県"
        "山梨|甲府|富士吉田" = "山梨県"
        "長野|信州|北信越|松本|諏訪" = "長野県"
        "岐阜|可児" = "岐阜県"
        "静岡|浜松|富士|富士スピードウェイ|FISCO|富士スピ|FSW" = "静岡県"
        "名古屋|愛知|豊田|岡崎" = "愛知県"
        "三重|鈴鹿|伊勢|鈴鹿サーキット" = "三重県"
        "滋賀|琵琶湖|大津" = "滋賀県"
        "京都|きょうと" = "京都府"
        "OSAKA|大阪|なにわ|難波|梅田" = "大阪府"
        "神戸|兵庫|姫路|尼崎" = "兵庫県"
        "奈良" = "奈良県"
        "和歌山" = "和歌山県"
        "鳥取" = "鳥取県"
        "島根|山陰" = "島根県"
        "岡山|奥津湖|鏡野" = "岡山県"
        "広島|HIROSHIMA" = "広島県"
        "山口" = "山口県"
        "徳島" = "徳島県"
        "香川|高松" = "香川県"
        "愛媛|松山" = "愛媛県"
        "高知" = "高知県"
        "福岡|博多|北九州|九州|門司|小倉" = "福岡県"
        "佐賀" = "佐賀県"
        "長崎" = "長崎県"
        "熊本|肥後" = "熊本県"
        "大分|オートポリス" = "大分県"
        "宮崎" = "宮崎県"
        "鹿児島|KAGOSHIMA" = "鹿児島県"
        "沖縄|OKINAWA|那覇" = "沖縄県"
    }
    foreach ($pattern in $map.Keys) {
        if ($name -match $pattern) { return $map[$pattern] }
    }
    return ""
}

$JMTY_PREF = @{
    hokkaido="北海道"; aomori="青森県"; iwate="岩手県"; miyagi="宮城県"; akita="秋田県"
    yamagata="山形県"; fukushima="福島県"; ibaraki="茨城県"; tochigi="栃木県"; gunma="群馬県"
    saitama="埼玉県"; chiba="千葉県"; tokyo="東京都"; kanagawa="神奈川県"; niigata="新潟県"
    toyama="富山県"; ishikawa="石川県"; fukui="福井県"; yamanashi="山梨県"; nagano="長野県"
    gifu="岐阜県"; shizuoka="静岡県"; aichi="愛知県"; mie="三重県"; shiga="滋賀県"
    kyoto="京都府"; osaka="大阪府"; hyogo="兵庫県"; nara="奈良県"; wakayama="和歌山県"
    tottori="鳥取県"; shimane="島根県"; okayama="岡山県"; hiroshima="広島県"; yamaguchi="山口県"
    tokushima="徳島県"; kagawa="香川県"; ehime="愛媛県"; kochi="高知県"; fukuoka="福岡県"
    saga="佐賀県"; nagasaki="長崎県"; kumamoto="熊本県"; oita="大分県"; miyazaki="宮崎県"
    kagoshima="鹿児島県"; okinawa="沖縄県"
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

# 推定が壊れていた収集元だけを対象にする
$SUSPECT = @('careventnavi','jmty','racry')

$PREFS = @("北海道","青森県","岩手県","宮城県","秋田県","山形県","福島県",
           "茨城県","栃木県","群馬県","埼玉県","千葉県","東京都","神奈川県",
           "新潟県","富山県","石川県","福井県","山梨県","長野県","岐阜県","静岡県","愛知県",
           "三重県","滋賀県","京都府","大阪府","兵庫県","奈良県","和歌山県",
           "鳥取県","島根県","岡山県","広島県","山口県",
           "徳島県","香川県","愛媛県","高知県",
           "福岡県","佐賀県","長崎県","熊本県","大分県","宮崎県","鹿児島県","沖縄県")

# ナビ・ヘッダー・フッター等を落として本文だけにする。
# ここを落とさないと「全都道府県リンク」を拾って誤判定する（今回の事故の本質）。
function Get-MainText($html) {
    $h = $html
    foreach ($tag in @('script','style','nav','header','footer','aside','select')) {
        $h = [regex]::Replace($h, "(?is)<$tag[^>]*>.*?</$tag>", ' ')
    }
    # 都道府県リンクの塊（<a href="...">○○県</a> が連続する箇所）も落とす
    $h = [regex]::Replace($h, '(?is)(<a [^>]*>\s*[^<]{2,5}[都道府県]\s*</a>\s*){5,}', ' ')
    return ($h -replace '<[^>]+>',' ' -replace '\s+',' ')
}

# ページ本文に「ちょうど1つだけ」都道府県が出てくるなら、それが開催地とみなせる。
# 複数出てくる場合は判断できないので使わない（誤りより未定を選ぶ）。
function Get-PrefectureUnique($text) {
    $found = @()
    foreach ($p in $PREFS) {
        if ($text -match [regex]::Escape($p)) { $found += $p }
    }
    $found = @($found | Sort-Object -Unique)
    if ($found.Count -eq 1) { return $found[0] }
    return ""
}

$changes = @()
$fetchFail = 0

function Repair-Events($list, $fileLabel) {
    foreach ($e in $list) {
        if ($SUSPECT -notcontains $e.source) { continue }

        $old = $e.prefecture
        $new = ""

        # ① jmty は URL のローマ字が最も確実
        if ($e.source -eq 'jmty' -and $e.url -match 'https://jmty\.jp/([a-z]+)/') {
            $new = $JMTY_PREF[$Matches[1]]
        }

        # ② イベント名から
        if (-not $new) {
            $venue = if ($e.venue -and $e.venue -ne '未定') { $e.venue } else { "" }
            $new = Get-PrefectureFromName "$($e.name) $venue"
        }

        # ③ 元ページを取得し直して、本文だけから判定
        if (-not $new -and $e.url -and $e.url -match '^https?://') {
            try {
                $res  = Invoke-WebRequest -Uri $e.url -UseBasicParsing -TimeoutSec 15
                $main = Get-MainText $res.Content

                $labels = '開催場所|開催地|開催県|会場|場所|住所|所在地|アクセス'
                foreach ($m in [regex]::Matches($main, "($labels)[^\p{L}\p{N}]{0,6}(.{0,40})")) {
                    $new = Get-PrefectureFromName $m.Groups[2].Value
                    if ($new) { break }
                }
                if (-not $new) { $new = Get-PrefectureUnique $main }
            } catch {
                $script:fetchFail++
            }
            Start-Sleep -Milliseconds 400
        }

        if (-not $new) { $new = "未定" }

        if ($new -ne $old) {
            $e.prefecture = $new
            $e.region = if ($REGION_MAP.ContainsKey($new)) { $REGION_MAP[$new] } else { "その他" }
            $script:changes += ,([PSCustomObject]@{
                file = $fileLabel; source = $e.source; name = $e.name
                before = $old; after = $new
            })
        }
    }
}

# ---- new-events.js ----
$neFile = "$PROJECT_ROOT\data\new-events.js"
$raw = Get-Content $neFile -Raw -Encoding UTF8
if ($raw -notmatch 'window\.NEW_EVENTS\s*=\s*(\[[\s\S]*?\]);') { throw "new-events.js を解析できません" }
$neJson = $Matches[1]
$newEvents = @($neJson | ConvertFrom-Json | ForEach-Object { $_ })
Repair-Events $newEvents "new-events.js"

# ---- legacy-events.json ----
$leFile = "$PROJECT_ROOT\data\legacy-events.json"
$legacy = @((Get-Content $leFile -Raw -Encoding UTF8) | ConvertFrom-Json | ForEach-Object { $_ })
Repair-Events $legacy "legacy-events.json"

# ---- 重複の検出（同じイベント名が複数レコードにある） ----
$dupes = @()
$byName = ($newEvents + $legacy) | Group-Object { ($_.name -replace '\s+','' -replace '[Vv][Oo][Ll]\.?','vol') }
foreach ($g in $byName) {
    if ($g.Count -gt 1) {
        $prefs = @($g.Group | ForEach-Object { $_.prefecture } | Sort-Object -Unique)
        if ($prefs.Count -gt 1) { $dupes += ,([PSCustomObject]@{ name = $g.Group[0].name; count = $g.Count; prefs = ($prefs -join ' / ') }) }
    }
}

# ---- 結果表示 ----
Write-Host ""
Write-Host "=== 都道府県の修正 $(@($changes).Count) 件 ==="
if (@($changes).Count -gt 0) {
    $changes | Format-Table @{L='収集元';E={$_.source}}, @{L='イベント名';E={ if ($_.name.Length -gt 34) { $_.name.Substring(0,34)+'…' } else { $_.name } }}, @{L='修正前';E={$_.before}}, @{L='修正後';E={$_.after}} -AutoSize
}
Write-Host "=== 都道府県が食い違う重複 $(@($dupes).Count) 件（手動確認が必要）==="
if (@($dupes).Count -gt 0) { $dupes | Format-Table -AutoSize -Wrap }

# ---- カバー都道府県数（47都道府県網羅の進捗を測る） ----
$after  = @(($newEvents + $legacy) | ForEach-Object { $_.prefecture } | Where-Object { $_ -and $_ -ne '未定' } | Sort-Object -Unique)
$missing = @($PREFS | Where-Object { $after -notcontains $_ })
Write-Host ""
Write-Host "=== カバー状況（修正後）: $($after.Count) / 47 都道府県 ==="
Write-Host "未カバー($($missing.Count)県): $($missing -join '、')"

if (-not $Apply) {
    Write-Host ""
    Write-Host "※ ドライランです。書き換えていません。実行するには -Apply を付けてください。"
    exit 0
}

# ---- 書き戻し（.bak を残す） ----
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $neFile "$neFile.bak-$stamp" -Force
Copy-Item $leFile "$leFile.bak-$stamp" -Force

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$header = "// 自動更新される。scripts/check-events.ps1 が書き換える"
$body = "window.NEW_EVENTS = " + ($newEvents | ConvertTo-Json -Depth 5 -Compress) + ";"
[IO.File]::WriteAllText($neFile, "$header`n$body`n", $utf8NoBom)
[IO.File]::WriteAllText($leFile, ($legacy | ConvertTo-Json -Depth 5), $utf8NoBom)

Write-Host ""
Write-Host "書き換えました。バックアップ: *.bak-$stamp"
