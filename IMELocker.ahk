#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
KeyHistory 0
ListLines False

;@Ahk2Exe-SetName IME Locker
;@Ahk2Exe-SetDescription IME Locker 輸入法鎖定工具
;@Ahk2Exe-SetVersion 0.1.0

; =============================================================================
; IME Locker：鎖定期間無法用鍵盤切換輸入法，用滑鼠切換則照常可用
;   - 鍵盤 hook 只在鎖定期間啟用，攔截 / 打斷常見的輸入法切換鍵
;   - 計時器 + 前景視窗切換事件做低頻檢查：
;       切換鍵按下後不久發生的變化 → 視為誤觸，切回
;       其他變化（例如用滑鼠點工作列切換）→ 視為主動切換，記成新的鎖定狀態
; =============================================================================

; ===== 可調整常數 =====
CHECK_INTERVAL_MS    := 750   ; 背景檢查與畫面更新間隔（建議 500–1000）
QUICK_CHECK_DELAY_MS := 150   ; 攔截到切換鍵、或前景視窗切換後，多久做一次即時檢查
MAX_QUICK_RETRY      := 3     ; 切回失敗時的快速重試次數，之後交給一般計時器
KEY_TRIGGER_WINDOW_MS := 1000 ; 切換鍵按下後多久內發生的變化視為鍵盤誤觸
RESTORE_WINDOW_MS    := 1500  ; 開始切回後，這段時間內持續切回（避免把切到一半的狀態當成新目標）
MASK_KEY             := "{vkE8}"  ; 無作用的虛擬鍵，用來打斷「單擊 Shift」等判定

; 鎖定期間直接吞掉的熱鍵。注意：Illustrator 的 Ctrl+Space 是放大鏡工具，
; 若需要保留可把 "$^Space" 移除（代價是 Ctrl+Space 可能切換輸入法開關，會由背景檢查切回）
BLOCKED_HOTKEYS := ["$^Space", "$#Space", "$+#Space"]
; 鎖定期間監看的修飾鍵：Shift 按下時送出 MASK_KEY，讓 Shift 單擊 / Alt+Shift / Ctrl+Shift 失效
MASKED_MODIFIERS := ["LShift", "RShift", "LAlt", "RAlt", "LCtrl", "RCtrl"]

; ===== Win32 / TSF 常數 =====
WM_INPUTLANGCHANGEREQUEST := 0x50
WM_IME_CONTROL            := 0x283
IMC_GETCONVERSIONMODE     := 0x1
IMC_SETCONVERSIONMODE     := 0x2
IMC_GETOPENSTATUS         := 0x5
IMC_SETOPENSTATUS         := 0x6
IME_CMODE_NATIVE          := 0x1
CMODE_COMPARE_MASK        := 0xB  ; NATIVE | KATAKANA | FULLSHAPE
TF_PROFILETYPE_INPUTPROCESSOR := 1
TF_PROFILETYPE_KEYBOARDLAYOUT := 2
TF_IPPMF_FORSESSION                     := 0x20000000
TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE   := 0x4

; ===== 狀態 =====
g_locked      := false
g_target      := ""        ; 鎖定時記錄的輸入法狀態
g_lastExtHwnd := DllCall("GetForegroundWindow", "Ptr")  ; 最近一個非本程式的前景視窗
g_lastShown   := ""
g_busy        := false
g_retry       := 0
g_lastKeyTick := 0         ; 最近一次按下切換鍵的時間
g_restoreUntil := 0        ; 目前這輪切回的截止時間
g_keyDown     := Map()     ; 避免按住修飾鍵時的 auto-repeat 重複送出 MASK_KEY
g_nameCache   := Map()
g_quickCheck  := Tick.Bind()  ; 與週期計時器分開的一次性計時器
g_tsf         := TsfInit()

