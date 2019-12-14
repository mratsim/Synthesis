# Synthesis

This is a support library for the [Weave](https://github.com/mratsim/weave) multithreading runtime

This contains support macros to synthesize static automata from
a declarative description of states, triggers and transitions
with all states, triggers and transitions known at compile-time.

## Technical constraints

The state machine is used as the core of a multithreading runtime:
- Must be thread-safe
- No heap allocation
- Easy to map to model checking and formal verification via clearly labeled: states, events, transitions.

  Multithreading is complex and the more we can prove properties (like the absence of deadlocks or livelocks)
  the more confidence we can have in the runtime.
- Extremely fast and very low-overhead, as overhead in the state machine means more latency in scheduling work. Furthermore, slowness effects are "scaled" by the number of cores.

- Extensibility: as runtime requirements grow (distributed clusters, heterogeneous computing, fine-grained barriers, IO, continuations, cancellations,...),

  Synthesis should help minimizing the potential for entangled control-flow
  and missing edge-cases.

Synthesis generates an automaton using gotos for transitions:
  - This avoids function calls/returns pushing/poping stack overhead
  - and switch dispatch branch prediction miss due to having a single point of dispatch..

## References
- [Mealy State Machine](https://en.wikipedia.org/wiki/Mealy_machine)
- [Pushdown Automaton](https://en.wikipedia.org/wiki/Pushdown_automaton)
- [Communicating Finite State Machines](https://en.wikipedia.org/wiki/Communicating_finite-state_machine)
- [Petri Nets](https://en.wikipedia.org/wiki/Petri_net)
- [Kahn Process Networks](https://en.wikipedia.org/wiki/Kahn_process_networks)

Extras
- [Overview/Slides from Marquette Embedded SystemS Laboratory](https://www.dejazzer.com/ece777/ECE777_3_system_modeling.pptx)
- [Berkeley's Ptolemy project](https://ptolemy.berkeley.edu/index.htm)
