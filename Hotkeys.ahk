
; Key Bindings
;===============================================================

;enable ctrl+v in Command Prompt
#IfWinActive ahk_class ConsoleWindowClass
^v::
	SendInput {Raw}%clipboard%
return
#IfWinActive

; menu key
+F10::Send {AppsKey}

; capslock
^#k::SetCapsLockState, % GetKeyState("CapsLock", "T")? "Off":"On"
^#j::SetCapsLockState, % GetKeyState("CapsLock", "T")? "Off":"On"
^#q::SetCapsLockState, % GetKeyState("CapsLock", "T")? "Off":"On"

; left-hand undo/cut/copy/paste
<^;:: Send ^z
<^q:: Send ^x
<^j:: Send ^c
<^k:: Send ^v
