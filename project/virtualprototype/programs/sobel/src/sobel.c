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


// Hough Configuration
#define THETA_RES 180      // 0 to 180 degrees
#define RHO_RES 200        // Adjust based on image diagonal
#define MAX_RHO 800
#define SCALE_RHO 8 // Scale factor to fit rho into accumulator
#define PI 3.14159265

uint16_t accumulator[THETA_RES][RHO_RES];

const int16_t sinLUT[180] = {
    0, 4, 8, 13, 17, 22, 26, 31, 35, 40, 44, 48, 53, 57, 61, 66, 70, 74, 79, 83,
    87, 91, 95, 100, 104, 108, 112, 116, 120, 124, 127, 131, 135, 139, 143, 146, 150, 153, 157, 160,
    164, 167, 171, 174, 177, 181, 184, 187, 190, 193, 196, 198, 201, 204, 207, 209, 212, 214, 217, 219,
    221, 223, 226, 228, 230, 232, 233, 235, 237, 238, 240, 241, 243, 244, 245, 246, 248, 249, 250, 250,
    251, 252, 253, 253, 254, 254, 254, 255, 255, 255, 256, 255, 255, 255, 254, 254, 254, 253, 253, 252,
    251, 250, 250, 249, 248, 246, 245, 244, 243, 241, 240, 238, 237, 235, 233, 232, 230, 228, 226, 223,
    221, 219, 217, 214, 212, 209, 207, 204, 201, 198, 196, 193, 190, 187, 184, 181, 177, 174, 171, 167,
    164, 160, 157, 153, 150, 146, 143, 139, 135, 131, 127, 124, 120, 116, 112, 108, 104, 100, 95, 91,
    87, 83, 79, 74, 70, 66, 61, 57, 53, 48, 44, 40, 35, 31, 26, 22, 17, 13, 8, 4
};

// Cosine is just Sine shifted by 90 degrees
int16_t getCos(int theta) {
    int idx = theta + 90;
    if (idx >= 180) idx -= 180;
    // For 90-180 of Cos, we use the property cos(x) = sin(x + 90)
    // But since our table is only 0-179, we handle the wrap:
    if (theta < 90) return sinLUT[90 - theta]; 
    return -sinLUT[theta - 90];
}


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
    
    
    // Run Hough transform
    // 1. Clear the Accumulator
    for (int t = 0; t < THETA_RES; t++) {
        for (int r = 0; r < RHO_RES; r++) {
            accumulator[t][r] = 0;
        }
    }

    // 2. Voting Process
    // We iterate through every pixel. If it's an edge (Sobel > 0), it votes.
    for (int y = 0; y < camParams.nrOfLinesPerImage; y++) {
        for (int x = 0; x < camParams.nrOfPixelsPerLine; x++) {
            if (!(sobel[y * camParams.nrOfPixelsPerLine + x] > 0)) {
                continue; // Not an edge pixel, skip
            }
                
        // For every edge pixel, calculate rho for all possible thetas
        for (int theta = 0; theta < THETA_RES; theta++) {
          // if (theta % 30 == 0 && x == 0 && y == 0) {
          //   // Red debug pixel to check if we are correctly calculating rho and voting
          //   grayscale[0] = 0xFF;
          //   grayscale[1] = 0xFF;
          //   grayscale[2] = 0xFF;
          //   grayscale[3] = 0xFF;
          //   grayscale[4] = 0xFF;
          //   grayscale[5] = 0xFF;
          //   grayscale[6] = 0xFF;
          //   grayscale[7] = 0xFF;
          // }
            int cosVal = getCos(theta);
            int sinVal = sinLUT[theta];
            int rho = (int)(x * cosVal + y * sinVal) >> 8;

            int rho_idx = (rho + MAX_RHO) / SCALE_RHO; 

            if (rho_idx >= 0) {
                accumulator[theta][rho_idx]++;
            }

        }
      }
    }

    // 3. Peak Detection (Finding the lines)
    uint16_t threshold = 250; // Minimum votes to be considered a line
    int num_lines = 0;
    for (int t = 0; t < THETA_RES; t++) {
        for (int r = 0; r < RHO_RES; r++) {
            if (!(accumulator[t][r] > threshold && num_lines < 10)) {
              continue; // Not a line, skip
            }
            num_lines++;

            printf("Line detected: Theta=%d degrees, Rho=%d pixels, Votes=%d\n", t, (r * SCALE_RHO) - MAX_RHO, accumulator[t][r]);

            // Convert accumulator indices back to real values
            int real_rho = (r * SCALE_RHO) - MAX_RHO;
            int cosVal = getCos(t);
            int sinVal = sinLUT[t];

            // If the line is more horizontal, iterate through X
            if (t > 45 && t < 135) {
                for (int x = 0; x < camParams.nrOfPixelsPerLine; x++) {
                    // y = (rho - x*cos) / sin
                    // Using fixed-point math (sin/cos are scaled by 256)
                    if (sinVal != 0) {
                        int y = ( (real_rho << 8) - (x * cosVal) ) / sinVal;
                        if (y >= 0 && y < camParams.nrOfLinesPerImage) {
                            sobel[y * camParams.nrOfPixelsPerLine + x] = 180; // Light gray line
                        }
                    }
                }
            } 
            // If the line is more vertical, iterate through Y to avoid gaps
            else {
                for (int y = 0; y < camParams.nrOfLinesPerImage; y++) {
                    // x = (rho - y*sin) / cos
                    if (cosVal != 0) {
                        int x = ( (real_rho << 8) - (y * sinVal) ) / cosVal;
                        if (x >= 0 && x < camParams.nrOfPixelsPerLine) {
                            sobel[y * camParams.nrOfPixelsPerLine + x] = 180;
                        }
                    }
                }
            }
          
        }
    }


    // // Profiling
    // asm volatile ("l.nios_rrr %[out1],r0,%[in2],12":[out1]"=r"(cycles):[in2]"r"(1<<8|7<<4));
    // asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],12":[out1]"=r"(stall):[in1]"r"(1),[in2]"r"(1<<9));
    // asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],12":[out1]"=r"(idle):[in1]"r"(2),[in2]"r"(1<<10));
    // printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
  }
}
