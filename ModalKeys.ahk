; Load Startup Settings
;===============================================================
#SingleInstance force
#InstallKeybdHook
#MaxHotkeysPerInterval 10000000
#HotkeyInterval 2000

SetWorkingDir, %A_ScriptDir%
#Include %A_ScriptDir%

#KeyHistory 1000
CoordMode, ToolTip, Screen
SetKeyDelay -1
SendMode Input
#EscapeChar \

; Global Variables
;===============================================================

; Debugging configuration
global Debug          := true
global Debug0         := true
global Debug1         := true
global Debug2         := true
global Debug3         := true

; Keyboard behaviour settings
global InsertOnPress_MaxTimeSinceLastAction := 500
global InsertOnRelease_MaxPressDuration := 500
global ModeActivationDelay := 500
global FirstRepetitionDelay := 500
global RepetitionDelay := 200

; Mode Names
global DefaultMode := "DefaultMode"
global BaseMode := "BaseMode"

; Import User Key Bindings
; this file should define KeyBindings[DefaultMode]
; along with any other Modes reachable from DefaultMode
KB_User := JSON_load("KB_User.json")

; Import Base Key Bindings
KB_Base := JSON_load("KB_Base.json")

; prepare global data structures
global KeyBindings := InitializeKeyBindings( KB_Base, KB_User[DefaultMode], KB_User )
global AllModifiers := FindAllModifiers(KeyBindings)
global ModeModModifiersMap := MakeModeModModifiersMap(KeyBindings)

; initialize status globals
G_ModifiersActiveMap := {} ; Map[modifier => Map[modKey => true] ]
global Key_Status := {}
global ModeActivationTime := 0
global LastActionTime := 0
global LastKeyPressTime := 0
global LastModifierReleaseTime := 0
global BaseBuffer := ""
global ActionBuffer := ""
global CurrentMode := DefaultMode

; Initializers
;===============================================================

InitializeKeyBindings( baseBindings, defaultBindings, userBindings){
  allBindings := {}
  fullDefaultBindings := baseBindings.Clone()
  UpdateBindings(fullDefaultBindings, defaultBindings)

  for mode, bindings in userBindings {
    ; initialize bindings with fullDefaultBindings bindings
    allBindings[mode] := fullDefaultBindings.Clone()
    UpdateBindings( allBindings[mode], userBindings[mode])
  }
  allBindings[BaseMode] := baseBindings
  return allBindings
}
UpdateBindings( bindings, updateWith ){
  for keyName, newBinding in updateWith {
    bindings[keyName] := newBinding
  }
}
FindAllModifiers( key_bindings ){
  all_modifiers := {}
  for mode, bindings in key_bindings {
    for modKey, binding in bindings {
      for i, modifier in binding["Modifiers"] {
        all_modifiers[modifier] := true
      }
    }
  }
  return all_modifiers
}
MakeModeModModifiersMap( KeyBindings ){
  modeModModifiers := {}
  for mode, bindings in KeyBindings {
    for modKey, binding in bindings {
      modifiers := binding["Modifiers"]
      setMode := binding["SetMode"]
      if ( modifiers and not setMode )
        or ( setMode == mode )
      {
        modeModModifiers[mode][modKey] := modifiers
      }
    }
  }
  return modeModModifiers
}

; AHK Key Bindings
;===============================================================

; AutoHotkey key bindings
PrintScreen & F8:: ListVars
PrintScreen & F9:: KeyHistory
PrintScreen & F10:: ListLines
PrintScreen & F11::
  Send {Control Up}
  Send {Alt Up}
  Send {Shift Up}
  Send {LWin Up}
  Send {RWin Up}
  Reload
  return
PrintScreen & F12:: Suspend
PrintScreen & Delete::
  Debug := not Debug
  ClearTooltip()
return
PrintScreen:: Send {PrintScreen}

;Capslock & F12:: Reload
;Capslock::Return

