# EULSUKDO Architecture

**A Dynamic Scheduling Implementation for Superscalar and Out-of-Order Execution**

[한국어(Main)](README.md)
**The translation used LLM. The author's main language is Korean.**

## What can I try in this repository?

I added two web apps to the current `gen/` scheduler. The [generator](gen/generator-app/README.md) lets you choose the structure and ISA definitions, then downloads the generated top, decoder, and RTL sources together as a ZIP. The [simulation visualizer](gen/sim_visualizer/README.md) reads a VCD and shows what each module actually did cycle by cycle. You can start with its included demo trace.

The long explanation below describes the architecture idea and some older experiments. For the current RTL and what I have verified, see [gen/VERIFICATION.md](gen/VERIFICATION.md).

## What is this?

This project aims to implement a processor architecture capable of:

* **Processing multiple instructions simultaneously**
* **Immediately executing instructions that are ready, regardless of original order**

In other words, it is a processor implementing both **superscalar execution** and **out-of-order execution**.

<u>**But it is still unfinished..**</u>

```Plain-text
Status notation
  v Completed (including verification)
  ? Not verified
  - Writing in progress
  x Not started

[Current Progress]
README
  v Background explanation
  - Overall diagram: current diagram does not reflect FCL and WBC
  v Description of each module
  x Comparison with other architectures
CODE-Memory and Position Splitter or FIFO Element
  v Memory
  v Position Splitter
  v FIFO
  v Multi_data i/o FIFO
  v Allocator
  v Allocator, Value Start 1
CODE-Architecture
  v Rv32I Decoder and IMM
  ? NEL
  v IST
  ? PRM
  ? RS
  v WBC
  v FCL
  x Top Module
```

---

## You’re making a processor? What even is that?

A processor is a **digital circuit that processes specific operations divided into instructions**.
CPUs and GPUs are the most famous examples.

When a processor handles instructions, it stores and processes values in dedicated spaces called **registers**.

A processor repeatedly reads from and writes to these registers to perform operations.
In practice, an instruction is essentially:

> *Reading registers and writing a new value into another register.*

So every instruction contains:

1. Which registers to read
2. How to process the read values
3. Which register to write the result into

By combining instructions, software can create complex behavior.
A properly ordered collection of instructions is what we call **software**.

So a processor executes software by **processing instructions in sequence**.

---

## Have architectures like this existed before? Especially the kind you're making?

Yes! In fact, the computer or smartphone you are using right now most likely uses them.

The structure that processes multiple instructions simultaneously is commonly known as **superscalar architecture**.

The method that executes instructions as soon as they are ready, regardless of order, is called **out-of-order execution**.

One of the most famous algorithms for implementing out-of-order execution is the **Tomasulo Algorithm**.

### Then why make this?

There are very few open-source processors implementing both superscalar execution and out-of-order execution.

