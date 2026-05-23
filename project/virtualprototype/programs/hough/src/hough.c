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
#define SCALE_RHO 4 // Scale factor to fit rho into accumulator
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


void writeDMA(uint32_t address, uint32_t data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2]"r"(data));
}

void readDMA(uint32_t address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(*data):[in1] "r"(address));
}

void calcRho(int xA, int yA, int thetaA, int xB, int yB, int thetaB, uint32_t *data) { // the ci ID is 0xA7 -> 167 in decimal
  // Verilog definition:
  // wire [7:0] thetaA = valueA[7:0];
  // wire signed [9:0] xA = valueA[17:8];
  // wire signed [9:0] yA = valueA[27:18];
  uint32_t valueA = thetaA | (xA << 8) | (yA << 18);
  uint32_t valueB = thetaB | (xB << 8) | (yB << 18);
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],167" :[out1]"=r"(*data) :[in1] "r"(valueA), [in2]"r"(valueB));
}


void waitForDMA() {
  uint32_t data;
  do {
    readDMA(STAT_CTRL, &data);
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

    uint32_t bufferA = 0;
    uint32_t bufferB = 256;
    uint32_t pixel1 = 0;
    uint32_t pixel2 = 0;

    // Transfer first 512 pixels to CI buffer A
    uint32_t pixel_block_addr = (uint32_t) &rgb[0];
    writeDMA(BUS_START, pixel_block_addr);
    writeDMA(MEMORY_START, bufferA);
    writeDMA(BLOCK_SIZE, 256);
    writeDMA(BURST_SIZE, 128);
    writeDMA(STAT_CTRL, 1); // start transfer
    waitForDMA();
    writeDMA(STAT_CTRL, 0); // stop transfer

    for (int idx = 0; idx < 599; idx++) {
      pixel_block_addr = (uint32_t) &rgb[256*(idx+1)];

      writeDMA(BUS_START, pixel_block_addr);
      writeDMA(MEMORY_START, bufferB);
      writeDMA(BLOCK_SIZE, 256);
      writeDMA(STAT_CTRL, 1); // start transfer bus -> ci

      // Convert pixels from bufferA: read 2x 32-bit word (4x16 bit pixel)) -> convert to 1x 32-bit gray word
      for (int pixelIdx = 0; pixelIdx < 256; pixelIdx += 2) {
        readDMA(bufferA + pixelIdx, &pixel1);
        readDMA(bufferA + pixelIdx + 1, &pixel2);

        // Swap order because different endianess of CPU and DMA
        uint32_t pixel1Reversed = swap_u32(pixel1);
        uint32_t pixel2Reversed = swap_u32(pixel2);
        asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],10":[out1]"=r"(grayPixels):[in1]"r"(pixel1Reversed),[in2]"r"(pixel2Reversed));
        writeDMA(bufferA + pixelIdx / 2, swap_u32(grayPixels));
      }

      waitForDMA();
      writeDMA(STAT_CTRL, 0); // stop transfer

      // Write the grayscale pixels to the output buffer
      writeDMA(BUS_START, (uint32_t) &grayscale[512*idx]);
      writeDMA(MEMORY_START, bufferA);
      writeDMA(BLOCK_SIZE, 128);
      writeDMA(STAT_CTRL, 2); // start transfer ci -> bus
      waitForDMA();
      writeDMA(STAT_CTRL, 0); // stop transfer

      // Swap the buffers
      bufferA = bufferA ^ 256; // XOR
      bufferB = bufferB ^ 256;
    }

    // Process the last chunk (bufferB), since we have already swapped addresses in the loop we must now use bufferA
    for (int pixelIdx = 0; pixelIdx < 256; pixelIdx += 2) {
      readDMA(bufferA + pixelIdx, &pixel1);
      readDMA(bufferA + pixelIdx + 1, &pixel2);

      uint32_t pixel1Reversed = swap_u32(pixel1);
      uint32_t pixel2Reversed = swap_u32(pixel2);
      asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],10":[out1]"=r"(grayPixels):[in1]"r"(pixel1Reversed),[in2]"r"(pixel2Reversed));
      writeDMA(bufferA + pixelIdx / 2, swap_u32(grayPixels));
    }
    
    writeDMA(BUS_START, (uint32_t) &grayscale[512*599]);
    writeDMA(MEMORY_START, bufferA);
    writeDMA(BLOCK_SIZE, 128);
    writeDMA(STAT_CTRL, 2); // start transfer ci -> bus
    waitForDMA();
    writeDMA(STAT_CTRL, 0); // stop transfer



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
        sobel[index] = (magnitude > 128) ? 255 : 0;
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
    uint16_t threshold = 500; // Minimum votes to be considered a line
    int num_lines = 0;
    int top_lines[5] = {0}; // Array to store the top 5 votes
    int top_theta[5] = {0}; // Array to store the corresponding theta values (indices)
    int top_rho_idx[5] = {0}; // Array to store the corresponding rho indices

    for (int t = 0; t < THETA_RES; t++) {
        for (int r = 0; r < RHO_RES; r++) {
            if (!(accumulator[t][r] > 400)) {
                continue; // Not a line, skip
            }
            
            // If this peak is within +-1 theta OR +-1 rho-index of an already stored top entry,
            // treat it as the same line and keep the stronger vote (don't insert a new separate line).
            int merged = 0;
            for (int j = 0; j < 5; j++) {
              if (top_lines[j] == 0) continue;
              int dt = top_theta[j] - t;
              if (dt < 0) dt = -dt;
              int dr = top_rho_idx[j] - r;
              if (dr < 0) dr = -dr;

              if (dt <= 1 || dr <= 1) {
                // Considered duplicate/nearby: merge by keeping the larger vote
                if (accumulator[t][r] > top_lines[j]) {
                  top_lines[j] = accumulator[t][r];
                  top_theta[j] = t;
                  top_rho_idx[j] = r;
                }
                merged = 1;
                break;
              }
            }
            if (merged) continue;

            // Insert into top 5 if applicable (normal insertion)
            for (int i = 0; i < 5; i++) {
              if (accumulator[t][r] > top_lines[i]) {
                // Shift lower entries
                for (int j = 4; j > i; j--) {
                  top_lines[j] = top_lines[j - 1];
                  top_theta[j] = top_theta[j - 1];
                  top_rho_idx[j] = top_rho_idx[j - 1];
                }
                // Insert new entry
                top_lines[i] = accumulator[t][r];
                top_theta[i] = t;
                top_rho_idx[i] = r;
                break;
              }
            }
        }
    }

    // Print the top 5 lines detected
    for (int i = 0; i < 5; i++) {
      if (top_lines[i] > 0) {
        int rho_val = (top_rho_idx[i] * SCALE_RHO) - MAX_RHO;
        printf("%d: Line detected: Theta=%d degrees, Rho=%d pixels, Votes=%d\n", i + 1, top_theta[i], rho_val, top_lines[i]);
      }
    }
    printf("\n");


    // test calc rho CI
    uint32_t rho_result;
    calcRho(100, 20, 160, 15, 25, 35, &rho_result);
    int16_t rhoA = (rho_result >> 16) & 0xFFFF;
    int16_t rhoB = rho_result & 0xFFFF;
    printf("Test calcRho CI: rhoA=%d, rhoB=%d\n", rhoA, rhoB);

  } // while

} // main
