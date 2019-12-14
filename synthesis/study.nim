# Synthesis
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import macros, factory

# To display the generated state machine at compileTime, use "-d:debugSynthesis"

# High-level API
# ----------------------------------------------------------------------------------------------------

macro behavior*(automaton, body: untyped): untyped =
  ## Add a new behavior to a declared automaton
  ##
  ## Syntax:
  ##
  ## behavior(myWater):
  ##   ini: Liquid
  ##   fin: Ice
  ##   event: Below0
  ##   transition:
  ##     freeze(temp)
  ##
  ## ``ini`` can be an array of initial states that have the same end state and transition
  ## provided the same event
  ##
  ## ``event`` is optional, in that case the transition will be the default one.
  ## Default transition are applied if all event based transitions do not trigger.
  ##
  ## ``event`` can also be replaced by ``interrupt`` a special trigger
  ## that dispatches immediately to the ``fin`` state without applying ``onEntry`` and ``onExit`` event.
  ##
  ## This should be used when termination is detected or when ``onEntry`` or ``onExit`` event
  ## assumptions (a container not being empty for example) are not valid.
  ## For example we might assume that before evaluating any event we need to pop it from a queue,
  ## and assign it to an existing ``temp`` variable and keep the old reading as oldTemp
  ##
  ## onEntry(myWater, [Solid, Liquid, Gas]):
  ##   let oldTemp = temp
  ##   temp = tempReadings.pop()
  ##   echo "new temperature: ", temp
  ##
  ## However, we need to deal with the case of tempReadings being empty.
  ## Interrupts ignore "onEntry" and "onExit" and will shortcut a state that can handle that
  ## here, the exit state.
  ##
  ## behavior(myWater):
  ##   ini: [Solid, Liquid, Gas]
  ##   fin: Exit
  ##   interrupt: OutOfReadings
  ##   transition:
  ##     echo "Running our of steam ..."
  ##
  ## with OutofReadings
  ##
  ## implEvent(OutOfReadings):
  ##   tempReadings.len == 0
  ##
  ## To specify multiple steady states where the default transition (i.e. no event) is staying in the same state
  ## you can use the ``steady``.
  ##
  ## behavior(myWater):
  ##   steady: [Solid, Liquid, Gas]
  ##   transition:
  ##     echo "The change in temperature wasn't enough to change phase."
  ##
  ## Transitions are not optional. Use "discard" if there are no specific transition processing
  ## Transitions accept normal Nim code.
  ## Any of the following symbols are visible:
  ##
  ## - parameters of the synthesized automaton function
  ## - variables declared in setPrologue
  ## - variables declared in ``onEntry`` unless this is the behavior of an interrupt
  body.expectMinLen(2)

  # Parsing
  # ---------------------------------------------------------
  var ini, fin, steady, event, interrupt, transition: NimNode
  for b in body:
    b.expectKind(nnkCall)
    b[0].expectKind(nnkIdent)
    b[1].expectKind(nnkStmtList)
    let arg = b[1][0]
    case $b[0]
    of "ini":
      arg.expectKind({nnkIdent, nnkBracket})
      ini = arg
    of "fin":
      arg.expectKind(nnkIdent)
      fin = arg
    of "steady":
      arg.expectKind({nnkIdent, nnkBracket})
      steady = arg
    of "event":
      arg.expectKind(nnkIdent)
      event = arg
    of "interrupt":
      arg.expectKind(nnkIdent)
      interrupt = arg
    of "transition":
      transition = b[1]
    else:
      error "Malformed automaton behavior description"

  # Checking
  # ---------------------------------------------------------
  doAssert not transition.isNil
  if steady.isNil:
    ini.expectKind({nnkIdent, nnkBracket})
    fin.expectKind(nnkIdent)
  else:
    doAssert ini.isNil
    doAssert fin.isNil
    doAssert event.isNil
    doAssert interrupt.isNil
  # Anyway to have the check less convolutated with xor?
  if not event.isNil: doAssert interrupt.isNil
  if not interrupt.isNil: doAssert event.isNil

  # Dispatching to automaton factory
  # ---------------------------------------------------------
  # getAst doesn't do overloading resolution of typed / openarray[typed]
  # so we need unique names.
  if not steady.isNil:
    if steady.kind == nnkBracket:
      return getAst(addSteadyStates(automaton, steady, transition))
    return getAst(addSteadyState(automaton, steady, transition))
  if not event.isNil:
    if ini.kind == nnkBracket:
      return getAst(addConditionalTransitions(automaton, ini, event, fin, transition))
    return getAst(addConditionalTransition(automaton, ini, event, fin, transition))
  if not interrupt.isNil:
    if ini.kind == nnkBracket:
      return getAst(addInterrupts(automaton, ini, interrupt, fin, transition))
    return getAst(addInterrupt(automaton, ini, interrupt, fin, transition))

  if ini.kind == nnkBracket:
    return getAst(addDefaultTransitions(automaton, ini, fin, transition))
  return getAst(addDefaultTransition(automaton, ini, fin, transition))
