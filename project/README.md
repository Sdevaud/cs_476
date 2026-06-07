# Embedded System Design – Final Project

## Group 23

* Sébastien Devaud (315 144)

## Summary

* Modified files and how to run
* Algorithm
* Result analysis and benchmarks
* Conclusion

## 1. Modified Files and How to Run

All modified Verilog files are located in:

```text
project/virtualprototype/modules/sobel/verilog
```

This folder contains:

```text
test_bench/          Verilog test benches
camera_optimised.v   Camera module with direct streaming conversion
sobel.v              Sobel computation module
dice.v
jaccard.v
white_counter.v
complementary.v
threshold.v          Method using the percentage of pixel changes
ram640640dp.v        Memory modules
ram2kdp.v            Memory modules from previous PW
rgb565Grayscale.v    Solution from previous PW
rgb565ISE.v          Solution from previous PW
```

The following files were adapted to connect the new modules to the system:

```text
yosysOr1420.script
or1420SingleCore.v
```
### Run 

Most of the added code is located near the end of these files, except for the camera module.

The software projects are located in:

```text
project/virtualprototype/programs/sobel                 Main project
project/virtualprototype/programs/sobel_only_c          Only C project, as requested
```

At the top of the file `/sobel/src/sobel.c` in the main project, there are three defines for the three different methods used to detect motion. They can be commented/uncommented to test each method. The best one, according to the results, is `__Jaccard__`:

```text
#define __profiling__
#define __Jaccard__
// #define __Dice__
// #define __Percent__
```

For the hardware part, go to `project/virtualprototype/systems/singleCore/scripts/yosysOr1420.script` and comment/uncomment the following lines as mentioned:

```text
# read -sv ../../../modules/camera/verilog/camera_grayscale.v       for the only_C project
# read -sv ../../../modules/sobel/verilog/camera_optimised.v        for the main project
# read -sv ../../../modules/camera/verilog/camera.v                 for the RGB camera
```
`Note: The project/virtualprototype/programs/test folder contains the swap ptr version explained below. This version is not relevant for the graduation, but is kept to show that it was implemented.`
## 2. Algorithm

### 2.1 Sobel

We reused the streaming approach from PW6 to apply the Sobel transformation directly in the video pipeline, similarly to the grayscale conversion. Motion detection is then performed using a ping-pong DMA implementation.

To apply the Sobel filter directly inside the `camera` module, we built the required `3x3` pixel window and handled the image borders. In our implementation, border pixels are assumed to be black.

To simplify border management, three image lines are loaded and stored in memory. After applying the Sobel filter, the line buffers are rotated to fetch the next line.

Another issue was the output rate. The previous module sent `4` pixels per cycle, while the Sobel filter computes only `1` pixel per cycle. Therefore, the pipeline had to be slowed down and grouped into `4`-word transfers to remain consistent with the previous grayscale conversion.

Source: https://homepages.inf.ed.ac.uk/rbf/HIPR2/sobel.htm

### 2.2 Motion Detection

Updating the streaming pipeline reduces unnecessary pixel transfers and conversions, making the processing faster and more suitable for real-time execution.

To compute motion detection, the previous frame must be kept in memory. We therefore use two frame buffers: one for the current frame and one for the previous frame. To avoid extra transfers when clearing data, we also added a third buffer filled with black pixels and simply swap pointers when needed.

The DMA memory is divided into four parts:

* two buffers for the previous frame;
* two buffers for the current frame.

These buffers are used in a ping-pong scheme between DMA memory and global memory. During each transfer, the CPU computes the number of white pixels and the overlap between the current and previous frame, depending on the selected metric. Once the computation is done, a final DMA transfer copies the current frame into the previous-frame buffer for the next iteration.

The main drawback is that motion detection is performed on black-and-white Sobel pixels instead of grayscale values. This makes the result more sensitive to noise, so the detection must be computed over the full pixel set to improve stability.

We tested three different metrics to detect motion. Let $A$ and $B$ be the sets of white pixels in the current frame and the previous frame, respectively.

