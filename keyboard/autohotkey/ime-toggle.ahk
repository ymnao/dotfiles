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
    ; Because CapsLock is remapped to LCtrl at the scan code level (line 22),
    ; releasing CapsLock alone also results in A_PriorKey being "LControl".
    if (A_PriorKey = "LControl") {
        ; Send IME Off key
        ; vkF3 = 無変換 (Muhenkan) - works with Microsoft IME
        Send "{vkF3}"
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
    ; Send IME On key
    ; vkF4 = 変換 (Henkan) - works with Microsoft IME
    Send "{vkF4}"
}

;---------------------------------------------------------------
; Alternative IME Key Codes (Uncomment if needed)
;---------------------------------------------------------------

; Google日本語入力の場合:
; Send "{vk1Dsc07B}"  ; 無変換
; Send "{vk1Csc079}"  ; 変換

; 一部のIMEでは以下が必要:
; IME Off: Send "{vkF3}" または Send "{Esc}{Esc}"
; IME On:  Send "{vkF4}" または Send "{vkF2}"
