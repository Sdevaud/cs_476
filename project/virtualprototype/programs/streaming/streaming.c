#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>

#define __profiling__

const uint16_t largeur = 640;
const uint16_t hauteur = 480;

#define WRITE_OPERATION (1<<9)
#define BUS_START (1<<10)
#define MEMORY_START (2<<10)
#define BLOCK_SIZE (3<<10)
#define BURST_SIZE (4<<10)
#define STATUS_CTRL (5<<10)
#define USED_BLOCK_SIZE largeur
#define USED_BURST_SIZE 31

const uint16_t green = 0x07E0;
const uint16_t black = 0x0000;
const uint16_t white = 0xFFFF;

void writeDMAGray(const uint32_t* address, const uint32_t* data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(*address | WRITE_OPERATION), [in2]"r"(*data));
}

void readDMAGray(const uint32_t* address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(*data):[in1] "r"(*address));
}

void waitDMAGray() {
  uint32_t data;
  do {
    readDMAGray(STATUS_CTRL, &data);
  } while (data & 1); // wait until the busy bit is zero
}

void concatenate_line1xline2(const uint32_t* line1, const uint32_t* line2, uint32_t* grayPixelOut) {
  asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],31":[out1]"=r"(*grayPixelOut):[in1]"r"(*line1),[in2]"r"(*line2));
}
void concatenate_line2xline3(const uint32_t* line2, const uint32_t* line3, uint32_t* grayPixelOut) {
  asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],32":[out1]"=r"(*grayPixelOut):[in1]"r"(*line2),[in2]"r"(*line3));
}

void sobel_ci(const uint32_t* grayPixel1, const uint32_t* grayPixel2, uint32_t* sobelPixel) {
  asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],30":[out1]"=r"(*sobelPixel):[in1]"r"(*grayPixel1),[in2]"r"(*grayPixel2));
}

void edge_detection(const uint32_t* sobelPixel, uint32_t* houghPixel) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,33" :[out1]"=r"(*houghPixel):[in1] "r"(*sobelPixel));
}

void profiling(const uint32_t* input, uint32_t* output) {
  asm volatile ("l.nios_rrr %[out1],r0,%[in2],12":[out1]"=r"(*output):[in2]"r"(*input));
}

void reset_profiling() {
  asm volatile ("l.nios_rrr r0,r0,%[in2],12"::[in2]"r"(7));
}

void increment_buffer(uint32_t* sobelBuffer1, uint32_t* sobelBuffer2, uint32_t* sobelBuffer3, uint32_t* sobelBuffer4) {
  uint32_t transition = *sobelBuffer1;
  *sobelBuffer1 = *sobelBuffer2;
  *sobelBuffer2 = *sobelBuffer3;
  *sobelBuffer3 = *sobelBuffer4;
  *sobelBuffer4 = transition;

}

int main () {
  // const uint8_t sevenSeg[10] = {0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F};
  volatile uint16_t rgb565[hauteur*largeur];
  volatile uint32_t result, cycles, stall, idle;
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
  vga[2] = swap_u32(2);

  /* set up the generic dma parameters */
  writeDMAGray(BLOCK_SIZE, USED_BLOCK_SIZE);
  writeDMAGray(BURST_SIZE, USED_BURST_SIZE);


  while(1) {  
    takeSingleImageBlocking((uint32_t) &rgb565[0]);

    #ifdef __profiling__
      reset_profiling();
    #endif

    asm volatile ("l.nios_rrr r0,r0,%[in2],12"::[in2]"r"(7));
    uint32_t * rgb = (uint32_t *) &rgb565[0];
    uint32_t rgbpointer = (uint32_t) &rgb[0];

    uint32_t sobelBuffer1 = 0;
    uint32_t sobelBuffer2 = largeur;
    uint32_t sobelBuffer3 = largeur * 2; // 1280 
    uint32_t sobelBuffer4 = largeur * 3; // 1920

    uint32_t package4Pixel1 = 0;
    uint32_t package4Pixel2 = 0;
    uint32_t linePixel1 = 0;
    uint32_t linePixel2 = 0;
    uint32_t linePixel3 = 0;

    uint32_t sobelPixel = 0;
    uint32_t houghPixel = 0;

    /* Load first 3 lines with DMA*/
    for (uint32_t loop = 0; loop < 3; ++loop) {
      writeDMAGray(BUS_START, rgbpointer);
      writeDMAGray(MEMORY_START, sobelBuffer1);
      writeDMAGray(STATUS_CTRL, 1);
      rgbpointer += largeur * sizeof(uint16_t);
      increment_buffer(&sobelBuffer1, &sobelBuffer2, &sobelBuffer3, &sobelBuffer4);
    }
    /* We wait that the 3 for line is loaded */
    waitDMAGray();

    for (uint32_t loop = 0; loop < hauteur; ++loop) {
      /* Perform DMA in */
      if (loop < hauteur - 3) {
        writeDMAGray(BUS_START, rgbpointer);
        writeDMAGray(MEMORY_START, sobelBuffer1);
        writeDMAGray(STATUS_CTRL, 1);
        rgbpointer += largeur * sizeof(uint16_t);
      }
      
      for (int pixel = 1; pixel < largeur - 1; ++pixel) {
        if ((0 < loop) && (loop < hauteur - 1)) {
          readDMAGray(sobelBuffer2 + pixel, &linePixel1);
          readDMAGray(sobelBuffer3 + pixel , &linePixel2);
          readDMAGray(sobelBuffer4 + pixel, &linePixel3);

          concatenate_line1xline2(&linePixel1, &linePixel2, &package4Pixel1);
          concatenate_line2xline3(&linePixel2, &linePixel3, &package4Pixel2);

          sobel_ci(&package4Pixel1, &package4Pixel2, &sobelPixel);
          edge_detection(&sobelPixel, &houghPixel);

          if (houghPixel == 0xFF) rgb565[loop*largeur + pixel] = green;
        }
      }
      waitDMAGray();
      increment_buffer(&sobelBuffer1, &sobelBuffer2, &sobelBuffer3, &sobelBuffer4);
  }

    #ifdef __profiling__
      profiling((1<<8 | 7<<4), &cycles);
      profiling((1<<9), &stall);
      profiling((1<<10), &idle);
    #endif


  } // end while(1)
} // end main
