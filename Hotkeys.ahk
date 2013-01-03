
; Key Bindings
;===============================================================


; AHK Key Bindings
;---------------------------------------------------------

; AutoHotkey key bindings
PrintScreen & F9::  ListVars
PrintScreen & F10::  KeyHistory
PrintScreen & F11::    ; Reload
  DeactivateAllKeys()
  Reload
  return
PrintScreen & F12::Suspend
PrintScreen & Delete:: ; toggle debug
  Debug := not Debug
  SetThreadInterruptability()
  DeactivateAllKeys()
  ClearTooltips()
  return
PrintScreen:: Send {PrintScreen} ; send PrintScreen on key up

; with Delete as Modifier

Delete & F9::  ListVars
Delete & F10::  KeyHistory
Delete & F11::    ; Reload
  DeactivateAllKeys()
  Reload
  return
Delete & F12::Suspend
Delete & Insert:: ; toggle debug
  Debug := not Debug
  SetThreadInterruptability()
  DeactivateAllKeys()
  ClearTooltips()
  return
Delete:: Send {Delete} ; send Delete on key up


;enable ctrl+v in Command Prompt
#IfWinActive ahk_class ConsoleWindowClass
^v::
	SendInput {Raw}%clipboard%
  Tooltip paste
return

#IfWinActive

; menu key
+F10::Send {AppsKey}

; capslock
^#a::SetCapsLockState, % GetKeyState("CapsLock", "T")? "Off":"On"

; left-hand undo/cut/copy/paste
<^o:: Send ^s
<^;:: Send ^z
<^q:: Send ^x
<^j:: Send ^c
<^k:: Send ^v


; scrolling

Esc & F1:: Repeat_Accel("F1", "{WheelDown}")
Esc & F1 Up:: return
Esc & F2:: Repeat_Accel("F2", "{WheelUp}")
Esc & F2 Up:: return
Esc & F3:: ChangeScrollLines(-3)
Esc & F3 Up:: return
Esc & F4:: ChangeScrollLines(3)
Esc & F4 Up:: return
Esc:: Send {Esc}

; mouse clicks
$F1::LButton
$F2::MButton
$F3::RButton

; Cliboard
$F4::SendInput {Raw}%clipboard%