ClearTooltip(){
  Loop, 20
  ToolTip, , 0, 0, A_Index
}


; Put Hooks into Keys
;===============================================================
#Include KeyHooks.ahk


; Key Repetition Handlers
;===============================================================

DoRepetitions:
  DoAction( CurrentlyRepeatingAction )
  SetTimer, DoRepetitions, % RepetitionDelay

return

StartRepeating( key ){
  CurrentlyRepeatingAction := key
  SetTimer, DoRepetitions, % FirstRepetitionDelay
}

StopRepeating(){
  CurrentlyRepeatingAction := ""
  SetTimer, DoRepetitions, Off
}

; Key Handlers
;===============================================================

PressKey( keyName ){
  if KeyIsInactive( keyName ) { ; disable hardware key-repetition
    ActivateKey( keyName )
    SetNow()
    DebugMsg( "lastActionTime: " LastActionTime)
    ReleaseInactiveModifiers()
    DebugMsg( "lastActionTime: " LastActionTime)

    Debug1( "press key: " keyName, 0 )

    ; dispatch to approprate handler
    if CurrentMode == BaseMode
    {
      ; We're in Base Mode; skip unneccesary work and just send the key
      baseAction := GetBaseAction( keyName )
      if baseAction
        PressNormalKey( keyName, baseAction )
      else
        PressBaseModKey( keyName )
    }
    else ; Not BaseMode
    {
      ; We need to do more work to determine where to dispatch to
      baseAction := GetBaseAction( keyName )
      currentBinding := GetCurrentBinding( keyName )
      ; TODO: get these values from within subsidiary functions
      action :=     currentBinding["Action"]
      modifiers :=  currentBinding["Modifiers"]
      setMode :=    currentBinding["SetMode"]
      newMode := setMode ? setMode : CurrentMode

      if baseAction {
        if KeyIsModKey( keyName, CurrentMode ) {
          ; ModKey Key
          PressModKey( keyName, baseAction, newMode )
        } else {
          ; NormalKey
          PressNormalKey( keyName, baseAction, action )
        }
      } else {
        ; Base Modifier Key
        PressBaseModKey( keyName )
      }
    }

    ; Always do these last actions
    LastKeyPressTime := Now()
    Debug0()
  }
}

ReleaseKey( keyName ){
  SetNow()

  ; dispatch to appropriate handler
  baseAction := GetBaseAction( keyName )
  currentBinding := GetCurrentBinding( keyName )
  modifiers := currentBinding["Modifiers"]
  releaseModifiers := MakeReleaseModifiers( modifiers )
  setMode := currentBinding["SetMode"]

  Debug1( "release key: " keyName ": " baseAction " / " releaseModifiers , 2 )

  if baseAction {
    if KeyIsModKey( keyName, CurrentMode ) {
      ; ModKey Key
      ReleaseModKey( keyName, baseAction )
    } else {
      ; NormalKey
      ReleaseNormalKey( keyName, baseAction )
    }
  } else {
    ; Base ModKey
    ReleaseBaseModKey( keyName )
  }

  ; activate default mode if no more pressed modKeys
  if ( ActiveModKeysCount() == 0 ){
    ; if user just pressed and released key(s) very quickly,
    ; revert to typing mode and retroactively insert queued BaseMode actions
    if ( Now() - LastKeyPressTime < InsertOnRelease_MaxPressDuration ) {
      flushed := FlushBaseBuffer()
      DebugMsg( "insert on release: " flushed )
    } else {
      ; it's too long since last key-press: forget queued characters
      ClearBuffers()
    }
    if ( CurrentMode != DefaultMode ){
      ActivateMode( DefaultMode )
    }
  }

  ReleaseInactiveModifiers()
  DeactivateKey( keyName )
  Debug0()
}

