# EULSUKDO gen3

`gen3` is a parameterized SystemVerilog implementation of the EULSUKDO dynamic
scheduler described in `docs/structure`.  It is independent of `gen` and `gen2`.
The decoder, physical register value file, execution units, instruction memory,
and exception handler remain integration boundaries; the scheduling architecture
itself is implemented here.

## Implemented blocks

- `eulsukdo_new_entry_logic`: architectural-to-physical rename map, physical
  register readiness, same-bundle rename forwarding, and control/retirement
  metadata generation.
- `eulsukdo_instruction_state_table`: instruction allocation, per-operand ready
  state, PRM dependency registration, wakeup, and ready-instruction selection.
- `eulsukdo_physical_register_mapper`: physical-register allocator and the
  physical-register-to-IST dependency queues used instead of an operand CAM.
- `eulsukdo_ready_station`: one parameterized FIFO per execution path, with a
  configurable number of issue ports per path.
- `eulsukdo_write_back_concatenation`: combinational extraction and broadcast of
  completed PC/flow/physical-register metadata.
- `eulsukdo_flow_control_logic`: PC/flow generation, non-speculative branch
  serialization, completion tracking, in-order retirement, and old physical
  register reclamation.
- `eulsukdo_gen3`: top-level composition.

Physical register zero is permanently allocated and ready.  Decode lanes form
one atomic bundle: all valid, non-exception lanes transfer together or all wait.
This preserves program order and makes same-cycle rename dependencies explicit.
When a bundle contains a control instruction, lanes after the first control are
consumed and discarded; fetching resumes at the selected target with a new flow.

## Packed interface formats

All packed records are repeated per lane/port.  Within one record, fields below
are listed from least-significant to most-significant bit.

| Interface | Record fields (LSB to MSB) |
|---|---|
| `o_fetch_data` | PC, flow |
| `o_issue_data` | PC, flow, micro-op, immediate, destination physical register, source physical registers |
| `i_result_data` | PC, flow, destination physical register |
| `i_branch_data` | branch PC, branch flow, taken, target PC |

Decoded fields use separate packed buses. Lane `n` always occupies
`[n*FIELD_WIDTH +: FIELD_WIDTH]`. Source operand `m` of lane `n` occupies
`[(n*OPERANDS+m)*LOG_REG_WIDTH +: LOG_REG_WIDTH]`.

The execution result carries scheduling metadata only. Register values belong to
the external physical register file/writeback network and can be widened or
routed independently without changing this scheduler.

A branch execution unit must assert its normal `i_result_valid` lane (so the ROB
can retire the instruction) and its `i_branch_valid` lane (so fetch can resume).

## Main parameters

The top level parameterizes ISA widths, decode width, IST/ROB/physical-register
sizes, operand count, dependency depth, wake/free/result ports, RS depth, and the
execution topology. `ISSUE_PORTS` must equal the sum of `ISSUE_PER_PATH`.

When changing `EX_PATHS`, override `ISSUE_PER_PATH` with an array of the same
length, for example:

```systemverilog
eulsukdo_gen3 #(
    .DECODE_WIDTH(1),
    .EX_PATHS(2),
    .ISSUE_PORTS(2),
    .ISSUE_PER_PATH({8'd1, 8'd1})
) scheduler (...);
```

## Verilator checks

Run from this directory:

```sh
make lint
make lint-parameters
make test
make test-wave
```

`lint-parameters` elaborates both the default topology and a smaller, differently
shaped topology. The lint flags suppress style-only warnings caused by portable
loop-based multi-port RTL; syntax, width-selection, connectivity, combinational
loop, and latch diagnostics remain enabled.

`make test` runs a self-checking ordered-behavior scenario. It verifies same-bundle
RAW renaming, independent out-of-order issue, selective dependency wakeup, renamed
physical-register addresses, control-lane truncation, branch fetch blocking, and
redirect to the next flow. Any mismatch terminates the simulation with `$fatal`.
`make test-wave` runs the same checks and also writes `eulsukdo_sequence.vcd`.

For the parameterized retire-IPC sweep and interpretation, see
[IPC_ANALYSIS.md](IPC_ANALYSIS.md). Reproduce all configurations with:

```sh
make ipc-sweep
```

For a self-contained Korean prompt that can be pasted into another LLM for
architecture, PPA, compiler, or benchmark review, see
[LLM_BENCHMARK_PROMPT.md](LLM_BENCHMARK_PROMPT.md).


## Deliberate integration limits

- Branch prediction and speculative squash are not implemented. Conditional and
  register-indirect controls pause new fetch requests until their result arrives.
- A decoded exception is consumed but not inserted into the scheduler. Connect an
  exception controller at the decoder boundary for architectural trap behavior.
- Memory ordering, load/store forwarding, and cache behavior are outside the
  scheduler, matching the scope stated by the project documentation.
