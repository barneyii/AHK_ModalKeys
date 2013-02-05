
; Key Bindings
;===============================================================


; AHK Key Bindings
;---------------------------------------------------------

; AutoHotkey key bindings
Insert & F9::  ListVars
Insert & F10::  KeyHistory
Insert & F11::    ; Reload
  DeactivateAllKeys()
  Reload
  return
Insert & F12::Suspend
Insert & Delete:: ; toggle debug
  Debug := not Debug
  SetThreadInterruptability()
  DeactivateAllKeys()
  ClearTooltips()
  UpdateStatusTooltip()
  return
Insert:: Send {Insert} ; send Insert on key up

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

; select keyboard layout
Esc & 1:: SetKeyboardLayout( "Qwerty" )
Esc & 2:: SetKeyboardLayout( "Dvorak" )

; Typing Mode Lock
Esc & Insert:: ActivateTypingLock()
Insert & Esc:: DeactivateTypingLock()

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