### Jaccard distance

$$
d_J(A, B) = 1 - \frac{|A \cap B|}{|A \cup B|} > \text{threshold}
$$

This metric measures both similarity and diversity.

Source: https://fr.wikipedia.org/wiki/Indice_et_distance_de_Jaccard

### Dice distance

$$
d_D(A, B) = 1 - \frac{2|A \cap B|}{|A| + |B|} > \text{threshold}
$$

This metric is based on the Dice similarity coefficient and gives more weight to the overlap between the two sets.

Source: https://fr.wikipedia.org/wiki/Indice_de_S%C3%B8rensen-Dice

### Percentage variation

$$
d_P(A, B) = \left|100 - \frac{|B| \cdot 100}{|A|}\right| > \text{threshold}
$$

This method compares the number of white pixels between two consecutive frames. If the variation exceeds a given percentage threshold, motion is detected.

## 3. Result Analysis and Benchmarks

For the results, we compare two aspects: the software optimization of the DMA pipeline, and the metric used for motion detection.
All measurements are averaged over `100` frames to reduce variance.

For the first comparison, the Jaccard distance is used. For the second one, the double DMA implementation is used.

### DMA Optimization

| Method        |      Cycles |       Stall |       Idle | Comment                                                                |
| ------------- | ----------: | ----------: | ---------: | ---------------------------------------------------------------------- |
| Simple DMA    |   3 208 063 |   1 204 529 |  1 135 196 | Loads the first frame, computes Jaccard while loading the second frame |
| Double DMA    |   3 007 144 |   1 320 288 |    958 238 | Splits the loop so that DMA transfers run continuously                 |
| Grayscale DMA |   3 021 176 |     458 948 |  1 440 572 | Reference DMA implementation for grayscale conversion                  |
| swap ptr      |   2 083 313 |   1 018 154 |    978 738 | Try to avoid DMA out with a ptr ping pong                              |
| Only C        | 139 429 313 | 110 260 984 | 61 753 400 | Pure software implementation                                           |

In the `simple DMA version`, both frames must be loaded into the DMA memory. The first frame is loaded first, then the Jaccard distance is computed while the second frame is being transferred.

In the `double DMA version`, the processing loop is split so that the DMA keeps running continuously. This is the version kept in the final implementation.

In the `swap ptr` version, the idea is to remove the copy into the previous-frame buffer by swapping the screen display pointer with the image acquisition pointer.
If this approach works, it gives a `33%` performance improvement. Motion detection works correctly, but for an unknown reason the video output flickers, because the display pointer keeps alternating between the previous frame and the current frame.

The double DMA version improves performance by about `6%`, which suggests that the CPU comparisons take slightly longer than one DMA pass. We also observe that stalls increase while idle cycles decrease. This is typically because the CPU is more often in conflict with the DMA. In conclusion, a better balance between DMA transfers and CPU operations could still be investigated.

The pure C version is around `40x` slower, even though the operations are simple. This shows that the main bottleneck comes from elementary operations and memory accesses on arrays. The final implementation also reaches performance close to the grayscale DMA version, despite doing more processing.

### Motion Detection Metric

| Method  |    Cycles |     Stall |      Idle | Comment                                                              |
| ------- | --------: | --------: | --------: | -------------------------------------------------------------------- |
| Percent | 2 917 793 | 1 264 559 |   935 456 | Fastest, only counts white pixels in the current frame               |
| Jaccard | 3 007 144 | 1 320 288 |   958 238 | Best practical result, more robust to spatial changes                |
| Dice    | 3 010 902 | 1 219 496 | 1 004 671 | Similar performance to Jaccard, but less robust for motion detection |

The percentage method is the fastest, since it only compares the number of white pixels between frames. However, it is not robust: if the same number of pixels changes position, no motion is detected. This makes the method unsuitable.

Dice and Jaccard have almost the same performance, but Jaccard gives better practical results, probably because it better accounts for the diversity of the changed regions.

