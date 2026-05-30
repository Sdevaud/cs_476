#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>
#include <stdbool.h>

#define __profiling__

const uint16_t largeur = 640;
const uint16_t hauteur = 480;
const uint8_t black = 0x00;
const uint8_t white = 0xFF;
const uint16_t setThresholdSobel = 64;
const uint16_t setThresholdMovement = 64;
const uint16_t maxFramesWithoutMovement = 10;

void f_init_black_screen(uint8_t blackScreen[]);


int main () {
  volatile uint32_t result;
  volatile uint8_t grayscale[hauteur*largeur];
  volatile uint8_t sobelA[hauteur*largeur];
  volatile uint8_t sobelB[hauteur*largeur];
  volatile unsigned int *vga = (unsigned int *) 0X50000020;
  camParameters camParams;
  uint16_t framesWithoutMovement = 0;
  vga_clear();

#ifdef __profiling__
    volatile uint32_t cycles, stall, idle;
#endif
  
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

  vga[2] = swap_u32(2);
  vga[3] = swap_u32((uint32_t) &sobelA[0]);
  // enableContinues((uint32_t) &grayscale[0]);

  f_init_black_screen((uint8_t *) sobelA);
  f_init_black_screen((uint8_t *) sobelB);

  while(1) {
    takeSingleImageBlocking((uint32_t) &grayscale[0]);

#ifdef __profiling__
    asm volatile ("l.nios_rrr r0,r0,%[in2],0xC"::[in2]"r"(7));
#endif

    uint32_t intersections = 0;
    uint32_t unionPixel = 0;

    for (size_t i = 0; i < (size_t) hauteur; ++i) {
      for (size_t j = 0; j < (size_t) largeur; ++j) {

        if (i == 0 || i == hauteur - 1 || j == 0 || j == largeur - 1) {
          sobelA[i*largeur + j] = black;
          sobelB[i*largeur + j] = black;
          continue;
        }

        uint16_t p1 = (uint16_t) grayscale[i*largeur + j - largeur - 1];
        uint16_t p2 = (uint16_t) grayscale[i*largeur + j - largeur];
        uint16_t p3 = (uint16_t) grayscale[i*largeur + j - largeur + 1];
        uint16_t p4 = (uint16_t) grayscale[i*largeur + j - 1];
        uint16_t p6 = (uint16_t) grayscale[i*largeur + j + 1];
        uint16_t p7 = (uint16_t) grayscale[i*largeur + j + largeur - 1];
        uint16_t p8 = (uint16_t) grayscale[i*largeur + j + largeur];
        uint16_t p9 = (uint16_t) grayscale[i*largeur + j + largeur + 1];
        int Gx =  p1 + (p2 << 1) + p3 - p7 - (p8 << 1) - p9;
        int Gy = p3 + (p6 << 1) + p9 - p1 - (p4 << 1) - p7;
        uint16_t magnitude = (uint16_t) ((Gx < 0 ? -Gx : Gx) + (Gy < 0 ? -Gy : Gy));

        if (magnitude > setThresholdSobel) {
          magnitude = white;
        } else {
          magnitude = black;
        }

        if (magnitude == white && sobelB[i*largeur + j] == white) ++intersections;
        if (magnitude == white || sobelB[i*largeur + j] == white) ++unionPixel;

        sobelB[i*largeur + j] = magnitude;
        sobelA[i*largeur + j] = magnitude;
      }// end for j
    } //end for i

    bool movement = false;

    if (unionPixel > 0) {
      uint32_t similarity = (100 * intersections) / unionPixel;
      movement = similarity < setThresholdMovement;
    }

    if (movement) {
      framesWithoutMovement = 0;
    } else {
      if (framesWithoutMovement < maxFramesWithoutMovement) ++framesWithoutMovement;
    }

    if (framesWithoutMovement >= maxFramesWithoutMovement) {
      f_init_black_screen((uint8_t *) sobelA);
    }
    


#ifdef __profiling__
    asm volatile ("l.nios_rrr %[out1],r0,%[in2],0xC":[out1]"=r"(cycles):[in2]"r"(1<<8|7<<4));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(stall):[in1]"r"(1),[in2]"r"(1<<9));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(idle):[in1]"r"(2),[in2]"r"(1<<10));
    printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
#endif

  } // end while(1)
} // end main


void f_init_black_screen(uint8_t blackScreen[]) {
  for (size_t i = 0; i < hauteur; ++i) {
    for (size_t j = 0; j < largeur; ++j) {
      blackScreen[i * largeur + j] = (uint8_t)black;
    }
  }
}