# ===================================================
# CARJAM タスクスケジューラ セットアップ
# 管理者権限で一度だけ実行すること
# ===================================================

$scriptPath = "$PSScriptRoot\daily-run.ps1"
$taskName   = "CARJAM_DailyUpdate"

# 既存タスクを削除して再登録
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# トリガー: 毎日 09:00、PCが起動していなかった場合も次回起動時に実行
$trigger = New-ScheduledTaskTrigger -Daily -At "09:00"
$trigger.ExecutionTimeLimit = "PT1H"  # 最大1時間

# アクション: PowerShell でスクリプトを実行
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""

# 設定: PC起動後に実行されるよう RunMissedIfAvailable を有効化
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -StartWhenAvailable `        # ← 起動していなかったら次回起動時に実行
    -RunOnlyIfNetworkAvailable   # ネット接続必須

# 現在のユーザーで登録（ログオン時のみ実行）
Register-ScheduledTask `
    -TaskName $taskName `
    -Trigger $trigger `
    -Action $action `
    -Settings $settings `
    -Description "CARJAMサイトの毎日更新：イベント収集＋ブログ自動生成" `
    -RunLevel Highest `
    -Force

Write-Host "✅ タスクスケジューラに登録しました: $taskName"
Write-Host "   実行時刻: 毎日 09:00"
Write-Host "   PC起動後キャッチアップ: 有効"
Write-Host ""
Write-Host "📝 次のステップ:"
Write-Host "   1. scripts\config.ps1 を開いて CLAUDE_API_KEY を設定"
Write-Host "   2. テスト実行: powershell -File '$scriptPath'"
