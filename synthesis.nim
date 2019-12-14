# Synthesis
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  macros, tables, hashes, sets

# To display the generated state machine at compileTime, use "-d:debugSynthesis"

# Note, ideally we would use generic enums for State and Event
# with `Automaton[State, Event: enum] = object`
# and replace Tables by arrays
#
# but they will trigger early symbol resolution in templates
# and cause "undeclared identifier" left and right

type
  State = string
  Event = string

  # Concrete implementation of an event/input
  # This should return a boolean
  EventImpl = NimNode

  # A function
  TransitionImpl = NimNode

  Automaton = ref object
    ## An automaton is:
    ## - an initial state
    ## - a set of states
    ## - a mapping of states -> valid events
    ## - an implementation of the valid events
    ## - a transition table which maps (State, Event) -> (new State)
    ## - a transition function table which applies the transition function before changing state
    # We cannot use enum typedesc as they trigger early symbol resolution

    stateEnum: NimNode
    eventEnum: NimNode

    # on Automaton start and end
    prologue: NimNode
    epilogue: NimNode
    # Starting and terminal state
    initial: State
    terminal: State
    # Set of states
    states: Hashset[State]
    # Events (or absence of) that requires exceptional handling (for example termination or normal input being empty)
    circuitBreakers: Table[State, seq[Event]]
    # Setup at each state entry
    stateEntries: Table[State, NimNode]
    # Events checked by each state
    triggers: Table[State, seq[Event]]
    # CircuitBreakers and Events implementation (boolean expressions)
    eventImpls: Table[Event, EventImpl]
    # (State, Event) -> State mapping
    condTransitions: Table[(State, Event), State]
    # State -> State mapping
    defaultTransitions: Table[State, State]
    # Processing during transition
    condTransitionsFn: Table[(State, Event), TransitionImpl]
    defaultTransitionsFn: Table[State, TransitionImpl]
    # State teardown
    stateExits: Table[State, NimNode]

proc hash(se: (State, Event)): Hash =
  hash($se[0] & "_" & $se[1])

var Registry* {.compileTime.}: Table[string, Automaton]

macro declareAutomaton*(
          automaton: untyped{nkIdent},
          stateEnum: typed{nkSym},
          eventEnum: typed{nkSym}) =
  ## Register an automaton
  ## The stateEnum will be materialized as goto labels
  ## The eventEnum is informative only and may be used in the future for graphics
  ## and documentation generation
  Registry[$automaton] = Automaton(stateEnum: stateEnum, eventEnum: eventEnum)

macro setPrologue*(automaton: untyped{nkIdent}, prologue: untyped) =
  ## Configure the state machine before entering any states.
  ## In particular variables that are not state-specific should be configured here
  Registry[$automaton].prologue = prologue

macro setEpilogue*(automaton: untyped{nkIdent}, epilogue: untyped) =
  ## Teardown the state machine after exit
  ## In particular memory reclamation should happen here
  Registry[$automaton].epilogue = epilogue

macro setInitialState*(automaton: untyped{nkIdent}, initialState: typed{nkSym}) =
  ## Set the state machine entry point.
  ## It must be a valid state and must be an enum literal.
  ##
  ## If your state machine has multiple entry points, you can configure them
  ## as transitions, potentially using ``when`` to force compile-time evaluation
  ## and allow compiler constant-folding of the dummy initial state.
  let A = Registry[$automaton]
  let S = $initialState
  A.states.incl(S)
  A.initial = $initialState

# Note: to support exit not being a real identifier
#       all outstate parameters must be untyped

macro setTerminalState*(automaton: untyped{nkIdent}, terminalState: untyped{nkIdent}) =
  ## Set the state machine exit point.
  ## This doesn't have to be a valid enum literal.
  ## It is a pseudo-state you can refer to in transitions
  let A = Registry[$automaton]
  let S = $terminalState
  A.states.incl(S)
  A.terminal = $terminalState

macro onEntry*(automaton: untyped{nkIdent}, state: typed{nkSym}, stmts: untyped) =
  ## Add a statement that will be executed at each entry of the designated state
  ## This is not added to circuit breaker transitions
  let A = Registry[$automaton]
  let S = $state
  A.states.incl(S)
  A.stateEntries[S] = stmts

macro onEntry*(automaton: untyped{nkIdent}, states: openarray[typed], stmts: untyped) =
  ## Add a statement that will be executed at each entry of the designated state
  ## This is not added to circuit breaker transitions
  let A = Registry[$automaton]
  for state in states:
    let S = $state
    A.states.incl(S)
    A.stateEntries[S] = stmts

