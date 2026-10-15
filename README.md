# gpctl

`gpctl` は、macOS にインストールされている Palo Alto Networks GlobalProtect アプリを、ターミナルから操作するための小さな CLI ユーティリティです。

接続、切断、接続の更新、状態確認、および接続状態の切り替えを、マウス操作なしで実行できます。

> [!IMPORTANT]
> `gpctl` は VPN プロトコルを独自実装するクライアントではありません。
> macOS の Accessibility API を通じて、インストール済みの公式 GlobalProtect アプリを操作します。
> 認証、MFA、端末検査、および接続ポリシーは、GlobalProtect と組織側の設定に従います。

## Features

- CLI から GlobalProtect へ接続
- CLI から GlobalProtect を切断
- CLI から GlobalProtect の接続を更新
- 現在の接続状態を表示
- 接続・切断を自動的に切り替える `toggle`
- 接続・切断操作は開始後すぐに終了し、完了したかは `status` で確認
- SAML や MFA が必要な場合は、GlobalProtect またはブラウザ上の認証フローへ引き継ぎ
- パスワードやセッショントークンを保存しない
- PanGPS/PanGPA を強制終了せず、通常の GlobalProtect UI 操作として処理

## Requirements

- macOS
- Palo Alto Networks GlobalProtect がインストール済みであること
- GlobalProtect の初期セットアップが完了していること
  - ポータルが設定されていること
  - 必要な System Extension / Network Extension が許可されていること
- 現在のユーザーに、GlobalProtect の接続権限があること
- 実行元のターミナルまたは `gpctl` に、macOS の Accessibility 権限が付与されていること
- GlobalProtect の接続方式が、手動接続または手動切断を許可していること

Always-On などの管理ポリシーによって切断が禁止されている場合、`gpctl disconnect` でその制限を回避することはできません。

## Installation

この README では、実行ファイル名を `gpctl` としています。

### リポジトリ内から直接実行する

```bash
chmod +x ./gpctl
./gpctl help
```

### ユーザーの PATH へ配置する

```bash
mkdir -p "$HOME/.local/bin"
install -m 0755 ./gpctl "$HOME/.local/bin/gpctl"
```

`$HOME/.local/bin` が PATH に含まれていない場合は、次の設定を `~/.zshrc` に追加します。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

設定を現在のシェルへ反映します。

```bash
source ~/.zshrc
```

## macOS Permissions

`gpctl` は GlobalProtect の画面を操作するため、Accessibility 権限が必要です。

1. `gpctl status` または `gpctl connect` を一度実行します。
2. macOS の **System Settings** を開きます。
3. **Privacy & Security** → **Accessibility** を開きます。
4. `gpctl` を実行するターミナルアプリを許可します。
   - Terminal
   - iTerm2
   - WezTerm
   - その他の使用中のターミナル
5. **Privacy & Security** → **Automation** に確認項目が表示された場合は、ターミナルから `System Events` を操作することを許可します。
6. ターミナルを再起動し、もう一度コマンドを実行します。

> [!WARNING]
> Accessibility 権限を持つアプリは、ほかのアプリの UI を操作できます。内容を確認した信頼できる実行ファイルにだけ権限を付与してください。

## Usage

```text
gpctl <command> [options]
```

### Commands

| Command | Description |
|---|---|
| `gpctl connect` | GlobalProtect の接続操作を開始します。 |
| `gpctl disconnect` | GlobalProtect の切断操作を開始します。 |
| `gpctl refresh` | GlobalProtect の **Refresh Connection** を実行します。 |
| `gpctl status` | 現在の接続状態を表示します。 |
| `gpctl toggle` | 未接続なら接続操作、接続済みなら切断操作を開始します。 |
| `gpctl help` | ヘルプを表示します。 |
| `gpctl version` | バージョンを表示します。 |

### Options

| Option | Description |
|---|---|
| `--verbose` | UI 検出や状態判定の詳細ログを表示します。 |

## Examples

### 接続する

```bash
gpctl connect
```

