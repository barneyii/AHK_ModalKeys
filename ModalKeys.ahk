;;;;;;;;;;;;;;;;;;;;;;;;;;;  NOTES  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; For best performance, set windows Keyboard settings as follows:
;; "Repeat Delay" to as Short as possible
;; "Repeate Rate" to as Slow as possile
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

; Keyboard behaviour settings
;===============================================================

global InactivityTimeout := 10000 ; enter DefaultMode after this long of inactivity
global TypingModeTimeout := 150  ; InactivityTimeout while in TypingMode
global DoubleTabTimeout := 150

; determines the duration of the mode transition period
; during the transition period, key presses do nothing immediately
; When a ModKey is pressed in DefaultMode, it must be released before
; the transition period ends, without pressing any other keys, in order to send
; it's normal typing action.
global ModeActivationDelay := 300

; the maximum number of non-modKey keys that may be held down
; during Mode Transition before TypingMode will be activated
global HotkeyPressesPermittedDuringModeTransition := 2

; Key Repetition
global EnableKeyRepetition := true
global FirstRepetitionDelay := 400
global RepetitionDelay := 50


; Global Variables
;===============================================================

; Debugging
global Debug := true

; Mode Names
global DefaultMode := "DefaultMode"
global TypingMode  := "TypingMode"
global BaseModMode := "BaseModMode"
global CurrentMode := DefaultMode

; Import User Key Bindings
; this file should define KeyBindings[DefaultMode]
; along with any other Modes reachable from DefaultMode
KB_User := JSON_load("KB_User.json")

; Import Base Key Bindings
KB_Base := JSON_load("KB_Base.json")
KB_BaseModMode := JSON_load("KB_BaseModMode.json")
KB_TypingMode := JSON_load("KB_TypingMode.json")

; prepare global data structures
global KeyBindings := InitializeKeyBindings( KB_Base, KB_BaseModMode, KB_TypingMode, KB_User )
global ModeModModifiersMap := MakeModeModModifiersMap(KeyBindings)

; Status Globals
; --------------------------------------------------------------

global ModifiersActiveMap := {} ; Map[modifier => Map[modKey => true] ]
global PressedKeys := {}
global TypingBuffer := ""
global QueuedModActions := []
global QueuedModKeys := {}
global InModeTransition := 0
global CurrentlyRepeatingAction := ""
global CurrentlyRepeatingKey := ""

; Initializers
;===============================================================

InitializeKeyBindings( baseBindings, baseModModeBindings, typingModeBindings, userBindings){
  allBindings := {}

  ; initialize BaseModMode binding
  allBindings[BaseModMode] := baseBindings.Clone()
  UpdateBindings( allBindings[BaseModMode], baseModModeBindings )
  ; initialize TypingMode binding
  allBindings[TypingMode] := baseBindings.Clone()
  UpdateBindings( allBindings[TypingMode], typingModeBindings )
  ; initialize user bindings
  for mode, bindings in userBindings {
    ; initialize bindings with baseBindings
    allBindings[mode] := baseBindings.Clone()
    UpdateBindings( allBindings[mode], userBindings[mode] )
  }
  return allBindings
}