## 4. Conclusion

The final implementation achieves good performance in terms of total cycle count. The main remaining bottlenecks are the DMA cycles caused by ping-pong buffering and the final DMA output.

One possible improvement would be to swap buffer pointers instead of copying data. This approach was tested and gave significantly better results, but it introduced a flickering issue in the video output that we were not able to fix. This optimization mainly targets the idle cycles.

For the DMA part, another possible improvement would be to better balance CPU processing and DMA transfers, as discussed previously. Increasing the DMA buffer size could also be tested to reduce idle time.

This project also highlighted several aspects of micro-optimization:

* Elementary operations can be expensive (`+`, `-`, `&&`, `||`, etc.), and moving them to Verilog modules can improve performance.
* The compiler can optimize multiplications/divisions into shifts when constants are known.
* The `volatile` keyword can significantly slow down execution and should be used carefully.
* Duplicating code to avoid `if` statements can improve performance.
* Declaring or allocating variables inside a loop does not have a major impact.
* Reading from and writing to arrays is expensive and should be moved to hardware when possible.
* Bit width and signed/unsigned handling are important for both correctness and performance.
* Overall, real performance must be measured and pipelined experimentally; theory alone is not enough.



## Filtre de Sobel

On considère une fenêtre de pixels $3 \times 3$ autour du pixel courant :

$$
I =
\begin{bmatrix}
p_{1} & p_{2} & p_{3} \\
p_{4} & p_{5} & p_{6} \\
p_{7} & p_{8} & p_{9}
\end{bmatrix}
$$

Les deux noyaux du filtre de Sobel sont :

$$
G_x =
\begin{bmatrix}
-1 & 0 & 1 \\
-2 & 0 & 2 \\
-1 & 0 & 1
\end{bmatrix}
$$

$$
G_y =
\begin{bmatrix}
1 & 2 & 1 \\
0 & 0 & 0 \\
-1 & -2 & -1
\end{bmatrix}
$$

L'application des deux noyaux sur la fenêtre de pixels donne :

$$
S_x =
\begin{bmatrix}
-1 & 0 & 1 \\
-2 & 0 & 2 \\
-1 & 0 & 1
\end{bmatrix}
*
\begin{bmatrix}
p_{1} & p_{2} & p_{3} \\
p_{4} & p_{5} & p_{6} \\
p_{7} & p_{8} & p_{9}
\end{bmatrix}
$$

$$
S_y =
\begin{bmatrix}
1 & 2 & 1 \\
0 & 0 & 0 \\
-1 & -2 & -1
\end{bmatrix}
*
\begin{bmatrix}
p_{1} & p_{2} & p_{3} \\
p_{4} & p_{5} & p_{6} \\
p_{7} & p_{8} & p_{9}
\end{bmatrix}
$$

En développant les multiplications, on obtient :

$$
S_x = (-1 \cdot p_1) + (0 \cdot p_2) + (1 \cdot p_3)
+ (-2 \cdot p_4) + (0 \cdot p_5) + (2 \cdot p_6)
+ (-1 \cdot p_7) + (0 \cdot p_8) + (1 \cdot p_9)
$$

Ce qui se simplifie en :

$$
S_x = -p_1 + p_3 - 2p_4 + 2p_6 - p_7 + p_9
$$

Pour le gradient vertical :

$$
S_y = (1 \cdot p_1) + (2 \cdot p_2) + (1 \cdot p_3)
+ (0 \cdot p_4) + (0 \cdot p_5) + (0 \cdot p_6)
+ (-1 \cdot p_7) + (-2 \cdot p_8) + (-1 \cdot p_9)
$$

Ce qui se simplifie en :

$$
S_y = p_1 + 2p_2 + p_3 - p_7 - 2p_8 - p_9
$$

La magnitude du gradient est ensuite calculée avec :

$$
G = \sqrt{S_x^2 + S_y^2}
$$

Une approximation souvent utilisée pour réduire les calculs est :

$$
G \approx |S_x| + |S_y|
$$