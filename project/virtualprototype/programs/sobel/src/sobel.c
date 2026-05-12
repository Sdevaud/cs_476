#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>


#define WRITE_OPERATION (1<<9)

#define BUS_START (1<<10)
#define MEMORY_START (2<<10)
#define BLOCK_SIZE (3<<10)
#define BURST_SIZE (4<<10)
#define STAT_CTRL (5<<10)


void writeCi(uint32_t address, uint32_t data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2]"r"(data));
}

void readCi(uint32_t address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(*data):[in1] "r"(address));
}

void waitForDMA() {
  uint32_t data;
  do {
    readCi(STAT_CTRL, &data);
  } while (data & 1); // wait until the busy bit is zero
}


uint16_t rgb565[640*480];
uint8_t grayscale[640*480];
uint8_t sobel[640*480];

int main () {
  volatile uint32_t result, cycles,stall,idle;
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
  vga[3] = swap_u32((uint32_t) &sobel[0]);

  
  while(1) {
    uint32_t* gray = (uint32_t*) &grayscale[0];
    uint32_t* rgb = (uint32_t*) &rgb565[0];
    takeSingleImageBlocking((uint32_t) &rgb565[0]);
    
    // Start counters
    // asm volatile ("l.nios_rrr r0,r0,%[in2],12"::[in2]"r"(7));




    uint32_t bufferA = 0;
    uint32_t bufferB = 256;
    uint32_t pixel1 = 0;
    uint32_t pixel2 = 0;

    // Transfer first 512 pixels to CI buffer A
    uint32_t pixel_block_addr = (uint32_t) &rgb[0];
    writeCi(BUS_START, pixel_block_addr);
    writeCi(MEMORY_START, bufferA);
    writeCi(BLOCK_SIZE, 256);
    writeCi(BURST_SIZE, 128);
    writeCi(STAT_CTRL, 1); // start transfer
    waitForDMA();
    writeCi(STAT_CTRL, 0); // stop transfer

    for (int idx = 0; idx < 599; idx++) {
      pixel_block_addr = (uint32_t) &rgb[256*(idx+1)];

      writeCi(BUS_START, pixel_block_addr);
      writeCi(MEMORY_START, bufferB);
      writeCi(BLOCK_SIZE, 256);
      writeCi(STAT_CTRL, 1); // start transfer bus -> ci

      // Convert pixels from bufferA: read 2x 32-bit word (4x16 bit pixel)) -> convert to 1x 32-bit gray word
      for (int pixelIdx = 0; pixelIdx < 256; pixelIdx += 2) {
        readCi(bufferA + pixelIdx, &pixel1);
        readCi(bufferA + pixelIdx + 1, &pixel2);

        // Swap order because different endianess of CPU and DMA
        uint32_t pixel1Reversed = swap_u32(pixel1);
        uint32_t pixel2Reversed = swap_u32(pixel2);
        asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],10":[out1]"=r"(grayPixels):[in1]"r"(pixel1Reversed),[in2]"r"(pixel2Reversed));
        writeCi(bufferA + pixelIdx / 2, swap_u32(grayPixels));
      }

      waitForDMA();
      writeCi(STAT_CTRL, 0); // stop transfer

      // Write the grayscale pixels to the output buffer
      writeCi(BUS_START, (uint32_t) &grayscale[512*idx]);
      writeCi(MEMORY_START, bufferA);
      writeCi(BLOCK_SIZE, 128);
      writeCi(STAT_CTRL, 2); // start transfer ci -> bus
      waitForDMA();
      writeCi(STAT_CTRL, 0); // stop transfer

      // Swap the buffers
      bufferA = bufferA ^ 256; // XOR
      bufferB = bufferB ^ 256;
    }

    // Process the last chunk (bufferB), since we have already swapped addresses in the loop we must now use bufferA
    for (int pixelIdx = 0; pixelIdx < 256; pixelIdx += 2) {
      readCi(bufferA + pixelIdx, &pixel1);
      readCi(bufferA + pixelIdx + 1, &pixel2);

      uint32_t pixel1Reversed = swap_u32(pixel1);
      uint32_t pixel2Reversed = swap_u32(pixel2);
      asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],10":[out1]"=r"(grayPixels):[in1]"r"(pixel1Reversed),[in2]"r"(pixel2Reversed));
      writeCi(bufferA + pixelIdx / 2, swap_u32(grayPixels));
    }
    
    writeCi(BUS_START, (uint32_t) &grayscale[512*599]);
    writeCi(MEMORY_START, bufferA);
    writeCi(BLOCK_SIZE, 128);
    writeCi(STAT_CTRL, 2); // start transfer ci -> bus
    waitForDMA();
    writeCi(STAT_CTRL, 0); // stop transfer



    // int size_picture = (camParams.nrOfLinesPerImage*
    //                       camParams.nrOfPixelsPerLine) >> 1;
    //   for (int pixels = 0; pixels < size_picture; pixels +=2) {
    //     uint32_t pixelsA = rgb[pixels];
    //     uint32_t pixelsB = rgb[pixels+1];
    //     asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xA":[out1]"=r"
    //                   (grayPixels):[in1]"r"(pixelsA),[in2]"r"(pixelsB));
    //     gray[0] = grayPixels;
    //     ++gray;
    //   }

    // for (int line = 0; line < camParams.nrOfLinesPerImage; line++) {
    //   for (int pixel = 0; pixel < camParams.nrOfPixelsPerLine; pixel++) {
    //     uint16_t rgb = swap_u16(rgb565[line*camParams.nrOfPixelsPerLine+pixel]);
    //     uint32_t red1 = ((rgb >> 11) & 0x1F) << 3;
    //     uint32_t green1 = ((rgb >> 5) & 0x3F) << 2;
    //     uint32_t blue1 = (rgb & 0x1F) << 3;
    //     uint32_t gray = ((red1*54+green1*183+blue1*19) >> 8)&0xFF;
    //     grayscale[line*camParams.nrOfPixelsPerLine+pixel] = gray;
    //   }
    // }


    for (int line = 0; line < camParams.nrOfLinesPerImage; line++) {
      for (int pixel = 0; pixel < camParams.nrOfPixelsPerLine; pixel++) {
        int index = line * camParams.nrOfPixelsPerLine + pixel;

        if (line == 0 || pixel == 0 ||
            line == camParams.nrOfLinesPerImage - 1 ||
            pixel == camParams.nrOfPixelsPerLine - 1) {
          sobel[index] = 0;
          continue;
        }

        int gx = -grayscale[(line - 1) * camParams.nrOfPixelsPerLine + (pixel - 1)]
                 - 2 * grayscale[line * camParams.nrOfPixelsPerLine + (pixel - 1)]
                 - grayscale[(line + 1) * camParams.nrOfPixelsPerLine + (pixel - 1)]
                 + grayscale[(line - 1) * camParams.nrOfPixelsPerLine + (pixel + 1)]
                 + 2 * grayscale[line * camParams.nrOfPixelsPerLine + (pixel + 1)]
                 + grayscale[(line + 1) * camParams.nrOfPixelsPerLine + (pixel + 1)];

        int gy = -grayscale[(line - 1) * camParams.nrOfPixelsPerLine + (pixel - 1)]
                 - 2 * grayscale[(line - 1) * camParams.nrOfPixelsPerLine + pixel]
                 - grayscale[(line - 1) * camParams.nrOfPixelsPerLine + (pixel + 1)]
                 + grayscale[(line + 1) * camParams.nrOfPixelsPerLine + (pixel - 1)]
                 + 2 * grayscale[(line + 1) * camParams.nrOfPixelsPerLine + pixel]
                 + grayscale[(line + 1) * camParams.nrOfPixelsPerLine + (pixel + 1)];

        int magnitude = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
        sobel[index] = (magnitude > 64) ? 255 : 0;
      }
    }

    
    // // Profiling
    // asm volatile ("l.nios_rrr %[out1],r0,%[in2],12":[out1]"=r"(cycles):[in2]"r"(1<<8|7<<4));
    // asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],12":[out1]"=r"(stall):[in1]"r"(1),[in2]"r"(1<<9));
    // asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],12":[out1]"=r"(idle):[in1]"r"(2),[in2]"r"(1<<10));
    // printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
  }
}