; ===== 介面 =====
g_gui := Gui("+AlwaysOnTop -MaximizeBox", "IME Locker")
g_gui.MarginX := 14, g_gui.MarginY := 12
g_gui.SetFont("s9 cGray", "Microsoft JhengHei UI")
g_gui.Add("Text", "w300", "目前輸入法")
g_gui.SetFont("s11 cDefault")
g_txtIme := g_gui.Add("Text", "w300 r2", "讀取中…")
g_gui.SetFont("s10 bold")
g_txtStatus := g_gui.Add("Text", "w300 r2 cGray", "○ 未鎖定")
g_gui.SetFont("s10 norm")
g_btn := g_gui.Add("Button", "w300 h36", "鎖定")
g_btn.OnEvent("Click", ToggleLock)
g_gui.OnEvent("Close", (*) => ExitApp())

InitHotkeys()
DllCall("RegisterShellHookWindow", "Ptr", g_gui.Hwnd)
OnMessage(DllCall("RegisterWindowMessageW", "Str", "SHELLHOOK", "UInt"), OnShellMsg)

g_gui.Show()
Tick()
SetTimer(Tick, CHECK_INTERVAL_MS)

; =============================================================================
; 鎖定 / 解除
; =============================================================================

ToggleLock(*) {
    global g_locked, g_target, g_retry
    if !g_locked {
        s := ReadState(CurrentTargetHwnd())
        if !s {
            MsgBox("無法讀取目前輸入法，請先切到要操作的視窗再試一次。", "IME Locker", "Icon!")
            return
        }
        g_target := s
        g_retry := 0
        g_locked := true
        SetHooks(true)
    } else {
        g_locked := false
        SetHooks(false)
        g_target := ""
    }
    UpdateStatusUi()
}

UpdateStatusUi() {
    if g_locked {
        g_txtStatus.SetFont("cC62828")
        g_txtStatus.Value := "● 已鎖定：" StateName(g_target)
        g_btn.Text := "解除鎖定"
    } else {
        g_txtStatus.SetFont("cGray")
        g_txtStatus.Value := "○ 未鎖定"
        g_btn.Text := "鎖定"
    }
}

UpdateImeText(cur) {
    global g_lastShown
    name := StateName(cur)
    if name != g_lastShown {
        g_txtIme.Value := name
        g_lastShown := name
    }
}

; =============================================================================
; 熱鍵（只在鎖定期間啟用；全部關閉時 AHK 會卸除鍵盤 hook）
; =============================================================================

InitHotkeys() {
    for hk in BLOCKED_HOTKEYS
        Hotkey(hk, OnBlocked, "Off")
    for key in MASKED_MODIFIERS {
        Hotkey("~*" key, OnModDown, "Off")
        Hotkey("~*" key " up", OnModUp, "Off")
    }
}

SetHooks(on) {
    opt := on ? "On" : "Off"
    for hk in BLOCKED_HOTKEYS
        Hotkey(hk, opt)
    for key in MASKED_MODIFIERS {
        Hotkey("~*" key, opt)
        Hotkey("~*" key " up", opt)
    }
    g_keyDown.Clear()
}

OnBlocked(*) {
    NoteSwitchKey()
    SetTimer(g_quickCheck, -QUICK_CHECK_DELAY_MS)
}

; 記錄切換鍵的時間。若距離上次按鍵已久，先檢查一次，把按鍵之前就發生的變化
; （例如剛用滑鼠切換、還沒被計時器偵測到）記成新目標，避免被這次按鍵誤判而切回
NoteSwitchKey() {
    global g_lastKeyTick
    if A_TickCount - g_lastKeyTick > KEY_TRIGGER_WINDOW_MS
        Tick()
    g_lastKeyTick := A_TickCount
}

; Shift 按下後立刻插入一個無作用鍵，系統 / IME 就不會把它當成「單擊 Shift」
; 或「Alt+Shift」「Ctrl+Shift」組合；按鍵本身照常送出，不影響大寫與快捷鍵
OnModDown(hk) {
    key := SubStr(hk, 3)  ; "~*LShift" -> "LShift"
    if g_keyDown.Has(key)
        return
    g_keyDown[key] := true
    if InStr(key, "Shift") || GetKeyState("Shift") {
        SendInput("{Blind}" MASK_KEY)
        NoteSwitchKey()
    }
}

