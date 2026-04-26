/*
Author : Till Beyer 25.04.2026
*/

#include <stdint.h>
#include <stdio.h>

#define WRITE_OPERATION (1<<9)
void writeCiMemory(uint32_t address, uint32_t data) { // the ci ID is 0xA5 -> 165 in decimal
  asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(address | WRITE_OPERATION), [in2]"r"(data));
}

void readCiMemory(uint32_t address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(*data):[in1] "r"(address));
}

int main() {
  uint32_t data;

  printf("\n === Test DMA Memory ===\n");

  printf("Check what's there now:\n");
  readCiMemory(0, &data);
  printf("Data at address (000) : %d\n", data);
  readCiMemory(511, &data);
  printf("Data at address (1FF) : %d\n", data);

  printf("\n-Overwrite everything with ones\n");
  for (int i = 0; i < 512; ++i) {
    writeCiMemory(i, 1);
  }

  printf("-Check if everything is one\n");
  for (int i = 0; i < 512; ++i) {
    readCiMemory(i, &data);
    if (data != 1) printf("Whoops, at address (%03X) we have '%d' instead of 1\n", i, data);
  }

  printf("-Write ascending numbers\n");
  for (int i = 0; i < 25; ++i) {
    writeCiMemory(i, 2*i);
  }

  printf("-Check if everything is correct\n");
  for (int i = 0; i < 25; ++i) {
    readCiMemory(i, &data);
    if (data != 2*i) printf("Whoops, at address (%03X) we have '%d' instead of %d\n", i, data, 2*i);
  }

  printf("-Check if rest is untouched\n");
  for (int i = 25; i < 512; ++i) {
    readCiMemory(i, &data);
    if (data != 1) printf("Whoops, at address (%03X) we have '%d' instead of 1\n", i, data);
  }

  printf("Test finished\n");
}
