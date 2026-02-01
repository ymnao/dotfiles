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
; IME Control Functions (using Windows API)
; These functions directly control IME state without relying on
; keyboard shortcuts that may behave differently per IME settings.
;---------------------------------------------------------------

; Set IME status (0 = Off, 1 = On)
; Note: This is a best-effort operation. The IME API return value is
; IME-implementation-defined and not reliable for success/failure detection.
IME_SetState(state, winTitle := "A") {
    static WM_IME_CONTROL := 0x283
    static IMC_SETOPENSTATUS := 0x6

    hwnd := WinExist(winTitle)
    if !hwnd
        return

    imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    if !imeWnd
        return

    DllCall("user32\SendMessageW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", IMC_SETOPENSTATUS, "Ptr", state)
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
        ; Use API to reliably turn IME Off
        IME_SetState(0)
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
    ; Send Henkan (変換) key to switch to Hiragana mode.
    ; Note: IME_SetState(1) only turns IME "on" but doesn't guarantee Hiragana mode,
    ; so we use key simulation here (asymmetric with IME Off which uses API).
    ; For Microsoft IME, vkF4 reliably switches to Hiragana input.
    ; For Google Japanese Input, use vk1Csc079 instead:
    ;   Send "{vk1Csc079}"
    Send "{vkF4}"
}
