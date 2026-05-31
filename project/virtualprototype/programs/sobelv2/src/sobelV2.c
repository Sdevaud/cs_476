#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>
#include <stdbool.h>

#define __profiling__
#define __Jaccard__
// #define __Dice__
// #define __Percent__

// ==========================================
// DMA setup
// ==========================================
#define WRITE_OPERATION (1 << 9)
#define BUS_START (1 << 10)
#define MEMORY_START (2 << 10)
#define BLOCK_SIZE (3 << 10)
#define BURST_SIZE (4 << 10)
#define STATUS_CTRL (5 << 10)
#define USED_BLOCK_SIZE 128
#define USED_BURST_SIZE 31
#define HALF_USED_BLOCK_SIZE (USED_BLOCK_SIZE >> 1)

const uint32_t sizeDMA = 2 * 1024; // 2 kB
const uint8_t nbrPixelPerPass = 4;
const uint8_t nbrBuffer = 4;
const uint32_t unitaryBuffer = sizeDMA / (nbrPixelPerPass * nbrBuffer); // 128


// ==========================================
// Camera global variables and constants
// ==========================================
#define largeur 640u
#define hauteur 480u

const uint8_t black = 0x00;
const uint32_t setThreshold = 0xFF << 24;
const uint32_t delayRefresh = 50;


volatile uint8_t blackScreen[hauteur * largeur] = {black};
volatile uint8_t A_SobelTab[largeur * hauteur];
volatile uint8_t B_SobelTab[largeur * hauteur];

// ==========================================
// Function prototypes
// ==========================================
void f_write_DMA(const uint32_t address, const uint32_t data);
uint32_t f_read_DMA(const uint32_t address);
void f_wait_DMA();
uint32_t f_complementary(uint32_t pixelA_Frame, uint32_t pixelB_Frame);
uint32_t f_white_counter(uint32_t pixelA_Frame);
uint32_t f_intersection_counter(uint32_t pixelA, uint32_t pixelB);
void f_profiling(const uint32_t input, volatile uint32_t *output);
void f_reset_profiling();
void f_swap_buffer(uint32_t *buffer1, uint32_t *buffer2);
bool f_jaccard(uint32_t unionAB, uint32_t IntersectionAB);
bool f_dice(uint32_t totalwhitepixel, uint32_t IntersectionAB);
void f_set_threshold();
bool f_percent_of_change(uint32_t pixelA, uint32_t pixelB);
void f_init_black_screen(volatile uint8_t blackScreen[]);