After searching around, I found projects like [risc-v boom](https://github.com/riscv-boom/riscv-boom).

There simply are not many attempts like this.

And honestly...

**I just wanted to build a computer processor myself.**

So here we are.

---

## But you said processors execute instructions sequentially. Why not just make a processor that handles sequences properly?

As explained earlier, instructions basically:

> *Read registers and write new values into other registers.*

At that point, the processor must decide <u>how to use the read values</u>.

A common example is arithmetic operations.
But sometimes the processor also needs to fetch values from external devices or memory.

Take a calculator as an example:
you need to obtain two input values before performing the calculation.

~~Otherwise you cannot calculate what you want..~~

The problem is that fetching external data is **extremely slow from the processor’s perspective**.

### Wait, computers feel instant though?

Of course. Even a simple addition operation is billions of times faster than what humans can do mentally.

While a human presses a button, the processor is already sitting there, bored, waiting.

So instead of doing nothing while waiting, it would be better if the processor worked on something else.

Too emotional?
Let’s explain it mathematically.

Suppose a processor can perform 100 million operations per second, but must wait 2 seconds to fetch data from an external device.

That means the processor wastes enough time to execute **200 million instructions** while waiting.

~~That’s quite a lot, right?~~

So many techniques were researched to solve this issue.

Among them, I focused on:

* **Superscalar execution** — processing multiple instructions simultaneously
* **Out-of-order execution** — immediately executing instructions that are ready

And I wanted to apply the **Tomasulo Algorithm** to a processor implementation.

---

## Is there really that much waiting? Wouldn’t one or two stalls be manageable?

Yes... especially memory access.

Memory is relatively slow compared to the processor.

Even obtaining data requires:

* generating addresses,
* waiting for responses,
* and transferring data back.

To improve this, engineers increase:

* memory speed,
* bandwidth,
* and use cache structures.

(Bandwidth is different from speed.
If speed is water pressure, bandwidth is hose diameter.)

Modern chips also pack many processor cores into a single chip, which increases waiting even further.

There are solutions, of course:
you can heavily optimize software.

But that is not easy at all.

(And if the dataset itself is huge, optimization alone cannot fully solve it.)

By the way, many modern processors communicate with external devices through memory-mapped interfaces.

So from this point on, external device access will simply be explained as **memory access**.

---

## Why combine superscalar and out-of-order execution?

~~Because greed. The ambition of the developer who created the EULSUKDO Architecture...~~

If a processor can only perform one operation at a time, then one stalled instruction stops everything.

Especially when waiting for external data.

That is why I use a **superscalar architecture** capable of multiple simultaneous operations.

But there is another problem.

If following instructions depend on the stalled value, then parallel execution still becomes meaningless.

(Everything would still wait.)

So instead, the processor should execute instructions whose operands are already ready.

That reduces the overall execution time.

(It is like working on another task during a team project while waiting for someone else to finish their part.)

So:

* **Superscalar** is the structural design
* **Out-of-order execution** is the execution behavior

That is the idea behind this architecture.

---

## Tomasulo Algorithm?

Sounds like some huge complicated algorithm, right?

It is important, but the most important part to me is:

> **Internally changing the processor’s register system.**

The register structure defined by the Instruction Set Architecture (ISA) has:

* limited register count,
* and frequent register reuse.

Software constantly overwrites the same architectural registers.

So the Tomasulo Algorithm introduces an **internal register system** with more register identifiers.

The processor operates using these expanded internal register numbers instead.

Another important concept I borrowed is:

> **Using instruction states as a core architectural mechanism.**

---

# So what exactly did you build?

The **EULSUKDO Architecture** is a processor project implementing:

* **superscalar execution**
* and **out-of-order execution**

during instruction processing.

To achieve this, I implemented a **dynamic scheduling structure** using:

* **register renaming**
* based on concepts from the Tomasulo Algorithm.

In particular, I attempted to implement this design **without using CAM structures**, in order to reduce power consumption.

The architecture changes the register system internally to eliminate conflicts caused by overlapping architectural register names.

---

# Then what does your structure look like?

The architecture can be divided into four major areas:

1. Decoding new instructions and converting them into the new register system
2. Tracking instruction states and dispatching ready instructions
3. Tracking which instructions use each physical register and updating states
4. Releasing registers that are no longer needed after instruction completion

To implement this, I divided the processor into six modules:

* New Entry Logic
* Instruction State Table
* Physical Register Mapper
* Ready Station
* Write Back Concatenation
* Flow Control Logic

Let’s go through them.

---

## Overall Structure

**Wait! This diagram is an older version that does not properly include Write Back Concatenation and Flow Control Logic! I’ll update it soon.**

![Diagram](Diagram.png)

---

## New Entry Logic (NEL)

**This module decodes incoming instructions and converts them into the new register system.**

This module connects to:

* *Instruction Memory*
* **Instruction State Table**
* **Physical Register Mapper**
* **Write Back Concatenation**
* **Flow Control Logic**

```Plain-text
Instruction Memory
[Receives]
 - New instructions

Instruction State Table
[Sends]
 - Internally converted instructions with renamed registers

Physical Register Mapper
[Receives]
 - Available physical register numbers

Write Back Concatenation
[Receives]
 - Completed register numbers

Flow Control Logic
[Sends]
 - Jump/branch instruction information
 - Previous register numbers overwritten by new mappings
```

Internally, this module contains a **Register File** that stores:

* mappings between architectural registers and physical registers
* readiness states

---

## Instruction State Table (IST)

**Tracks instruction states, updates them when necessary, and notifies when instructions are ready for execution.**

This module connects to:

* **New Entry Logic**
* **Physical Register Mapper**
* **Ready Station**

```Plain-text
New Entry Logic
[Receives]
 - Internally converted instructions with renamed registers

Physical Register Mapper
[Sends]
 - Required physical register numbers and IST indices
[Receives]
 - IST indices and updated register information

Ready Station
[Sends]
 - Ready instructions
```

Internally, it contains:

* a **Register File** storing instructions and states
* an **allocator** for assigning entries

---

## Physical Register Mapper (PRM)

**Tracks which instructions use each physical register.**

This module connects to:

* **New Entry Logic**
* **Instruction State Table**
* **Write Back Concatenation**
* **Flow Control Logic**

```Plain-text
New Entry Logic
[Sends]
 - Available physical register numbers

Instruction State Table
[Receives]
 - Physical register numbers and IST indices
[Sends]
 - Updated IST indices and register information

Write Back Concatenation
[Receives]
 - Completed register numbers

Flow Control Logic
[Receives]
 - Registers that are no longer needed
```

Internally, this module contains:

* a **Register File** storing IST addresses and usage counts for each physical register
* an **allocator_start_one**
  (because physical register 0 will always contain constant zero)

---

## Ready Station (RS)

**Dispatches ready instructions to execution and memory-access units.**

This module connects to:

* **Instruction State Table**
* *Execution Units*

```Plain-text
Instruction State Table
[Receives]
 - Ready instructions

Execution Units
[Sends]
 - Ready instructions waiting for execution
```

Internally, it contains a **FIFO** storing instructions waiting for execution.

---

## Write Back Concatenation (WBC)

**Transfers information from completed instructions.**

This module connects to:

* *Execution Units*
* **Physical Register Mapper**
* **New Entry Logic**
* **Flow Control Logic**

```Plain-text
Execution Units
[Receives]
 - Completed instruction PC addresses
 - Register numbers
 - Partial results
   (For branches: new fetch PC)

Physical Register Mapper
[Sends]
 - Completed register numbers

New Entry Logic
[Sends]
 - Completed register numbers

Flow Control Logic
[Sends]
 - Completed instruction addresses
```

This module gathers register numbers from execution outputs and forwards them externally.

Specialized execution units such as branch units may also provide additional values separately.

---

## Flow Control Logic (FCL)

**Tracks instruction order and completed instructions to release unused registers.**

This module connects to:

* **New Entry Logic**
* **Physical Register Mapper**
* **Write Back Concatenation**
* *Instruction Memory*

```Plain-text
New Entry Logic
[Receives]
 - Jump/branch instruction information
 - Previous overwritten register numbers

Physical Register Mapper
[Sends]
 - Registers that are no longer needed

Write Back Concatenation
[Receives]
 - Completed instruction addresses

Instruction Memory
[Sends]
 - New instruction fetch PC
```

Internally, it contains several structures for register reclamation.

Specifically:

* registers storing PC start/end values,
* counters tracking completed instructions within the range,
* and FIFOs storing overwritten register numbers.

When all instructions within a PC range complete,
the stored register numbers are returned to the PRM allocator.

Then the range is reset for reuse.

Since PC ranges can become large,
the architecture limits the maximum range size to:

> half the number of physical registers

(for example, 32 instructions if 64 physical registers exist).

---

# Some modules look unusual: position_splitter? fifo_ordering_position? allocator?

While implementing this processor, I created a hardware sorting structure called **position_splitter**.

Using it, I implemented:

* a variable multi-input/output FIFO
* and a hardware allocator/deallocator system.

Those became:

* `fifo_ordering_position`
* `allocator`

---

## position_splitter

This module gathers up to `n` unordered inputs toward the LSB direction.

Inputs:

* up to `n` data entries
* `n`-bit valid signal

Outputs:

* LSB-aligned ordered data
* output valid bits

---

## fifo_ordering_position

This module is a **FIFO Memory** that:

* stores up to `m` unordered inputs
* outputs `n` ordered entries aligned toward the LSB side

Inputs:

* up to `m` data entries
* `m`-bit valid signal

Outputs:

* up to `n` ordered entries
* `n`-bit valid signal

To dequeue data,
a `get` signal specifies which entries are consumed.

In the next cycle:

* remaining entries are reordered,
* and stored entries move forward automatically.

---

## allocator / allocator_start_one

These modules are hardware number allocators/deallocators.

They can:

* allocate up to `n` numbers
* return up to `m` numbers simultaneously

Inputs:

* returned numbers
* valid bits

Outputs:

* allocatable numbers aligned toward the LSB side
* valid bits

To allocate numbers,
the user sends a `get` signal indicating which entries to consume.

`allocator` starts from 0.

`allocator_start_one` starts from 1.

---

# How should I browse this repository?

You should take a look at the Verilog RTL code I worked hard on.

To organize everything, I structured the directories like this:

```Plain-text
RTL/ : Verilog RTL source code
    RTL/1decode3issue : Decodes up to one instruction at a time,
                        while supporting three simultaneous operations:
                        arithmetic/logic, memory access, and branch handling.
                        This directory contains that implementation.

TB/  : Testbench files for verifying RTL modules
```

---

## Wait a second!

This project currently implements the **RISC-V RV32I instruction set**.

So all explanations below are based on RV32I.

<u>**But it is still unfinished..**</u>

---

# Why is it called EULSUKDO?

I was born in Busan and grew up in Gimhae, so Eulsukdo feels familiar to me.

Eulsukdo is an island located in Gangseo-gu, Busan, near Hadan.

It’s beautiful.

You should visit someday.

Also, I highly recommend the nearby duck restaurants.

Absolutely delicious.
