# Embedded system design PW2 Part 1/2

### **Group 13:**

* Sébastien Devaud (315144)
* Till Beyer (414801)

---

### launch

* in `virtualprotype/virtualprototype/programs/grayscale` launch `make`
* in `virtualprotype/virtualprototype/systems/singleCore/sandbox` launch `../scripts/synthesizeOr1420.sh`

---

### Content

This archive contains the code implementation for part 2 of the PW2. The following files/directories were added or modified:


* `virtualprototype/programs/grayscale/src/grayscale.c`
  Contains the code running the grayscale conversion.
  We added the reads and writes to the custom instruction. With the macro at the beginning, you can choose to use the custom instruction or not.


* `virtualprototype/modules/grayscaleCi/verilog`
  Contains the Verilog files defining:

  * the profiling custom instruction (`profileCi.v`)
  * the counter (`counter.v`)
  * a testbench for testing the custom instruction (`profileCi_tb.v`)

  The testbench can be run with iverilog using:

  ```
  iverilog -s profileCiTestbench -o testbench profileCi.v counter.v profileCi_tb.v
  ```

  We also added:

  * the grayscale module (`grayscale.v`)
  * a simpler version of the grayscale (`grayscale_2.v`) using direct multiplications

  This simpler version seems to have the same performance.
  In the testbench, the executed version is `grayscale.v`.


* `virtualprototype/systems/singleCore/verilog/or1420SingleCore.v`
  We added the grayscale module at the end of the file.


* `virtualprototype/systems/singleCore/scripts/yosysOr1420.script`
  Added one line to include `grayscale.v`.

---

### Performance results

* without the custom instruction:

```
CPU-Cycles : 29 129 333
CPU-Stalls : 17 756 326
CPU-Idles  : 16 754 135
```

* with the grayscale custom instruction:

```
CPU-Cycles : 8 204 047
CPU-Stalls : 6 668 095
CPU-Idles  : 3 602 631
```

* with the grayscale_2 custom instruction:

```
CPU-Cycles : 8 201 920
CPU-Stalls : 6 665 968
CPU-Idles  : 3 602 662
```

---

### Notes

* The two grayscale implementations (`grayscale.v` and `grayscale_2.v`) show almost identical performance.
* The custom instruction significantly improves execution time compared to the software-only version.
