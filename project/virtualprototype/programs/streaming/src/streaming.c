#include <stdio.h>
#include <ov7670.h>
#include <delay.h>
#include <swap.h>
#include <vga.h>

// #define __RGB565__

// void delay(float seconds) {
//   delay_blocking_usec((int) (seconds * 1000000));
// }

volatile uint16_t rgb565[640*480];
volatile uint8_t grayscale[640*480];

int main () {
  const uint8_t sevenSeg[10] = {0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F};
  // volatile uint16_t rgb565[640*480];
  // volatile uint8_t grayscale[640*480];
  volatile uint32_t result, cycles,stall,idle;
  volatile unsigned int *vga = (unsigned int *) 0X50000020;
  volatile unsigned int *gpio = (unsigned int *) 0x40000000;
  camParameters camParams;
  vga_clear();
  
  printf("Initialising camera (this takes up to 3 seconds)!\n" );
  camParams = initOv7670(VGA);
  printf("Done!\n" );
  printf("NrOfPixels : %d\n", camParams.nrOfPixelsPerLine );
  result = (camParams.nrOfPixelsPerLine <= 320) ? camParams.nrOfPixelsPerLine | 0x80000000 : camParams.nrOfPixelsPerLine;
  vga[0] = swap_u32(result);
  printf("NrOfLines  : %d\n", camParams.nrOfLinesPerImage );
  result =  (camParams.nrOfLinesPerImage <= 240) ? camParams.nrOfLinesPerImage | 0x80000000 : camParams.nrOfLinesPerImage;
  vga[1] = swap_u32(result);
  printf("PCLK (kHz) : %d\n", camParams.pixelClockInkHz );
  printf("FPS        : %d\n", camParams.framesPerSecond );
  uint32_t grayPixels;
#ifdef __RGB565__
  vga[2] = swap_u32(1);
  vga[3] = swap_u32((uint32_t) &rgb565[0]);
  enableContinues((uint32_t) &rgb565[0]);
#else
  setSobelMode(1);
  vga[2] = swap_u32(2);
  vga[3] = swap_u32((uint32_t) &grayscale[0]);
  setSobelThreshold(60);
  enableContinues((uint32_t) &grayscale[0]);
#endif

printf("Starting streaming...\n" );
delay_blocking_usec(4000000);
printf("Streaming started!\n" );

printf("Switching to RGB...\n" );
disableContinues();
setSobelMode(0);
vga[2] = swap_u32(1);
vga[3] = swap_u32((uint32_t) &rgb565[0]);
enableContinues((uint32_t) &rgb565[0]);
delay_blocking_usec(4000000);

printf("Switching to Sobel...\n" );
disableContinues();
setSobelMode(1);
vga[2] = swap_u32(2);
vga[3] = swap_u32((uint32_t) &grayscale[0]);
enableContinues((uint32_t) &grayscale[0]);
delay_blocking_usec(4000000);
printf("Done...\n" );


while(1) {

  printf("Switching to RGB...\n" );
  disableContinues();
  setSobelMode(0);
  vga[2] = swap_u32(1);
  vga[3] = swap_u32((uint32_t) &rgb565[0]);
  enableContinues((uint32_t) &rgb565[0]);
  delay_blocking_usec(4000000);

  printf("Switching to Sobel...\n" );
  disableContinues();
  setSobelMode(1);
  vga[2] = swap_u32(2);
  vga[3] = swap_u32((uint32_t) &grayscale[0]);
  enableContinues((uint32_t) &grayscale[0]);
  delay_blocking_usec(4000000);

  }
}
