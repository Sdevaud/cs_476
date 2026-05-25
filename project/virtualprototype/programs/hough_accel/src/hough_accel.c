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

void writeDMA(uint32_t address, uint32_t data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2]"r"(data));
}

void readDMA(uint32_t address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(*data):[in1] "r"(address));
}

void waitForDMA() {
  uint32_t data;
  do {
    readDMA(STAT_CTRL, &data);
  } while (data & 1); // wait until the busy bit is zero
}


// Hough Configuration
#define THETA_RES 3      // 0 to 180 degrees
#define N_THETA (int)(180 / THETA_RES)
#define RHO_RES 200        // Adjust based on image diagonal
#define MAX_RHO 800
#define SCALE_RHO 4 // Scale factor to fit rho into accumulator
#define PI 3.14159265




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




uint16_t accumulator[N_THETA][RHO_RES];
uint16_t line_accumulator [RHO_RES]; // This is what we fill up repeatedly with the DMA and unload into the big accumulator

inline uint32_t calcRho(int theta, int y, int xA, uint8_t sobelA, uint8_t sobelB, uint8_t sobelC, uint8_t sobelD) {
  // valueA [0:31] = {theta(8bit), y(10bit), x1(10bit),
  //      sobelBin1(1bit), sobelBin2(1bit), sobelBin3(1bit), sobelBin4(1bit)}
  // valueB [0:31] = {x2(10bit), x3(10bit), x4(10bit), reserved(2bit)}
  uint32_t valueA = theta | (y << 8) | (xA << 18) |
    ((sobelA & 1) << 28 | (sobelB & 1) << 29 | (sobelC & 1) << 30 | (sobelD & 1) << 31);
  uint32_t valueB = (xA+2) | ((xA+4) << 10) | ((xA+6) << 20);

  uint32_t result;

  // the ci ID is 0xA7 -> 167 in decimal
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],167" :[out1]"=r"(result) :[in1] "r"(valueA), [in2]"r"(valueB));

  // int cosVal = getCos(theta);
  // int sinVal = sinLUT[theta];
  // int rhoLeft = (int)(xA * cosVal + y * sinVal) >> 8;
  // int rhoRight = (int)((xA + 2) * cosVal + y * sinVal) >> 8;

  // int rhoLeft_scaled = (rhoLeft + MAX_RHO) / SCALE_RHO; 
  // int rhoRight_scaled = (rhoRight + MAX_RHO) / SCALE_RHO; 

  // data[0] = (rhoLeft_scaled << 16) | rhoRight_scaled; // Return both rhos in one 32-bit word for simplicity

  return result;
}

inline void voteHoughCi(int theta, int y, int xA, uint8_t sobelA, uint8_t sobelB, uint8_t sobelC, uint8_t sobelD) {
  uint32_t valueA = theta | (y << 8) | (xA << 18) |
    ((sobelA & 1) << 28 | (sobelB & 1) << 29 | (sobelC & 1) << 30 | (sobelD & 1) << 31);
  uint32_t valueB = (xA+2) | ((xA+4) << 10) | ((xA+6) << 20);

  asm volatile("l.nios_rrr r0,%[in1],%[in2],167" ::[in1] "r"(valueA), [in2]"r"(valueB));
}

inline void incrementAccumulator(int theta_idx, int rho_idx) {
  uint32_t voteCount;
  // Read vote count from CI memory
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],167" :[out1]"=r"(voteCount) :[in1] "r"(rho_idx), [in2]"r"(1<<31));
  accumulator[theta_idx][rho_idx] += voteCount;
}
  


uint8_t sobel[640*480];

