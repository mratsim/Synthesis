# Synthesis
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../synthesis

# Welcome to Synthesis tutorial.
# This will go over the functionalities of Synthesis with
# an executable example.
#
# Important: ensure you use the exact same case for your states
#            SOlid and Solid, will be considered different.
#
# First of all, declare the States of your state machine and the
# events it will react to.

type Phase = enum
  ## States of your automaton.
  ## The terminal state does not need to be defined
  Solid
  Liquid
  Gas
  Plasma # Plasma is almost unused

type Event = enum
  ## Named events. They will be associated with a boolean expression.
  Over100
  Between0and100
  Below0
  OutOfWater

# Reminder: use the exact same case for your states and events

# Common configuration
# -------------------------------------------
# Then declare your automaton
# And setup its entry and exit.

# Create a "waterMachine" entry.
declareAutomaton(waterMachine, Phase, Event)

# Optionally setup the "prologue". Extra state goes there, the variables are visible by all.
setPrologue(waterMachine):
  echo "Welcome to the Steamy machine version 2000!\n"
  var temp: float64

# Mandatory initial state. This must be one of the valid state of the "Phase" enum.
setInitialState(waterMachine, Liquid)

# Terminal state is mandatory. It's a pseudo state and does not have to be part of the state enum.
setTerminalState(waterMachine, Exit)

# Optionally setup the "epilogue". Cleaning up what was setup in the prologue goes there.
setEpilogue(waterMachine):
  echo "Now I need some coffee."

# Events
# -------------------------------------------
# Events are named boolean expressions that will be reused
# to trigger state transitions.
#
# Events have visibility over the following variables:
# - The parameters of the synthesized state machine in our case it is `tempFeed`
#   ```
#   synthesize(waterMachine):
#     proc observeWater(tempFeed: var seq[float])
#   ```
# - The variables created in `setPrologue`
# - The variables created in `onEntry`. Keep in mind
#   that `onEntry` in state-specific and that
#   exceptional `interrupt` event do not trigger `onEntry`
#
# Event checks are directly inlined in the state machine.

implEvent(waterMachine, OutOfWater):
  tempFeed.len == 0

implEvent(waterMachine, Between0and100):
  0 < temp and temp < 100

implEvent(waterMachine, Below0):
  temp < 0

implEvent(waterMachine, Over100):
  100 < temp

# Reminder: use the exact same case for your states and events

# `onEntry` and `onExit` hooks
# -------------------------------------------
#
# `onEntry` and `onExit` are state-specific processing
# introduced:
# - before checking if an event happened for `onEntry`
# - after the transition function and before changing state for `onExit`
#
# They can accept an array of states
#
# `onEntry` and `onExit` have visibility over the following variables:
# - parameters of the synthesized automaton
# - variables created in `setPrologue`
#
# `onEntry` can defined state-local variables that will be visible for
# events or transitioons.
#
# `onEntry` and `onExit` are bypassed in case of an `interrupt` behaviour
#
# `onEntry` and `onExit` are directly inlined in the state machine.

onEntry(waterMachine, [Solid, Liquid, Gas]):
  let oldTemp = temp
  temp = tempFeed.pop()
  echo "Temperature: ", temp

# `behaviors`
# -------------------------------------------
#
# Behaviours describe the transitions between state in a declarative way.
#
# They all must have a `transition` section. Normal Nim code can be used
# there: function calls, if/then/else, even nested proc declarations.
# Use `discard` if there is no transition function to apply.
#
# Transitions are directly inlined in the state machine
#
# - `ini` takes an initial state or an array of those
# - `fin` takes a final state switched to after the transition is applied
# - `steady` is used for states that do not change unless an event is triggered.
#   This is equivalent to a ``while true`` loop.
# Either ini+fin or steady are required.
#
# Ini+fin behaviours can be conditional on an named `event`
# that should be implemented with `implEvent`.
# `implEvent` does not have to be called before the behavior,
# any order is acceptable.
#
# For special cases, you can use `interrupt` instead of `event` to
# model situations that require specific handling.
# `interrupt` are bypass `onEntry` and `onExit` hooks.
#
# Interrupts purpose is handling termination or broken assumptions like
# a container or a message queue being empty while onEntry and normal
# behaviours may assume that it is not empty in general.
#
# In case of conflicting conditions:
#
# - Interrupt behaviors are always resolved before normal event-based behaviour.
# - In the same class, behaviors are checked in their order of declaration.
#   If there is potential conflict, it is recommended to declare all behaviors
#   pertaining to a state in a single file to not depend on the order of imports.
# - Default behaviour (with no event, including steady) have no conditions and are
#   applied last.

# Termination condition. `Exit` was declared in setTerminalState.
behavior(waterMachine):
  ini: [Solid, Liquid, Gas, Plasma]
  fin: Exit
  interrupt: OutOfWater
  transition:
    echo "Running out of steam ..."

