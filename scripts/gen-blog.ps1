# ===================================================
# CARJAM ブログ記事 自動生成スクリプト
# Claude API を使って毎日2記事生成
# ===================================================

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

function Invoke-ClaudeAPI($prompt) {
    $body = @{
        model      = "claude-haiku-4-5-20251001"
        max_tokens = 1500
        messages   = @(@{ role = "user"; content = $prompt })
    } | ConvertTo-Json -Depth 5

    $headers = @{
        "x-api-key"         = $CLAUDE_API_KEY
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }

    $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" `
        -Method POST -Headers $headers -Body $body -TimeoutSec 60
    return $response.content[0].text
}

Write-Log "=== gen-blog.ps1 開始 ==="

# APIキーチェック
if ($CLAUDE_API_KEY -eq "ここにAPIキーを貼り付けてください") {
    Write-Log "ERROR: config.ps1 の CLAUDE_API_KEY を設定してください"
    exit 1
}

# 既存の new-blog-posts.js を読み込む
$blogFile = "$PROJECT_ROOT\data\new-blog-posts.js"
$existingPosts = @()
if (Test-Path $blogFile) {
    $raw = Get-Content $blogFile -Raw
    if ($raw -match 'window\.NEW_BLOG_POSTS\s*=\s*(\[[\s\S]*?\]);') {
        try { $existingPosts = $Matches[1] | ConvertFrom-Json } catch {}
    }
}

$nextId = $NEW_BLOG_START_ID
if ($existingPosts.Count -gt 0) {
    $maxId = ($existingPosts | Measure-Object -Property id -Maximum).Maximum
    if ($maxId -ge $nextId) { $nextId = $maxId + 1 }
}

$today = Get-Date -Format "yyyy-MM-dd"
$newPosts = @()

# 既に今日の記事が生成済みかチェック
$todayPosts = @($existingPosts | Where-Object { $_.date -eq $today })
$hasCustom = ($todayPosts | Where-Object { $_.category -eq "カスタム情報" }).Count -gt 0
$hasTrouble = ($todayPosts | Where-Object { $_.category -eq "車のトラブル解消" }).Count -gt 0

# カスタム情報 記事のトピックプール（ローテーション）
$customTopics = @(
    "車高調整（ローダウンサス・エアサス）の選び方と注意点"
    "ホイール交換の基礎知識：PCD・オフセット・インセットの計算方法"
    "マフラー交換で変わる排気音と馬力アップの仕組み"
    "エアロパーツ（フロントリップ・リアディフューザー）の選び方"
    "フィルムチューニング：ウィンドウフィルムとラッピングの違い"
    "ブレーキキャリパー塗装・交換でブレーキ性能を向上させる方法"
    "ドライブレコーダー最新機種の選び方と取り付けポイント"
    "LED化でヘッドライト・テールランプをカスタムする方法"
    "シートバケット交換：純正シートとスポーツシートの違い"
    "ステアリング交換の選び方とエアバッグキャンセラーの注意事項"
    "サスペンション交換前後の違いと走行フィーリング改善方法"
    "タービン交換・ターボチューンで出力を大幅アップする方法"
    "オイルクーラー取り付けでエンジンを守る方法"
    "ロールケージ取り付けの基礎とメリット・デメリット"
    "フルコン・サブコン：ECUチューニングの基礎知識"
)

# 車のトラブル解消 記事のトピックプール
$troubleTopics = @(
    "エンジンがかからない原因TOP5と対処法"
    "タイヤのパンク応急処置と交換のタイミング"
    "エアコンが効かない原因と冷媒（ガス）補充方法"
    "ブレーキの異音・振動の原因と対処法"
    "警告灯が点灯したときの対応ガイド"
    "バッテリー上がりのジャンプスタート方法と予防法"
    "オーバーヒートの原因と冷却水（クーラント）管理方法"
    "ガラスのくもり・油膜を除去してクリアな視界を保つ方法"
    "異音（ゴトゴト・キーキー・カラカラ）別の原因と診断方法"
    "ドアが開かない・閉まらないときの応急対処法"
    "車検に通らない主な理由と事前チェックポイント"
    "オイル漏れを発見したときの緊急対応と修理方法"
    "ガス欠直前の対処法と燃費を改善するドライビングテクニック"
    "雨天時のワイパーびびり・筋が残る原因と解消方法"
    "スリップ・横滑りを防ぐ冬道・雨道の安全運転テクニック"
)

# トピック選択（日付をシードにしてローテーション）
$dayOfYear = (Get-Date).DayOfYear
$customTopic = $customTopics[$dayOfYear % $customTopics.Count]
$troubleTopic = $troubleTopics[$dayOfYear % $troubleTopics.Count]