int main () {
  volatile uint32_t result, cycles,stall,idle;
  volatile unsigned int *vga = (unsigned int *) 0X50000020;
  camParameters camParams;
  vga_clear();


  // test calc rho CI
  uint32_t rho_result;
  rho_result = calcRho(0, 20, 40, 1, 1, 1, 0);
  uint8_t rhoA = (rho_result >> 24) & 0xFF;
  uint8_t rhoB = (rho_result >> 16) & 0xFF;
  uint8_t rhoC = (rho_result >> 8) & 0xFF;
  uint8_t rhoD = rho_result & 0xFF;
  printf("Test calcRho CI: rhoA=%d, rhoB=%d\n", rhoA, rhoB);
  printf("Test calcRho CI: rhoC=%d, rhoD=%d\n", rhoC, rhoD);
  printf("Raw result: 0x%08X\n", rho_result);

  
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
  vga[2] = swap_u32(2); // 2: 8bit pixels, 1: 16bit pixels
  vga[3] = swap_u32((uint32_t) &sobel[0]);
  setSobelThreshold(120);
  setSobelMode(1);

  // 1. Clear the Accumulator
  for (int t = 0; t < N_THETA; t++) {
      for (int r = 0; r < RHO_RES; r++) {
          accumulator[t][r] = 0;
      }
  }

  
  while(1) {
    takeSingleImageBlocking((uint32_t) &sobel[0]);


    uint32_t bufferA = 0;
    uint32_t bufferB = 320;
    uint32_t voteBuffer = 640;
    uint32_t pixels_top_rev = 0;
    uint32_t pixels_bot_rev = 0;

    for (int t = 0; t < N_THETA; t++) { // Iterate over every theta separately
      // Transfer first 1280 pixels to CI buffer A
      uint32_t pixel_block_addr = (uint32_t) &sobel[0];
      writeDMA(BUS_START, pixel_block_addr);
      writeDMA(MEMORY_START, bufferA);
      writeDMA(BLOCK_SIZE, 320); // 320 words = 1280 pixels = 2 lines
      writeDMA(BURST_SIZE, 80);
      writeDMA(STAT_CTRL, 1); // start transfer
      waitForDMA();
      writeDMA(STAT_CTRL, 0); // stop transfer

      int cosVal = getCos(THETA_RES * t);
      int sinVal = sinLUT[THETA_RES * t];
      
      for (int y = 0; y < 478; y+=2) { // We process 1280 sobel (8bit) pixels at a time (two lines)
        pixel_block_addr = (uint32_t) &sobel[160*(y+2)];

        writeDMA(BUS_START, pixel_block_addr);
        writeDMA(MEMORY_START, bufferB);
        writeDMA(STAT_CTRL, 1); // start transfer bus -> ci
        
        uint8_t rhoMax;
        for (int wordIdx = 0; wordIdx < 160; wordIdx++) {
          readDMA(bufferA + wordIdx, &pixels_top_rev); // This reads 1x32-bit word = 4x8-bit sobel pixel
          readDMA(bufferA + 160 + wordIdx, &pixels_bot_rev);
          uint32_t pixels_top = swap_u32(pixels_top_rev);
          uint32_t pixels_bot = swap_u32(pixels_bot_rev);

          // Calculate Rho, lower resolution for rho (4 pixels counted as one)
          uint32_t rho_result;
          int xLeft = 4*wordIdx+1;
          uint8_t sobelT1 = pixels_top & 0xFF;
          uint8_t sobelT2 = (pixels_top >> 8) & 0xFF;
          uint8_t sobelB1 = pixels_bot & 0xFF;
          uint8_t sobelB2 = (pixels_bot >> 8) & 0xFF;
          uint16_t sobelLeft = sobelT1 | sobelT2 | sobelB1 | sobelB2;

          uint8_t sobelT3 = (pixels_top >> 16) & 0xFF;
          uint8_t sobelT4 = (pixels_top >> 24) & 0xFF;
          uint8_t sobelB3 = (pixels_bot >> 16) & 0xFF;
          uint8_t sobelB4 = (pixels_bot >> 24) & 0;
          uint16_t sobelRight = sobelT3 | sobelT4 | sobelB3 | sobelB4;

          // rho_result = calcRho(t, y, xLeft, sobelLeft, sobelRight, 0, 0);

          int rhoLeftRaw = (int)(xLeft * cosVal + y * sinVal) >> 8;
          int rhoRightRaw = (int)((xLeft + 2) * cosVal + y * sinVal) >> 8;

          int rhoLeft_scaled = (rhoLeftRaw + MAX_RHO) / SCALE_RHO; 
          int rhoRight_scaled = (rhoRightRaw + MAX_RHO) / SCALE_RHO; 

          uint8_t rhoLeft = (rhoLeft_scaled & 0xFF);
          uint8_t rhoRight = (rhoRight_scaled & 0xFF);
        
          uint32_t voteAddress = rhoLeft <= rhoRight ? rhoLeft : rhoRight;
          rhoMax = rhoLeft >= rhoRight ? rhoLeft : rhoRight;

          if (rhoLeft - rhoRight == 0) {
            uint32_t vote = (sobelLeft & 1) + (sobelRight & 1);
            if (voteAddress % 2 == 0) {
              writeDMA(voteBuffer + voteAddress/2, swap_u32(vote));
            } else {
              writeDMA(voteBuffer + (voteAddress-1)/2, swap_u32((vote && 0xFFFF) >> 16)); // write into upper half of the word
            }
          } else if (rhoLeft - rhoRight == -1) {
            uint32_t voteLeft = sobelLeft & 1;
            uint32_t voteRight = sobelRight & 1;
            if (voteAddress % 2 == 0) {
              writeDMA(voteBuffer + voteAddress/2, swap_u32(voteLeft | (voteRight >> 16)));
            } else {
              writeDMA(voteBuffer + (voteAddress-1)/2, swap_u32(voteLeft >> 16));
              writeDMA(voteBuffer + (voteAddress+1)/2, swap_u32(voteRight));            
            }
          } else if (rhoLeft - rhoRight == -2) {
            uint32_t voteLeft = sobelLeft & 1;
            uint32_t voteRight = sobelRight & 1;
            if (voteAddress % 2 == 0) {
              writeDMA(voteBuffer + voteAddress/2, swap_u32(voteLeft));
              writeDMA(voteBuffer + (voteAddress+2)/2, swap_u32(voteRight));            
            } else {
              writeDMA(voteBuffer + (voteAddress-1)/2, swap_u32(voteLeft >> 16));
              writeDMA(voteBuffer + (voteAddress+1)/2, swap_u32(voteRight >> 16));            
            }
          } else if (rhoLeft - rhoRight == 1) {
            uint32_t voteLeft = sobelLeft & 1;
            uint32_t voteRight = sobelRight & 1;
            if (voteAddress % 2 == 0) {
              writeDMA(voteBuffer + voteAddress/2, swap_u32(voteRight | (voteLeft >> 16)));
            } else {
              writeDMA(voteBuffer + (voteAddress-1)/2, swap_u32(voteRight >> 16));
              writeDMA(voteBuffer + (voteAddress+1)/2, swap_u32(voteLeft));            
            }
          } else if (rhoLeft - rhoRight == 2) {
            uint32_t voteLeft = sobelLeft & 1;
            uint32_t voteRight = sobelRight & 1;
            if (voteAddress % 2 == 0) {
              writeDMA(voteBuffer + voteAddress/2, swap_u32(voteRight));
              writeDMA(voteBuffer + (voteAddress+2)/2, swap_u32(voteLeft));            
            } else {
              writeDMA(voteBuffer + (voteAddress-1)/2, swap_u32(voteRight >> 16));
              writeDMA(voteBuffer + (voteAddress+1)/2, swap_u32(voteLeft >> 16));            
            }
          }

          /*
          Idea: dont pack pixels in 300 little packets. Instead go through image line by line
          (so 480 outer loop interations instead of 300). Then we save one line per side of the
          ping pong buffer (which wont be full then but only hold 160 words per side instead of
          256). Now for each line we read the pixels and accumulate the votes back in the dma buffer
          (this will have the side effect that votes can only be 1 or 0, therefore horizontal lines 
          cant be detected). This dma buffer is unloaded into the accumulator after each line. This 
          probably cant be done directly (at least i dont see a way) so we first have to dump it into a
          separate array in memory that can then be incremented onto the accumulator (No idea how slow
          this will be).

          Problems:
          - votes are 16bit each so we cant take out one 32 word (4 pixels) and write back all 4 votes into the buffer
            --> Downsampling
          - We cant simply write back into DMA at address of RHO because it would overwrite the existing pixel information
            --> We have to write the votes into a separate segment of the buffer for this
          */
        }

        // waitForDMA();
        // writeDMA(STAT_CTRL, 0); // stop transfer

        // // Write the grayscale pixels to the output buffer
        // writeDMA(BUS_START, (uint32_t) &line_accumulator[0]);
        // writeDMA(MEMORY_START, voteBuffer);
        // writeDMA(BLOCK_SIZE, rhoMax); // THis block size needs to be adaptive now to only read what we populated
        // writeDMA(STAT_CTRL, 2); // start transfer ci -> bus
        // waitForDMA();
        // writeDMA(STAT_CTRL, 0); // stop transfer

        // Swap the buffers
        bufferA = bufferA ^ 256; // XOR
        bufferB = bufferB ^ 256;

        // Increment accumulator theta row with collected votes from above
        for (int i; i<rhoMax; i++) {
          accumulator[t][i] += line_accumulator[i];
        }

      } // Y loop

    } // Theta loop
    printf("Theta loop complete\n");


    continue;
    // Peak Detection (Finding the lines)
    uint16_t threshold = 250; // Minimum votes to be considered a line
    int num_lines = 0;
    int top_lines[5] = {0}; // Array to store the top 5 votes
    int top_theta[5] = {0}; // Array to store the corresponding theta values (indices)
    int top_rho_idx[5] = {0}; // Array to store the corresponding rho indices

    for (int t = 0; t < N_THETA; t++) {
        for (int r = 0; r < RHO_RES; r++) {
          uint16_t acc_value = accumulator[t][r];
          acc_value = 0; // Clear accumulator after reading its value
            if (!(acc_value > threshold)) {
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
                if (acc_value > top_lines[j]) {
                  top_lines[j] = acc_value;
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
              if (acc_value > top_lines[i]) {
                // Shift lower entries
                for (int j = 4; j > i; j--) {
                  top_lines[j] = top_lines[j - 1];
                  top_theta[j] = top_theta[j - 1];
                  top_rho_idx[j] = top_rho_idx[j - 1];
                }
                // Insert new entry
                top_lines[i] = acc_value;
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

  } // while

} // main
