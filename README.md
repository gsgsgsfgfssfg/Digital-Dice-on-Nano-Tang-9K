# Digital Dice — FPGA

A simple digital dice implemented in **Verilog HDL** for the **Tang Nano 9K FPGA**.

This project also includes a short YouTube video demonstrating the digital dice in action:

[Watch the Digital Dice demonstration on YouTube](https://youtu.be/NOxrzV2kcZY?si=3BTmFtMJSMYQi6Wj)

The video shows the rolling process, button interaction, and LED output on the Tang Nano 9K.

The project uses a **3-bit pseudo-random generator** to continuously generate dice states while the Roll button is held. Releasing the button captures the current state and displays a value from **1 to 6** by lighting the corresponding number of horizontally arranged LEDs.

## Hardware

* **FPGA:** Tang Nano 9K
* **Clock:** 27 MHz
* **Buttons:** 2 × active-low push buttons
* **LEDs:** 6 × onboard LEDs arranged horizontally and driven as active-low

### Inputs

| Signal        | Description              |
| ------------- | ------------------------ |
| `clk_27m`     | 27 MHz system clock      |
| `btn_roll_n`  | Roll button, active-low  |
| `btn_reset_n` | Reset button, active-low |

### Output

| Signal     | Description                                        |
| ---------- | -------------------------------------------------- |
| `led[5:0]` | Six active-low LEDs used to display the dice value |

---

## Functionality

### Reset

When the Reset button is pressed:

```text
Dice = 1
```

One LED is turned on by driving its output low. The remaining LEDs are driven high.

### Rolling

When the Roll button is pressed and held:

```text
IDLE
  ↓
ROLLING
  ↓
Pseudo-random generator continuously updates
```

The displayed dice result is not changed until the Roll button is released.

### Capture

When the Roll button is released:

```text
ROLLING
    ↓
Capture current generator state
    ↓
Convert to dice value
    ↓
Display 1–6 LEDs
```

The result remains displayed until the next roll or reset.

---

## Pseudo-Random Generator

The design uses a 3-bit pseudo-random generator.

The six valid states correspond directly to dice values:

| Generator State | Dice Value |
| --------------- | ---------: |
| `001`           |          1 |
| `010`           |          2 |
| `011`           |          3 |
| `100`           |          4 |
| `101`           |          5 |
| `110`           |          6 |

The `111` state is treated as invalid and is skipped.

This provides exactly six usable dice states without requiring modulo arithmetic.

---

## FSM

The main controller uses three states:

```text
       Roll Press
IDLE ─────────────► ROLLING
 ▲                    │
 │                    │ Roll Release
 │                    ▼
 └──────────────── DISPLAY
```

### IDLE

* Wait for the Roll button.
* Hold the current dice result.
* LFSR is not updated.

### ROLLING

* Update the pseudo-random generator continuously.
* Wait for the Roll button to be released.

### DISPLAY

* Hold the captured dice result.
* Wait for the next Roll operation.

---

## Button Handling

The buttons are active-low:

```text
0 → Pressed
1 → Released
```

The design handles button inputs using:

1. Two-flip-flop synchronization.
2. Debouncing.
3. Clean press/release detection.

The raw asynchronous button signals are not used directly by the main FSM.

---

## Clocking

The entire design uses the **27 MHz system clock**.

No additional clock is generated.

Instead, a clock-enable signal is used to control the update rate of the pseudo-random generator:

```text
27 MHz System Clock
        │
        ├── Button Synchronization
        ├── Debouncing
        ├── FSM
        │
        └── Clock Enable
                │
                ▼
          Random Generator
```

---

## LED Dice Display

Because of the physical layout of the Tang Nano 9K board, the six LEDs are arranged in a single horizontal row:

```text
LED0   LED1   LED2   LED3   LED4   LED5
```

All LEDs are **active-low**:

```text
0 → LED on
1 → LED off
```

The number of LEDs that are turned on directly represents the dice value. Therefore, the display does not reproduce the traditional dot pattern of a dice face. Instead, it lights the first `N` LEDs from left to right, where `N` is the current dice value.

Example:

```text
1:

●
```

```text
2:

●   ●
```

```text
3:

●   ●   ●
```

```text
4:

●   ●   ●   ●
```

```text
5:

●   ●   ●   ●   ●
```

```text
6:

●   ●   ●   ●   ●   ●
```

The decoder maps each dice value to the corresponding number of active-low LEDs:

| Dice Value | LED Pattern (`led[5:0]`) |
| ---------: | ------------------------ |
|          1 | `111110`                 |
|          2 | `111100`                 |
|          3 | `111000`                 |
|          4 | `110000`                 |
|          5 | `100000`                 |
|          6 | `000000`                 |

The patterns assume that `led[0]` corresponds to the leftmost LED and that each LED is active-low. If the physical LED order is reversed, the bit order can be adjusted in the decoder module while preserving active-low polarity.

---

## Project Structure

```text
digital-dice/
│
├── README.md
│
├── digitaldice.v
│   ├── top
│   ├── button_sync
│   ├── button_debounce
│   ├── clock_enable
│   ├── dice_controller
│   ├── lfsr_3bit
│   └── dice_decoder
│
└── digital_dice.cst
```

---

## Design Flow

The intended FPGA development flow is:

```text
Verilog RTL
    ↓
Simulation
    ↓
Synthesis
    ↓
Place & Route
    ↓
Bitstream Generation
    ↓
Tang Nano 9K
    ↓
Physical Testing
```

The testbench should verify:

* Reset behavior.
* Button synchronization/debouncing.
* Roll state.
* Continuous pseudo-random generation while rolling.
* Result capture when Roll is released.
* Correct mapping of states to dice values.
* Correct active-low LED patterns for each dice value.
* Reset after previous rolls.

---

## Tools

The project can be developed using an open-source FPGA toolchain such as:

* OSS CAD Suite
* Yosys
* nextpnr
* Gowin FPGA toolchain/programmer as required by the Tang Nano 9K workflow

---

## Design Goals

The project is intentionally small and focuses on fundamental FPGA design concepts:

* Synchronous RTL design
* Finite State Machines
* Button synchronization
* Button debouncing
* Clock enable generation
* Pseudo-random number generation
* Combinational decoding
* FPGA hardware verification

The design avoids unnecessary complexity while providing a complete input → processing → output FPGA system.
