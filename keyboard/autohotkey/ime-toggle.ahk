; IME Toggle Module for AutoHotkey v2
; Replicates Karabiner-Elements IME behavior on Windows
;
; Features:
; - CapsLock → Left Ctrl
; - Left Ctrl (alone) → IME Off (英数/半角)
; - Left Ctrl + Space → IME On (かな/全角)
;
; Note: Only LEFT Ctrl triggers IME toggle (not Right Ctrl).
; This matches macOS Karabiner behavior where CapsLock→Ctrl is used.

#Requires AutoHotkey v2.0

;---------------------------------------------------------------
; IME Control Constants
;---------------------------------------------------------------
global WM_IME_CONTROL := 0x283
global IMC_SETOPENSTATUS := 0x6
global IMC_SETCONVERSIONMODE := 0x2
global IME_CMODE_NATIVE := 0x0001
global IME_CMODE_FULLSHAPE := 0x0008
global IME_CMODE_HIRAGANA := IME_CMODE_NATIVE | IME_CMODE_FULLSHAPE

;---------------------------------------------------------------
; IME Control Functions (using WM_IME_CONTROL)
;
; Uses ImmGetDefaultIMEWnd + WM_IME_CONTROL for IME control.
; This approach was confirmed working for IME Off.
;
; Note: These are best-effort operations. IME behavior can vary
; depending on the IME implementation (Microsoft IME, Google IME, etc.)
;---------------------------------------------------------------

; Get IME window handle for the active window
IME_GetWindow(winTitle := "A") {
    hwnd := WinExist(winTitle)
    if !hwnd
        return 0
    return DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
}

; Turn IME Off
IME_Off(winTitle := "A") {
    global WM_IME_CONTROL, IMC_SETOPENSTATUS

    imeWnd := IME_GetWindow(winTitle)
    if !imeWnd
        return

    DllCall("user32\SendMessageW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", IMC_SETOPENSTATUS, "Ptr", 0)
}

; Turn IME On (to Hiragana mode)
IME_On(winTitle := "A") {
    global WM_IME_CONTROL, IMC_SETOPENSTATUS, IMC_SETCONVERSIONMODE, IME_CMODE_HIRAGANA

    imeWnd := IME_GetWindow(winTitle)
    if !imeWnd
        return

    ; Turn IME on
    DllCall("user32\SendMessageW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", IMC_SETOPENSTATUS, "Ptr", 1)
    ; Set to Hiragana mode
    DllCall("user32\SendMessageW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", IMC_SETCONVERSIONMODE, "Ptr", IME_CMODE_HIRAGANA)
}

;---------------------------------------------------------------
; CapsLock → Left Control
;---------------------------------------------------------------

; Ensure CapsLock is always off
SetCapsLockState "AlwaysOff"

; Remap CapsLock to Left Control
*CapsLock::LCtrl

;---------------------------------------------------------------
; Left Control (alone) → IME Off
; Uses A_PriorKey to detect if Ctrl was pressed alone
;---------------------------------------------------------------

~LCtrl up:: {
    ; A_PriorKey contains the name of the last key pressed before the current one
    ; If it's "LControl", that means Left Ctrl was pressed and released without other keys.
    ; Because CapsLock is remapped to LCtrl by AutoHotkey,
    ; releasing CapsLock alone also results in A_PriorKey being "LControl".
    if (A_PriorKey = "LControl") {
        IME_Off()
    }
}

;---------------------------------------------------------------
; Left Control + Space → IME On
;---------------------------------------------------------------

; Use LCtrl & Space syntax so remapped CapsLock→LCtrl also works correctly.
; Note: Having just this one custom combination is fine - the original issue
; was caused by defining 80+ LCtrl & key combinations which interfered with
; normal Ctrl shortcuts.
LCtrl & Space:: {
    IME_On()
}
