AHK_ModalKeys
=============

ModalKeys is an AutoHotkey script that enables any key to be used as a modifier key.

I wrote this script because I make extensive use of keyboard shortcuts and, being a sufferer of RSI, I find that stretching to reach Ctrl, Alt and Win keys frequently is slow and exacerbates my RSI. This script allows any key to become a hybrid key that behaves like a modifier key when used like a modifier key and like a normal key when used like a normal key. In this way I have converted my home row (and many other easily accessible keys) into modifier keys - not just the standard Shift, Alt, Ctrl, Win, but also custom modifier keys that activate custom modes with mode-specific actions associated with each key.
The rules for distinguishing between typing behaviour and modifier behaviour are complicated, but basically a hybrid key behaves like a modifier when you hold it down and then press other keys and like a normal key when you press and release it quickly. It works well enough that I have experienced a substantial improvement in productivity and noticeably less issues with RSI despite occasional glitches caused by AutoHotkey's imperfect ability to keep track of which keys are currently pressed.
