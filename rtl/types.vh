`ifndef SM_TYPES_VH
`define SM_TYPES_VH
`include "config.vh"

//[ RW | Module_ID | Local_Address | Priority | DATA | CORE_ID ]  

// Total packet width: RW + MOD_ID + LOCAL_ADDR + PRI + DATA + CORE_ID
`define PACKET_W              (1 + `MOD_ID_BITS + `LOCAL_ADDR_BITS + `PRI_BITS + `DATA_WIDTH + `CORE_ID_BITS)

// Bit positions (MSB → LSB)
`define PKT_RW_MSB            (`PACKET_W - 1)
`define PKT_RW_LSB            (`PKT_RW_MSB - 0)

`define PKT_MODID_MSB         (`PKT_RW_LSB - 1)
`define PKT_MODID_LSB         (`PKT_MODID_MSB - `MOD_ID_BITS + 1)

`define PKT_LOCAL_MSB         (`PKT_MODID_LSB - 1)
`define PKT_LOCAL_LSB         (`PKT_LOCAL_MSB - `LOCAL_ADDR_BITS + 1)

`define PKT_PRI_MSB           (`PKT_LOCAL_LSB - 1)
`define PKT_PRI_LSB           (`PKT_PRI_MSB - `PRI_BITS + 1)

`define PKT_DATA_MSB          (`PKT_PRI_LSB - 1)
`define PKT_DATA_LSB          (`PKT_DATA_MSB - `DATA_WIDTH + 1)

`define PKT_CORE_ID_MSB       (`PKT_DATA_LSB - 1)
`define PKT_CORE_ID_LSB       0

// Macros for extracting fields
`define PKT_RW(p)             (p[`PKT_RW_MSB    : `PKT_RW_LSB])
`define PKT_MODULE_ID(p)      (p[`PKT_MODID_MSB : `PKT_MODID_LSB])
`define PKT_LOCAL_ADDR(p)     (p[`PKT_LOCAL_MSB : `PKT_LOCAL_LSB])
`define PKT_PRIORITY(p)       (p[`PKT_PRI_MSB   : `PKT_PRI_LSB])
`define PKT_DATA(p)           (p[`PKT_DATA_MSB  : `PKT_DATA_LSB])
`define PKT_CORE_ID(p)        (p[`PKT_CORE_ID_MSB : `PKT_CORE_ID_LSB])

// Macro for assembling a packet
`define MAKE_PACKET(rw, mid, loc, pri, data, core_id) \
  {rw, mid[`MOD_ID_BITS-1:0], loc[`LOCAL_ADDR_BITS-1:0], pri[`PRI_BITS-1:0], data[`DATA_WIDTH-1:0], core_id[`CORE_ID_BITS -1:0]}



`define BACK_PACKET_W         (`CORE_ID_BITS +`PRI_BITS + 1 +`DATA_WIDTH)

//[ CORE_ID | Priority | Succeses | DATA ]  

// Core ID: after the module_id
`define BACK_PKT_CORE_ID_MSB  (`BACK_PACKET_W - 1)
`define BACK_PKT_CORE_ID_LSB  (`BACK_PKT_CORE_ID_MSB  - `CORE_ID_BITS + 1)

`define BACK_PKT_PRI_MSB      (`BACK_PKT_CORE_ID_LSB - 1 )
`define BACK_PKT_PRI_LSB      (`BACK_PKT_PRI_MSB - `PRI_BITS + 1 )

`define BACK_PKT_SUC_MSB    (`BACK_PKT_PRI_LSB - 1) 
`define BACK_PKT_RET_LSB    (`BACK_PKT_SUC_MSB - 0)

// DATA: least significant (LSB)
`define BACK_PKT_DATA_MSB     (`BACK_PKT_RET_LSB - 1)
`define BACK_PKT_DATA_LSB     0

// Macros for extracting fields
`define BACK_PKT_CORE_ID(p)   (p[`BACK_PKT_CORE_ID_MSB : `BACK_PKT_CORE_ID_LSB])
`define BACK_PKT_PRIORITY(p)  (p[`BACK_PKT_PRI_MSB   : `BACK_PKT_PRI_LSB])
`define BACK_PKT_SUC(p)       (p[`BACK_PKT_SUC_MSB : `BACK_PKT_RET_LSB])
`define BACK_PKT_DATA(p)      (p[`BACK_PKT_DATA_MSB : `BACK_PKT_DATA_LSB])

// Macro for assembling the back packet
`define MAKE_BACK_PACKET( core_id,prio,suc, data) \
  {  core_id[`CORE_ID_BITS -1:0],prio[`PRI_BITS -1:0],suc, data[`DATA_WIDTH-1:0] }

`endif