macro onExit*(automaton: untyped{nkIdent}, state: typed{nkSym}, stmts: untyped) =
  ## Add a statement that will be executed at each exit points of the designated state
  ## If a state has multiple transitions, those statement will be executed after each transition.
  ## This is not added to circuit breaker transitions
  let A = Registry[$automaton]
  let S = $state
  A.states.incl(S)
  A.stateExits[S] = stmts

macro onExit*(automaton: untyped{nkIdent}, states: openarray[typed], stmts: untyped) =
  ## Add a statement that will be executed at each exit points of the designated state
  ## If a state has multiple transitions, those statement will be executed after each transition.
  ## This is not added to circuit breaker transitions
  let A = Registry[$automaton]
  for state in states:
    let S = $state
    A.states.incl(S)
    A.stateExits[S] = stmts

macro implEvent*(automaton: untyped{nkIdent}, event: typed{nkSym}, trigger: untyped) =
  ## Add the implementation of an event to an automaton.
  ## If an event is applicable to many states, it will be reused for all of them.
  let A = Registry[$automaton]
  A.eventImpls[$event] = trigger

macro addCircuitBreaker*(
        automaton: untyped{nkIdent},
        inState, event: typed{nkSym},
        outState: untyped{nkIdent},
        transitionFn: untyped
      ) =
  ## Add a special transition (state, event) -> new state
  ## that is checked in priority and does not trigger onEntry and onExit hooks.
  ## This is meant for exceptional handling like termination or input being empty.
  let
    A = Registry[$automaton]
    I = $inState
    E = $event
    O = $outState

  A.states.incl(I)
  A.states.incl(O)
  A.circuitBreakers.mgetOrPut($I, @[]).add(E)
  A.condTransitions[(I, E)] = O
  A.condTransitionsFn[(I, E)] = transitionFn

macro addCircuitBreaker*(
        automaton: untyped{nkIdent},
        inStates: openarray[typed],
        event: typed{nkSym},
        outState: untyped{nkIdent},
        transitionFn: untyped
      ) =
  ## Add special transitions (state, event) -> new state
  ## that is checked in priority and does not trigger onEntry and onExit hooks.
  ## This is meant for exceptional handling like termination or input being empty.
  ##
  ## For states that respond the same to an event
  let
    A = Registry[$automaton]
    E = $event
    O = $outState

  A.states.incl(O)
  for inState in inStates:
    let I = $inState
    A.states.incl(I)
    A.circuitBreakers.mgetOrPut(I, @[]).add(E)
    A.condTransitions[(I, E)] = O
    A.condTransitionsFn[(I, E)] = transitionFn

macro addConditionalTransition*(
        automaton: untyped{nkIdent},
        inState, event: typed{nkSym},
        outState: untyped{nkIdent},
        transitionFn: untyped
      ) =
  ## Add a mapping (state, event) -> new state
  let
    A = Registry[$automaton]
    I = $inState
    E = $event
    O = $outState

  A.states.incl(I)
  A.states.incl(O)
  A.triggers.mgetOrPut($I, @[]).add(E)
  A.condTransitions[(I, E)] = O
  A.condTransitionsFn[(I, E)] = transitionFn

macro addConditionalTransition*(
        automaton: untyped{nkIdent},
        inStates: openarray[typed],
        event: typed{nkSym},
        outState: untyped{nkIdent},
        transitionFn: untyped
        ) =
  ## Add a mapping (states, event) -> new state
  ##
  ## For states that respond the same to an event
  let
    A = Registry[$automaton]
    E = $event
    O = $outState

  A.states.incl(O)
  for inState in inStates:
    let I = $inState
    A.states.incl(I)
    A.triggers.mgetOrPut(I, @[]).add(E)
    A.condTransitions[(I, E)] = O
    A.condTransitionsFn[(I, E)] = transitionFn

macro addDefaultTransition*(
        automaton: untyped{nkIdent},
        inState: typed{nkSym},
        outState: untyped{nkIdent},
        transitionFn: untyped
      ) =
  ## Add a mapping state -> new state
  let
    A = Registry[$automaton]
    I = $inState
    O = $outState

  A.states.incl(I)
  A.states.incl(O)
  A.defaultTransitions[I] = O
  A.defaultTransitionsFn[I] = transitionFn

macro addDefaultTransition*(
        automaton: untyped{nkIdent},
        inStates: openarray[typed],
        outState: untyped{nkIdent},
        transitionFn: untyped
        ) =
  ## Add a mapping states -> new state
  ##
  ## For states that respond the same to an event
  let
    A = Registry[$automaton]
    O = $outState

  A.states.incl(O)
  for inState in inStates:
    let I = $inState
    A.states.incl(I)
    A.defaultTransitions[I] = O
    A.defaultTransitionsFn[I] = transitionFn

