#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>


#define WRITE_OPERATION (1<<10)

#define BUS_START (1<<11)
#define MEMORY_START (2<<11)
#define BLOCK_SIZE (3<<11)
#define BURST_SIZE (4<<11)
#define STAT_CTRL (5<<11)

static inline void writeDMA(uint32_t address, uint32_t data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2]"r"(data));
}

static inline void readDMA(uint32_t address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(*data):[in1] "r"(address));
}

static inline void waitForDMA() {
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
#define SCALE_RHO 8 // Scale factor to fit rho into accumulator
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

static inline void voteHoughCi(int theta, uint32_t y, uint32_t xA, uint32_t sobelA, uint32_t sobelB, uint32_t sobelC, uint32_t sobelD) {
  uint32_t valueA = theta | (y << 8) | (xA << 18) |
    ((sobelA&1) << 28 | (sobelB&1) << 29 | (sobelC&1) << 30 | (sobelD&1) << 31);
  uint32_t valueB = (xA+2) | ((xA+4) << 10) | ((xA+6) << 20);
  asm volatile("l.nios_rrr r0,%[in1],%[in2],167" ::[in1] "r"(valueA), [in2]"r"(valueB));
}

static inline void incrementAccumulator(int theta_idx, int rho_idx) {
  uint32_t voteCount;
  // Read vote count from CI memory
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],167" :[out1]"=r"(voteCount) :[in1] "r"(rho_idx), [in2]"r"(1<<30));
  // if (theta_idx == 30) {
  //   printf("Incrementing Accumulator at Theta index %d, Rho index %d. Current votes: %d\n", theta_idx, rho_idx, voteCount);
  // }
  accumulator[theta_idx][rho_idx] = voteCount;
}
  


uint8_t sobel[640*480];