OnModUp(hk) {
    key := SubStr(hk, 3, -3)  ; "~*LShift up" -> "LShift"
    if g_keyDown.Has(key)
        g_keyDown.Delete(key)
    if InStr(key, "Shift") || GetKeyState("Shift") {
        NoteSwitchKey()
        SetTimer(g_quickCheck, -QUICK_CHECK_DELAY_MS)
    }
}

; 前景視窗切換：記錄最後一個外部視窗，並立即檢查一次
OnShellMsg(wParam, lParam, *) {
    global g_lastExtHwnd
    if (wParam = 4 || wParam = 0x8004) && lParam && !IsOwnWindow(lParam) {  ; HSHELL_(RUDE)WINDOWACTIVATED
        g_lastExtHwnd := lParam
        SetTimer(g_quickCheck, -QUICK_CHECK_DELAY_MS)
    }
}

; =============================================================================
; 檢查與切回
; =============================================================================

Tick() {
    global g_busy, g_retry
    if g_busy
        return
    g_busy := true
    try {
        if !g_locked && WinGetMinMax(g_gui.Hwnd) = -1
            return
        cur := ReadState(CurrentTargetHwnd())
        if !cur
            return
        if g_locked && (what := Diff(cur, g_target)) {
            if A_TickCount - g_lastKeyTick <= KEY_TRIGGER_WINDOW_MS || A_TickCount < g_restoreUntil
                Restore(cur, what)
            else
                AdoptTarget(cur)
        } else {
            g_retry := 0
        }
        UpdateImeText(cur)
    } catch {
        ; 視窗在讀取途中關閉等暫時性錯誤，下次檢查再處理
    } finally {
        g_busy := false
    }
}

Diff(cur, tgt) {
    if cur.hkl != tgt.hkl
        return "hkl"
    if tgt.prof && cur.prof && cur.prof.key != tgt.prof.key
        return "profile"
    if tgt.isIme && tgt.open != "" && tgt.conv != "" && cur.open != "" && cur.conv != "" {
        if (cur.open != 0) != (tgt.open != 0)
            return "conv"
        if tgt.open && (cur.conv & CMODE_COMPARE_MASK) != (tgt.conv & CMODE_COMPARE_MASK)
            return "conv"
    }
    return ""
}

; 不是按鍵造成的變化（例如用滑鼠切換），改鎖定在新的狀態
AdoptTarget(cur) {
    global g_target, g_retry
    g_target := cur
    g_retry := 0
    UpdateStatusUi()
}

Restore(cur, what) {
    global g_retry, g_restoreUntil
    if A_TickCount >= g_restoreUntil {
        g_restoreUntil := A_TickCount + RESTORE_WINDOW_MS
        g_retry := 0
    }
    switch what {
        case "hkl":
            DllCall("PostMessageW", "Ptr", cur.hwnd, "UInt", WM_INPUTLANGCHANGEREQUEST, "Ptr", 0, "Ptr", g_target.hkl)
        case "profile":
            ActivateTsfProfile(g_target.prof)
        case "conv":
            if imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", cur.hwnd, "Ptr") {
                ImeControl(imeWnd, IMC_SETOPENSTATUS, g_target.open)
                if g_target.open
                    ImeControl(imeWnd, IMC_SETCONVERSIONMODE, g_target.conv)
            }
    }
    ; 切回分好幾層（鍵盤配置 → TSF 輸入法 → 中/英模式），稍後再檢查一次直到一致
    if ++g_retry <= MAX_QUICK_RETRY
        SetTimer(g_quickCheck, -200)
}

; =============================================================================
; 讀取輸入法狀態
; =============================================================================

