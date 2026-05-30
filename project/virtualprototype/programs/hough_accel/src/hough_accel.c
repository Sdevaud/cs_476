#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>

#define __profiling__

// === DMA Config ===
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


// == Hough Transform Config ===
#define THETA_RES 3
#define N_THETA (int)(180 / THETA_RES)
#define N_RHO 200
#define MAX_RHO 800
#define RHO_RES 8 // Scale factor to fit rho into accumulator

uint16_t accumulator[N_THETA][N_RHO];

static inline void voteHoughCi(int theta, uint32_t y, uint32_t xA, uint32_t sobelVotes) {
  uint32_t valueA = theta | (y << 8) | (xA << 18) | sobelVotes;
  asm volatile("l.nios_rrr r0,%[in1], r0,167" ::[in1] "r"(valueA));
}

static inline void incrementAccumulator(int theta_idx, int rho_idx) {
  uint32_t voteCount;
  // Read vote count from CI memory
  asm volatile("l.nios_rrr %[out1],%[in1],%[in2],167" :[out1]"=r"(voteCount) :[in1] "r"(rho_idx), [in2]"r"(1<<30));
  accumulator[theta_idx][rho_idx] = voteCount;
}

static inline void voteCountCi(uint32_t pixelsTopReversed, uint32_t pixelsBotReversed, uint32_t *voteCount) {
  asm volatile("l.nios_rrr %[out1],%[in1], %[in2],166" :[out1]"=r"(*voteCount) :[in1] "r"(pixelsTopReversed), [in2] "r"(pixelsBotReversed));
}

// === Peak Finding Config ===
#define TOP_LINE_COUNT 3
#define MERGE_RHO_DELTA (6 * RHO_RES)
#define MERGE_THETA_DELTA (2 * THETA_RES)
#define THRESHOLD_PEAK 200
#define MERGE_DEBUG 1

typedef struct {
  uint16_t votes;
  uint16_t peak_votes;
  uint32_t theta_weight_sum;
  uint32_t rho_weight_sum;
  int theta_idx;
  int rho_idx;
} LinePeak;

static inline int rhoIdxToPixels(int rho_idx) {
  return (rho_idx * RHO_RES) - MAX_RHO;
}

static inline int thetaIdxToDegrees(int theta_idx) {
  return theta_idx * THETA_RES;
}

  
uint8_t sobel[640*480];
uint16_t rgb565[640*480];

