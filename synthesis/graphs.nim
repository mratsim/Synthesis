# Synthesis
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[macros, strutils, sequtils, sets, tables],
  ./factory

# Display the Finite-State-Automaton as a graph
# ----------------------------------------------------------------------------------------------------

const indent = "    "
const EOL = ";\n"

type
  PrevNodeKind = enum
    pnState
    pnInterrupt
    pnEvent

  PrevNode = tuple[id: string, kind: PrevNodeKind]

proc graphVizReprImpl(automaton: NimNode): string =
  ## Generates a stringified representation of the Finite-State Automaton
  ## in Graphviz .dot format
  ##
  ## Note: we make events/triggers first-class by giving them a node
  ##       instead of them being just a label on top of an arrow
  ##
  ## The tests of conditions for events/triggers reflect the code generation

  let aName = $automaton
  let A = Registry[aName]

  result.add "digraph " & aName & "{\n"

  # Style orthogonal lines
  result.add indent & "splines=ortho;\n"

  # Double-circle entry and exit states
  result.add indent & "node [shape = doublecircle]; InitialState " & A.terminal & EOL
  # Circle states
  result.add indent & "node [shape = circle, fontcolor=white, fillcolor=darkslategrey, style=\"filled\"];"
  for state in A.states:
    if state != A.terminal:
      result.add " " & state
  result.add EOL

  # Initial state
  result.add indent & "InitialState -> " & A.initial & " [color=\"black:invis:black\", xlabel=\"entry point\"]" & EOL

  # Making events/triggers have their own first-class node
  var eventLabels: string
  var interruptLabels: string
  var eventDecl: string
  var interruptDecl: string
  # Normal events
  if A.triggers.len > 0:
    eventDecl.add indent & "node [shape = octagon, fontcolor=black, fillcolor=lightsteelblue, style=\"rounded,filled\"]; "
    for state, events in A.triggers:
      for event in events:
        let nodeID = state & "_" & event
        let nodeLabel = A.eventImpls[event].repr().replace("\x0a", "") # Somehow the string repr start with CR (\x0a)
        eventDecl.add nodeID & " "
        eventLabels.add indent & nodeID & " [label=\"" & event & "\\n" & nodeLabel & "\"]" & EOL
    eventDecl.add EOL
    result.add eventDecl
  # Interrupt events
  if A.interrupts.len > 0:
    interruptDecl.add indent & "node [shape = diamond, fontcolor=black, fillcolor=coral, style=\"rounded,filled\"]; "
    for state, interrupts in A.interrupts:
      for interrupt in interrupts:
        let nodeID = state & "_" & interrupt
        let nodeLabel = A.eventImpls[interrupt].repr().replace("\x0a", "") # Somehow the string repr start with CR (\x0a)
        interruptDecl.add nodeID & " "
        interruptLabels.add indent & nodeID & " [label=\"" & interrupt & "\\n" & nodeLabel & "\"]" & EOL
    interruptDecl.add EOL
    result.add interruptDecl

  result.add eventLabels
  result.add interruptLabels

  var unreachables: string
  var graph: string

  # Graph, mimics the code generation
  # Edges:
  # - Unreachables are in dotted grey
  # - "always" taken paths are bolded
  # - "interrupts" special paths are in outlined grey (interrupt event to true)
  # - "interrupts" normal paths are in normal solid black (interrupt event to false)
  # - "triggers" `true` paths are dashed black
  # - "triggers" `false` path are dotted black
  # - "default" paths are in black
  for state in A.states:
    if state == A.terminal:
      continue

    var prevNode: PrevNode = (state, pnState)

    # Interrupts
    for interrupt in A.interrupts.getOrDefault(state):
      let nodeID = state & "_" & interrupt
      graph.add indent & prevNode.id & " -> " & nodeID
      if prevNode.kind == pnState:
        graph.add "[style=bold, xlabel=\"always\"]"
      else:
        graph.add "[xlabel=\"normal flow\"]"
      graph.add EOL
      let newState = A.condTransitions[(state, interrupt)]
      graph.add indent & nodeID & " -> " & newState &
        " [color=\"coral\", fontcolor=\"coral\", xlabel=\"interrupted\"]" & EOL
      prevNode = (nodeID, pnInterrupt)

    # Conditional events
    for trigger in A.triggers.getOrDefault(state):
      let nodeID = state & "_" & trigger
      graph.add indent & prevNode.id & " -> " & nodeID
      if prevNode.kind == pnState:
        graph.add "[style=bold, xlabel=\"always\"]"
      elif prevNode.kind == pnInterrupt:
        graph.add "[xlabel=\"normal flow\"]"
      else:
        graph.add "[style=dotted, xlabel=\"false\"]"
      graph.add EOL
      let newState = A.condTransitions[(state, trigger)]
      graph.add indent & nodeID & " -> " & newState & " [style=dashed, xlabel=\"true\"]" & EOL
      prevNode = (nodeID, pnEvent)

    # Default transition
    let default = A.defaultTransitions.getOrDefault(state)
    if default != "":
      graph.add indent & prevNode.id & " -> " & default & " [xlabel=\"default\"]" & EOL
    else:
      let unreachID = state & "_unreachable"
      if unreachables == "":
        unreachables = indent & "node [shape = doubleoctagon, fontcolor=black, fillcolor=white]; "
      unreachables.add " " & unreachID
      graph.add indent & prevNode.id & " -> " & unreachID & " [style=dotted, color=grey, xlabel=\"unreachable\"]" & EOL

  if unreachables != "":
    result.add "\n" & unreachables & EOL
  result.add graph
  result.add '}'

macro toGraphviz*(automaton: untyped): untyped =
  ## Generates a stringified representation of the Finite-State Automaton
  ## in Graphviz .dot format
  ##
  ## Note: we make events/triggers first-class by giving them a node
  ##       instead of them being just a label on top of an arrow
  ##
  ## The tests of conditions for events/triggers reflect the code generation
  ##
  ## Note: A transition is defined as (State, Event) -> State
  ##       Events that are checked in multiple states are duplicated per state
  result = newLit automaton.graphVizReprImpl()
