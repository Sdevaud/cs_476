/*
Author : Till Beyer 26.04.2026
*/

#include <stdint.h>
#include <stdio.h>
#include <swap.h>


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

int main() { 
  printf("\n === Test DMA internal memory ===\n");

  uint32_t data;

  printf("Check what's there now:\n");
  readCi(0, &data);
  printf("Data at address (000) : %d\n", data);
  readCi(511, &data);
  printf("Data at address (1FF) : %d\n", data);

  printf("\n-Overwrite everything with ones\n");
  for (int i = 0; i < 512; ++i) {
    writeCi(i, 1);
  }

  printf("-Check if everything is one\n");
  for (int i = 0; i < 512; ++i) {
    readCi(i, &data);
    if (data != 1) printf("Whoops, at address (%03X) we have '%d' instead of 1\n", i, data);
  }

  printf("-Write ascending numbers\n");
  for (int i = 0; i < 25; ++i) {
    writeCi(i, 2*i);
  }

  printf("-Check if everything is correct\n");
  for (int i = 0; i < 25; ++i) {
    readCi(i, &data);
    if (data != 2*i) printf("Whoops, at address (%03X) we have '%d' instead of %d\n", i, data, 2*i);
  }

  printf("-Check if rest is untouched\n");
  for (int i = 25; i < 512; ++i) {
    readCi(i, &data);
    if (data != 1) printf("Whoops, at address (%03X) we have '%d' instead of 1\n", i, data);
  }


  printf("\n === Test DMA --> Ci-memory ===\n");

  uint32_t desc[10]; // descending numbers
  for (int i = 0; i < 10; ++i) {
      desc[i] = swap_u32(9 - i); // cpu is big-endian, bus is little-endian, so we swap here
  }
  uint32_t desc_addr = 0;
  uint32_t desc_block_size = 10;
  uint32_t desc_burst_size = 2;


  uint32_t ones[256];
  for (int i = 0; i < 256; ++i) {
      ones[i] = swap_u32(1);
  }
  uint32_t ones_addr = 10;
  uint32_t ones_block_size = 256;
  uint32_t ones_burst_size = 16;

  printf("\n-Write array of ascending numbers to Ci-memory\n");
  printf("-Configure registers ...\n");

  writeCi(BUS_START, (uint32_t) &desc[0]);
  writeCi(MEMORY_START, desc_addr);
  writeCi(BLOCK_SIZE, desc_block_size);
  writeCi(BURST_SIZE, desc_burst_size);

  printf("-Start transfer ...\n");
  writeCi(STAT_CTRL, 1);

  printf("-Verify transfer ...\n");
  for (int i = desc_addr; i < desc_addr+desc_block_size; ++i) {
    readCi(i, &data);
    if (data != 9 - (i-desc_addr)) printf("Whoops, at address (%03X) we have '%d' instead of %d\n", i, data, 9-(i-desc_addr));
  }

  
  printf("-Stop transfer ...\n");
  writeCi(STAT_CTRL, 0);


  printf("\n-Write array of ones to Ci-memory\n");
  printf("-Configure registers ...\n");

  writeCi(BUS_START, (uint32_t) &ones[0]);
  writeCi(MEMORY_START, ones_addr);
  writeCi(BLOCK_SIZE, ones_block_size);
  writeCi(BURST_SIZE, ones_burst_size);

  printf("-Start transfer ...\n");
  writeCi(STAT_CTRL, 1);

  printf("-Verify transfer ...\n");
  for (int i = ones_addr; i < ones_addr+ones_block_size; ++i) {
    readCi(i, &data);
    if (data != 1) printf("Whoops, at address (%03X) we have '%d' instead of 1\n", i, data);
  }

  printf("\nTest finished\n");

}
