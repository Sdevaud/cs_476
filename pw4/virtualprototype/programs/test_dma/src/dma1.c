/*
Author : Till Beyer 25.04.2026
*/

#include <stdint.h>
#include <stdio.h>

#define CI_ADDR 0xA5

void writeCiMemory(uint32_t address, uint32_t data) {
  uint32_t writeOperation= 1<<9;
  asm volatile("l.nios_rrr r0,%[in1],%[in2],%[id]" ::[in1] "r"(address | writeOperation), [in2]"r"(data), [id] "r"(CI_ADDR));
}

void readCiMemory(uint32_t address, uint32_t *data) {
  asm volatile("l.nios_rrr %[out1],%[in1],r0,%[id]" :[out1]"=r"(*data):[in1] "r"(address), [id] "r"(CI_ADDR));
}

int main() {

  uint32_t ramAddress, ramData;
  printf("Writing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    writeCiMemory(ramAddress, 0);
  }
  printf("Comparing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    readCiMemory(ramAddress, &ramData);
    if (ramData != 0) printf("Error at address 0x%03X : 0x%08X\n", ramAddress, ramData);
  }
  printf("Writing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    writeCiMemory(ramAddress, ramAddress ^ 0xFFFFFF);
  }
  printf("Comparing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    readCiMemory(ramAddress, &ramData);
    if (ramData != (ramAddress ^ 0xFFFFFF)) printf("Error at address 0x%03X : 0x%08X\n", ramAddress, ramData);
  }
}
