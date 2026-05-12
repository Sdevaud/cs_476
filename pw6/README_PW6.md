
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


### Performance Comparison (Averaged over 10 runs)
#### Grayscale with Custom Instruction (CI) and DMA
```text
CPU-Cycles : 2 553 500 
CPU-Stalls : 456 200 
CPU-Idles  : 1 070 500
```

#### Grayscale with Custom Instruction (CI) and without DMA
```text
CPU-Cycles : 8 173 000
CPU-Stalls : 6 447 000
CPU-Idles  : 3 518 000
```


#### Grayscale without Custom Instruction (CI) and without DMA
```text
CPU-Cycles : 29 020 000
CPU-Stalls : 17 511 000
CPU-Idles  : 16 401 000
```

These profiling results shows the impact of the DMA, which is able to achieve the same grayscale conversion using significantly fewer clock cycles. The DMA approach offloads data transfers from the CPU. As a result, the processor can focus exclusively on coordinating the grayscale conversion via the CI instead of handling memory transfers.

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

### Performance discussion

Though we don't make optimal use of our bus capacity, implementing the grayscale conversion directly into the streaming still achieves a significant performance improvement compared to the previous exercise. The resulting video feed is smoother and more responsive. 

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

### Performance discussion
This optimized version achieves the best performance among the three implementations. By making full use of the bus width, we can transfer more pixel data per cycle. Although the difference compared to the implementation in Ex. 2 is not dramatic, there still is an improvement in the smoothness and responsiveness of the video.


