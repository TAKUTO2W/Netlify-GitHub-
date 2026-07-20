# note 自動投稿の使い方

CARJAM の note 週1投稿を自動化する仕組みです。

## 全体の流れ

```
gen-note-draft.ps1  →  note-drafts\note-draft-YYYY-MM-DD.json  →  post-to-note.ps1  →  note に下書き
   （下書きを作る係）                    （受け渡しファイル）              （アップする係）
```

- **下書きを作る係**と**アップする係**が分かれているので、片方だけ直せます。
- JSON の `status` で状態を管理します: `pending`（未投稿）→ `drafted`（下書き保存済み）。
  失敗すると `failed` になり、`lastError` に理由が入ります。

## 現時点でできること / できないこと

| | 状態 |
|---|---|
| 下書きを note に自動で作る | ✅ できる |
| 本文・タイトルを自動で入れる | ✅ できる |
| **公開（公開ボタンを押す）** | ❌ **手動**。note の公開APIが未特定のため |
| アイキャッチ画像の設定 | ❌ 手動 |

つまり今は「**note を開いたら本文が全部入った下書きができている**」状態まで自動化されます。
画像を選んで公開ボタンを押すだけになります。

---

## 初回セットアップ：Cookie を config.ps1 に貼る

note には公式APIが無いため、**ログイン状態を表す Cookie** をそのまま使います。

### 手順

1. Chrome で https://note.com を開き、`@usdmstaff` でログインしておく
2. **F12** キーを押して開発者ツール（DevTools）を開く
3. 上部のタブで **Network（ネットワーク）** を選ぶ
4. **F5** でページを再読み込みする
5. 左のリストの **いちばん上の行**（`note.com` という名前のもの）をクリック
6. 右側の **Headers（ヘッダー）** タブ → **Request Headers（リクエストヘッダー）** の中の
   **`cookie:`** の行を探す
7. その **値を全部コピー**する（`_note_session_v5=...; note_gql_auth_token=...` のように長い1行）
8. `scripts\config.ps1` をメモ帳で開き、いちばん下に次の1行を足す:

```powershell
$NOTE_COOKIE = "ここに貼り付け"
```

9. **保存したら、文字コードを UTF-8 BOM 付きに戻す**（メモ帳は cp932 で保存することがあり、
   そうなると PowerShell が日本語を読めなくなります）。戻し方:

```powershell
$p = "C:\Users\user\claude-code\car-site\scripts\config.ps1"
$t = [IO.File]::ReadAllText($p)
[IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true)))
```

### 注意

- **Cookie は期限切れになります。** 投稿が `failed` になり `lastError` に
  「Cookieが期限切れの可能性」と出たら、上の手順でやり直してください。
- `config.ps1` は `.gitignore` 済みです。**絶対にコミットしない**でください。

---

## 使い方

```powershell
cd C:\Users\user\claude-code\car-site\scripts

# 何が送られるか確認するだけ（実際には送らない）
.\post-to-note.ps1 -WhatIf

# 最新の未投稿分を下書き保存する
.\post-to-note.ps1

# 日付を指定する
.\post-to-note.ps1 -Date 2026-07-24

# failed になったものを再試行する
.\post-to-note.ps1 -Retry
```

### 安全のしくみ

- **二重投稿防止**: `status` が `drafted` の JSON は自動で飛ばされます
- **空の下書きを量産しない**: 途中で失敗しても `noteKey` を JSON に控えるので、
  再試行時は同じ下書きを使い回します
- **失敗しても黙って止まらない**: 失敗理由は `run.log` と JSON の `lastError` に残ります
- **公開はしない**: このスクリプトは下書き保存までしか行いません

---

## 毎週の自動実行につなぐ（まだ設定していません）

動作に問題がないと確認できたら、`daily-run.ps1` の
`gen-note-draft.ps1` を呼んでいる行の**直後**に次を足します:

```powershell
& "$PSScriptRoot\post-to-note.ps1"
```

---

## 技術メモ（非公式API）

note に公式APIはありません（[公式ヘルプ](https://www.help-note.com/hc/ja/articles/46643492548121)に
「公開予定も未定」と明記）。以下は 2026-07-20 に実際の通信を観測して特定した非公式仕様です。

| 手順 | 通信 |
|---|---|
| 下書きを作る | `GET note.com/notes/new` → 302 → `editor.note.com/notes/{key}/edit/` |
| key → 数値ID | `GET note.com/api/v3/notes/{key}` の `data.id`（9桁） |
| 本文を保存 | `POST note.com/api/v1/text_notes/draft_save?id={数値ID}&is_temp_saved=true` |
| アイキャッチ | `POST note.com/api/v1/image_upload/note_eyecatch`（multipart: `note_id` / `file` / `width` / `height`） |

アイキャッチの**推奨サイズは 1280×670px**。上記はすべて reCAPTCHA なしで通る。

**公開だけは自動化しない**（`PUT /api/v1/text_notes/{数値ID}` の直前に reCAPTCHA が入るため）。
判断の経緯は Obsidian の `Decisions/2026-07-20-note-publish-manual.md` 参照。

送信データ:
```json
{ "body": "<p name=\"{uuid}\" id=\"{uuid}\">本文</p>",
  "body_length": 792, "name": "タイトル",
  "index": false, "is_lead_form": false }
```

**リスク**（承知の上で採用）:
- 規約グレー。`@usdmstaff` が停止される可能性がある
- note 側の仕様変更で予告なく壊れる。壊れたら `.txt` を使った手動コピペ運用に戻せる