int main () {
  volatile uint32_t result;
  volatile unsigned int *vga = (unsigned int *) 0X50000020;
  camParameters camParams;
  vga_clear();

  // Clear Ci memory (just in case)
  for (int r = 0; r < N_RHO; r++) {
    incrementAccumulator(0, r);
  }

  // Clear main accumulator
  for (int t = 0; t < N_THETA; t++) {
    for (int r = 0; r < N_RHO; r++) {
        accumulator[t][r] = 0;
    }
  }

  // printf("Starting Line Detection!\n" );
  camParams = initOv7670(VGA);
  // printf("...\n" );
  result = (camParams.nrOfPixelsPerLine <= 320) ? camParams.nrOfPixelsPerLine | 0x80000000 : camParams.nrOfPixelsPerLine;
  vga[0] = swap_u32(result);
  result =  (camParams.nrOfLinesPerImage <= 240) ? camParams.nrOfLinesPerImage | 0x80000000 : camParams.nrOfLinesPerImage;
  vga[1] = swap_u32(result);
  vga[2] = swap_u32(1); // 2: 8bit pixels, 1: 16bit pixels
  vga[3] = swap_u32((uint32_t) &rgb565[0]);

  setSobelThreshold(100);

#ifdef __profiling__
  volatile uint32_t  cycles, stall, idle;
  asm volatile ("l.nios_rrr r0,r0,%[in2],0xC"::[in2]"r"(7));
#endif
  
  while(1) {
      
    setSobelMode(0);
    takeSingleImageBlocking((uint32_t) &rgb565[0]);

    setSobelMode(1);
    takeSingleImageBlocking((uint32_t) &sobel[0]);

#ifdef __profiling__
    asm volatile ("l.nios_rrr r0,r0,%[in2],0xC"::[in2]"r"(7));
#endif

    // dummy data into sobel
    // for (int i = 0; i < 640*480; i++) {
    //   if (640*8 <= i && i < 640*10) sobel[i] = 255; // Horizontal line at the top
    //   // else if (i % 641 == 100) sobel[i] = 255; // Diagonal line TL to BR
    //   else if (i % 641 == 0) sobel[i] = 255; // Diagonal line TL to BR
    //   // else if (i % 641 == 630) sobel[i] = 255; // Diagonal line TR to BL
    //   else if (i % 641 == 530) sobel[i] = 255; // Diagonal line TR to BL
    //   // else if (i % 640 == 300) sobel[i] = 255; // Vertical line
    //   // else if (i % 640 == 500) sobel[i] = 255; // Vertical line
    //   else sobel[i] = 0; 
    // }

    uint32_t bufferA = 0;
    uint32_t bufferB = 320;
    uint32_t pixels_top_left_rev = 0;
    uint32_t pixels_top_right_rev = 0;
    uint32_t pixels_bot_left_rev = 0;
    uint32_t pixels_bot_right_rev = 0;
    uint32_t voteCountLeft = 0;
    uint32_t voteCountRight = 0;

    for (int t = 0; t < N_THETA; t++) { // Iterate over every theta separately
      // Transfer first 1280 pixels to CI buffer A
      uint32_t pixel_block_addr = (uint32_t) &sobel[0];
      writeDMA(BUS_START, pixel_block_addr);
      writeDMA(MEMORY_START, bufferA);
      writeDMA(BLOCK_SIZE, 320); // 320 words = 1280 pixels = 2 lines
      writeDMA(BURST_SIZE, 160);
      writeDMA(STAT_CTRL, 1); // start transfer
      waitForDMA();
      writeDMA(STAT_CTRL, 0); // stop transfer

      int theta = t * THETA_RES;
      
      for (uint32_t y = 0; y < 478; y+=2) { // We process 1280 sobel (8bit) pixels at a time (two lines)
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
          // */
          readDMA(bufferA + wordIdx, &pixels_top_left_rev); // This reads 1x32-bit word = 4x8-bit sobel pixel
          readDMA(bufferA + wordIdx + 1, &pixels_top_right_rev);
          readDMA(bufferA + 160 + wordIdx, &pixels_bot_left_rev);
          readDMA(bufferA + 160 + wordIdx + 1, &pixels_bot_right_rev);

          uint32_t xA = 4*wordIdx;

          if (pixels_top_left_rev == 0 && pixels_top_right_rev == 0 && 
            pixels_bot_left_rev == 0 && pixels_bot_right_rev == 0) {
            continue; 
          }

          voteCountCi(pixels_top_left_rev, pixels_bot_left_rev, &voteCountLeft);
          voteCountCi(pixels_top_right_rev, pixels_bot_right_rev, &voteCountRight);

          uint32_t votes = (voteCountLeft >> 2) | voteCountRight;

          voteHoughCi(theta, y, xA, votes);

        }
        waitForDMA();
        writeDMA(STAT_CTRL, 0); // stop transfer
        // Swap the buffers
        bufferA = bufferA ^ 320; // XOR
        bufferB = bufferB ^ 320;

      } // Y loop

      // Add to the main accumulator
      for (int r = 0; r < N_RHO; r++) {
        incrementAccumulator(t, r);
      }      

    } // Theta loop

    // printf("Finished processing one frame. Performing peak detection...\n");
    // continue;

    // ==========================================
    // 1. Peak Detection via Non-Maximum Suppression
    // ==========================================
    static LinePeak merged_lines[N_THETA * N_RHO];
    int merged_line_count = 0;

    for (int t = 0; t < N_THETA; t++) {
        for (int r = 0; r < N_RHO; r++) {
            uint16_t acc_value = accumulator[t][r];
            if (acc_value <= THRESHOLD_PEAK) {
                accumulator[t][r] = 0; // Clear it out
                continue;
            }

            // Check 8-way neighbors to ensure this cell is a local peak
            int is_local_max = 1;
            for (int dt = -1; dt <= 1; dt++) {
                for (int dr = -1; dr <= 1; dr++) {
                    int nt = t + dt;
                    int nr = r + dr;
                    
                    // Boundary checking
                    if (nt >= 0 && nt < N_THETA && nr >= 0 && nr < N_RHO) {
                        // If a neighbor has MORE votes, this cell is not the peak
                        if (accumulator[nt][nr] > acc_value) {
                            is_local_max = 0;
                            break;
                        }
                    }
                }
                if (!is_local_max) break;
            }

            // Clear accumulator cell now that we are done with it
            accumulator[t][r] = 0;

            if (is_local_max && merged_line_count < (N_THETA * N_RHO)) {
                merged_lines[merged_line_count].votes = acc_value;
                merged_lines[merged_line_count].theta_idx = t;
                merged_lines[merged_line_count].rho_idx = r;
                merged_line_count++;
            }
        }
    }

    // ==========================================
    // 2. Proximity Merge Pass 
    // ==========================================
    // Now that we only have true local peaks, merge peaks that are too close
    for (int i = 0; i < merged_line_count - 1; i++) {
        if (merged_lines[i].votes == 0) continue; // Skip already swallowed lines

        for (int j = i + 1; j < merged_line_count; j++) {
            if (merged_lines[j].votes == 0) continue;

            int theta_delta = thetaIdxToDegrees(merged_lines[i].theta_idx) - thetaIdxToDegrees(merged_lines[j].theta_idx);
            if (theta_delta < 0) theta_delta = -theta_delta;

            int rho_delta = rhoIdxToPixels(merged_lines[i].rho_idx) - rhoIdxToPixels(merged_lines[j].rho_idx);
            if (rho_delta < 0) rho_delta = -rho_delta;

            // If they fall within your defined window, merge them!
            if (theta_delta <= MERGE_THETA_DELTA && rho_delta <= MERGE_RHO_DELTA) {
                // Keep the one with higher votes, invalidate the weaker one
                if (merged_lines[i].votes >= merged_lines[j].votes) {
                    merged_lines[i].votes += merged_lines[j].votes; // optionally pool votes
                    merged_lines[j].votes = 0; // eliminate j
                } else {
                    merged_lines[j].votes += merged_lines[i].votes;
                    merged_lines[i].votes = 0; // eliminate i
                    break; // i is dead, stop checking neighbors for it
                }
            }
        }
    }
    

    // Sort lines by vote count
    for (int i = 0; i < merged_line_count - 1; i++) {
      for (int j = i + 1; j < merged_line_count; j++) {
        if (merged_lines[j].votes > merged_lines[i].votes) {
          LinePeak tmp = merged_lines[i];
          merged_lines[i] = merged_lines[j];
          merged_lines[j] = tmp;
        }
      }
    }


    // Print the top 3 merged lines detected
    uint32_t rho_vals [TOP_LINE_COUNT] = {0};
    uint32_t theta_vals [TOP_LINE_COUNT] = {0};
    for (int i = 0; i < TOP_LINE_COUNT && i < merged_line_count; i++) {
        rho_vals[i] = merged_lines[i].rho_idx;
        theta_vals[i] = merged_lines[i].theta_idx * THETA_RES;
        // printf("%d: Line detected: Theta=%d degrees, Rho=%d pixels, Votes=%d\n", i + 1, theta_vals[i], rhoIdxToPixels(rho_vals[i]), merged_lines[i].votes);
      }
    setLineParameters(theta_vals[0], rho_vals[0], theta_vals[1], rho_vals[1], theta_vals[2], rho_vals[2]);
    // printf("=====\n");

#ifdef __profiling__
    asm volatile ("l.nios_rrr %[out1],r0,%[in2],0xC":[out1]"=r"(cycles):[in2]"r"(1<<8|7<<4));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(stall):[in1]"r"(1),[in2]"r"(1<<9));
    asm volatile ("l.nios_rrr %[out1],%[in1],%[in2],0xC":[out1]"=r"(idle):[in1]"r"(2),[in2]"r"(1<<10));
    printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
#endif

    // Draw lines on RGB image

  } // while

} // main