int main() {
  volatile uint8_t* ptrSobelA = A_SobelTab;
  volatile uint8_t* ptrSobelB = B_SobelTab;
  // ==========================================
  // Variables for motion detection
  // ==========================================
  bool movement = false;
  bool frameMovement = false;
  bool displayScreen = true;
  uint32_t timeCounter = 0;

  #ifdef __Percent__
  uint32_t whitePixelCounterA = 0;
  uint32_t whitePixelCounterB = 0;
  #endif

  #ifdef __Jaccard__
  uint32_t IntersectionAB = 0;
  uint32_t ComplementaryAB = 0;
  uint32_t unionAB = 0;
  #endif  
  
  #ifdef __Dice__ 
  uint32_t IntersectionAB = 0;
  uint32_t ComplementaryAB = 0;
  uint32_t whitePixelCounterA = 0;
  uint32_t whitePixelCounterB = 0;
  #endif

  #ifdef __profiling__
    volatile uint32_t cycles, stall, idle;
  #endif

// ==========================================
// Initialize FPGA
// ==========================================
  volatile uint32_t result;
  volatile unsigned int *vga = (unsigned int *)0X50000020;
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
  f_init_black_screen(blackScreen);
  vga[3] = swap_u32((uint32_t) blackScreen);

// ==========================================
// Initialize first frame
// ==========================================
  f_write_DMA(BLOCK_SIZE, USED_BLOCK_SIZE);
  f_write_DMA(BURST_SIZE, USED_BURST_SIZE);
  f_set_threshold();
  takeSingleImageBlocking((uint32_t) ptrSobelA);

  while (1) {
    takeSingleImageBlocking((uint32_t) ptrSobelA);


    #ifdef __profiling__
    asm volatile ("l.nios_rrr r0,r0,%[in2],0xC"::[in2]"r"(7));
    #endif

    // ==========================================
    // Initialize buffers and pointers
    // ==========================================
    uint32_t B_Buffer1 = unitaryBuffer * 0;
    uint32_t B_Buffer2 = unitaryBuffer * 1;
    uint32_t A_Buffer1 = unitaryBuffer * 2;
    uint32_t A_Buffer2 = unitaryBuffer * 3;

    uint32_t pixelB = 0;
    uint32_t pixelA = 0;

    uint32_t PtrB = (uint32_t) ptrSobelB;
    uint32_t PtrA = (uint32_t) ptrSobelA;


    // ==========================================
    // Initialize DMA for the first pass
    // ==========================================
    f_write_DMA(BUS_START, PtrB);
    f_write_DMA(MEMORY_START, B_Buffer1);
    f_write_DMA(STATUS_CTRL, 1);
    f_wait_DMA();
    f_swap_buffer(&B_Buffer1, &B_Buffer2);
    PtrB += USED_BLOCK_SIZE * sizeof(uint32_t);

    f_write_DMA(BUS_START, PtrA);
    f_write_DMA(MEMORY_START, A_Buffer1);
    f_write_DMA(STATUS_CTRL, 1);
    f_wait_DMA();
    f_swap_buffer(&A_Buffer1, &A_Buffer2);
    PtrA += USED_BLOCK_SIZE * sizeof(uint32_t);

    for (uint32_t loop = 0; loop < 600; ++loop) {
      // ==========================================
      // Initialize DMA for the first pass
      // ==========================================
      if (loop < 599) {
        f_write_DMA(BUS_START, PtrB);
        f_write_DMA(MEMORY_START, B_Buffer1);
        f_write_DMA(STATUS_CTRL, 1);
      }

      // ==========================================
      // Count the number of pixels 4 by 4
      // ==========================================
      for (size_t pixel = 0; pixel < HALF_USED_BLOCK_SIZE; ++pixel) {
        pixelB = f_read_DMA(B_Buffer2 + pixel);
        pixelA = f_read_DMA(A_Buffer2 + pixel);

        #ifdef __Percent__
        whitePixelCounterA += f_white_counter(pixelA);
        #endif

        #ifdef __Jaccard__
        ComplementaryAB += f_complementary(pixelA, pixelB);
        IntersectionAB += f_intersection_counter(pixelA, pixelB);
        #endif

        #ifdef __Dice__
        whitePixelCounterA += f_white_counter(pixelA);
        IntersectionAB += f_intersection_counter(pixelA, pixelB);
        #endif      
      }

      // we gain a little bit of cycles of writing a second for loop than introduce 
      // an if in the previous loop
      if (loop < 599) {
        f_wait_DMA();
        f_write_DMA(BUS_START, PtrA);
        f_write_DMA(MEMORY_START, A_Buffer1);
        f_write_DMA(STATUS_CTRL, 1);
        }

      for (size_t pixel = HALF_USED_BLOCK_SIZE; pixel < USED_BLOCK_SIZE; ++pixel) {
        pixelB = f_read_DMA(B_Buffer2 + pixel);
        pixelA = f_read_DMA(A_Buffer2 + pixel);

        #ifdef __Percent__
        whitePixelCounterA += f_white_counter(pixelA);
        #endif

        #ifdef __Jaccard__
        ComplementaryAB += f_complementary(pixelA, pixelB);
        IntersectionAB += f_intersection_counter(pixelA, pixelB);
        #endif

        #ifdef __Dice__
        whitePixelCounterA += f_white_counter(pixelA);
        IntersectionAB += f_intersection_counter(pixelA, pixelB);
        #endif  
      }

      f_wait_DMA();

      // ==========================================
      // DMA out the previous frame
      // ==========================================
      // PtrB -= USED_BLOCK_SIZE * sizeof(uint32_t);
      // f_write_DMA(BUS_START, PtrB);
      // f_write_DMA(MEMORY_START, A_Buffer2);
      // f_write_DMA(STATUS_CTRL, 2);
      // f_wait_DMA();

      // swap the buffer takes 400 000 cycles why ? (both)
      f_swap_buffer(&B_Buffer1, &B_Buffer2);
      f_swap_buffer(&A_Buffer1, &A_Buffer2);
      PtrB += USED_BLOCK_SIZE * sizeof(uint32_t);
      PtrA += USED_BLOCK_SIZE * sizeof(uint32_t);
    } // one frame

    // ==========================================
    // Compute if there is movement
    // ==========================================
    #ifdef __Percent__
    movement = f_percent_of_change(whitePixelCounterA, whitePixelCounterB);
    whitePixelCounterB = whitePixelCounterA;
    whitePixelCounterA = 0;
    #endif

    #ifdef __Jaccard__
    unionAB = ComplementaryAB + IntersectionAB;
    movement = f_jaccard(unionAB, IntersectionAB);
    unionAB = 0;
    IntersectionAB = 0;
    ComplementaryAB = 0;
    #endif    
    
    #ifdef __Dice__
    movement = f_dice(whitePixelCounterA + whitePixelCounterB, IntersectionAB);
    whitePixelCounterB = whitePixelCounterA;
    whitePixelCounterA = 0;
    IntersectionAB = 0;
    #endif   

    if (movement) {
      frameMovement = true;
      timeCounter = 0;
      displayScreen = true;
    }

    

    if (frameMovement) {
      ++timeCounter;
      if (timeCounter > delayRefresh) {
        frameMovement = false;
        timeCounter = 0;
        displayScreen = false;
        vga[3] = swap_u32((uint32_t) blackScreen);
      }
    }

    volatile uint8_t* tmp = ptrSobelA;
    ptrSobelA = ptrSobelB;
    ptrSobelB = tmp;

    if (displayScreen) {
      vga[3] = swap_u32((uint32_t) ptrSobelA);
      // printf("Hello \n");
    }
    #ifdef __profiling__
    asm volatile ("l.nios_rrr %[out1],r0,%[in2],0xC":[out1]"=r"(cycles):[in2]"r"(1<<8|7<<4));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(stall):[in1]"r"(1),[in2]"r"(1<<9));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(idle):[in1]"r"(2),[in2]"r"(1<<10));
    printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
    #endif

  } // end while(1)
} // end main



