# Synthesis

This is a support library for the [Weave](https://github.com/mratsim/weave) multithreading runtime

The runtime is modelized as Finite-State-Machine communicating over channels.

Each worker owns the following channels:
- N Channels for receiving tasks, N = WV_MaxConcurrentStealPerWorker (Single-Producer Single-Consumer)
- 1 Channel for receiving steal requests (Multi-Producer Single-Consumer)

Each worker can send messages to the following channels
- Their peers steal request channels.
- A task channel included in a steal request.

This contains support macros to synthesize static automata from
a declarative description of states, triggers and transitions
with all states, triggers and transitions known at compile-time.

## Technical constraints

The state machine is used as the core of a multithreading runtime:
- the state machine should be thread-safe
- no heap allocation
- easy to map to model checking and formal verification via clearly labeled: states, inputs, transitions
  Multithreading is complex and the more we can prove properties (like the absence of deadlocks or livelocks)
  the more confidence we can have in the runtime.
- low-overhead, more overhead in the state machine means more latency in scheduling work.
  In particular:
  - function calls should not lead to a stack overflow due to nested state transitions
  - dispatching should be as predictable as possible by the hardware prefetcher.
    (Switch dispatch with a single point of dispatch often means automatic branch prediction miss)
- extensibility: as runtime requirements grow (distributed clusters, heterogeneous computing, fine-grained dependencies barriers)
  Synthesis should help minimizing the potential for entangled control-flow
  and missing edge-cases.

==> A set of macros will generate an automaton using gotos for transitions which avoids function calls and switch dispatch.

## References
- [Mealy State Machine](https://en.wikipedia.org/wiki/Mealy_machine)
- [Pushdown Automaton](https://en.wikipedia.org/wiki/Pushdown_automaton)
- [Communicating Finite State Machines](https://en.wikipedia.org/wiki/Communicating_finite-state_machine)
- [Petri Nets](https://en.wikipedia.org/wiki/Petri_net)
- [Kahn Process Networks](https://en.wikipedia.org/wiki/Kahn_process_networks)

- [Slides from Marquette Embedded SystemS Laboratory](www.dejazzer.com/ece777/ECE777_3_system_modeling.pptx)
- [Berkeley's Ptolemy project](https://ptolemy.berkeley.edu/index.htm)
