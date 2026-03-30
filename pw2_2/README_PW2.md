# Embedded system design PW2 Part 1/2

### **Group 13:**
- Sébastien Devaud (315144)
- Till Beyer (414801)

### launch
- in `virtualprotype/virtualprototype/programs/grayscale` laucnh `make`
- in`virtualprotype/virtualprototype/systems/singleCore/sandbox` launch `../scripts/synthesizeOr1420.sh`


### Content
This archive contains the code implementation for part 2 of the PW2. The following files/directories were added or changed:

- `virtualprototype/programs/grayscale/src/grayscale.c`: Contains the code running the grayscale conversion. We added the reads and writes from and to the custom instruction. with the macro at the beginings, you can choose to use the custom instruction or not.

- `virtualprototype/modules/grayscaleCi/verilog`: Contains the verilog files defining the profile constom instruction (`profileCi.v`), the counter (`counter.v`) and a testbench for testing the custom instruction (`profileCi_tb.v`). The testbench can be run in iverilog with the command `iverilog -s profileCiTestbench -o testbench profileCi.v counter.v profileCi_tb.v`. We also added the module of the grayscale.

- `virtualprototype/systems/singleCore/verilog/or1420SingleCore.v`: Here we added the module of the grayscale at the end.

- `virtualprototype/systems/singleCore/scripts/yosysOr1420.script`: Added one line to include the `grayscale.v`.

- you can see here the performance for the code without the CI : 

CPU-Cycles : 29 129 333

CPU-Stalls : 17 756 326

CPU-Idles  : 16 754 135


- and here with the CI : 

CPU-Cycles : 8 289 648

CPU-Stalls : 6 753 703

CPU-Idles  : 3 602 014