# カスタム情報 記事を生成
if (-not $hasCustom) {
    Write-Log "カスタム情報 記事生成中: $customTopic"
    try {
        $prompt = @"
あなたは日本の車好きに向けた自動車ブログの編集者です。
以下のテーマでブログ記事を日本語で書いてください。

テーマ: $customTopic

要件:
- 文字数: 400〜600字（本文のみ）
- 読者: 車のカスタムに興味があるカーエンスージアスト
- SEO向け: テーマのキーワードを自然に含める
- タグを3〜5個提案すること
- 出力はJSON形式で以下のキーを含めること:
  { "title": "...", "excerpt": "（1〜2文のリード文）", "content": "...", "tags": ["tag1","tag2",...] }

JSONのみ出力してください（```json などのコードブロックは不要）。
"@
        $result = Invoke-ClaudeAPI $prompt
        $article = $result | ConvertFrom-Json

        $post = [PSCustomObject]@{
            id       = $nextId
            category = "カスタム情報"
            date     = $today
            title    = $article.title
            excerpt  = $article.excerpt
            content  = $article.content
            tags     = $article.tags
        }
        $newPosts += $post
        $nextId++
        Write-Log "カスタム情報 記事完了: $($article.title)"
    } catch {
        Write-Log "カスタム情報 生成エラー: $_"
    }
} else {
    Write-Log "カスタム情報 は今日生成済みのためスキップ"
}

# 車のトラブル解消 記事を生成
if (-not $hasTrouble) {
    Write-Log "車のトラブル解消 記事生成中: $troubleTopic"
    try {
        $prompt = @"
あなたは日本の車好きに向けた自動車ブログの編集者です。
以下のテーマでブログ記事を日本語で書いてください。

テーマ: $troubleTopic

要件:
- 文字数: 400〜600字（本文のみ）
- 読者: 車のトラブルに困っている一般ドライバーからカーエンスージアスト
- SEO向け: テーマのキーワードを自然に含める
- タグを3〜5個提案すること
- 出力はJSON形式で以下のキーを含めること:
  { "title": "...", "excerpt": "（1〜2文のリード文）", "content": "...", "tags": ["tag1","tag2",...] }

JSONのみ出力してください（```json などのコードブロックは不要）。
"@
        $result = Invoke-ClaudeAPI $prompt
        $article = $result | ConvertFrom-Json

        $post = [PSCustomObject]@{
            id       = $nextId
            category = "車のトラブル解消"
            date     = $today
            title    = $article.title
            excerpt  = $article.excerpt
            content  = $article.content
            tags     = $article.tags
        }
        $newPosts += $post
        $nextId++
        Write-Log "車のトラブル解消 記事完了: $($article.title)"
    } catch {
        Write-Log "車のトラブル解消 生成エラー: $_"
    }
} else {
    Write-Log "車のトラブル解消 は今日生成済みのためスキップ"
}

# new-blog-posts.js に追記
if ($newPosts.Count -gt 0) {
    $merged = @($existingPosts) + @($newPosts)
    $jsonPosts = $merged | ConvertTo-Json -Depth 5 -Compress
    if ($merged.Count -eq 1) { $jsonPosts = "[$jsonPosts]" }
    $jsContent = "// 自動更新される。scripts/gen-blog.ps1 が書き換える`nwindow.NEW_BLOG_POSTS = $jsonPosts;`n"
    Set-Content -Path $blogFile -Value $jsContent -Encoding UTF8
    Write-Log "new-blog-posts.js 更新: 合計 $($merged.Count) 件"

    # updates.js を更新
    $updatesFile = "$PROJECT_ROOT\data\updates.js"
    $currentUpdates = @{ lastChecked = $null; announcements = @() }
    if (Test-Path $updatesFile) {
        $raw = Get-Content $updatesFile -Raw
        if ($raw -match 'window\.SITE_UPDATES\s*=\s*(\{[\s\S]*?\});') {
            try { $currentUpdates = $Matches[1] | ConvertFrom-Json } catch {}
        }
    }
    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $currentUpdates.lastChecked = $now

    $ann = [PSCustomObject]@{
        type    = "blog"
        count   = $newPosts.Count
        date    = $today
        message = "ブログ記事 $($newPosts.Count) 件を更新しました"
        names   = ($newPosts | ForEach-Object { $_.title }) -join "、"
    }
    $anns = @($currentUpdates.announcements) + @($ann)
    if ($anns.Count -gt 10) { $anns = $anns | Select-Object -Last 10 }
    $currentUpdates.announcements = $anns

    $updJson = $currentUpdates | ConvertTo-Json -Depth 5 -Compress
    $updJs = "// 自動更新される。scripts/check-events.ps1 / gen-blog.ps1 が書き換える`nwindow.SITE_UPDATES = $updJson;`n"
    Set-Content -Path $updatesFile -Value $updJs -Encoding UTF8
}

Write-Log "=== gen-blog.ps1 完了 (新規: $($newPosts.Count) 件) ==="