UpdateBindings( bindings, updateWith ){
  for key, newBinding in updateWith {
    bindings[key] := newBinding
  }
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
PrintScreen & F8::  ListVars
PrintScreen & F9::  KeyHistory
PrintScreen & F10:: ; toggle debug
  Debug := not Debug
  DeactivateAllKeys()
  ClearTooltip()
  return
PrintScreen & F11::    ; Reload
  DeactivateAllKeys()
  Reload
  return
PrintScreen & F12::Suspend
PrintScreen:: Send {PrintScreen} ; send PrintScreen on key up


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
  if ( EnableKeyRepetition and not A_IsSuspended ) {
    if (GetKeyState(CurrentlyRepeatingKey, "P")){
      DoAction( CurrentlyRepeatingAction, GetAllActiveModifiers() ) ; don't consider key-holding as normal typing
      SetTimer, DoRepetitions, % RepetitionDelay
    } else {
      DebugMsg("[bug] repetition called on unpressed key: " CurrentlyRepeatingKey)
      StopRepeating()
    }
  }
  return

StartRepeating( key, action ){
  ;DebugMsg("start repeating: " key " - " action)
  CurrentlyRepeatingKey := key
  CurrentlyRepeatingAction := action
  SetTimer, DoRepetitions, % FirstRepetitionDelay
}


StopRepeating(){
  if CurrentlyRepeatingAction {
    ;DebugMsg("stop repeating: " CurrentlyRepeatingKey " - " CurrentlyRepeatingAction)
  }
  CurrentlyRepeatingAction := ""
  CurrentlyRepeatingKey := ""
  SetTimer, DoRepetitions, Off
}

; Status Change Handlers
;===============================================================

EndModeTransition:
  InModeTransition := false
  SetTimer EndModeTransition, Off
  ;DebugMsg( CurrentMode " Mode Transition over")
  return

DelayEndModeTransition(){
  SetTimer EndModeTransition, % ModeActivationDelay
}

EnterDefaultMode:
  if ( not A_IsSuspended ){
    if ( CurrentMode != DefaultMode ){
      ;DebugMsg( "enter DefaultMode from " CurrentMode )
      ActivateMode( DefaultMode )
    }
    DelayEnterDefaultMode()
  }
  return
DelayEnterDefaultMode(){
  static currentlyScheduled
  currentWait := currentlyScheduled - A_TickCount

  if ( NoPressedKeys() and CurrentMode == TypingMode ) {
    newWait := TypingModeTimeout
  } else {
    newWait := InactivityTimeout
  }

  ;DebugMsg( CurrentMode ": delaying DefaultMode mode " currentWait "ms => " newWait "ms")
  SetTimer EnterDefaultMode, % newWait
  currentlyScheduled := A_TickCount + newWait
}



; Key Handlers
;===============================================================

PressKeyEvent( key ){
  ; delay auto-retun to DefaultMode after %InactivityTimout%
  DelayEnterDefaultMode()

  if KeyIsUnpressed( key ) { ; disable hardware key-repetition
    DebugMsg( StrPad("P> " key, 14) " " MakeStatusMsg(), false )
    SetNow()
    activeModifiers := GetAllActiveModifiers()
    SetKeyPressed( key )

    ; use separate function for performing actions so it can be called separately
    DoKeyPress( key, activeModifiers )

    UpdateStatusTooltip()
    DebugMsg( StrPad("<P " key, 14) " " MakeStatusMsg(), false )
  }
}
DoKeyPress( key, activeModifiers ){
  ReleaseInactiveModifiers()

  ; add typingKey to queue in case we retroactively need to switch to typingMode
  typingAction := GetTypingAction( key )
  AppendToTypingBuffer( typingAction )

  StopRepeating() ; only repeat between key press/release events

  binding := GetCurrentBinding( key )

  if QueuedModActionsLimitReached() { ; already a queued modAction -> assume typing intended
    ActivateMode( TypingMode )
  }
  ; do Mode Change
  else if ( (newMode := binding["SetMode"]) and newMode != CurrentMode ){
    ActivateMode( newMode )
  }
  ; activate Modifier
  else if ( modifiers := binding["Modifiers"] ) {
    ActivateModKey( key, modifiers )
  }
  ; do Action
  else if ( action := binding["Action"] ) {
    if ( CurrentMode == DefaultMode ){
      ; actions in DefaultMode mode indicate typing
      ActivateMode( TypingMode )
    }
    else if InModeTransition { ; prepare for different contingencies
      ; remember this action and perform it if this key is immediately released
      QueueModAction( key, action )
    }
    else { ; We are now confidently in this mode: send Action immediately
      DoAction( action, activeModifiers )
    }

    ; start repeating action
    StartRepeating( key, action )
  }
}


ReleaseKeyEvent( key ){
  DebugMsg( StrPad( "R> " key, 14) " " MakeStatusMsg(), false )
  SetNow()
  activeModifiers := GetAllActiveModifiers()
  DeactivateKey( key )

  ReleaseInactiveModifiers() ; release any modifiers that were deactivated

  ; stop repeating upon any action
  StopRepeating()

  binding := GetCurrentBinding( key )

  if QueuedModKeys[key] { ; perform queued modActions on release
    DoQueuedModActions( activeModifiers )
    InModeTransition := false ; confirm user wants this mode
  }
  else if InModeTransition { ; release actions other than the queued action
                                  ; during transition phase are assumed to indicate typing
    ActivateMode( TypingMode )
  }

  ; if this was the last key released, activate DefaultMode
  ;PrunePressedKeys()
  if NoPressedKeys() {
    if ( CurrentMode == TypingMode ){
      DelayEnterDefaultMode()
    } else {
      ;DebugMsg("no keys pressed. entering default mode")
      GoSub EnterDefaultMode ; this sub activates if no keys are pressed
    }
  }

  UpdateStatusTooltip()
  DebugMsg( StrPad( "R< " key, 14) " " MakeStatusMsg(), false )
}


; Mode Change Handlers
;===============================================================

ActivateMode( newMode ) {
  oldMode := CurrentMode
  ;DebugMsg( "activating mode: " newMode )

  if ( oldMode == newMode ) {
    DebugMsg( "[bug] oldMode(" oldMode ") = newMode(" newMode ")" )
    return
  }

  ; if we are entering base mode, flush the TypingBuffer
  if ( newMode == TypingMode ){
    FlushTypingBuffer()
  }
  if ( newMode == DefaultMode ){
    ClearBuffers()
    DeactivateAllModKeys()
    ;DeactivateAllKeys()
  }

  ; activate pressed modifiers for new Mode
  werePressed := GetPressedKeys().Clone()
  persistingModKeys := {}
  for modKey, t in werePressed {
    if KeyIsModKey( modKey, newMode ) {
      persistingModKeys[modKey] := true
    }
  }
  oldModkeys := DeactivateAllModKeys() ; doesn't deactivate the keys themselves
  CurrentMode := newMode

  activatedModifiers := ActivateModKeys( persistingModKeys )

  if ( newMode == TypingMode or newMode == BaseModMode
    or newMode == DefaultMode ){
    GoSub EndModeTransition
    PressActiveModifiers()
  }
  else {
    InModeTransition := Now()
    DelayEndModeTransition()
  }

  ;DebugMsg( "  mode change key transition: ("
  ;  . mkString(werePressed) ")(" mkString(oldModkeys) ") - [" mkString(keysToDeactivate) "] => "
  ;  . "(" mkString(persistingModKeys) ")(" mkString(activatedModifiers) ")" )

}

; Action Buffer Helpers
;===============================================================

DoModifierChange( modifierChange ){
  if ( modifierChange ){
    Send % modifierChange
    DebugMsg( "**send_m: " modifierChange)
  }
}

AppendToTypingBuffer( typingAction ){
  TypingBuffer .= typingAction
}

FlushTypingBuffer( typingActions := "" ){
  global TypingBuffer
  actions := TypingBuffer . typingActions
  ClearBuffers() ; TODO: use Object.Remove() for atomicity if necessary

  if actions {
    DebugMsg("**type: " actions )
    Send {Blind}%actions%
  }
  return actions
}

DoAction( action, activeModifiers ){
  PressUnpressedModifiers( activeModifiers )
  ;Sleep 10
  DebugMsg("**send: " action )
  Send {Blind}%action%
  ClearBuffers()
  return action
}


DoQueuedModActions( activeModifiers ){
  return DoAction( mkString(QueuedModActions, ""), activeModifiers )
}

ModActionsQueued(){
  return QueuedModActions.MaxIndex()
}

QueuedModActionsLimitReached(){
  return SizeOf(QueuedModActions) >= HotkeyPressesPermittedDuringModeTransition
}

QueueModAction( key, modAction ){
  if QueuedModActionsLimitReached() {
    DebugMsg("[bug] too many queued modActions: "
      . mkString(QueuedModKeys) ":" mkString(QueuedModActions)
      . " => " key ":" modAction, false )
    return
  }
  QueuedModKeys[key] := true
  QueuedModActions.Insert( modAction )
}

ClearBuffers(){
  TypingBuffer := ""
  QueuedModActions := []
  QueuedModKeys := {}
}


; Key Status handlers
;===============================================================

PressUnpressedModifiers( modifiers ){
  toPress := {}

  for modifier, prx in modifiers {
    modifierPressed := GetKeyState( modifier )
    if not modifierPressed {
      toPress[modifier] := true
    }
  }
  if not IsEmpty( toPress ) {
    pressModifiersStr := MakePressModifiersStr( toPress )
    DoModifierChange( pressModifiersStr )
  }

  return toPress
}

PressActiveModifiers() {
  PressUnpressedModifiers( GetAllActiveModifiers() )
}

ReleaseInactiveModifiers(){
  PrunePressedKeys()
  toRelease := {}

  for modifier, t in GetAllModifiers() {
    activeModKeys := GetActiveModKeysFor(modifier)
    modifierPressed := GetKeyState(modifier)

    if modifierPressed and isEmpty(activeModKeys) {
      toRelease[modifier] := true
    }
  }
  if not IsEmpty( toRelease ) {
    releaseModifiersStr := MakeReleaseModifiersStr( toRelease )
    DoModifierChange( releaseModifiersStr )
  }

  return toRelease
}

PrunePressedKeys(){
  toPrune := {}
  for key, t in GetPressedKeys() {
    ;DebugMsg("  checking " key  "\t" GetKeyState(key, "P") "\t" GetKeyState(key))
    if ( not GetKeyState(key, "P") ){
      toPrune[key] := true
    }
  }
  deactivatedModifiers := DeactivateKeys( toPrune )
  if !IsEmpty( toPrune ){
    DebugMsg("[bug] Unpressed keys found in PressedKeys: " mkString(toPrune) )
  }
  if !IsEmpty( deactivatedModifiers ){
    DebugMsg("[bug] Modifiers deactivated during prune: " mkString(deactivatedModifiers))
  }
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
ActivateModKey( modKey, modifiers := false ){
  global ModifiersActiveMap
  if (not modifiers){
    modifiers := GetCurrentBinding( modKey )["Modifiers"]
  }

  SetKeyPressed( modKey )
  activatedModifiers := {}
  for i, modifier in modifiers {
    ModifiersActiveMap[modifier, modKey] := true
    activatedModifiers[modifier] := true
  }
  ModifiersActiveMap["", modKey] := true

  return activatedModifiers
}

DeactivateKeys( modKeys ){
  deactivatedModifiers := {}
  for modKey, t in modKeys {
    for modifier, t in DeactivateKey( modKey ){
      deactivatedModifiers[modifier] := true
    }
  }
  return deactivatedModifiers
}

DeactivateKey( modKey ){
  global ModifiersActiveMap
  setkeyreleased( modkey )
  deactivatedModifiers := {}
  for modifier, activeModKeys in ModifiersActiveMap {
    if activeModKeys[modKey] {
      activeModKeys.Remove(modKey)
      if IsEmpty( activeModKeys ){
        deactivatedModifiers[modifier] := true
      }
    }
  }
  for modifier, t in deactivatedModifiers {
    ModifiersActiveMap.Remove(modifier)
  }

  return deactivatedModifiers
}

GetAllActiveModifiers(){
  global ModifiersActiveMap
  modifiers := {}
  for modifier, modKeys in ModifiersActiveMap {
    modifiers[modifier] := true
  }
  modifiers.Remove("")
  return modifiers
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
  n := SizeOf( GetAllActiveModKeys() )
  return n
}

ModKeyIsActive(modKey){
  isActive := GetAllActiveModKeys()[modKey]
  return isActive
}

DeactivateAllModKeys(){
  global ModifiersActiveMap
  wereActive := ModifiersActiveMap
  ModifiersActiveMap := {}
  for modifier, modKeys in wereActive {
    SetKeysReleased( modKeys )
  }
  return wereActive
}

DeactivateAllKeys(){
  global ModifiersActiveMap, PressedKeys
  if Debug { ; only bother with this for debugging
    active := Merge( ModifiersActiveMap, PressedKeys )
  }
  ModifiersActiveMap := {}
  PressedKeys := {}
  return active
}

KeyIsPressed( key ){
  global PressedKeys
  return PressedKeys[key]
}

KeyIsUnpressed( key ){
  return not KeyIsPressed( key )
}

SetKeyPressed( key ){
  global PressedKeys
  PressedKeys[key] := true
}

SetKeysReleased( keys ){
  for key, t in keys {
    SetKeyReleased( key )
  }
}
SetKeyReleased( key ){
  global PressedKeys
  PressedKeys.Remove(key)
}


GetPressedKeys(){
  global PressedKeys
  return PressedKeys
}

PressedKeyCount(){
  return SizeOf(GetPressedKeys())
}

NoPressedKeys(){
  return PressedKeyCount() == 0
}

GetPressedNormalKeys(){
  normalKeys := GetPressedKeys().Clone()
  for modKey, t in GetAllActiveModKeys() {
    normalKeys.Remove( modKey )
  }
  return normalKeys
}

PressedNormalKeyCount(){
  return SizeOf(GetPressedNormalKeys())
}

GetAllModifiers(){
  static modifiers := { "LAlt": "!"
                      , "RAlt": "!"
                      , "LControl": "^"
                      , "RControl": "^"
                      , "LShift": "+"
                      , "RShift": "+"
                      , "LWin": "#"
                      , "RWin": "#" }
  return modifiers
}

GetActionPrefix(){
  MakeModifierPrefix( GetAllActiveModifiers() )
}

MakeModifierPrefix( activeModifiers ){
  prefix := ""
  for modifier, prx in GetAllModifiers() {
    if activeModifiers[modifier]
      prefix .= prx
  }
  return prefix
}

PressModifiers( modifiers ){
  DoModifierChange( MakePressModifiersStr( modifiers ) )
}
ReleaseModifiers( modifiers ){
  DoModifierChange( MakeReleaseModifiersStr( modifiers ) )
}

MakePressModifiersStr( modifiers ){
  return mkString( modifiers, "", "{", " Down}")
}

MakeReleaseModifiersStr( modifiers ){
  return mkString( modifiers, "", "{", " Up}")
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

KeyIsModKey( key, mode ){
  binding := KeyBindings[mode][key]
  isModKey := binding["Modifiers"] or binding["SetMode"]
  return isModKey
}

IsBaseModKey( key ){
  return not KeyBindings[TypingMode][key].HasKey("Action")
}

GetTypingAction( key ){
  return KeyBindings[TypingMode][key]["Action"]
}

GetCurrentBinding( key ){
  binding := KeyBindings[CurrentMode][key]
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
          . ( GetKeyState("RAlt", mode ) ? ".!" : "" )
          . ( GetKeyState("RControl", mode ) ? ".^" : "" )
          . ( GetKeyState("RShift", mode ) ? ".+" : "" )
          . ( GetKeyState("RWin", mode ) ? ".#" : "" )
  return prefix
}

; Helper Functions
;===============================================================

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

IsEmpty( obj ){
  empty := true
  for key, value in obj {
    empty := false
  }
  return empty
}

SizeOf( obj ){
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

SetSubtract( set1, set2 ){
  intersection := set1.Clone()
  for elem2, t in set2 {
    intersection.Remove(elem2)
  }
  return intersection
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
  global TypingBuffer, QueuedModActions
  if Debug {
    mode := StrPad(CurrentMode, 12)
    buffers := (TypingBuffer or ModActionsQueued()) ? "<" TypingBuffer . " . " mkString(QueuedModActions, "") "> " : ""
    prefixes := ( ModifierPrefix_Display() or GetActionPrefix() )
        ? "{" ModifierPrefix_Display() " . " GetActionPrefix() "}" : ""
    keys := " active: " mkString( GetPressedKeys() )
    msg := mode . buffers . prefixes . keys
    return msg
  }
}
OffsetTooltip(msg, rowOffset := 0){
  Tooltip % msg, 0, 18*4*rowOffset, rowOffset+1
}

RemoveStatusTooltip:
  Tooltip % "", 0, 0, 1
  return

UpdateStatusTooltip(){
  Tooltip % CurrentMode " " ModifierPrefix_Display() "" mkString( GetPressedKeys(), "," ), 0, 0, 1
  SetTimer, RemoveStatusTooltip, % 2000
}