; 前景是本程式視窗時（例如剛按下按鈕），改以最後一個外部視窗為準
CurrentTargetHwnd() {
    global g_lastExtHwnd
    fg := DllCall("GetForegroundWindow", "Ptr")
    if fg && !IsOwnWindow(fg) {
        g_lastExtHwnd := fg
        return fg
    }
    return (g_lastExtHwnd && DllCall("IsWindow", "Ptr", g_lastExtHwnd)) ? g_lastExtHwnd : fg
}

IsOwnWindow(hwnd) {
    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    return pid = DllCall("GetCurrentProcessId", "UInt")
}

ReadState(hwnd) {
    if !hwnd || !DllCall("IsWindow", "Ptr", hwnd)
        return ""
    tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
    hkl := DllCall("GetKeyboardLayout", "UInt", tid, "Ptr")
    ; TSF 讀到的是本程式執行緒的輸入法；語言對不上表示不是同一份狀態，不採用
    prof := ReadTsfProfile()
    if prof && prof.langid != (hkl & 0xFFFF)
        prof := ""
    isIme := (prof && prof.type = TF_PROFILETYPE_INPUTPROCESSOR) || ((hkl & 0xFFFFFFFF) >> 28) = 0xE
    open := "", conv := ""
    if isIme && (imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")) {
        open := ImeControl(imeWnd, IMC_GETOPENSTATUS)
        conv := ImeControl(imeWnd, IMC_GETCONVERSIONMODE)
    }
    return {hwnd: hwnd, hkl: hkl, prof: prof, isIme: isIme, open: open, conv: conv}
}

ImeControl(imeWnd, cmd, value := 0) {
    result := 0
    ok := DllCall("SendMessageTimeoutW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", cmd, "Ptr", value
        , "UInt", 0x2, "UInt", 100, "Ptr*", &result, "Ptr")  ; SMTO_ABORTIFHUNG
    return ok ? result : ""
}

StateName(s) {
    key := s.prof ? s.prof.key : "HKL:" Format("{:08X}", s.hkl & 0xFFFFFFFF)
    if !g_nameCache.Has(key) {
        desc := (s.prof && s.prof.type = TF_PROFILETYPE_INPUTPROCESSOR) ? TsfProfileDesc(s.prof) : ""
        if desc = ""
            desc := LayoutNameFromHkl((s.prof && s.prof.type = TF_PROFILETYPE_KEYBOARDLAYOUT) ? s.prof.hkl : s.hkl)
        lang := LanguageName(s.hkl & 0xFFFF)
        g_nameCache[key] := desc = "" ? lang : lang "（" desc "）"
    }
    name := g_nameCache[key]
    if s.isIme && s.open != ""
        name .= "｜" ((s.open && s.conv != "" && (s.conv & IME_CMODE_NATIVE)) ? "中文模式" : "英數模式")
    return name
}

LanguageName(langid) {
    buf := Buffer(256, 0)
    if DllCall("GetLocaleInfoW", "UInt", langid, "UInt", 0x6F, "Ptr", buf, "Int", 128)  ; LOCALE_SLOCALIZEDLANGUAGENAME
        return StrGet(buf, "UTF-16")
    return Format("0x{:04X}", langid)
}

