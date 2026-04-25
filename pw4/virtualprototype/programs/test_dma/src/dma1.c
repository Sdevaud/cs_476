/*
Author : Till Beyer 25.04.2026
*/

#include <stdint.h>
#include <stdio.h>

#define CI_ADDR 0xA5
#define WRITE_OPERATION 1<<9

int main() {
  uint32_t ramAddress, ramData;
  printf("Writing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    asm volatile("l.nios_rrr r0,%[in1],r0,165" ::[in1] "r"(ramAddress | WRITE_OPERATION)); // we clear the memory
  }
  printf("Comparing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(ramData):[in1] "r"(ramAddress)); // we control that the memory is empty
    if (ramData != 0) printf("Error at address 0x%03X : 0x%08X\n", ramAddress, ramData);
  }
  printf("Writing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    asm volatile("l.nios_rrr r0,%[in1],%[in2],165" ::[in1] "r"(ramAddress | WRITE_OPERATION), [in2]"r"(ramAddress ^ 0xFFFFFF)); // we fill the memory
  }
  printf("Comparing\n");
  for (ramAddress = 0; ramAddress < 512; ramAddress++) {
    asm volatile("l.nios_rrr %[out1],%[in1],r0,165" :[out1]"=r"(ramData):[in1] "r"(ramAddress)); // we control that the memory is correct
    if (ramData != (ramAddress ^ 0xFFFFFF)) printf("Error at address 0x%03X : 0x%08X\n", ramAddress, ramData);
  }
}
