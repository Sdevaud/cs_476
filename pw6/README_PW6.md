
# Embedded System Design – PW6

## Group 23

- Sébastien Devaud (315144)
- Till Beyer (414801)


## Exercise 1 – Grayscale Conversion Using DMA

**Source file:**

```text
/pw6/virtualprototype/programs/grayscale_dma/src/grayscale_dma.c
```
This file contains `grayscale_dma.c`, which implements the grayscale conversion using a DMA-based solution.

You must also modify the following file:

```text
/pw6/virtualprototype/systems/singleCore/scripts/yosysOr1420.script
```

At the end of the file:

1. Comment out all paths located between the `### ###` markers.
2. Uncomment the following line:

```text
read -sv ../../../modules/camera/verilog/camera.v
```

Run the following commands:

```bash
cd systems/singleCore/sandbox
../scripts/synthesizeOr1420.sh
```


### Performance Comparison
#### Grayscale with Custom Instruction (CI) and DMA

```text
CPU-Cycles : 3 021 176 
CPU-Stalls : 458 948 
CPU-Idles  : 1 440 572
```

#### Grayscale with Custom Instruction (CI) and without DMA

```text
CPU-Cycles : 29 129 333
CPU-Stalls : 17 756 326
CPU-Idles  : 16 754 135
```

#### Grayscale without Custom Instruction (CI) and without DMA

```text
CPU-Cycles : 8 204 047
CPU-Stalls : 6 668 095
CPU-Idles  : 3 602 631
```

These results show the impact of the DMA, which offloads data transfers from the CPU. As a result, the processor can focus exclusively on grayscale conversion computations instead of handling memory transfers.

---

## Exercise 2 – Grayscale Conversion in the Camera Module

**Source file:**

```text
/pw6/virtualprototype/modules/camera/verilog/camera_simple.v
```

### Required Modifications

You must also modify the following file:

```text
/pw6/virtualprototype/systems/singleCore/scripts/yosysOr1420.script
```

At the end of the file:

1. Comment out all paths located between the `### ###` markers.
2. Uncomment the following line:

```text
read -sv ../../../modules/camera/verilog/camera_simple.v
```

Run the following commands:

```bash
cd systems/singleCore/sandbox
../scripts/synthesizeOr1420.sh
```

you also need to go in the file : 
```bash
/programs/streaming/src/streaming.c
```

and UNCOMMENT :
```bash
"#define __RGB565__"
```

and make again in straming folder

### Description

This version converts the pixel data received from the camera directly into grayscale, but it does not use the full width of the available bus.

---

## Exercise 3 – Optimized Grayscale Conversion

**Source file:**

```text
/pw6/virtualprototype/modules/camera/verilog/camera_optimised.v
```

### Required Modifications

You must also modify the following file:

```text
/pw6/virtualprototype/systems/singleCore/scripts/yosysOr1420.script
```

At the end of the file:

1. Comment out all paths located between the `### ###` markers.
2. Uncomment the following line:

```text
read -sv ../../../modules/camera/verilog/camera_optimised.v
```

Run the following commands:

```bash
cd systems/singleCore/sandbox
../scripts/synthesizeOr1420.sh
```

you also need to go in the file : 
```bash
/programs/streaming/src/streaming.c
```

and COMMENT :
```bash
"#define __RGB565__"
```

and make again in straming folder

### Description

This version also converts the camera pixel data directly into grayscale, but it uses a 32-bit bus to improve data throughput.


