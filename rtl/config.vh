`ifndef SM_CONFIG_VH
`define SM_CONFIG_VH

// Width of the global address 
`define ADDR_WIDTH       16

// Width of the data bus 
`define DATA_WIDTH       8

// Set n = 2^K  (example: K=5 so we have 32 cores)
`define K_LOG2          5

// Number of cores (derived from K_LOG2)
`define N          (1 << `K_LOG2)

// Number of bits to identify a memory module
`define MOD_ID_BITS      (`K_LOG2 -1)
`define CORE_ID_BITS     (`K_LOG2)
`define TOTAL_SWITCHES   ((`K_LOG2 - 1)*(`N/2)) + (`K_LOG2*(`N/2))
`define TOTAL_SWITCHES_LOG2 $clog2(`TOTAL_SWITCHES + 1)

// Width of the internal address inside a memory module 
`define LOCAL_ADDR_BITS  (`ADDR_WIDTH - `MOD_ID_BITS)

// Width of the priority field in the packet
`define PRI_BITS         2

`endif