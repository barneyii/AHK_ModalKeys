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
global Debug              := true

; Keyboard behaviour settings
global InsertOnPress_MaxTimeSinceLastAction := 200
global InsertOnRelease_MaxPressDuration := 1000
global ModeActivationDelay := 300
global EnableKeyRepetition := true
global FirstRepetitionDelay := 400
global RepetitionDelay := 50

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
ModifiersActiveMap := {} ; Map[modifier => Map[modKey => true] ]
PressedKeys := { }
BaseBuffer := ""
ActionBuffer := ""
global LastActionWasTyping := false
global ModeActivationTime := 0
global LastActionTime := 0
global LastKeyPressTime := 0
global CurrentMode := DefaultMode

; Initializers
;===============================================================
InitializeKeyBindings( baseBindings, defaultBindings, userBindings){
  allBindings := {}

  for mode, bindings in userBindings {
    ; initialize bindings with baseBindings
    allBindings[mode] := baseBindings.Clone()
    UpdateBindings( allBindings[mode], userBindings[mode] )
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
PrintScreen & F1:: Send ^^#2
PrintScreen & F2:: Send #3

PrintScreen & F8::  ListVars
PrintScreen & F9::  KeyHistory
PrintScreen & F10:: ListLines
PrintScreen & F11::    ; Reload
  DeactivateAllKeys()
  Reload
  return
PrintScreen & F12::    ; Suspend
  DeactivateAllKeys()
  Suspend
  return
PrintScreen & Delete:: ; toggle debug
  Debug := not Debug
  DeactivateAllKeys()
  ClearTooltip()
  return
PrintScreen:: Send {PrintScreen} ; send PrintScreen on key up

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
global CurrentlyRepeatingAction, CurrentlyRepeatingKey, CurrentlyRepeatingKeyPhName
if (EnableKeyRepetition) {
  if (GetKeyState(CurrentlyRepeatingKeyPhName, "P")){
    DoModActions( CurrentlyRepeatingAction ) ; don't consider key-holding as normal typing
    SetTimer, DoRepetitions, % RepetitionDelay
  } else {
    DebugMsg("repetition called on unpressed key: " CurrentlyRepeatingKey)
    StopRepeating()
  }
}
return

StartRepeating( key, action ){
  ;DebugMsg("start repeating: " key " - " action)
  global CurrentlyRepeatingAction, CurrentlyRepeatingKey, CurrentlyRepeatingKeyPhName
  CurrentlyRepeatingKey := key
  CurrentlyRepeatingKeyPhName := GetKeyPhName(key)
  CurrentlyRepeatingAction := action
  SetTimer, DoRepetitions, % FirstRepetitionDelay
}

StopRepeating(){
  global CurrentlyRepeatingAction, CurrentlyRepeatingKey, CurrentlyRepeatingKeyPhName
  ;DebugMsg("stop repeating: " CurrentlyRepeatingKey " - " CurrentlyRepeatingAction)
  CurrentlyRepeatingAction := ""
  CurrentlyRepeatingKey := ""
  CurrentlyRepeatingKeyPhName := ""
  SetTimer, DoRepetitions, Off
}

; Key Handlers
;===============================================================

PressKeyEvent( keyName ){
  if KeyIsUnpressed( keyName ) { ; disable hardware key-repetition
    DebugMsg( StrPad("P> " keyName, 14) " " MakeStatusMsg(), false )
    SetKeyPressed( keyName )
    SetNow()
    ReleaseInactiveModifiers()

    ; dispatch to approprate handler
    if IsBaseModKey( keyName ) {
      ; Base ModKey
      PressBaseModKey( keyName )
    } else {
      if ( CurrentMode != BaseMode and KeyIsModKey( keyName, CurrentMode )) {
        ; ModKey
        PressModKey( keyName )
      } else {
        ; Normal Key
        PressNormalKey( keyName )
      }
    }

    ; Always do these last actions
    LastKeyPressTime := Now()
    DebugMsg( StrPad("<P " keyName, 14) " " MakeStatusMsg(), false )
  }
}

ReleaseKeyEvent( keyName ){
  DebugMsg( StrPad( "R> " keyName, 14) " " MakeStatusMsg(), false )
  SetKeyReleased( keyName )
  SetNow()

  if ( keyName == CurrentlyRepeatingKey ) {
    StopRepeating()
  }

  ; dispatch to appropriate handler
  if IsBaseModKey( keyName ) {
    ; Base ModKey
    ReleaseBaseModKey( keyName )
  } else {
    if ( CurrentMode != BaseMode and KeyIsModKey( keyName, CurrentMode )) {
      ; ModKey
      ReleaseModKey( keyName )
    } else {
      ; Normal Key
      ReleaseNormalKey( keyName )
    }
  }

  ; activate default mode if there are no keys pressed
  PrunePressedKeys()
  if ( PressedKeyCount() == 0 ){
    DebugMsg("nokey: " MakeStatusMsg())
    wereActive := DeactivateAllKeys() ; ensure all modifiers and modKeys are released as well
    if Count(wereActive){
      DebugMsg("modKeys were active when no keys were pressed: " mkString(wereActive))
    }
    ; if user just pressed and released key(s) very quickly,
    ; revert to typing mode and retroactively insert queued BaseMode actions
    if ( Now() - LastKeyPressTime < InsertOnRelease_MaxPressDuration ) {
      DoBaseActions()
    } else {
      ; it's too long since last key-press: forget queued characters
      ClearBuffers()
    }
    if ( CurrentMode != DefaultMode ){
      ActivateMode( DefaultMode )
    }
    ; ensure there is no repetition going on if there are no keys pressed
    StopRepeating()

  }

  ReleaseInactiveModifiers()
  DebugMsg( StrPad( "R< " keyName, 14) " " MakeStatusMsg(), false )
}

; Base Modifier Handlers: Factory Default Modifier Keys like Control, Alt)
; ------------------------------------------------------------
PressBaseModKey( keyName ){
  ;DebugMsg("base key: " keyName)

  if ( CurrentMode == BaseMode ){
    ;ResetActiveKeysToLogicallyActiveModifiers()
  } else {
    ActivateMode( BaseMode )
  }

  modifiersToPress := ActivateModKey( keyName )
  pressModifierStr := MakePressModifiersStr( modifiersToPress )
  DoModifierAction( pressModifierStr )
}


ReleaseBaseModKey( keyName ){

  DeactivateModKey( keyName )

}


; Normal Key handlers (BaseMode keys or Modifier-specific action)
; ------------------------------------------------------------
PressNormalKey( keyName ){
  DebugMsg( keyName " press normal key" )

  numPressedKeys := PressedKeyCount()
  action := GetCurrentBinding( keyName )["Action"]
  baseAction := GetBaseAction( keyName )
  ; if this is the first key pressed, assume typing intended
  ; and activate BaseMode
  if (numPressedKeys == 1 and CurrentMode != BaseMode ){
    ActivateMode(BaseMode)
    DebugMsg( keyName " atv bm" )
  }

  if ( CurrentMode == BaseMode )
  {
    ;DebugMsg( "reset keys: " MakeStatusMsg() )
    ;ResetActiveKeysToLogicallyActiveModifiers()
    DoBaseActions( baseAction )
    StartRepeating( keyName, baseAction )
    ;DebugMsg( "af reset" )
  }
  else if ( Now() - ModeActivationTime > ModeActivationDelay )
  { ; send action immediately if mode has been active long enough
    DoModActions( action )
    StartRepeating( keyName, action )
    DebugMsg( keyName " mod act" )
  }
  else
  { ; we don't know whether typing or hotkey was intended:
    ;add baseAction and action to buffers
    AppendToBaseBuffer( baseAction )
    AppendToActionBuffer( action )
    ; start repeating hotkey action after a delay since
    ; that is what will be desired if both the mod keys
    ; and this key continue to be held down
    StartRepeating( keyName, action )
    DebugMsg( keyName " hedge" )
  }

}

ReleaseNormalKey( keyName ){
  global ActionBuffer
  DebugMsg( keyName " release normal key. buffer: " ActionBuffer)
  DoModActions()
}



; Hybrid Key Handlers (Normal Keys converted into Modifiers)
; ------------------------------------------------------------
PressModKey( keyName ) {
  DebugMsg( keyName " press mod key" )

  numActiveMods := ActiveModKeysCount()
  isFirstModKey := (numActiveMods == 0)
  baseAction := GetBaseAction( keyName )
  setMode := GetCurrentBinding( keyName )["SetMode"]
  newMode := setMode ? setMode : CurrentMode

  ; if this is the first modifier key pressed AND
    ; this is very soon after a normal (no-modifier) action
    ; then assume user is typing and insert immediately
  if isFirstModKey
    and ( Now() - LastActionTime < InsertOnPress_MaxTimeSinceLastAction )
    and ( LastActionWasTyping )
  {
    DebugMsg( keyName " insert. lst_act: " Now() - LastActionTime)
    DoBaseActions( baseAction )
    StartRepeating( keyName, baseAction )
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
  }
}
ReleaseModKey( keyName ) {
  numActiveMods := ActiveModKeysCount()
  isLastReleased := PressedKeyCount() == 0

  DebugMsg( keyName " release mod key:" )

  ; if it was in modKey mode, deactivate it
  if ModKeyIsActive( keyName ) {
    DeactivateModKey( keyName )
    DebugMsg( keyName " off. last_released: " isLastReleased
      . " last_act: " Now() - LastActionTime " mod_actv: " Now() - ModeActivationTime
      . " last_key_p: " Now() - LastKeyPressTime )
    ; if this was not the only key pressed and no actions have been performed
    ; since the mode was activated, flush the BaseBuffer and switch to typing mode
    if ( !isLastReleased and LastActionTime < ModeActivationTime ){
      ; if it has been too long since last key press, don't insert anything
      if ( Now() - LastKeyPressTime > InsertOnRelease_MaxPressDuration ){
        ClearBuffers()
      }
      StopRepeating()
      DebugMsg( keyName " actv BaseMode. buffer: " BaseBuffer )
      ActivateMode( BaseMode ) ; this will flush the BaseBuffer
    }
  }
}


; Action Buffer Helpers
;===============================================================

DoModifierAction( modifierAction ){
  if (modifierAction){
    Send {Blind}%modifierAction%
    DebugMsg( "send: " modifierAction)
  }
}
DoBaseActions( baseActions := "" ){
  global BaseBuffer, LastActionWasTyping
  actions := BaseBuffer . baseActions
  FlushBuffer( actions )
  if actions { ; if actions are being performed, record whether they are typing-actions or not
    if ( GetKeyState("Control")
      or GetKeyState("Alt")
      or GetKeyState("LWin") ) {
      LastActionWasTyping := false
    } else {
      LastActionWasTyping := true
    }
  }
  return actions
}
DoModActions( actions := "" ){
  global ActionBuffer, LastActionWasTyping
  actions := ActionBuffer . actions
  FlushBuffer( actions )
  if actions {
    LastActionWasTyping := false
  }
  return actions
}
FlushBuffer( buffer ){
  if buffer {
    DebugMsg("send: " buffer)
    Send {Blind}%buffer%
    global LastActionTime := Now()
  }
  ClearBuffers()
  return buffer
}
ClearBuffers(){
  global BaseBuffer, ActionBuffer
  BaseBuffer := ""
  ActionBuffer := ""
}

AppendToBaseBuffer( baseAction ){
  ; no modifiers should ever get in here since
  ; any base modifier press will first flush the buffer
  global BaseBuffer .= baseAction
}
AppendToActionBuffer( actions ){
  global ActionBuffer .= actions
}


; Mode Change Handlers
;===============================================================

ActivateMode( newMode ) {
  oldMode := CurrentMode

  if (oldMode == newMode) {
    DebugMsg( "oldMode(" oldMode ") = newMode(" newMode ")" )
    return
  }

  ; if we are entering base mode, flush the BaseBuffer
  ; and deactivate all Modifiers/ModKeys
  if (newMode == BaseMode) {
    CurrentMode := BaseMode
    DeactivateAllKeys()
    DoBaseActions()
  } else {
    ; otherwise queue modifier change actions
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
    modifierActionStr := releaseModifiersStr . pressModifiersStr

    AppendToActionBuffer( modifierActionStr )
  }

  ; Always do
  ModeActivationTime := Now()
}


; Modifier/ModKey Status handlers
; ------------------------------------------------------------

ReleaseInactiveModifiers(){
  PruneActiveModKeys()
  releasedModifiers := {}

  for modifier, t in GetAllModifiers() {
    activeModKeys := GetActiveModKeysFor(modifier)
    modifierActive := GetKeyState(modifier)

    if modifierActive and isEmpty(activeModKeys)
    { ; release modifier
      releasedModifiers[modifier] := true
    }
  }
  if (Count(releasedModifiers) > 0){
    releaseModifiersStr := MakeReleaseModifiers( releasedModifiers )
    DebugMsg("release inactive: " modifier)
    DoModifierAction(releaseModifiersStr)
  }

  return releasedModifiers
}

PruneActiveModKeys(){
  global ModifiersActiveMap
  toPrune := {}
  for modKey, t in ModifiersActiveMap[""] {
    pKeyName := GetKeyPhName(modKey)
    if ( not GetKeyState(pKeyName, "P") ){
      toPrune[modKey] := true
      DebugMsg("Unpressed active modKey found: " modKey)
    }
  }
  DeactivateModKeys( toPrune )
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
  global ModifiersActiveMap
  SetKeyPressed( modKey )
  modifiers := GetCurrentBinding( modKey )["Modifiers"]
  activatedModifiers := {}
  for i, modifier in modifiers {
    ModifiersActiveMap[modifier, modKey] := true
    activatedModifiers[modifier] := true
  }
  ModifiersActiveMap["", modKey] := true
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
  global ModifiersActiveMap
  SetKeyReleased( modKey )
  deactivatedModifiers := {}
  for modifier, activeModKeys in ModifiersActiveMap {
    activeModKeys.Remove(modKey)
    if isEmpty( activeModKeys ){
      deactivatedModifiers[modifier] := true
    }
  }
  for modifier, t in deactivatedModifiers {
    ModifiersActiveMap.Remove(modifier)
  }
  return deactivatedModifiers
}
GetActiveModKeysFor(modifier){
  global ModifiersActiveMap
  return ModifiersActiveMap[modifier]
}
GetAllActiveModKeys(){
  global ModifiersActiveMap
  return ModifiersActiveMap[""]
}

ActiveModKeysCount(){
  n := Count( GetAllActiveModKeys() )
  return n
}
ModKeyIsActive(modKey){
  isActive := GetAllActiveModKeys()[modKey]
  return isActive
}

GetAllModifiers(){
  global AllModifiers
  return AllModifiers
}

; TODO check if this does anything useful
ResetActiveKeysToLogicallyActiveModifiers(){
  global ModifiersActiveMap, PressedKeys
  m_before := ModifiersActiveMap
  m_after := {}
  k_before := PressedKeys
  PressedKeys := {}
  for modifier, modKeys in ModifiersActiveMap {
    if GetKeyState(modifier) {
      m_after["", modifier] := true
      m_after[modifier, modifier] := true
      SetKeyPressed(modifier)
    }
  }
  ModifiersActiveMap := m_after
  ;DebugMsg("  mod reset: (" mkString(m_before[""]) "/" mkString(m_after[""]) ")"
  ;  . " (" mkString(k_before) "/" mkString(PressedKeys) ")")
}


GetModKeyPrefix(){
  global ModifiersActiveMap
  prefix := ( (ModifiersActiveMap["LAlt"] or ModifiersActiveMap["RAlt"]) ? "!" : "")
          . ( (ModifiersActiveMap["LControl"] or ModifiersActiveMap["RControl"]) ? "^" : "")
          . ( (ModifiersActiveMap["LShift"] or ModifiersActiveMap["RShift"]) ? "+" : "")
          . ( (ModifiersActiveMap["LWin"] or ModifiersActiveMap["RWin"]) ? "#" : "")
  return prefix
}

; Key Status handlers
; ------------------------------------------------------------
PrunePressedKeys(){
  global PressedKeys
  for key, t in PressedKeys {
    phKeyName := GetKeyPhName(key)
    ;DebugMsg("  checking " phKeyName  "\t" GetKeyState(phKeyName, "P") "\t" GetKeyState(phKeyName))
    if ( not GetKeyState(phKeyName, "P") ){
      PressedKeys.Remove(key)
      DebugMsg("  Unpressed key found in PressedKeys: " key)
    }
  }
}
DeactivateAllKeys(){
  global ModifiersActiveMap, PressedKeys
  active := Merge(ModifiersActiveMap, PressedKeys)
  ModifiersActiveMap := {}
  PressedKeys := {}
  ReleaseInactiveModifiers()
  return active
}
KeyIsPressed( keyName ){
  global PressedKeys
  return PressedKeys[keyName]
}
KeyIsUnpressed( keyName ){
  return not KeyIsPressed( keyName )
}
SetKeyPressed( keyName ){
  global PressedKeys
  PressedKeys[keyName] := true
}
SetKeyReleased( keyName ){
  global PressedKeys
  PressedKeys.Remove(keyName)
}
SetKeysReleased( keys ){
  for key, t in keys {
    SetKeyReleased( key )
  }
}
GetPressedKeys(){
  global PressedKeys
  return PressedKeys
}
PressedKeyCount(){
  global PressedKeys
  return Count(PressedKeys)
}


; Generic Getters and Setters
;===============================================================
Now(){
  global CurrentEventTime
  return CurrentEventTime
}
SetNow(){
  global CurrentEventTime := A_TickCount
}

KeyIsModKey( keyName, mode ){
  binding := KeyBindings[mode][keyName]
  isModKey := binding["Modifiers"] or binding["SetMode"]
  return isModKey
}
IsBaseModKey( keyName ){
  return not KeyBindings[BaseMode][keyName].HasKey("Action")
}
GetBaseAction( keyName ){
  return KeyBindings[BaseMode][keyName]["Action"]
}
GetBaseModifiers( keyName ){
  return KeyBindings[BaseMode][keyName]["Modifiers"]
}
GetKeyPhName( keyName ){
  phName := KeyBindings[BaseMode][keyName]["PhName"]
  return phName
}
GetCurrentBinding( keyName ){
  binding := KeyBindings[CurrentMode][keyName]
  return binding
}


GetModifierPrefix( mode := "" ){
  prefix := (GetKeyState("Alt", mode ) ? "!" : "")
          . (GetKeyState("Control", mode ) ? "^" : "")
          . (GetKeyState("Shift", mode ) ? "+" : "")
          . ( (GetKeyState("LWin", mode ) or GetKeyState("RWin", mode ) ) ? "#" : "")
  return prefix
}
ModifierPrefix_Display( mode := ""  ){
  prefix := ( GetKeyState("LAlt", mode ) ? "!" : "" )
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

mkString( obj, separator := ",", before := "", after := "" ){
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

StrPad(str, padlen, left := true){
  static spaces := "                              "
  diff := padlen - StrLen(str)
  StringLeft, padding, spaces, diff
  return left ? str padding : padding str
}

StrPad_binary(str, padlen, padchar := " ", left := false){
  if (i := padlen - StrLen(str)) {
    VarSetCapacity(w, i, asc(padchar))
    NumPut(0, &w+i, "Char")
    VarSetCapacity(w, -1)
  }
  return left ? w str : str w
}

Merge( obj1, obj2 ){
  new := obj1.Clone()
  for k, v in obj2 {
    new[k] := v
  }
  return new
}

RemoveIntersection( ByRef set1, ByRef set2 ){
  removed := {}
  for elem1, t in set1 {
    if set2[elem1] {
      set2.Remove(elem1)
      removed[elem1] := true
    }
  }
  for elem2, t in removed {
    set1.Remove(elem2)
  }
  return removed
}

; Debugging
;===============================================================

DebugMsg( msg, prepend_space := true ){
  logFile := "debug.log"
  if (Debug) {
    sp := prepend_space ? "        " : "  "
    FormatTime timestamp, , yyyy-MM-dd HH:mm:ss
    FileAppend, % timestamp sp msg "\n", % logFile
  }
}
MakeStatusMsg(){
  global BaseBuffer, ActionBuffer
  if Debug {
    mode := StrPad(CurrentMode, 12)
    buffers := (BaseBuffer or ActionBuffer) ? "<" BaseBuffer . " . " ActionBuffer "> " : ""
    prefixes := ( ModifierPrefix_Display() or GetModKeyPrefix() )
        ? "{" ModifierPrefix_Display() " . " GetModKeyPrefix() "}" : ""
    keys := " active: " mkString( GetPressedKeys() )
    msg := mode . buffers . prefixes . keys
    return msg
  }
}
OffsetTooltip(msg, rowOffset := 0){
  Tooltip % msg, 0, 18*4*rowOffset, rowOffset+1
}