; Base Modifier Handlers: Factory Default Modifier Keys like Control, Alt)
; ------------------------------------------------------------
PressBaseModKey( modKey ){
  Debug2( "press base modifier: " modKey , 0 )

  if ( CurrentMode != BaseMode ){
    ActivateMode( BaseMode )
  }
  flushed := FlushBaseBuffer()
  DebugMsg( "flushed: " flushed )

  modifiersToPress := ActivateModKey( modKey )
  pressModifierStr := MakePressModifiersStr( modifiersToPress )
  DoModifierAction( pressModifierStr )

  Debug2( "pressed modifiers: " pressModifierStr , 1 )
}

ReleaseBaseModKey( modKey ){
  numActiveMods := ActiveModKeysCount()
  isLastActive := (numActiveMods <= 1)

  Debug2( "release base modifier(" numActiveMods "): " modKey
    , 3 )

  DeactivateModKey( modKey )

  ; BaseBuffer should be empty, but just in case...
  ClearBuffers()

  LastModifierReleaseTime := Now()
}

; Hybrid Key Handlers (Normal Keys converted into Modifiers)
; ------------------------------------------------------------
; l
PressModKey( keyName, baseAction, newMode ) {
  numActiveMods := ActiveModKeysCount()
  isFirstModKey := (not numActiveMods)

  Debug2( "press modKey(" numActiveMods "): " keyName ": " baseAction
        . "\n lastAction: " A_PriorKey " (" Now() - LastActionTime " ms ago)"
        . "\n modReleaseTime: " Now() - LastModifierReleaseTime " ms ago"
        , 3 )

  ; if this is the first modifier key pressed AND
    ; this is very soon after a normal (no-modifier) action
    ; then assume user is typing and insert immediately
  if isFirstModKey
    and ( Now() - LastActionTime < InsertOnPress_MaxTimeSinceLastAction )
    and ( LastActionTime > LastModifierReleaseTime )
  {
    FlushBaseBuffer() ; this should be empty already
    DoAction( baseAction )
    ;StartRepeating( baseAction )

    Debug2( "modKey: insert on press: " baseAction, 6 )
  } else {
    ; We don't yet know whether key should act as modKey or ordinary key
    ; So change mode provisionally and prepare action buffers for both

    ; activate newMode (if changed)
    if ( CurrentMode != newMode){ ; Activate New Mode
      ActivateMode( newMode )
    }
    ; activate modKey
    modifiersToPress := ActivateModKey( keyName )
    pressModifiersStr := MakePressModifiersStr( modifiersToPress )

    ; queue actions
    AppendToBaseBuffer( baseAction )
    AppendToActionBuffer( pressModifiersStr )

    Debug2( "modKey activate " keyName " : " pressModifiersStr, 6)
  }
}
ReleaseModKey( keyName, baseAction ) {
  numActiveMods := ActiveModKeysCount()

  ; if it was in modKey mode, deactivate it
  if ModKeyIsActive( keyName ) {
    DeactivateModKey( keyName )
    LastModifierReleaseTime := Now()
  }

  Debug2( "release modKey(" numActiveMods "): " keyName ": " baseAction
        . "\n last Action / Keypress: " A_PriorKey " (" Now() - LastActionTime
          . " / " Now() - LastKeyPressTime " ms ago)"
        . "\n modReleaseTime: " Now() - LastModifierReleaseTime " ms ago"
        , 8 )


  if ( baseAction == CurrentlyRepeatingAction ) {
    StopRepeating()
  }
  ; a key that was in repeat-insert mode cannot have been in modifier mode,
  ; but we might as well check separately anyway
}


; Hotkey Handlers (Modifier-specific action)
; ------------------------------------------------------------
PressNormalKey( keyName, baseAction, action := "" ){
  Debug2( "press " CurrentMode " hotkey: " keyName ": " baseAction " / " action
    . "\n actionBuffer: " ActionBuffer "    delay: " Now() - ModeActivationTime "ms"
    , 13 )

  if ( CurrentMode == BaseMode )
  {
    DoAction( baseAction )
  }
  else if ( Now() - ModeActivationTime > ModeActivationDelay )
  { ; send action immediately if mode has been active long enough
    FlushActionsBuffer()
    DoAction( action )
  }
  else
  { ; add baseAction and action to buffers
    AppendToBaseBuffer( baseAction )
    AppendToActionBuffer( action )
  }

}

