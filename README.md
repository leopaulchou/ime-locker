# IME-locker

For shortcut-heavy workflows (remote desktop, design software) where Shift keeps switching your IME mid-task — lock it in place with one click.

**Languages:** [English](#english) | [繁體中文](#繁體中文)

---

## English

### What it does

IME Locker is for Windows users who rely on shortcut-heavy workflows — remote desktop sessions (e.g. Chrome Remote Desktop) or design software like Adobe Illustrator.

In these situations, a single Shift press (or other IME toggle key) can accidentally switch the input method mid-task — breaking sync in a remote session, or hijacking a keyboard shortcut meant for the app.

IME Locker lets you lock your current input method with one click. While locked, Shift / Ctrl+Space / Win+Space / Alt+Shift are blocked from switching it, so nothing changes until you manually unlock it.

### Features

- Small window showing your current input method and lock status
- One click to lock the input method you're currently on (no need to pre-select one)
- Blocks Shift, Ctrl+Space, Win+Space, and Alt+Shift while locked
- Manual unlock only — no timers, no auto-expiry
- Lightweight, keyboard-hook based — negligible CPU/memory footprint while idle

### Requirements

- Windows 10 or 11

### Install

Download the latest `.exe` from the [Releases](../../releases) page — no need to install AutoHotkey separately.

> First run may trigger a Windows SmartScreen warning (unsigned app). Click **More info → Run anyway**.

### Build from source

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Open `IMELocker.ahk` to run it directly, or use the bundled **Ahk2Exe** tool to compile it into a standalone `.exe`

### License

MIT

---

## 繁體中文

### 這個工具做什麼

IME Locker 是給需要大量使用快捷鍵的 Windows 使用者的小工具 —— 例如透過 Chrome 遠端桌面操作,或是使用 Adobe Illustrator 這類設計軟體。

在這些情境下,按一下 Shift(或其他輸入法切換鍵)就可能不小心把輸入法切掉,導致遠端桌面兩邊狀態不同步,或是軟體裡的快捷鍵被輸入法劫持。

IME Locker 讓你一鍵鎖定目前的輸入法。鎖定期間,Shift、Ctrl+Space、Win+Space、Alt+Shift 都不會把輸入法切走,直到你手動解除鎖定為止。

### 功能

- 小視窗即時顯示目前輸入法與鎖定狀態
- 一鍵鎖定「目前正在使用」的輸入法,不用事先指定
- 鎖定期間攔截 Shift、Ctrl+Space、Win+Space、Alt+Shift
- 僅支援手動解除鎖定,沒有計時器自動解鎖
- 以鍵盤 hook 為核心,待機時幾乎不耗 CPU / 記憶體

### 系統需求

- Windows 10 或 11

### 安裝方式

到 [Releases](../../releases) 頁面下載最新的 `.exe`,不需要另外安裝 AutoHotkey。

> 第一次執行可能會跳出 Windows SmartScreen 警告(因為沒有數位簽章),點選「其他資訊 → 仍要執行」即可。

### 從原始碼編譯

1. 安裝 [AutoHotkey v2](https://www.autohotkey.com/)
2. 直接開啟 `IMELocker.ahk` 執行,或用內附的 **Ahk2Exe** 工具編譯成獨立 `.exe`

### 授權

MIT