// ==========================================
// Function definitions
// ==========================================

void f_write_DMA(const uint32_t address, const uint32_t data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2] "r"(data));
}

uint32_t f_read_DMA(const uint32_t address) {
  uint32_t data = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" : [out1] "=r"(data) : [in1] "r"(address));
  return data;
}

void f_wait_DMA() {
  uint32_t data = 0;
  do
  {
    data = f_read_DMA(STATUS_CTRL);
  } while (data & 1); // wait until the busy bit is zero
}

uint32_t f_complementary(uint32_t pixelA_Frame, uint32_t pixelB_Frame) {
  uint32_t move = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],40" : [out1] "=r"(move) : [in1] "r"(pixelA_Frame), [in2] "r"(pixelB_Frame));
  return move;
}

uint32_t f_white_counter(uint32_t pixelA_Frame) {
  uint32_t whitePixel = 0;
  asm volatile("l.nios_rrr %[out1],%[in1],r0,41" : [out1] "=r"(whitePixel) : [in1] "r"(pixelA_Frame));
  return whitePixel;
}

uint32_t f_intersection_counter(uint32_t pixelA, uint32_t pixelB) {
  uint32_t sobelPixel = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],44" : [out1] "=r"(sobelPixel) : [in1] "r"(pixelA), [in2] "r"(pixelB));
  return sobelPixel;
}

void f_profiling(const uint32_t input, volatile uint32_t *output) {
  asm volatile("l.nios_rrr %[out1],r0,%[in2],12" : [out1] "=r"(*output) : [in2] "r"(input));
}

void f_reset_profiling() {
  asm volatile("l.nios_rrr r0,r0,%[in2],12" ::[in2] "r"(7));
}

void f_swap_buffer(uint32_t *buffer1, uint32_t *buffer2) {
  uint32_t transition = 0;
  transition = *buffer1;
  *buffer1 = *buffer2;
  *buffer2 = transition;
}

bool f_jaccard(uint32_t unionAB, uint32_t IntersectionAB) {
  volatile uint32_t move = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],42" : [out1] "=r"(move) : [in1] "r"(unionAB), [in2] "r"(IntersectionAB));
  return move == 1u;
}

bool f_dice(uint32_t totalwhitepixel, uint32_t IntersectionAB) {
  volatile uint32_t move = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],43" : [out1] "=r"(move) : [in1] "r"(totalwhitepixel), [in2] "r"(IntersectionAB));
  return move == 1u;
}

void f_set_threshold() {
  asm volatile("l.nios_rrr r0,%[in1],%[in2],42" ::[in1] "r"(setThreshold), [in2] "r"(20));
  asm volatile("l.nios_rrr r0,%[in1],%[in2],43" ::[in1] "r"(setThreshold), [in2] "r"(20));
  asm volatile("l.nios_rrr r0,%[in1],%[in2],45" ::[in1] "r"(setThreshold), [in2] "r"(10));
}

bool f_percent_of_change(uint32_t pixelA, uint32_t pixelB) {
  volatile uint32_t move = 0u;
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],43" : [out1] "=r"(move) : [in1] "r"(pixelA), [in2] "r"(pixelB));
  return move == 1u;
}

void f_init_black_screen(volatile uint8_t blackScreen[]) {
  for (size_t i = 0; i < hauteur; ++i) {
    for (size_t j = 0; j < largeur; ++j) {
      blackScreen[i * largeur + j] = (uint8_t)black;
    }
  }
}