# Conditional state change, depending on temperature.
behavior(waterMachine):
  ini: Solid
  fin: Liquid
  event: Between0and100
  transition:
    assert 0 <= temp and temp <= 100
    echo "Ice is melting into Water.\n"

behavior(waterMachine):
  ini: Liquid
  fin: Gas
  event: Over100
  transition:
    assert temp >= 100
    echo "Water is vaporizing into Vapor.\n"

behavior(waterMachine):
  ini: Solid
  fin: Gas
  event: Over100
  transition:
    assert temp >= 100
    echo "Ice is sublimating into Vapor.\n"

behavior(waterMachine):
  ini: Gas
  fin: Solid
  event: Below0
  transition:
    assert temp <= 0
    echo "Vapor is depositing into Ice.\n"

behavior(waterMachine):
  ini: Gas
  fin: Liquid
  event: Between0and100
  transition:
    assert 0 <= temp and temp <= 100
    echo "Vapor is condensing into Water.\n"

behavior(waterMachine):
  ini: Liquid
  fin: Solid
  event: Below0
  transition:
    assert temp <= 0
    echo "Water is freezing into Ice.\n"

# Steady state, if no phase change was triggered, we stay in our current phase
behavior(waterMachine):
  steady: [Solid, Liquid, Gas]
  transition:
    # Note how we use the oldTemp that was declared in `onEntry`
    echo "Changing temperature from ", oldTemp, " to ", temp, " didn't change phase. How exciting!\n"

# `Synthesize`
# -------------------------------------------
#
# Synthesizing the automaton will transform the previous specification
# into a concrete procedure with a name, type and inputs of your choosing.
#
# Assertions are inserted to ensure the automaton
# stops if a state+event combination was not handled.
#
# You can pass "-d:debugSynthesis" to view the state machine generated
# at compile-time.
#
# The generated code can also be copy-pasted for debugging or for extension.
synthesize(waterMachine):
  proc observeWater(tempFeed: var seq[float])

# Dump in graphviz format ".dot"
# -------------------------------------------
const dotRepr = toGraphviz(waterMachine)
writeFile("water_phase_transitions.dot", dotRepr)

# Running the machine
# -------------------------------------------
import random, sequtils

echo "\n"
var obs = newSeqWith(20, rand(-50.0..150.0))
echo obs
echo "\n\n"
observeWater(obs)

# Output
# -------------------------------------------
# @[-3.460770047808822, 114.5693402308219, 16.66758940395412, 147.8992369379481, 38.74529893378966, -34.83679531473696, 68.73127270016445, -10.89306136942781, 55.17781700115015, 114.8825749296374, 86.88038583504948, 47.98729291960338, -40.94605405014646, 141.4807806383724, -19.78255259056119, -1.654260475969281, 37.0554825533913, 80.74588296425821, -7.707680239048244, 37.63170603752019]

# Welcome to the Steamy machine version 2000!
#
# Temperature: 37.63170603752019
# Changing temperature from 0.0 to 37.63170603752019 didn't change phase. How exciting!
#
# Temperature: -7.707680239048244
# Water is freezing into Ice.
#
# Temperature: 80.74588296425821
# Ice is melting into Water.
#
# Temperature: 37.0554825533913
# Changing temperature from 80.74588296425821 to 37.0554825533913 didn't change phase. How exciting!
#
# Temperature: -1.654260475969281
# Water is freezing into Ice.
#
# Temperature: -19.78255259056119
# Changing temperature from -1.654260475969281 to -19.78255259056119 didn't change phase. How exciting!
#
# Temperature: 141.4807806383724
# Ice is sublimating into Vapor.
#
# Temperature: -40.94605405014646
# Vapor is depositing into Ice.
#
# Temperature: 47.98729291960338
# Ice is melting into Water.
#
# Temperature: 86.88038583504948
# Changing temperature from 47.98729291960338 to 86.88038583504948 didn't change phase. How exciting!
#
# Temperature: 114.8825749296374
# Water is vaporizing into Vapor.
#
# Temperature: 55.17781700115015
# Vapor is condensing into Water.
#
# Temperature: -10.89306136942781
# Water is freezing into Ice.
#
# Temperature: 68.73127270016445
# Ice is melting into Water.
#
# Temperature: -34.83679531473696
# Water is freezing into Ice.
#
# Temperature: 38.74529893378966
# Ice is melting into Water.
#
# Temperature: 147.8992369379481
# Water is vaporizing into Vapor.
#
# Temperature: 16.66758940395412
# Vapor is condensing into Water.
#
# Temperature: 114.5693402308219
# Water is vaporizing into Vapor.
#
# Temperature: -3.460770047808822
# Vapor is depositing into Ice.
#
# Running out of steam ...
# Now I need some coffee.
