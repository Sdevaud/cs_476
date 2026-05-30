#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>
#include <stdbool.h>

#define __profiling__

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

const uint32_t setThreshold = 0xFF << 24;

const uint32_t delayRefresh = 50;

void write_DMA(const uint32_t address, const uint32_t data)
{ // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2] "r"(data));
}

uint32_t read_DMA(const uint32_t address)
{
  uint32_t data = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" : [out1] "=r"(data) : [in1] "r"(address));
  return data;
}

void wait_DMA()
{
  uint32_t data = 0;
  do
  {
    data = read_DMA(STATUS_CTRL);
  } while (data & 1); // wait until the busy bit is zero
}

uint32_t complementary(uint32_t pixelActualFrame, uint32_t pixelPreviousFrame)
{
  uint32_t move = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],40" : [out1] "=r"(move) : [in1] "r"(pixelActualFrame), [in2] "r"(pixelPreviousFrame));
  return move;
}

uint32_t white_counter(const volatile uint32_t *pixelActualFrame) {
  uint32_t whitePixel = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],r0,41" : [out1] "=r"(whitePixel) : [in1] "r"(*pixelActualFrame));
  return whitePixel;
}

uint32_t intersection_counter(uint32_t actualPixel, uint32_t previousPixel) {
  uint32_t sobelPixel = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],44" : [out1] "=r"(sobelPixel) : [in1] "r"(actualPixel), [in2] "r"(previousPixel));
  return sobelPixel;
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

bool jaccard(uint32_t unionPreviousActualPicture, uint32_t IntersectionPreviousActualPicture) {
  volatile uint32_t move = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],42" : [out1] "=r"(move) : [in1] "r"(unionPreviousActualPicture), [in2] "r"(IntersectionPreviousActualPicture));
  return move == 1u;
}

bool dice(uint32_t totalwhitepixel, uint32_t IntersectionPreviousActualPicture) {
  volatile uint32_t move = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],43" : [out1] "=r"(move) : [in1] "r"(totalwhitepixel), [in2] "r"(IntersectionPreviousActualPicture));
  return move == 1u;
}

void set_threshold() {
  asm volatile("l.nios_rrr r0,%[in1],%[in2],42" ::[in1] "r"(setThreshold), [in2] "r"(30));
  asm volatile("l.nios_rrr r0,%[in1],%[in2],43" ::[in1] "r"(setThreshold), [in2] "r"(30));
}

volatile uint8_t actualSobelTab[640 * 480];
volatile uint8_t previousSobelTab[640 * 480];
volatile uint8_t blackScreen[640 * 480];

int main()
{
  // const uint8_t sevenSeg[10] = {0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F};
  
  volatile uint8_t* previousSobel = previousSobelTab;
  volatile uint8_t* actualSobel = actualSobelTab;

  bool actualMovement = false;
  bool frameMovement = false;
  uint32_t whitePixelCounterActual = 0;
  uint32_t whitePixelCounterPrevious = 0;
  uint32_t unionPreviousActualPicture = 0;
  uint32_t IntersectionPreviousActualPicture = 0;
  uint32_t ComplementaryPreviousActualPicture = 0;
  
  volatile uint32_t result, cycles, stall, idle;
  uint32_t timeCounter = 0;
  volatile unsigned int *vga = (unsigned int *)0X50000020;
  // volatile unsigned int *gpio = (unsigned int *)0x40000000;
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
  set_threshold();

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

    if (frameMovement) {
      ++timeCounter;
      if (timeCounter > delayRefresh) {
        printf("hello \n");
        frameMovement = false;
        timeCounter = 0;
        vga[3] = swap_u32((uint32_t) blackScreen);
      }
    }

#ifdef __profiling__
    volatile uint32_t result, cycles, stall, idle;
    asm volatile ("l.nios_rrr r0,r0,%[in2],0xC"::[in2]"r"(7));
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
        previousPixel = read_DMA(previousBuffer2 + pixel);
        actualPixel = read_DMA(actualBuffer2 + pixel);

        ComplementaryPreviousActualPicture += complementary(actualPixel, previousPixel);
        // whitePixelCounterActual += white_counter(&actualPixel);
        IntersectionPreviousActualPicture += intersection_counter(actualPixel, previousPixel);
      } // DMA Pass

      wait_DMA();

      previousPtr -= USED_BLOCK_SIZE * sizeof(uint32_t);
      write_DMA(BUS_START, previousPtr);
      write_DMA(MEMORY_START, actualBuffer2);
      write_DMA(STATUS_CTRL, 2);
      wait_DMA();

      swap_buffer(&previousBuffer1, &previousBuffer2);
      swap_buffer(&actualBuffer1, &actualBuffer2);
      previousPtr += 2*USED_BLOCK_SIZE * sizeof(uint32_t);
      actualPtr += USED_BLOCK_SIZE * sizeof(uint32_t);
    } // one frame

    unionPreviousActualPicture = ComplementaryPreviousActualPicture + IntersectionPreviousActualPicture;
    actualMovement = jaccard(unionPreviousActualPicture, IntersectionPreviousActualPicture);
    // actualMovement = dice(whitePixelCounterActual + whitePixelCounterPrevious, &IntersectionPreviousActualPicture);

    if (actualMovement) {
      frameMovement = true;
      vga[3] = swap_u32((uint32_t) actualSobel);
      timeCounter = 0;
    }

    unionPreviousActualPicture = 0;
    IntersectionPreviousActualPicture = 0;
    ComplementaryPreviousActualPicture = 0;
    whitePixelCounterPrevious = whitePixelCounterActual;
    whitePixelCounterActual = 0;


#ifdef __profiling__
    asm volatile ("l.nios_rrr %[out1],r0,%[in2],0xC":[out1]"=r"(cycles):[in2]"r"(1<<8|7<<4));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(stall):[in1]"r"(1),[in2]"r"(1<<9));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(idle):[in1]"r"(2),[in2]"r"(1<<10));
    printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
#endif

  } // end while(1)
} // end main