ReleaseNormalKey( keyName, baseAction ){
  Debug2( "release hotkey: " keyName ": " baseAction
    . "\n actionBuffer: " ActionBuffer "    delay: " Now() - ModeActivationTime
    , 15 )

  FlushActionsBuffer()
}


; Action Buffer Helpers
;===============================================================

DoAction( action ){
  ClearBuffers()
  Send {Blind}%action%
  global LastActionTime := Now()
}
DoModifierAction( modifierAction ){
  Send {Blind}%modifierAction%
}
ClearBuffers(){
  static i := 0
  i := mod(i, 4)
  Debug3( "clearing buffers: \n  key: " BaseBuffer "\n hkey: " ActionBuffer
        , i * 3, 2 )
  i++

  global BaseBuffer := ""
  global ActionBuffer := ""
}

AppendToBaseBuffer( baseAction ){
  ; no modifiers should ever get in here since
  ; any base modifier press will first flush the buffer
  global BaseBuffer .= baseAction
}
AppendToActionBuffer( actions ){
  global ActionBuffer .= actions
}

FlushBaseBuffer(){
  global BaseBuffer
  return FlushBuffer( BaseBuffer )
}
FlushActionsBuffer(){
  global ActionBuffer
  return FlushBuffer( ActionBuffer )
}
FlushBuffer( buffer ){
  if buffer {
    DoAction(buffer)
  }
  return buffer
}


; Mode Change Handlers
;===============================================================

ActivateMode( newMode ) {
  oldMode := CurrentMode

  if (oldMode == newMode) {
    DebugMsg( "oldMode(" oldMode ") = newMode(" newMode ")" )
    return
  }

  ; for each active modifier, queue old release action and new press action
  currentModKeys := GetAllActiveModKeys().Clone()
  deactivatedModifiers := DeactivateModKeys(currentModKeys)
  persistingModKeys := {}
  for modKey, t in currentModKeys {
    if KeyIsModKey( modKey, newMode ) {
      persistingModKeys[modKey] := true
    }
  }
  CurrentMode := newMode
  activatedModifiers := ActivateModKeys( persistingModKeys )
  RemoveIntersection(deactivatedModifiers, activatedModifiers )
  releaseModifiersStr := MakeReleaseModifiers( deactivatedModifiers )
  pressModifiersStr := MakePressModifiersStr( activatedModifiers )

  AppendToActionBuffer( releaseModifiersStr . pressModifiersStr )

  ; Always do
  ModeActivationTime := Now()

  Debug2( "Activated Mode: " newMode " from " oldMode
    . "\n release: " releaseModifiersStr
    . "\n press: " pressModifiersStr
    , 17)
}


; Modifier Status handlers
; ------------------------------------------------------------

