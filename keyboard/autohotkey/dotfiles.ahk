; Dotfiles AutoHotkey v2 Main Script
; This script loads all keyboard customization modules
;
; Requirements:
; - AutoHotkey v2.0+
; - Windows 10 1607+ or Windows 11
;
; Installation:
; 1. Install AutoHotkey v2: winget install AutoHotkey.AutoHotkey
; 2. Run this script: .\dotfiles.ahk
; 3. Or add to Startup folder for auto-start

#Requires AutoHotkey v2.0
#SingleInstance Force

; Script settings
SendMode "Input"
SetWorkingDir A_ScriptDir

; Startup notification
TrayTip "Dotfiles keyboard customization loaded", "AutoHotkey", "Icon1 Mute"

;---------------------------------------------------------------
; Load Modules
;---------------------------------------------------------------

; IME Toggle (CapsLock → Ctrl, Ctrl alone → IME toggle)
#Include "ime-toggle.ahk"

; Key Remapping (HHKB-style)
#Include "key-remapping.ahk"

;---------------------------------------------------------------
; Tray Menu Customization
;---------------------------------------------------------------

; Create custom tray menu
A_TrayMenu.Delete()
A_TrayMenu.Add("Reload Script", (*) => Reload())
A_TrayMenu.Add("Edit Script", (*) => Edit())
A_TrayMenu.Add()
A_TrayMenu.Add("Open Dotfiles Folder", (*) => Run("explorer.exe " A_ScriptDir "\..\..\"))
A_TrayMenu.Add()
A_TrayMenu.Add("Suspend Hotkeys", (*) => Suspend())
A_TrayMenu.Add("Pause Script", (*) => Pause())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())

; Set default action (double-click tray icon)
A_TrayMenu.Default := "Reload Script"

;---------------------------------------------------------------
; Global Hotkeys
;---------------------------------------------------------------

; Win+Shift+R: Reload this script
#+r:: {
    TrayTip "Reloading...", "AutoHotkey", "Icon1 Mute"
    Sleep 500
    Reload
}

; Win+Shift+E: Edit this script
#+e::Edit

; Win+Shift+P: Suspend all hotkeys temporarily
; Note: Win+Shift+S is reserved for Windows Screenshot
#+p:: {
    Suspend
    if (A_IsSuspended) {
        TrayTip "Hotkeys suspended", "AutoHotkey", "Icon3 Mute"
    } else {
        TrayTip "Hotkeys resumed", "AutoHotkey", "Icon1 Mute"
    }
}
