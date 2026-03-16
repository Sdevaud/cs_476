# Embedded system design PW2 Part 1/2

### **Group 13:**
- Sébastien Devaud (315144)
- Till Beyer (414801)


### Content
This archive contains the code implementation for part 1 of the PW2. The following files/directories were added or changed:

- `virtualprototype/programs/grayscale/src/grayscale.c`: Contains the code running the grayscale conversion. We added the reads and writes from and to the custom instruction.

- `virtualprototype/programs/grayscale/verilog`: Contains the verilog files defining the profile constom instruction (`profileCi.v`), the counter (`counter.v`) and a testbench for testing the custom instruction (`profileCi_tb.v`). The testbench can be run in iverilog with the command `iverilog -s profileCiTestbench -o testbench profileCi.v counter.v profileCi_tb.v`

- `virtualprototype/systems/singleCore/verilog/or1420SingleCore.v`: Here only the profileCi module was added at the bottom of the file as well as the necessary "or"-commands further up.

- `virtualprototype/systems/singleCore/scripts/yosysOr1420.script`: Added two lines to include the `profileCi.v` and `counter.v` verilog files in the synthesis.

- `virtualprototype/systems/singleCore/scripts/synthesizeOr1420.sh`: replace `openFPGALoader` with `ecpprog -S or1420SingleCore.bit`
