
ChangeScrollLines(change){
  global Scroll_Lines
  DllCall("SystemParametersInfo", UInt, 0x68, UInt, 0, UIntP, Scroll_Lines, UInt, 0)
  if (Scroll_Lines > 3 or (Scroll_Lines >= 3 and change > 0))
    Scroll_Lines += change
  else
    Scroll_Lines += round(change / abs(change))

  if (Scroll_Lines < 1)
    Scroll_Lines := 1

  SetScrollLines(Scroll_Lines)
  Tooltip % "Scroll_Lines = " Scroll_Lines
}
SetScrollLines(n){
  global Scroll_Lines := n
  DllCall("SystemParametersInfo", UInt, 0x69, UInt, Scroll_Lines, UInt, 0, UInt, 0)
}

Repeat_Accel(key, action, num_times := 1, init_delay := 250, min_delay := 60, accel := 0.6){
  current_delay := init_delay
  While GetKeyState(key, "P") {

    Send %action%
    Sleep, current_delay
    if(current_delay > min_delay){
      current_delay *= accel
    }
  }
}