LayoutNameFromHkl(hkl) {
    static root := "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts"
    hkl &= 0xFFFFFFFF
    hi := hkl >> 16
    klid := ""
    if (hi & 0xF000) = 0xE000 {          ; 舊式 IMM 輸入法，例如 E0200404
        klid := Format("{:08X}", hkl)
    } else if (hi & 0xF000) = 0xF000 {   ; 變體配置，用 Layout Id 反查
        want := hi & 0x0FFF
        Loop Reg, root, "K" {
            try {
                if Integer("0x" RegRead(A_LoopRegKey "\" A_LoopRegName, "Layout Id")) = want {
                    klid := A_LoopRegName
                    break
                }
            }
        }
    } else {
        klid := Format("{:08X}", hi)
    }
    if klid = ""
        return ""
    key := root "\" klid
    try {
        disp := RegRead(key, "Layout Display Name")
        if SubStr(disp, 1, 1) = "@" {
            out := Buffer(1024, 0)
            if DllCall("shlwapi\SHLoadIndirectString", "WStr", disp, "Ptr", out, "UInt", 512, "Ptr", 0) = 0
                return StrGet(out, "UTF-16")
        }
    }
    try return RegRead(key, "Layout Text")
    return ""
}

; =============================================================================
; TSF（注音、新版嘸蝦米等 TSF 輸入法共用同一個 HKL，只能靠 TSF profile 區分）
; =============================================================================

TsfInit() {
    try {
        mgr := ComObject("{33C53A50-F456-4884-B049-85FD643ECFED}", "{71C6E74C-0F28-11D8-A82A-00065B84435C}")  ; ITfInputProcessorProfileMgr
        profiles := ComObjQuery(mgr, "{1F02B6C5-7842-4EE6-8A0B-9A24183A95CA}")  ; ITfInputProcessorProfiles
        return {mgr: mgr, profiles: profiles, catid: GuidBuf("{34745C63-B2F0-4784-8B67-5E12C8701A31}")}  ; GUID_TFCAT_TIP_KEYBOARD
    }
    return ""
}

ReadTsfProfile() {
    static size := A_PtrSize = 8 ? 88 : 72     ; sizeof(TF_INPUTPROCESSORPROFILE)
    static offHkl := A_PtrSize = 8 ? 72 : 64
    if !g_tsf
        return ""
    p := Buffer(size, 0)
    try ComCall(10, g_tsf.mgr, "Ptr", g_tsf.catid, "Ptr", p)  ; GetActiveProfile
    catch
        return ""
    type := NumGet(p, 0, "UInt")
    if type != TF_PROFILETYPE_INPUTPROCESSOR && type != TF_PROFILETYPE_KEYBOARDLAYOUT
        return ""
    prof := {type: type, langid: NumGet(p, 4, "UShort"), hkl: NumGet(p, offHkl, "Ptr")
        , clsid: Buffer(16, 0), guid: Buffer(16, 0)}
    if type = TF_PROFILETYPE_INPUTPROCESSOR {
        DllCall("RtlMoveMemory", "Ptr", prof.clsid, "Ptr", p.Ptr + 8, "Ptr", 16)
        DllCall("RtlMoveMemory", "Ptr", prof.guid, "Ptr", p.Ptr + 24, "Ptr", 16)
        prof.key := GuidStr(prof.clsid) GuidStr(prof.guid)
    } else {
        prof.key := "HKL:" Format("{:08X}", prof.hkl & 0xFFFFFFFF)
    }
    return prof
}

TsfProfileDesc(prof) {
    bstr := 0
    try ComCall(12, g_tsf.profiles, "Ptr", prof.clsid, "UShort", prof.langid, "Ptr", prof.guid, "Ptr*", &bstr)  ; GetLanguageProfileDescription
    catch
        return ""
    if !bstr
        return ""
    s := StrGet(bstr, "UTF-16")
    DllCall("oleaut32\SysFreeString", "Ptr", bstr)
    return s
}

ActivateTsfProfile(prof) {
    if !g_tsf || !prof
        return
    try ComCall(3, g_tsf.mgr, "UInt", prof.type, "UShort", prof.langid, "Ptr", prof.clsid, "Ptr", prof.guid
        , "Ptr", prof.type = TF_PROFILETYPE_KEYBOARDLAYOUT ? prof.hkl : 0
        , "UInt", TF_IPPMF_FORSESSION | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE)  ; ActivateProfile
}

GuidBuf(str) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", str, "Ptr", buf, "HRESULT")
    return buf
}

GuidStr(ptr) {
    buf := Buffer(78, 0)
    DllCall("ole32\StringFromGUID2", "Ptr", ptr, "Ptr", buf, "Int", 39)
    return StrGet(buf, "UTF-16")
}
