
# Embedded System Design – Final Project

## Group 23

- Sébastien Devaud (315144)
- Till Beyer (414801)


# Project README

## Preamble

Our initial goal was to implement an edge detection pipeline based on the following processing chain:

```text
RGB -> Grayscale -> Sobel -> Hough Transform -> Edge Detection
```

After several weeks of development, the edge detection algorithm was partially working, but it was not fast enough to be considered real-time. To ensure that we had a stable final result, we started working in parallel on the base project: motion detection using Sobel filtering.

In the end, the Hough Transform version was not selected as the main project because its performance was not sufficient. However, the corresponding files are still included in the submission for reference.

## Summary

* Algorithm
* Modify file and How to Run
* Result analysis and benchmarks
* Hough Transform attempt

## 1. Algorithm

We reused the streaming approach from PW6 to apply the Sobel transformation directly in the video pipeline, similarly to the grayscale conversion. Motion detection is then performed using a ping-pong DMA implementation.

This reduces unnecessary pixel transfers and conversions, making the processing much faster and more suitable for real-time execution.

The main drawback is that motion detection is done on black and white Sobel pixels instead of grayscale values. This makes the result more sensitive to noise, so additional operations over the full pixel set are required to make the detection more stable.

## 2. How find modify file and How to Run


## 3. Result Analysis and Benchmarks

## 4. Hough Transform Attempt

