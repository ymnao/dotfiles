; IME Toggle Module for AutoHotkey v2
; Replicates Karabiner-Elements IME behavior on Windows
;
; Features:
; - CapsLock → Left Ctrl
; - Left Ctrl (alone) → IME Off (英数/半角)
; - Left Ctrl + Space → IME On (かな/全角)
;
; This provides a similar experience to macOS Karabiner-Elements
; for Japanese input method switching.

#Requires AutoHotkey v2.0

;---------------------------------------------------------------
; CapsLock → Left Control
;---------------------------------------------------------------

; Ensure CapsLock is always off
SetCapsLockState "AlwaysOff"

; Remap CapsLock to Left Control
; * = Fire regardless of modifier state
; Note: A_PriorKey will be "LControl" when CapsLock (remapped to LCtrl) is released,
; because the remapping happens at the scan code level.
*CapsLock::LCtrl

;---------------------------------------------------------------
; Left Control (alone) → IME Off
;---------------------------------------------------------------

; Track if other keys were pressed while Ctrl was held
global ctrlUsedWithOtherKey := false

; When any key is pressed while Ctrl is down, mark it as used
; Note: Explicit listing is used instead of a loop for:
;   1. Easier debugging (can comment out individual keys)
;   2. Explicit visibility of which keys are handled
;   3. Ability to customize individual key behavior if needed
; Letters (a-z)
~LCtrl & a::ctrlUsedWithOtherKey := true
~LCtrl & b::ctrlUsedWithOtherKey := true
~LCtrl & c::ctrlUsedWithOtherKey := true
~LCtrl & d::ctrlUsedWithOtherKey := true
~LCtrl & e::ctrlUsedWithOtherKey := true
~LCtrl & f::ctrlUsedWithOtherKey := true
~LCtrl & g::ctrlUsedWithOtherKey := true
~LCtrl & h::ctrlUsedWithOtherKey := true
~LCtrl & i::ctrlUsedWithOtherKey := true
~LCtrl & j::ctrlUsedWithOtherKey := true
~LCtrl & k::ctrlUsedWithOtherKey := true
~LCtrl & l::ctrlUsedWithOtherKey := true
~LCtrl & m::ctrlUsedWithOtherKey := true
~LCtrl & n::ctrlUsedWithOtherKey := true
~LCtrl & o::ctrlUsedWithOtherKey := true
~LCtrl & p::ctrlUsedWithOtherKey := true
~LCtrl & q::ctrlUsedWithOtherKey := true
~LCtrl & r::ctrlUsedWithOtherKey := true
~LCtrl & s::ctrlUsedWithOtherKey := true
~LCtrl & t::ctrlUsedWithOtherKey := true
~LCtrl & u::ctrlUsedWithOtherKey := true
~LCtrl & v::ctrlUsedWithOtherKey := true
~LCtrl & w::ctrlUsedWithOtherKey := true
~LCtrl & x::ctrlUsedWithOtherKey := true
~LCtrl & y::ctrlUsedWithOtherKey := true
~LCtrl & z::ctrlUsedWithOtherKey := true

; Numbers (0-9)
~LCtrl & 0::ctrlUsedWithOtherKey := true
~LCtrl & 1::ctrlUsedWithOtherKey := true
~LCtrl & 2::ctrlUsedWithOtherKey := true
~LCtrl & 3::ctrlUsedWithOtherKey := true
~LCtrl & 4::ctrlUsedWithOtherKey := true
~LCtrl & 5::ctrlUsedWithOtherKey := true
~LCtrl & 6::ctrlUsedWithOtherKey := true
~LCtrl & 7::ctrlUsedWithOtherKey := true
~LCtrl & 8::ctrlUsedWithOtherKey := true
~LCtrl & 9::ctrlUsedWithOtherKey := true

; Common punctuation and brackets
~LCtrl & [::ctrlUsedWithOtherKey := true
~LCtrl & ]::ctrlUsedWithOtherKey := true
~LCtrl & `;::ctrlUsedWithOtherKey := true
~LCtrl & '::ctrlUsedWithOtherKey := true
~LCtrl & ,::ctrlUsedWithOtherKey := true
~LCtrl & .::ctrlUsedWithOtherKey := true
~LCtrl & /::ctrlUsedWithOtherKey := true
~LCtrl & \::ctrlUsedWithOtherKey := true
~LCtrl & -::ctrlUsedWithOtherKey := true
~LCtrl & =::ctrlUsedWithOtherKey := true
~LCtrl & `::ctrlUsedWithOtherKey := true

