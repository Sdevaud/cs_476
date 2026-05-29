#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>
#include <stdbool.h>

// #define __profiling__

const uint16_t largeur = 640;
const uint16_t hauteur = 480;

#define WRITE_OPERATION (1 << 9)
#define BUS_START (1 << 10)
#define MEMORY_START (2 << 10)
#define BLOCK_SIZE (3 << 10)
#define BURST_SIZE (4 << 10)
#define STATUS_CTRL (5 << 10)
#define USED_BLOCK_SIZE 128
#define USED_BURST_SIZE 31

const uint32_t sizeDMA = 2 * 1024; // 2 kB
const uint8_t nbrPixelPerPass = 4;
const uint8_t nbrBuffer = 4;
const uint32_t unitaryBuffer = sizeDMA / (nbrPixelPerPass * nbrBuffer); // 128

const uint16_t green = 0x07E0;
const uint16_t black = 0x0000;
const uint16_t white = 0xFFFF;

const uint32_t delayRefresh = 10;

void write_DMA(const uint32_t address, const uint32_t data)
{ // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2] "r"(data));
}

void read_DMA(const uint32_t address, volatile uint32_t *data)
{
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" : [out1] "=r"(*data) : [in1] "r"(address));
}

void wait_DMA()
{
  uint32_t data;
  do
  {
    read_DMA(STATUS_CTRL, &data);
  } while (data & 1); // wait until the busy bit is zero
}

bool movement_screen(const volatile uint32_t *pixelActualFrame, const volatile uint32_t *pixelPreviousFrame)
{
  uint32_t move = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],40" : [out1] "=r"(move) : [in1] "r"(*pixelActualFrame), [in2] "r"(*pixelPreviousFrame));
  printf("move : %u\n", move);
  return move == 10;
}

void profiling(const uint32_t input, volatile uint32_t *output)
{
  asm volatile("l.nios_rrr %[out1],r0,%[in2],12" : [out1] "=r"(*output) : [in2] "r"(input));
}

void reset_profiling()
{
  asm volatile("l.nios_rrr r0,r0,%[in2],12" ::[in2] "r"(7));
}

void init_black_screen(volatile uint8_t blackScreen[])
{
  for (size_t i = 0; i < hauteur; ++i) {
    for (size_t j = 0; j < largeur; ++j) {
      blackScreen[i * largeur + j] = (uint8_t)black;
    }
  }
}

void swap_buffer(uint32_t *buffer1, uint32_t *buffer2)
{
  uint32_t transition = 0;
  transition = *buffer1;
  *buffer1 = *buffer2;
  *buffer2 = transition;
}


volatile uint8_t actualSobelTab[640 * 480];
volatile uint8_t previousSobelTab[640 * 480];
volatile uint8_t blackScreen[640 * 480];