macro addSteadyState*(
        automaton: untyped{nkIdent},
        steadyState: typed{nkSym},
        transitionFn: untyped
      ) =
  ## Add a mapping state -> same state
  ## For states that reoccur by default
  let
    A = Registry[$automaton]
    S = $steadyState

  A.states.incl(S)
  A.defaultTransitions[S] = S
  A.defaultTransitionsFn[S] = transitionFn

macro addSteadyState*(
        automaton: untyped{nkIdent},
        steadyStates: openarray[typed],
        transitionFn: untyped
        ) =
  ## Add a mapping state -> same state
  ## For states that reoccur by default
  let A = Registry[$automaton]

  for state in steadyStates:
    let S = $state
    A.states.incl(S)
    A.defaultTransitions[S] = S
    A.defaultTransitionsFn[S] = transitionFn

const withBuiltins = defined(gcc) or defined(clang) or defined(icc) or defined(llvm_gcc)

proc builtin_unreachable(){.nodecl, importc: "__builtin_unreachable".}

template unreachable(procName, state, circuitBreakers, triggers, default: string): untyped =
  assert(false, procName & " had an invalid transition from state \"" & state & "\".\n" &
                  "Supported transition circuitBreakers are " & circuitBreakers & "\".\n" &
                  "Supported transition triggers are " & circuitBreakers & "\".\n" &
                  "Default transition is " & default & "\".\n")
  when withBuiltins:
    builtin_unreachable()

proc nextStateOrBreak(
        stateBody: var NimNode,
        event: NimNode,
        gotoState, breakState, stateExit: NimNode,
        newState, terminalState: State, transitionFn: NimNode) =
  # if not newState.eqident(A.terminal):
  #   stateBody.add quote do:
  #     if `cbImpl`:
  #       `transFn`
  #       `stateExit`
  #       `State` = `newState`
  # else:
  #   stateBody.add quote do:
  #     if `cbImpl`:
  #       `transFn`
  #       `stateExit`
  #       break `SteadyStates`
  #
  # Or
  #
  # if default.eqIdent(A.terminal):
  #   stateBody.add quote do:
  #     `transFn`
  #     `stateExit`
  #     break `SteadyStates`
  # elif not default.eqIdent(""):
  #   stateBody.add quote do:
  #     `transFn`
  #     `stateExit`
  #     `State` = `default`
  #
  # quote do causes issue with identifier resolution
  let stateExit = if stateExit.isNil: nnkDiscardStmt.newTree(newLit"CircuitBreaker: no state exit")
                  else: stateExit
  let next = if newState == terminalState: nnkBreakStmt.newTree(breakState)
             else: newAssignment(gotoState, ident(newState))

  if not event.isNil:
    stateBody.add nnkIfStmt.newTree(
      nnkElifBranch.newTree(
        event,
        nnkStmtList.newTree(
          transitionFn,
          stateExit,
          next
        )
      )
    )
  else:
    stateBody.add nnkBlockStmt.newTree(
      ident"DefaultTransition",
      nnkStmtList.newTree(
        transitionFn,
        stateExit,
        next
      )
    )

macro buildAutomaton*(automaton, fnSignature: untyped): untyped =
  ## Build a proc with the required signature from a registered
  ## automaton description

  # Sanity checks
  # ---------------------------------------------------
  fnSignature.expectKind(nnkStmtList)
  fnSignature[0].expectKind({nnkProcDef, nnkFuncDef})
  fnSignature.expectLen(1)

  let procDef = fnSignature[0]
  let A = Registry[$automaton]
  let State = ident"SynthesisCurrentState"
  let SteadyStates = ident"SynthesisSteadyStates"
  let noTransFn = nnkDiscardStmt.newTree(newLit "No transition function.")
  let noEntryFn = nnkDiscardStmt.newTree(newLit "No Entry function.")
  let noExitFn = nnkDiscardStmt.newTree(newLit "No Exit function.")
  let noPrologue = nnkDiscardStmt.newTree(newLit "No Prologue function.")
  let noEpilogue = nnkDiscardStmt.newTree(newLit "No Epilogue function.")

  procDef[^1].expectKind(nnkEmpty) # Expect no proc body

  var body = newStmtList()
  if A.prologue.isNil:
    body.add noPrologue
  else:
    body.add A.prologue

  let initState = ident(A.initial)
  var steadyBlock = newStmtList()
  steadyBlock.add quote do:
    var `State` {.goto.} = `initState`

  var SM = nnkCaseStmt.newTree(State)
  for state in A.states:
    if state == A.terminal:
      # Special handling
      continue
    var stateBody = newStmtList()

    # Handle the circuit breakers
    for cb in A.circuitBreakers.getOrDefault(state):
      let newState = A.condTransitions[(state, cb)]
      let transFn = A.condTransitionsFn.getOrDefault((state, cb), noTransFn)
      let cbImpl = A.eventImpls[cb]
      nextStateOrBreak(
        stateBody, cbImpl,
        State, SteadyStates,
        nil, newState, A.terminal, transFn)


    # Setup the common processing at each state entry
    stateBody.add A.stateEntries.getOrDefault(state, noEntryFn)
    let stateExit = A.stateExits.getOrDefault(state, noExitFn)

    # Check each event accepted by the current state
    for trigger in A.triggers.getOrDefault(state):
      let newState = A.condTransitions[(state, trigger)]
      let transFn = A.condTransitionsFn.getOrDefault((state, trigger), noTransFn)
      let eventImpl = A.eventImpls[trigger]
      nextStateOrBreak(
        stateBody, eventImpl,
        State, SteadyStates,
        stateExit, newState, A.terminal, transFn)

    # Add a default transition
    let default = A.defaultTransitions.getOrDefault(state)
    let transFn = A.defaultTransitionsFn.getOrDefault(state, noTransFn)
    if default != "":
      nextStateOrBreak(
        stateBody, nil,
        State, SteadyStates,
        stateExit, default, A.terminal, transFn)

    block: # Sanity check
      let procName = $procDef[0]
      let stateStr = $state
      let circBreakers = $A.circuitBreakers.getOrDefault(state)
      let triggers = $A.triggers.getOrDefault(state)
      let default = if default.eqIdent(""): "\"\""
                    else: $default
      stateBody.add getAst(unreachable($procDef[0], stateStr, circBreakers, triggers, default))

    SM.add nnkOfBranch.newTree(
      ident($state),
      stateBody
    )

  steadyBlock.add SM
  body.add nnkBlockStmt.newTree(
    SteadyStates,
    steadyBlock
  )
  if A.epilogue.isNil:
    body.add noEpilogue
  else:
    body.add A.epilogue

  procDef.body = body
  result = procDef

  when defined(debugSynthesis):
    echo "=============================="
    echo result.toStrLit
    echo "=============================="