`gpctl connect` は接続ボタンを押した時点で終了し、接続完了を待ちません。認証が必要な場合は GlobalProtect またはブラウザで完了し、その後 `gpctl status` で接続を確認してください。終了コード `0` は操作の開始、または既に接続済みであることを示します。
画面が既に `connecting` と表示されている場合は再操作せず、終了コード `1` で返ります。

```text
Connection started. Check 'gpctl status' to confirm it.
```

### 切断する

```bash
gpctl disconnect
```

切断操作を開始した時点で終了します。切断完了は `gpctl status` で確認してください。

### 接続を更新する

```bash
gpctl refresh
```

GlobalProtect のオプションメニューから **Refresh Connection** を選び、確認画面の同名のボタンを押して終了します。接続し直すまで待たないため、認証が必要な場合はブラウザで完了し、更新後に `gpctl status` で状態を確認してください。

### 接続状態を確認する

```bash
gpctl status
```

想定される状態は次のとおりです。

```text
connected
disconnected
connecting
disconnecting
authentication-required
unknown
```

### シェルスクリプトから使用する

```bash
if gpctl status >/dev/null 2>&1; then
  echo "GlobalProtect is connected"
else
  gpctl connect
fi
```

### 接続状態を切り替える

```bash
gpctl toggle
```

## Authentication

`gpctl` はユーザー名、パスワード、MFA コード、SAML assertion、認証 Cookie などを取得または保存しません。

認証が必要な場合は、GlobalProtect が通常どおり認証画面またはブラウザを開きます。ユーザーはその画面で認証を完了してください。

次の値をコマンドライン引数や環境変数へ保存しないでください。

- パスワード
- ワンタイムパスワード
- SAML response
- セッション Cookie
- クライアント証明書の秘密鍵

コマンドライン引数や環境変数は、プロセス情報、シェル履歴、デバッグログなどから露出する可能性があります。

## Exit Codes

| Code | Meaning |
|---:|---|
| `0` | 操作を開始したか、既に目的の状態です。`status` の場合は接続済みです。 |
| `1` | 接続・切断操作を開始しませんでした。`status` の場合は接続済み以外の判定可能な状態です。 |
| `2` | 引数またはコマンドの指定が不正です。 |
| `3` | GlobalProtect が見つからない、または起動できません。 |
| `4` | Accessibility / Automation 権限が不足しています。 |
| `6` | GlobalProtect の状態または UI を判定できませんでした。 |

## How It Works

`gpctl connect` は、概ね次の順序で動作します。

1. `/Applications/GlobalProtect.app` の存在を確認します。
2. GlobalProtect が起動していなければ起動します。
3. `osascript` と `System Events` を使用して GlobalProtect の UI 状態を 1 回取得します。
4. 接続可能な状態であれば、表示されている **Connect** ボタンを 1 回押します。クリック時にポップオーバーが閉じていた場合は、再表示せずエラーで終了します。
5. 状態を再取得せずに終了します。接続完了は後から `gpctl status` で確認します。

`gpctl disconnect` も状態を 1 回取得し、必要な場合に **Disconnect** ボタンを 1 回押して終了します。`gpctl toggle` は 1 回取得した状態に応じて接続または切断を選びます。
`gpctl refresh` はオプションメニューの **Refresh Connection** を選び、確認画面のボタンを押して終了します。更新後の接続状態は監視しません。

`status` は GlobalProtect の画面表示を読み取ります。画面が `connecting` のまま固まっている場合、接続処理が進行中とは限りません。
`status` はポップオーバーを閉じずに戻るため、画面が表示されたままになる場合があります。

このツールは、通常の接続または切断のために次の操作を行いません。

- PanGPS/PanGPA の強制終了
- `launchctl` による GlobalProtect サービスの unload
- GlobalProtect の設定ファイルや認証 Cookie の直接編集
- 組織が設定した Always-On、MFA、HIP、端末証明書、またはアクセス制御の回避

## Troubleshooting

### Accessibility 権限のエラーになる

代表的なエラー例です。

