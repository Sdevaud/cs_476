#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>

#ifndef CI
  #define CI 1
#endif

#ifndef COUNTERS
  #define COUNTERS 1
#endif



int main () {
  volatile uint16_t rgb565[640*480];
  volatile uint8_t grayscale[640*480];
  volatile uint32_t result, cycles,stall,idle;
  volatile uint32_t control, counterid;
  volatile unsigned int *vga = (unsigned int *) 0X50000020;
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
  vga[2] = swap_u32(2);
  vga[3] = swap_u32((uint32_t) &grayscale[0]);
  while(1) {
    uint32_t* gray = (uint32_t*) &grayscale[0];
    uint32_t* rgb = (uint32_t*) &rgb565[0];
    takeSingleImageBlocking((uint32_t) &rgb565[0]);

    // Start counters
    control = 7; // Enable all counters -> DataB = 1110 0000 0000
    asm volatile ("l.nios_rrr r0,r0,%[in2],0xB"::[in2]"r"(control));

    #if CI
      int size_picture = (camParams.nrOfLinesPerImage*
                          camParams.nrOfPixelsPerLine) >> 1;
      for (int pixels = 0; pixels < size_picture; pixels +=2) {
        uint32_t pixelsA = rgb[pixels];
        uint32_t pixelsB = rgb[pixels+1];
        asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xA":[out1]"=r"
                      (grayPixels):[in1]"r"(pixelsA),[in2]"r"(pixelsB));
        gray[0] = grayPixels;
        ++gray;
      }
    #else
      for (int line = 0; line < camParams.nrOfLinesPerImage; line++) {
        for (int pixel = 0; pixel < camParams.nrOfPixelsPerLine; pixel++) {
          uint16_t rgb = swap_u16(rgb565[line*camParams.nrOfPixelsPerLine+pixel]);
          uint32_t red1 = ((rgb >> 11) & 0x1F) << 3;
          uint32_t green1 = ((rgb >> 5) & 0x3F) << 2;
          uint32_t blue1 = (rgb & 0x1F) << 3;
          uint32_t gray = ((red1*54+green1*183+blue1*19) >> 8)&0xFF;
          grayscale[line*camParams.nrOfPixelsPerLine+pixel] = gray;
        }
      }

    #endif
    
    #if COUNTERS
      // Print Counter values
      counterid = 0; // cpu cycles
      asm volatile ("l.nios_rrr %[out1], %[in1], r0, 0xB":[out1]"=r"(cycles):
                                                          [in1]"r"(counterid));
      printf("\n");
      printf("CPU-Cycles : %u\n", cycles);

      counterid = 1; // cpu stalls
      asm volatile ("l.nios_rrr %[out1], %[in1], r0, 0xB":[out1]"=r"(stall):
                                                          [in1]"r"(counterid));
      printf("CPU-Stalls : %u\n", stall);

      counterid = 2; // cpu bud idle
      asm volatile ("l.nios_rrr %[out1], %[in1], r0, 0xB":[out1]"=r"(idle):
                                                          [in1]"r"(counterid));
      printf("CPU-Idles  : %u\n", idle);
    #endif

  }
  // Stop Counters
  control = 7<<4; // Disable all counters -> DataB = 0000 1110 0000
  asm volatile ("l.nios_rrr r0,r0,%[in2],0xB"::[in2]"r"(control));
}
