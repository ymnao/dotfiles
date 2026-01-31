; Key Remapping Module for AutoHotkey v2
; HHKB-style key bindings and other useful remaps
;
; Note: CapsLock → Ctrl is handled in ime-toggle.ahk

#Requires AutoHotkey v2.0

;---------------------------------------------------------------
; Vim-style Key Bindings
;---------------------------------------------------------------

; Ctrl+[ → Escape (Vim-style escape)
^[::Send "{Escape}"

; Ctrl+h → Backspace (Vim-style backspace)
; Note: This may conflict with some applications
; Uncomment if desired
; ^h::Send "{Backspace}"

;---------------------------------------------------------------
; Navigation Keys (Optional)
;---------------------------------------------------------------

; Windows + hjkl → Arrow keys
; Useful for keyboard navigation without moving hands
; Uncomment to enable

; #h::Send "{Left}"
; #j::Send "{Down}"
; #k::Send "{Up}"
; #l::Send "{Right}"

; Alt + hjkl → Arrow keys (alternative)
; May be more compatible with some applications
; Uncomment to enable

; !h::Send "{Left}"
; !j::Send "{Down}"
; !k::Send "{Up}"
; !l::Send "{Right}"

;---------------------------------------------------------------
; Quick Actions
;---------------------------------------------------------------

; Win + Enter → Open Windows Terminal
; Uncomment to enable
; #Enter::Run "wt.exe"

; Win + Shift + Enter → Open Windows Terminal as Admin
; Uncomment to enable
; #+Enter::Run "*RunAs wt.exe"

;---------------------------------------------------------------
; Application-Specific Remaps
;---------------------------------------------------------------

; Example: Remap keys only in specific applications
; Uncomment and modify as needed

; #HotIf WinActive("ahk_exe code.exe")  ; VS Code
; ; Your VS Code specific remaps here
; #HotIf

; #HotIf WinActive("ahk_exe chrome.exe")  ; Chrome
; ; Your Chrome specific remaps here
; #HotIf

; #HotIf WinActive("ahk_exe WindowsTerminal.exe")  ; Windows Terminal
; ; Your Terminal specific remaps here
; #HotIf

;---------------------------------------------------------------
; Function Keys (Optional)
;---------------------------------------------------------------

; Example: F1-F12 remaps for specific functions
; Uncomment and modify as needed

; F1::Send "^z"  ; F1 → Undo
; F2::Send "^y"  ; F2 → Redo
; F3::Send "^f"  ; F3 → Find
; F4::Send "!{F4}"  ; F4 → Close window

;---------------------------------------------------------------
; Mouse Button Remaps (Optional)
;---------------------------------------------------------------

; Example: Remap mouse buttons
; Uncomment and modify as needed

; XButton1::Send "!{Left}"   ; Back button → Browser back
; XButton2::Send "!{Right}"  ; Forward button → Browser forward

;---------------------------------------------------------------
; Insert Key Disable (Optional)
;---------------------------------------------------------------

; Disable Insert key to prevent accidental overwrite mode
; Uncomment to enable

; Insert::return

;---------------------------------------------------------------
; Scroll Lock / Pause Break (Optional)
;---------------------------------------------------------------

; Repurpose rarely used keys
; Uncomment to enable

; ScrollLock::Send "#{PrintScreen}"  ; Scroll Lock → Screenshot
; Pause::Send "#l"  ; Pause → Lock screen

;---------------------------------------------------------------
; Numpad Enhancements (Optional)
;---------------------------------------------------------------

; Example: Numpad shortcuts when NumLock is off
; Uncomment and modify as needed

; NumpadHome::Send "^{Home}"   ; Numpad 7 → Go to beginning
; NumpadEnd::Send "^{End}"     ; Numpad 1 → Go to end
; NumpadPgUp::Send "^{PgUp}"   ; Numpad 9 → Previous tab
; NumpadPgDn::Send "^{PgDn}"   ; Numpad 3 → Next tab