# Sanity checks
# ---------------------------------------------------

when isMainModule:
  type Phase = enum
    Solid
    Liquid
    Gas
    Plasma

  type Temps = enum
    Over100
    Between0and100
    Below0
    OutofWater

  proc melt(temp: float64) =
    assert temp >= 0
    echo "Ice is melting into Water.\n"

  proc vaporize(temp: float64) =
    assert temp >= 100
    echo "Water is vaporizing into Vapor.\n"

  proc sublimate(temp: float64) =
    assert temp >= 100
    echo "Ice is sublimating into Vapor.\n"

  proc freeze(temp: float64) =
    assert temp <= 0
    echo "Water is freezing into Ice.\n"

  proc condense(temp: float64) =
    assert temp <= 100
    echo "Vapor is condensing into Water.\n"

  proc deposit(temp: float64) =
    assert temp <= 0
    echo "Vapor is depositing into Ice.\n"

  proc noChange(oldTemp, newTemp: float64) =
    echo "Changing temperature from ", oldTemp, " to ", newTemp, " didn't change phase. How exciting!\n"

  declareAutomaton(waterMachine, State, Temps)
  setPrologue(waterMachine):
    echo "Welcome to the Steamy machine version 2000!\n"
    var temp: float64

  setInitialState(waterMachine, Liquid)
  setTerminalState(waterMachine, Exit)

  implEvent(waterMachine, OutOfWater):
    tempFeed.len == 0

  implEvent(waterMachine, Between0and100):
    0 < temp and temp < 100

  implEvent(waterMachine, Below0):
    temp < 0

  implEvent(waterMachine, Over100):
    100 < temp

  onEntry(waterMachine, [Solid, Liquid, Gas]):
    let oldTemp = temp
    temp = tempFeed.pop()
    echo "Temperature: ", temp

  addCircuitBreaker(waterMachine, [Solid, Liquid, Gas, Plasma], OutOfWater, Exit):
    echo "Running out of steam ..."

  addConditionalTransition(waterMachine, Solid, Between0and100, Liquid):
    melt(temp)

  addConditionalTransition(waterMachine, Liquid, Over100, Gas):
    vaporize(temp)

  addConditionalTransition(waterMachine, Solid, Over100, Gas):
    sublimate(temp)

  addConditionalTransition(waterMachine, Liquid, Below0, Solid):
    freeze(temp)

  addConditionalTransition(waterMachine, Gas, Between0and100, Liquid):
    condense(temp)

  addConditionalTransition(waterMachine, Gas, Below0, Solid):
    deposit(temp)

  addSteadyState(waterMachine, [Solid, Liquid, Gas]):
    noChange(oldTemp, temp)

  buildAutomaton(waterMachine):
    proc observeWater(tempFeed: var seq[float])

  import random, sequtils

  echo "\n"
  var obs = newSeqWith(20, rand(-50.0..150.0))
  echo obs
  echo "\n\n"
  observeWater(obs)