int main () {
  volatile uint32_t result, cycles,stall,idle;
  volatile unsigned int *vga = (unsigned int *) 0X50000020;
  camParameters camParams;
  vga_clear();

  // Clear Ci memory (just in case)
  for (int r = 0; r < RHO_RES; r++) {
    incrementAccumulator(0, r);
  }

  // Clear main accumulator
  for (int t = 0; t < N_THETA; t++) {
    for (int r = 0; r < RHO_RES; r++) {
        accumulator[t][r] = 0;
    }
  }

  // ==========================================
  // TEST SEQUENCE FOR STATEFUL HOUGH CI
  // ==========================================
  printf("--- Starting Stateful Hough CI Test ---\n");
  uint32_t one = 1;
  uint32_t x = 5;
  uint32_t y = 20;
  voteHoughCi(0, y, x, one, one, one, one);
  asm volatile("l.nop"); // Skip a cycle
  voteHoughCi(0, y, x, one, one, one, one);

  printf("Reading back accumulator window from hardware BRAM:\n");
  int found_votes = 0;
  for (int test_rho = 100; test_rho < 110; test_rho++) {
      incrementAccumulator(0, test_rho);
  }

  for (int test_rho = 100; test_rho < 110; test_rho++) {
      uint16_t votes = accumulator[0][test_rho];
      printf("Rho Index %d: Votes = %d\n", test_rho, votes);
      if (votes > 0) found_votes++;
  }

  // 3. Verify the "Destructive Read" / Clear feature worked.
  // Reading the exact same window again should return absolutely zero.
  uint32_t clear_check = 0;
  asm volatile("l.nios_rrr %[out1], %[in1], %[in2], 167" 
              : [out1] "=r" (clear_check) 
              : [in1] "r" (105), [in2] "r" (1 << 30));

  printf("  -> Post-clear verification at Index 105: 0x%08X (Expected: 0)\n", clear_check);
  printf("--- Stateful Hough CI Test Complete ---\n\n");
  // ==========================================


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

  // Clear main accumulator
  for (int t = 0; t < N_THETA; t++) {
    for (int r = 0; r < RHO_RES; r++) {
        accumulator[t][r] = 0;
    }
  }

  
  while(1) {
    takeSingleImageBlocking((uint32_t) &sobel[0]);

    // dummy data into sobel
    for (int i = 0; i < 640*480; i++) {
      if (i < 640*4) sobel[i] = 255; // Horizontal line at the top
      else if (i % 641 == 0) sobel[i] = 255; // Diagonal line TL to BR
      // else if (i % 641 == 20) sobel[i] = 255; // Diagonal line TL to BR
      else if (i % 639 == 630) sobel[i] = 255; // Diagonal line TR to BL
      // else if (i % 640 == 300) sobel[i] = 255; // Vertical line
      else sobel[i] = 0; 
    }
    // for (int i = 0; i < 640*480; i++) {
    //   sobel[i] = (i % 100 == 0) ? 255 : 0; // Sparse random edges for testing
    // }

    uint32_t bufferA = 0;
    uint32_t bufferB = 320;
    uint32_t pixels_top_left_rev = 0;
    uint32_t pixels_top_right_rev = 0;
    uint32_t pixels_bot_left_rev = 0;
    uint32_t pixels_bot_right_rev = 0;

    uint32_t x = 21;
    uint32_t y = 20;

    for (int t = 0; t < N_THETA; t++) { // Iterate over every theta separately
      // if ((t<28) || (t>32)) continue;
      // Transfer first 1280 pixels to CI buffer A
      uint32_t pixel_block_addr = (uint32_t) &sobel[0];
      writeDMA(BUS_START, pixel_block_addr);
      writeDMA(MEMORY_START, bufferA);
      writeDMA(BLOCK_SIZE, 320); // 320 words = 1280 pixels = 2 lines
      writeDMA(BURST_SIZE, 80);
      writeDMA(STAT_CTRL, 1); // start transfer
      waitForDMA();
      writeDMA(STAT_CTRL, 0); // stop transfer

      int theta = t * THETA_RES;
      
      for (uint32_t y = 0; y < 478; y+=2) { // We process 1280 sobel (8bit) pixels at a time (two lines)
        // if (y>2) continue;
        pixel_block_addr = (uint32_t) &sobel[640*(y+2)];

        writeDMA(BUS_START, pixel_block_addr);
        writeDMA(MEMORY_START, bufferB);
        writeDMA(STAT_CTRL, 1); // start transfer bus -> ci
        for (int wordIdx = 0; wordIdx < 160; wordIdx += 2) {
          /*
          Lower Resolution: take 16 pixels at a time from two lines like:
          [P1, P2,  P3,  P4,  P5,  P6,  P7,  P8]  (line y)
          [P9, P10, P11, P12, P13, P14, P15, P16] (line y+1)

          Then we form subpixels like:
          A: [P1,  P2,
              P9,  P10]
          B: [P3,  P4,
              P11, P12]
          C: [P5,  P6,
              P13, P14]
          D: [P7,  P8,
              P15, P16]
          */
          readDMA(bufferA + wordIdx, &pixels_top_left_rev); // This reads 1x32-bit word = 4x8-bit sobel pixel
          readDMA(bufferA + wordIdx + 1, &pixels_top_right_rev);
          readDMA(bufferA + 160 + wordIdx, &pixels_bot_left_rev);
          readDMA(bufferA + 160 + wordIdx + 1, &pixels_bot_right_rev);
          uint32_t pixels_top_left = swap_u32(pixels_top_left_rev);
          uint32_t pixels_top_right = swap_u32(pixels_top_right_rev);
          uint32_t pixels_bot_left = swap_u32(pixels_bot_left_rev);
          uint32_t pixels_bot_right = swap_u32(pixels_bot_right_rev);

          // A: P1, P2, P9, P10
          uint32_t xA = 4*wordIdx;
          uint32_t sobelP1 = (pixels_top_left >> 16) & 1;
          uint32_t sobelP2 = (pixels_top_left >> 24) & 1;
          uint32_t sobelP9 = (pixels_bot_left >> 16) & 1;
          uint32_t sobelP10 = (pixels_bot_left >> 24) & 1;
          uint32_t sobelA = sobelP1 | sobelP2 | sobelP9 | sobelP10;
          
          // B: P3, P4, P11, P12
          uint32_t sobelP3 = pixels_top_left & 1;
          uint32_t sobelP4 = (pixels_top_left >> 8) & 1;
          uint32_t sobelP11 = pixels_bot_left & 1;
          uint32_t sobelP12 = (pixels_bot_left >> 8) & 1;
          uint32_t sobelB = sobelP3 | sobelP4 | sobelP11 | sobelP12;

          // C: P5, P6, P13, P14
          uint32_t sobelP5 = (pixels_top_right >> 16) & 1;
          uint32_t sobelP6 = (pixels_top_right >> 24) & 1;
          uint32_t sobelP13 = (pixels_bot_right >> 16) & 1;
          uint32_t sobelP14 = (pixels_bot_right >> 24) & 1;
          uint32_t sobelC = sobelP5 | sobelP6 | sobelP13 | sobelP14;

          // D: P7, P8, P15, P16
          uint32_t sobelP7 = (pixels_top_right) & 1;
          uint32_t sobelP8 = (pixels_top_right >> 8) & 1;
          uint32_t sobelP15 = (pixels_bot_right) & 1;
          uint32_t sobelP16 = (pixels_bot_right >> 8) & 1;
          uint32_t sobelD = sobelP7 | sobelP8 | sobelP15 | sobelP16;

          // if (theta == ) {
          //   printf("Theta %d, Y %d, X %d: Sobel A=%d, B=%d, C=%d, D=%d\n", theta, y, xA, sobelA, sobelB, sobelC, sobelD);
          // }
          
          // if ((sobelA == 0) && (sobelB == 0) && (sobelC == 0) && (sobelD == 0) && (theta == 45)) {
          //   printf("Theta=45, Y=%d: Acc = %4d\n", y, accumulator[t][100] + accumulator[t][99]);
          // }

          if ((sobelA == 0) && (sobelB == 0) && (sobelC == 0) && (sobelD == 0)) {
            continue; // Skip if no edges in this block
          }

          voteHoughCi(theta, y, xA, sobelA, sobelB, sobelC, sobelD);
        }
        waitForDMA();
        writeDMA(STAT_CTRL, 0); // stop transfer
        // Swap the buffers
        bufferA = bufferA ^ 320; // XOR
        bufferB = bufferB ^ 320;

      } // Y loop

      // Add to the main accumulator
      for (int r = 0; r < RHO_RES; r++) {
        incrementAccumulator(t, r);
      }      

    } // Theta loop

    // Peak Detection (Finding the lines)
    uint16_t threshold = 200; // Minimum votes to be considered a line
    int num_lines = 0;
    int top_lines[5] = {0}; // Array to store the top 5 votes
    int top_theta[5] = {0}; // Array to store the corresponding theta values (indices)
    int top_rho_idx[5] = {0}; // Array to store the corresponding rho indices

    for (int t = 0; t < N_THETA; t++) {
        for (int r = 0; r < RHO_RES; r++) {
          uint16_t acc_value = accumulator[t][r];
          accumulator[t][r] = 0; // Clear accumulator after reading its value
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
        int theta_val = top_theta[i] * THETA_RES;
        printf("%d: Line detected: Theta=%d degrees, Rho=%d pixels, Votes=%d\n", i + 1, theta_val, rho_val, top_lines[i]);
      }
    }
    printf("=====\n");

  } // while

} // main
