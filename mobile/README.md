# スマホ操作（Android ADB + MCP）

Cursor エージェントから Android スマホを操作するための基盤です。  
**ADB（Android Debug Bridge）** でデバイスに接続し、**MCP サーバー**経由でタップ・スワイプ・スクリーンショットなどを実行できます。

> **対応**: Android（USB / ワイヤレスデバッグ）  
> **非対応**: iOS（macOS + Xcode が必要なため本構成の対象外）

## 構成

```
[Android Phone] ──USB/WiFi──> [ADB] ──> [MCP Server] ──> [Cursor Agent]
```

| コンポーネント | 役割 |
|---|---|
| `adb` | Android デバイスとの通信 |
| `mobile/mcp-server/` | Cursor 向け MCP ツール（tap, swipe, screenshot 等） |
| `mobile/scripts/` | 接続・ブリッジ用スクリプト |

## クイックスタート

### 1. インストール

```bash
cd mobile
chmod +x install.sh scripts/*.sh
./install.sh
```

### 2. スマホ側の準備

1. **開発者向けオプション**を有効化（ビルド番号を7回タップ）
2. **USBデバッグ**を ON
3. PC 接続時に「USBデバッグを許可しますか？」→ **許可**

### 3. 接続方法（いずれか）

#### A. USB（WSL2 + Windows）

WSL から USB を使うには [usbipd-win](https://learn.microsoft.com/windows/wsl/connect-usb) が必要です。

```bash
./scripts/setup-usb-wsl.sh   # 手順表示
./scripts/check-device.sh    # 接続確認
```

#### B. ワイヤレスデバッグ（同一 Wi‑Fi / 到達可能な IP）

```bash
# ペアリング（初回のみ、スマホ画面の6桁コードを使用）
adb pair 192.168.1.50:37123 123456

# 接続
./scripts/connect-wireless.sh 192.168.1.50 5555
./scripts/check-device.sh
```

#### C. Cloud Agent からローカル USB 端末を使う（SSH トンネル）

スマホは WSL の USB に接続、Cloud Agent はリモートの場合:

**WSL（端末1）** — USB 端末 + ADB サーバー:
```bash
./scripts/adb-bridge-usb.sh
```

**WSL（端末2）** — リモートへ SSH リバーストンネル:
```bash
./scripts/adb-bridge-ssh.sh ubuntu <cloud-agent-host>
```

**Cloud Agent 側**:
```bash
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
adb devices
```

### 4. Cursor MCP 設定

プロジェクトルートに `.cursor/mcp.json` を作成（`mcp.json.example` をコピー）:

```bash
cp mobile/mcp.json.example .cursor/mcp.json
```

Cursor を再起動すると、以下の MCP ツールが使えるようになります:

| ツール | 説明 |
|---|---|
| `mobile_list_devices` | 接続デバイス一覧 |
| `mobile_connect` | ワイヤレス接続 |
| `mobile_pair` | ワイヤレスペアリング |
| `mobile_screenshot` | スクリーンショット |
| `mobile_tap` | タップ |
| `mobile_swipe` | スワイプ |
| `mobile_input_text` | テキスト入力 |
| `mobile_press_key` | キー押下（HOME, BACK 等） |
| `mobile_shell` | adb shell コマンド |
| `mobile_dump_ui` | UI 階層 XML |
| `mobile_current_activity` | 現在のアプリ/Activity |
| `mobile_launch_app` | アプリ起動 |

### 5. 動作確認

Cursor でエージェントに次のように依頼:

> 接続されている Android デバイスを確認して

エージェントが `mobile_list_devices` を呼び、デバイスが表示されれば成功です。

## 環境変数

| 変数 | 説明 |
|---|---|
| `ADB_SERVER_SOCKET` | リモート ADB サーバー（例: `tcp:127.0.0.1:5037`） |
| `ADB_SERIAL` | 複数台接続時のデフォルト端末シリアル |

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `no devices` | USB デバッグ許可、ケーブル、ドライバを確認 |
| WSL で USB が見えない | usbipd-win で attach |
| Cloud Agent から見えない | SSH トンネル + `ADB_SERVER_SOCKET` を設定 |
| ワイヤレス接続失敗 | 同一ネットワーク、ファイアウォール、ペアリングを再実行 |
| `uiautomator dump` 失敗 | 画面 ON・ロック解除・対象アプリを前面に |

## セキュリティ

- ADB は端末のフル操作権限を持ちます。**信頼できる PC / ネットワーク**でのみ有効にしてください。
- `adb-bridge-usb.sh` は全インターフェースで 5037 を開きます。LAN 内の信頼できる用途に限定してください。