```text
System Events got an error: osascript is not allowed assistive access
Not authorized to send Apple events to System Events
```

次を確認してください。

1. **System Settings** → **Privacy & Security** → **Accessibility** で、実行元のターミナルを許可します。
2. **Automation** に表示されている `System Events` の操作も許可します。
3. ターミナルを完全に終了してから再起動します。
4. `gpctl status --verbose` を再実行します。

### GlobalProtect が見つからない

```bash
test -d /Applications/GlobalProtect.app && echo found || echo not-found
```

`not-found` と表示される場合は、組織が提供する手順で公式 GlobalProtect アプリをインストールしてください。

### UI element not found と表示される

GlobalProtect の更新、表示言語、または UI 構造の変更によって、対象のボタンを検出できなくなっている可能性があります。

```bash
gpctl status --verbose
open -a GlobalProtect
```

GlobalProtect の画面を手動で開き、次を確認してください。

- サインイン画面やエラーダイアログが前面に出ていないか
- 接続ボタンが利用可能か
- ポータルが設定されているか
- 管理ポリシーによって操作が制限されていないか

### 操作後も接続されない

`gpctl status` で状態を確認し、次を調べてください。

- ブラウザまたは GlobalProtect 内で認証が完了しているか
- MFA の承認待ちになっていないか
- System Extension / Network Extension が許可されているか
- インターネットへ接続できるか
- GlobalProtect のポータルへ到達できるか
- GlobalProtect 自体にエラーが表示されていないか

UI の状態を詳しく見るには `gpctl status --verbose` を実行します。

### 切断できない

GlobalProtect が Always-On などの管理モードで構成されている場合、ユーザーによる切断が禁止されることがあります。`gpctl` はこの制限を解除または回避しません。

### GlobalProtect のログを確認する

ユーザー側エージェントのログです。

```bash
tail -f "$HOME/Library/Logs/PaloAltoNetworks/GlobalProtect/PanGPA.log"
```

GlobalProtect サービスのログです。

```bash
sudo tail -f "/Library/Logs/PaloAltoNetworks/GlobalProtect/PanGPS.log"
```

> [!CAUTION]
> GlobalProtect のログには、社内ホスト名、ポータル名、ユーザー情報、ネットワーク情報などが含まれる場合があります。Issue やチャットへ貼り付ける前に、機密情報を削除してください。

## Limitations

- GlobalProtect の UI 構造に依存するため、GlobalProtect の更新で動作しなくなる可能性があります。
- 表示言語によって UI ラベルが異なる場合、追加対応が必要になることがあります。
- SAML、MFA、Touch ID、クライアント証明書選択などの対話操作を完全に無人化するものではありません。
- GUI セッションが必要です。SSH のみの headless セッションや、ログインユーザーが存在しない環境では使用できません。
- Always-On など、管理者が操作を制限している構成では、一部のコマンドを実行できません。
- 複数の macOS ユーザーが同時にログインしている環境では、意図した GUI セッションを操作できない場合があります。

## Security Notes

- 通常の実行に `sudo` を使用しないでください。
- パスワードや MFA コードを設定ファイルへ保存しないでください。
- GlobalProtect の Cookie や設定ファイルを直接解析・変更しないでください。
- Accessibility 権限は、ソースまたは配布元を確認した実行ファイルにだけ付与してください。
- 組織の VPN、端末管理、情報セキュリティ、および Acceptable Use Policy に従って使用してください。

## References

- [Palo Alto Networks: Use the GlobalProtect App for macOS](https://docs.paloaltonetworks.com/globalprotect/user-guide/6-3/globalprotect-app-for-mac/use-the-globalprotect-app-for-mac)
- [Apple: Change Privacy & Security settings on Mac](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)
- [Apple: Automating the User Interface](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html)

## Disclaimer

このプロジェクトは Palo Alto Networks, Inc. と提携、承認、または後援されているものではありません。

GlobalProtect は Palo Alto Networks, Inc. の商標です。

## License

ライセンスについては [`LICENSE`](./LICENSE) を参照してください。
