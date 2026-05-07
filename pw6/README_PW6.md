# Embedded system design PW4

### **Group 23:**

* Sébastien Devaud (315144)
* Till Beyer (414801)

---

### Launch
Les trois exercicise peuvent être trouver à ces emplacements : 

1)   /virtualprototype/programs/grayscale_dma/src/
   vous y trouverez le fichier grayscale_dma.c qui utilise la solution avec le DMA, nous avons obtenues ces pefromances dans l'état actule : 

    On voit ici l'Impact du DMA qui permet de décharger le CPU lorsqu'il fait ces opérations de 
  

2) 

---

### Content

This archive contains the code implementation for PW4. In each of the exercises the following files/directories were added or modified:


* `virtualprototype/programs/dma/src/dmaX.c`
  Contains code to test the functionality of the given custom instruction.


* `virtualprototype/modules/dma/verilog`
  Contains the Verilog files defining:

  * the dual ported ssram (`dual_ported.v`)
  * the dma controller (`ramDmaCi_X.v`)
  * a testbench for testing the custom instruction (`ramDmaCi_1_tb.v`, only for exercise 1)

  The testbench can be run with iverilog using:

  ```
  iverilog -s ramDmaCi_tb -o testbench ramDmaCi_1_tb.v ramDmaCi_1.v dual_ported.v ramDmaCi_1_tb.v
  ```


* `virtualprototype/systems/singleCore/verilog/or1420SingleCore.v`
  We implemented the dma module and added the necessary connections.


* `virtualprototype/systems/singleCore/scripts/yosysOr1420.script`
  Added two lines to include `ramDmaCi_X.v` and `dual_ported.v`.

### Note
openFPGALoader was causing problems on our machines so that we replaced it with `ecpprog -S` in the `synthesizeOr1420.sh` script
