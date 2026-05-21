# Roadmap for ESD-Project: Edge Detection

## Software-only version

### Idea
Get RGB image from Camera (`takeSingleImageBlocking`) and process it with:
- Grayscale conversion
- Sobel filter
- Hough transform
  - Find maxima and draw lines on screen (preferably RGB output)

### ToDo
- [x] Sobel Filter
- [ ] Hough Transform
- [ ] Draw lines on RGB frame

## Hardware version

### Idea
Continuously stream RGB image to screen. Take sobel filtered image from camera (`takeSingleImageBlocking`) and process it. Use a DMA with ping-pong buffer and execute Hough-CI on pixels one batch (e.g. line) at a time. Find maximum of Hough accumulator in software and calculate corresponding lines. Tell image streaming where to put these lines.

### ToDo
- [x] Sobel filter, real time streaming
  - [x] Adjust threshold via CI
- [ ] Set up DMA ping-pong (like in Ex6)
- [ ] Hough Custom Instruction
- [ ] Software processing of Hough output
- [ ] Line output on image