int main()
{
  // const uint8_t sevenSeg[10] = {0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F};
  
  volatile uint8_t* previousSobel = previousSobelTab;
  volatile uint8_t* actualSobel = actualSobelTab;
  bool frameMovement = false;
  bool stopOuterLoop = false;
  bool firstDifferent = false;
  bool twoDifferentInARow = false;
  bool threeDifferentInARow = false;

  
  volatile uint32_t result, cycles, stall, idle;
  volatile uint32_t timeCounter = 0;
  volatile unsigned int *vga = (unsigned int *)0X50000020;
  volatile unsigned int *gpio = (unsigned int *)0x40000000;
  camParameters camParams;
  vga_clear();

  printf("Initialising camera (this takes up to 3 seconds)!\n");
  camParams = initOv7670(VGA);
  printf("Done!\n");
  printf("NrOfPixels : %d\n", camParams.nrOfPixelsPerLine);
  result = (camParams.nrOfPixelsPerLine <= 320) ? camParams.nrOfPixelsPerLine | 0x80000000 : camParams.nrOfPixelsPerLine;
  vga[0] = swap_u32(result);
  printf("NrOfLines  : %d\n", camParams.nrOfLinesPerImage);
  result = (camParams.nrOfLinesPerImage <= 240) ? camParams.nrOfLinesPerImage | 0x80000000 : camParams.nrOfLinesPerImage;
  vga[1] = swap_u32(result);
  printf("PCLK (kHz) : %d\n", camParams.pixelClockInkHz);
  printf("FPS        : %d\n", camParams.framesPerSecond);
  vga[2] = swap_u32(2);
  init_black_screen(blackScreen);
  vga[3] = swap_u32((uint32_t) blackScreen);

  /* set up the generic dma parameters */
  write_DMA(BLOCK_SIZE, USED_BLOCK_SIZE);
  write_DMA(BURST_SIZE, USED_BURST_SIZE);

  takeSingleImageBlocking((uint32_t) previousSobel);

  while (1) {

    takeSingleImageBlocking((uint32_t) actualSobel);

    uint32_t previousBuffer1 = unitaryBuffer * 0;
    uint32_t previousBuffer2 = unitaryBuffer * 1;
    uint32_t actualBuffer1 = unitaryBuffer * 2;
    uint32_t actualBuffer2 = unitaryBuffer * 3;

    uint32_t previousPixel = 0;
    uint32_t actualPixel = 0;

    uint32_t previousPtr = (uint32_t) previousSobel;
    uint32_t actualPtr = (uint32_t) actualSobel;

    reset_profiling();

    if (frameMovement) {
      printf("timeCounter : %u \n", timeCounter);
      ++timeCounter;
      if (timeCounter > delayRefresh) {
        printf("frameMovement : %d\n", frameMovement);
        frameMovement = false;
        timeCounter = 0;
        vga[3] = swap_u32((uint32_t) blackScreen);
      }
    }

#ifdef __profiling__
    reset_profiling();
#endif

    /* INIT DMA for first pass */
    write_DMA(BUS_START, previousPtr);
    write_DMA(MEMORY_START, previousBuffer1);
    write_DMA(STATUS_CTRL, 1);
    wait_DMA();
    swap_buffer(&previousBuffer1, &previousBuffer2);
    previousPtr += USED_BLOCK_SIZE * sizeof(uint32_t);

    write_DMA(BUS_START, actualPtr);
    write_DMA(MEMORY_START, actualBuffer1);
    write_DMA(STATUS_CTRL, 1);
    wait_DMA();
    swap_buffer(&actualBuffer1, &actualBuffer2);
    actualPtr += USED_BLOCK_SIZE * sizeof(uint32_t);

    for (uint32_t loop = 0; loop < 600; ++loop) {

      /* Perform DMA in */
      if (loop < 599) {
        write_DMA(BUS_START, previousPtr);
        write_DMA(MEMORY_START, previousBuffer1);
        write_DMA(STATUS_CTRL, 1);
        wait_DMA();

        write_DMA(BUS_START, actualPtr);
        write_DMA(MEMORY_START, actualBuffer1);
        write_DMA(STATUS_CTRL, 1);
      }

      for (size_t pixel = 0; pixel < USED_BLOCK_SIZE; ++pixel) {
        read_DMA(previousBuffer2 + pixel, &previousPixel);
        read_DMA(actualBuffer2 + pixel, &actualPixel);

        if (actualPixel != previousPixel) {
          frameMovement = true;
          vga[3] = swap_u32((uint32_t) actualSobel);
          timeCounter = 0;
          stopOuterLoop = true;
          break;
        }
      }
      wait_DMA();
      if (stopOuterLoop) {
        stopOuterLoop = false;
        break;
      }

      swap_buffer(&previousBuffer1, &previousBuffer2);
      swap_buffer(&actualBuffer1, &actualBuffer2);
      previousPtr += USED_BLOCK_SIZE * sizeof(uint32_t);
      actualPtr += USED_BLOCK_SIZE * sizeof(uint32_t);
    }

    previousSobel = actualSobel;

#ifdef __profiling__
    profiling((1 << 8 | 7 << 4), &cycles);
    profiling((1 << 9), &stall);
    profiling((1 << 10), &idle);
#endif

  } // end while(1)
} // end main