; Function keys
~LCtrl & F1::ctrlUsedWithOtherKey := true
~LCtrl & F2::ctrlUsedWithOtherKey := true
~LCtrl & F3::ctrlUsedWithOtherKey := true
~LCtrl & F4::ctrlUsedWithOtherKey := true
~LCtrl & F5::ctrlUsedWithOtherKey := true
~LCtrl & F6::ctrlUsedWithOtherKey := true
~LCtrl & F7::ctrlUsedWithOtherKey := true
~LCtrl & F8::ctrlUsedWithOtherKey := true
~LCtrl & F9::ctrlUsedWithOtherKey := true
~LCtrl & F10::ctrlUsedWithOtherKey := true
~LCtrl & F11::ctrlUsedWithOtherKey := true
~LCtrl & F12::ctrlUsedWithOtherKey := true

; Navigation and editing keys
~LCtrl & Tab::ctrlUsedWithOtherKey := true
~LCtrl & Enter::ctrlUsedWithOtherKey := true
~LCtrl & Backspace::ctrlUsedWithOtherKey := true
~LCtrl & Delete::ctrlUsedWithOtherKey := true
~LCtrl & Home::ctrlUsedWithOtherKey := true
~LCtrl & End::ctrlUsedWithOtherKey := true
~LCtrl & PgUp::ctrlUsedWithOtherKey := true
~LCtrl & PgDn::ctrlUsedWithOtherKey := true
~LCtrl & Up::ctrlUsedWithOtherKey := true
~LCtrl & Down::ctrlUsedWithOtherKey := true
~LCtrl & Left::ctrlUsedWithOtherKey := true
~LCtrl & Right::ctrlUsedWithOtherKey := true
~LCtrl & Insert::ctrlUsedWithOtherKey := true
~LCtrl & Escape::ctrlUsedWithOtherKey := true

; Note: Space is handled by the dedicated LCtrl & Space:: handler below,
; which already sets ctrlUsedWithOtherKey := true

; When Left Control is released
~LCtrl up:: {
    global ctrlUsedWithOtherKey

    ; If Ctrl was pressed alone (no other key was pressed)
    if (!ctrlUsedWithOtherKey && A_PriorKey = "LControl") {
        ; Send IME Off key
        ; vkF3 = 無変換 (Muhenkan) - works with Microsoft IME
        ; Alternative: vk1Dsc07B for some IME configurations
        Send "{vkF3}"
    }

    ; Reset the flag
    ctrlUsedWithOtherKey := false
}

;---------------------------------------------------------------
; Left Control + Space → IME On
;---------------------------------------------------------------

; Ctrl + Space toggles IME to hiragana mode
LCtrl & Space:: {
    global ctrlUsedWithOtherKey
    ctrlUsedWithOtherKey := true

    ; Send IME On key
    ; vkF4 = 変換 (Henkan) - works with Microsoft IME
    ; Alternative: vkF2 = ひらがな for some IME configurations
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

;---------------------------------------------------------------
; Debug Mode (Uncomment for troubleshooting)
;---------------------------------------------------------------

; Shows a tooltip when IME toggle is triggered
; Useful for debugging if the keys aren't working

; ~LCtrl up:: {
;     global ctrlUsedWithOtherKey
;     if (!ctrlUsedWithOtherKey && A_PriorKey = "LControl") {
;         ToolTip "IME Off (vkF3)"
;         SetTimer () => ToolTip(), -1000
;         Send "{vkF3}"
;     }
;     ctrlUsedWithOtherKey := false
; }
;
; LCtrl & Space:: {
;     global ctrlUsedWithOtherKey
;     ctrlUsedWithOtherKey := true
;     ToolTip "IME On (vkF4)"
;     SetTimer () => ToolTip(), -1000
;     Send "{vkF4}"
; }
