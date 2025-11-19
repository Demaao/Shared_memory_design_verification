
# Shared Memory System – Butterfly Network Verification

A complete shared-memory design and verification project implementing a multi-stage Butterfly Network (BN) in Verilog, including full RTL modules, a self-checking testbench, and automated simulation scripts.  
This repository captures both architectural design and verification workflows similar to real hardware development environments.

---

## Project Overview

This project implements a **scalable shared-memory communication fabric** based on a Butterfly Network topology.  
Each core sends memory requests (read/write) through a forwarding network, interacts with dual-port RAM modules, and receives responses through a backward network with arbitration, buffering, and collision handling.

The verification environment stresses the design under different traffic modes and automatically reports:
- Switch collisions  
- Memory collisions  
- Latency (average and max)  
- Total drops  
- End-to-end correctness  

The entire flow is fully automated using provided scripts.

> **Note:** The architectural design supports scalability for **K values ranging from 2 to 10**, where `K_LOG2` determines the number of cores and modules.  
> Verification and detailed performance evaluation were performed specifically for **K = 5**, corresponding to **32 cores/modules**, with representative results documented in the accompanying **PDF report** included in this repository.

---

## Key Features

### RTL Design
- **switch2x2** – routing logic with valid signals, collision detection, priority handling, and internal buffering  
- **Dual-Port RAM** – parallel memory access for multiple cores  
- **bitflip_network** – complete forward and backward multi-stage network  
- **Address hashing module** – maps each core to its destination memory module  
- **Collision detection bus** – cycle-accurate reporting of switch conflicts  

### Verification Environment
- Self-checking **testbench** for the full network  
- Randomized traffic generation (READ, WRITE, MIXED)  
- Automatic detection of routing conflicts and invalid drops  
- Scoreboarding for correctness tracking  
- Measurement of latency, throughput, and collision statistics  

### Automation Scripts
- **run_all.bat** – executes all test modes (`READ_ONLY`, `WRITE_ONLY`, `MIXED_RW`)  
- Output logs automatically stored under the `simulation/` directory  
- Each log includes:
  ```
  Total drops:
  Total switch collisions:
  Total memory collisions:
  Global Average Latency:
  Global Max Latency:
  ```

---

## Repository Structure

```
Shared_memory_design_verification/
├── rtl/
│   ├── switch2x2.v
│   ├── dual_port_ram.v
│   ├── bitflip_network.v
│   ├── types.vh
│   └── config.vh
├── tb/
│   ├── tb_butterfly_network.v
├── simulation/
│   ├── simulation_K5_READ_ONLY.txt
│   ├── simulation_K5_WRITE_ONLY.txt
│   └── simulation_K5_MIXED_RW.txt
├── scripts/
│   └── run_all.bat
├── report/
│   └── SharedMemory_Report.pdf   ← contains detailed results for K = 2–10
└── README.md
```

---

## Running the Simulation

Requires **Icarus Verilog**.

From the project root:

```
scripts\run_all.bat
```

The script will:
1. Compile the RTL and testbench  
2. Run all three traffic modes  
3. Save results under `/simulation`  
4. Print a summary in the terminal  

---

## Academic Context

This project was completed as part of a **PROJECT IN HARDWARE DESIGN FOR Embeddedn Course** at the **University of Haifa**, and received a **final grade of 100** for its design quality, and technical documentation.

---

## Author

**Dema Omar,Aya Fodi**  
B.Sc. Computer Science & Mathematics, University of Haifa  
RTL Design | Verification | Simulation  
GitHub: [https://github.com/Demaao](https://github.com/Demaao)
