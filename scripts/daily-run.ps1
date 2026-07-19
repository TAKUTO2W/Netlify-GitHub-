# ===================================================
# CARJAM 毎日の自動実行まとめスクリプト
# タスクスケジューラからこれを呼ぶ
# ===================================================

. "$PSScriptRoot\config.ps1"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $LOG_FILE -Append
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# イベント収集
& "$scriptDir\check-events.ps1"

# ブログ自動生成 + はてなブログ投稿
& "$scriptDir\gen-blog.ps1"

# イベント・記事の個別ページと sitemap.xml を生成（SEO用）
& "$scriptDir\gen-pages.ps1"

# Xにイベント告知を投稿（2日に1回・偶数日のみ）
& "$scriptDir\gen-x-events.ps1"

# note用の週末イベントまとめ下書きを生成（毎週金曜のみ・投稿は手動コピペ）
& "$scriptDir\gen-note-draft.ps1"

# GitHub に push して Netlify を自動更新
Write-Log "GitHub へ push 中..."
try {
    Set-Location $PROJECT_ROOT
    $git = "C:\Program Files\Git\cmd\git.exe"
    & $git add -A data/new-events.js data/new-blog-posts.js data/updates.js data/known-event-urls.json events articles sitemap.xml
    $today = Get-Date -Format "yyyy-MM-dd"
    & $git commit -m "auto update: $today"
    & $git push
    Write-Log "GitHub push 完了 → Netlify 自動デプロイ開始"
} catch {
    Write-Log "GitHub push エラー: $_"
}
