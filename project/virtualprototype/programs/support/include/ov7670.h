#ifndef __OV7670_H__
#define __OV7670_H__
#include <stdint.h>

  /*
   * this code is a copy/modification of the code presented:
   * https://github.com/ComputerNerd/ov7670-no-ram-arduino-uno
   */

typedef enum resolution_t {VGA,QVGA,QQVGA} resolution;
typedef struct camParam_t {
  uint32_t nrOfPixelsPerLine;
  uint32_t nrOfLinesPerImage;
  uint32_t pixelClockInkHz;
  uint32_t framesPerSecond;
} camParameters;

int readOv7670Register( int reg );
void writeOv7670Register(int reg , int value);
camParameters initOv7670(resolution res);
void takeSingleImageBlocking(uint32_t framebuffer);
void takeSingleImageNonBlocking(uint32_t framebuffer);
void waitForNextImage();
void enableContinues(uint32_t framebuffer);
void disableContinues();
void setSobelThreshold(uint8_t threshold);
void setSobelMode(int mode);
void setLineParameters(uint32_t theta0, uint32_t rho0, uint32_t theta1, uint32_t rho1, uint32_t theta2, uint32_t rho2);
uint32_t pollSingleShotDone();

#endif
