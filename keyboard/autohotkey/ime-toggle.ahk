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
; IME Control Functions (using Windows IMM32 API)
;
; Uses ImmSetOpenStatus / ImmSetConversionStatus for reliable
; IME control. This is more reliable than WM_IME_CONTROL messages
; or sending virtual keys (vkF3/vkF4) which may toggle instead of
; setting a specific state depending on IME configuration.
;
; Note: These are best-effort operations. IME behavior can vary
; depending on the IME implementation (Microsoft IME, Google IME, etc.)
;---------------------------------------------------------------

; Turn IME Off (半角/英数)
IME_Off(winTitle := "A") {
    hwnd := WinExist(winTitle)
    if !hwnd
        return

    hIMC := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if !hIMC
        return

    DllCall("imm32\ImmSetOpenStatus", "Ptr", hIMC, "Int", 0)
    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", hIMC)
}

; Turn IME On and set to Hiragana mode (ひらがな/全角)
IME_On(winTitle := "A") {
    static IME_CMODE_NATIVE := 0x0001      ; Japanese mode
    static IME_CMODE_FULLSHAPE := 0x0008   ; Full-width characters
    static IME_CMODE_HIRAGANA := IME_CMODE_NATIVE | IME_CMODE_FULLSHAPE

    hwnd := WinExist(winTitle)
    if !hwnd
        return

    hIMC := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if !hIMC
        return

    ; Turn IME on
    DllCall("imm32\ImmSetOpenStatus", "Ptr", hIMC, "Int", 1)

    ; Set conversion mode to Hiragana
    ; Second parameter: conversion mode, Third parameter: sentence mode (0 = default)
    DllCall("imm32\ImmSetConversionStatus", "Ptr", hIMC, "UInt", IME_CMODE_HIRAGANA, "UInt", 0)

    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", hIMC)
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