ReleaseInactiveModifiers(){
  releasedModifiers := {}

  for modifier, t in GetAllModifiers() {
    activeModKeys := GetActiveModKeysFor(modifier)
    modifierActive := GetKeyState(modifier)

    if modifierActive and isEmpty(activeModKeys)
    { ; release modifier
      releasedModifiers[modifier] := true
    }
  }
  releaseModifiersStr := MakeReleaseModifiers( releasedModifiers )
  DoModifierAction(releaseModifiersStr)

  return releasedModifiers
}
ActivateModKeys( modKeys ){
  activatedModifiers := {}
  for modKey, t in modKeys {
    for modifier, t in ActivateModKey( modKey ) {
      activatedModifiers[modifier] := true
    }
  }
  return activatedModifiers
}
ActivateModKey( modKey ){
  global G_ModifiersActiveMap
  modifiers := GetCurrentBinding( modKey )["Modifiers"]
  activatedModifiers := {}
  for i, modifier in modifiers {
    G_ModifiersActiveMap[modifier, modKey] := true
    activatedModifiers[modifier] := true
  }
  G_ModifiersActiveMap["", modKey] := true
  return activatedModifiers
}
DeactivateModKeys( modKeys ){
  deactivatedModifiers := {}
  for modKey, t in modKeys {
    for modifier, t in DeactivateModKey( modKey ){
      deactivatedModifiers[modifier] := true
    }
  }
  return deactivatedModifiers
}
DeactivateModKey( modKey ){
  global G_ModifiersActiveMap
  modifiers := GetCurrentBinding( modKey )["Modifiers"]
  deactivatedModifiers := {}
  for i, modifier in modifiers {
    activeModifiers := G_ModifiersActiveMap[modifier]
    activeModifiers.Remove(modKey)
    deactivatedModifiers[modifier] := true
    if isEmpty( activeModifiers ){
      G_ModifiersActiveMap.Remove(modifier)
    }
  }
  G_ModifiersActiveMap[""].Remove(modKey)
  return deactivatedModifiers
}


; Getters and Setters
;===============================================================
Now(){
  global CurrentEventTime
  return CurrentEventTime
}
SetNow(){
  global CurrentEventTime := A_TickCount
  DebugMsg( "setting now: " CurrentEventTime ", " Now() )
}
KeyIsActive( keyName ){
  global Key_Status
  return Key_Status[keyName]
}
KeyIsInactive( keyName ){
  return not KeyIsActive( keyName )
}
SetKeyStatus( keyName, keyStatus ) {
  global Key_Status
  Key_Status[keyName] := keyStatus
}
ActivateKey( keyName ){
  SetKeyStatus( keyName, true )
}
DeactivateKey( keyName ){
  SetKeyStatus( keyName, false )
}

KeyIsModKey( keyName, mode ){
  binding := KeyBindings[mode][keyName]
  isModKey := binding["Modifiers"] or binding["SetMode"]
  return isModKey
}
GetBaseAction( keyName ){
  return KeyBindings[BaseMode][keyName]["Action"]
}
GetBaseModifiers( keyName ){
  return KeyBindings[BaseMode][keyName]["Modifiers"]
}
GetAHK_KeyName( keyName ){
  ahk_name := KeyBindings[BaseMode][keyName]["AHK_Name"]
  return ahk_name
}
GetCurrentBinding( keyName ){
  binding := KeyBindings[CurrentMode][keyName]
  return binding
}

GetActiveModKeysFor(modifier){
  global G_ModifiersActiveMap
  return G_ModifiersActiveMap[modifier]
}
GetAllActiveModKeys(){
  global G_ModifiersActiveMap
  return G_ModifiersActiveMap[""]
}
ActiveModKeysCount(){
  n := Count( GetAllActiveModKeys() )
  return n
}
ModKeyIsActive(modKey){
  return GetAllActiveModKeys()[modKey]
}

GetAllModifiers(){
  global AllModifiers
  return AllModifiers
}

GetModifierPrefix( physical := true ){
  mode := physical ? "P" : ""
  prefix := (GetKeyState("Alt", mode ) ? "!" : "")
    . (GetKeyState("Control", mode ) ? "^" : "")
    . (GetKeyState("Shift", mode ) ? "+" : "")
    . ( (GetKeyState("LWin", mode ) or GetKeyState("RWin", mode ) ) ? "#" : "")
  return prefix
}
ModifierPrefix_Display( physical := true ){
  mode := physical ? "P" : ""
  prefix := " "
    . ( GetKeyState("LAlt", mode ) ? "!" : "" )
    . ( GetKeyState("LControl", mode ) ? "^" : "" )
    . ( GetKeyState("LShift", mode ) ? "+" : "" )
    . ( GetKeyState("LWin", mode ) ? "#" : "" )
    . ( GetKeyState("RAlt", mode ) ? "_!" : "" )
    . ( GetKeyState("RControl", mode ) ? "_^" : "" )
    . ( GetKeyState("RShift", mode ) ? "_+" : "" )
    . ( GetKeyState("RWin", mode ) ? "_#" : "" )
  return prefix
}

; Helper Functions
;===============================================================

MakePressModifiersStr( modifiers ){
  return mkString( modifiers, "", "{", " Down}")
}

MakeReleaseModifiers( modifiers ){
  return mkString( modifiers, "", "{", " Up}")
}

mkString( obj, separator := ", ", before := "", after := "" ){
  str := ""
  isArray := obj.MaxIndex()
  doneFirst := false
  for k, v in obj {
    value := isArray ? v : k
    if (not doneFirst) {
      str .= before . value . after
      doneFirst := true
    } else {
      str .= separator . before . value . after
    }
  }
  return str
}

isEmpty( obj ){
  empty := true
  for key, value in obj {
    empty := false
  }
  return empty
}
Count( obj ){
  n := 0
  for k, v in obj {
    n++
  }
  return n
}
RemoveIntersection( ByRef set1, ByRef set2 ){
  return ; TODO: implement
}

; Debugging
;===============================================================

DebugMsg( ByRef msg, row := 0, col := 0, cycleRows := 0, cycleCols := 0 , Debug_level := 0 ){
  static toolTipIndex := 3
  static DebugRowOffset := {}
  static DebugColOffset := {}

  static Debug0StartCol := 0
  static Debug0StartRow := 0
  static Debug1StartCol := 0
  static Debug1StartRow := 5
  static Debug2StartCol := 0
  static Debug2StartRow := 15
  static Debug3StartCol := 0
  static Debug3StartRow := 35

  if ( Debug and Debug%Debug_level% ){
    OutputDebug \n %msg%

    if DebugTooltip%Debug_level% {
      toolTipIndex := ( Debug_level == 0 ) ? 1
        : ( mod(toolTipIndex, 18) + 3  ) ; cycle from 3 to 20

      Debug4StartRow := 50
      nextDLevel := Debug_level + 1
      rowsAvailable := Debug%nextDLevel%StartRow - Debug%Debug_level%StartRow

      if cycleCols {
        offs := (0 DebugColOffset[cycleCols])
        msg := offs " " msg
        col := col + offs
        DebugColOffset[cycleCols] := offs + 1
      }
      if cycleRows {
        offs := (0 DebugRowOffset[cycleRows])
        msg := offs " " msg
        row := row + offs
        DebugRowOffset[cycleRows] := offs + 1
      }
      col := mod( col, 4 )
      row := mod( row, rowsAvailable )
      col_abs := (Debug%Debug_level%StartCol + col) * 200
      row_abs := (Debug%Debug_level%StartRow + row) * 18

      Tooltip, % msg, col_abs, row_abs, toolTipIndex
    }
  }
}
Debug0(){
  msg := " state: " CurrentMode " (" ActiveModKeysCount() "): " mkString( GetAllActiveModKeys() )
      . "\n prefix: " ModifierPrefix_Display() " / " ModifierPrefix_Display( false )
      . "\n BaseBuffer: " BaseBuffer
      . "\n ActionBuffer: " ActionBuffer
  DebugMsg( msg )
}
Debug1( ByRef msg, row := 0, col := 0, cycleRows := 0, cycleCols := 0 ){
  DebugMsg( msg, row, col, cycleRows, cycleCols, 1)
}

Debug2( ByRef msg, row := 0, col := 0, cycleRows := 0, cycleCols := 0 ){
  DebugMsg( msg, row, col, cycleRows, cycleCols, 2)
}

Debug3( ByRef msg, row := 0, col := 0, cycleRows := 0, cycleCols := 0 ){
  DebugMsg( msg, row, col, cycleRows, cycleCols, 3)
}

