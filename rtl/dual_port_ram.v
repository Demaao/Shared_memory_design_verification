`include "types.vh"
`timescale 1ns / 1ps

// Dual-Port RAM Module
// Supports two independent ports (A and B) for read/write
// Handles conflicts (same address access, write-write, read-write hazards)
//  Returns a "back packet" with data, core_id, priority, and success flag


// Memory Initialization Modes
`define INIT_NONE 2'd0
`define INIT_ZERO 2'd1
`define INIT_FILL 2'd2
`define INIT_FILE 2'd3


module dual_port_ram #(
    parameter integer INIT_MODE       = `INIT_ZERO,
    parameter [`DATA_WIDTH-1:0] INIT_FILL = {`DATA_WIDTH{1'b0}},
    parameter INIT_FILE_ENABLE        = 0
)(
    input  wire                        clk,

    // Port A
    input  wire                        we_a,          // Write enable
    input  wire [`LOCAL_ADDR_BITS-1:0] local_addr_a,  // Local address
    input  wire [`PRI_BITS-1:0]        pri_a,         // Priority
    input  wire [`DATA_WIDTH-1:0]      wdata_a,       // Write data
    input  wire [`CORE_ID_BITS -1:0]   core_id_a,     // Core ID
    input  wire                        valid_a,       // Valid signal
    output reg                         valid_a_out,   // Valid output flag
    output reg  [`BACK_PACKET_W-1:0]   rpkt_a,        // Response packet
    
    
    // Port B
    input  wire                        we_b,
    input  wire [`LOCAL_ADDR_BITS-1:0] local_addr_b,
    input  wire [`PRI_BITS-1:0]        pri_b,
    input  wire [`DATA_WIDTH-1:0]      wdata_b,
    input  wire [`CORE_ID_BITS -1:0]   core_id_b,
    input  wire                        valid_b,
    output reg                         valid_b_out,
    output reg  [`BACK_PACKET_W-1:0]   rpkt_b,

    // Conflict flags
    output wire                        same_addr,       // Both ports access same address
    output wire                        ww_conflict,     // Write-Write conflict
    output wire                        rw_hazard_ab,    // Port A write vs Port B read
    output wire                        rw_hazard_ba     // Port B write vs Port A read
);

    localparam integer DEPTH = (1 << `LOCAL_ADDR_BITS);  // Memory depth

    // Declare memory
    (* ram_style = "block" *) 
    reg [`DATA_WIDTH-1:0] mem [0:DEPTH-1];             // Actual block RAM storage
    reg [`DATA_WIDTH-1:0] dout_a, dout_b;              // Output read registers

    // Initialization Block
    integer i;
    initial begin
          for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] = i+1;
      //          $display("[INIT]  mem[%0d] = %0d",i,mem[i]);
          end      
//        if (INIT_MODE == `INIT_FILL) begin
//            for (i = 0; i < DEPTH; i = i + 1)
//                mem[i] = INIT_FILL;
//        end else if (INIT_MODE == `INIT_FILE && INIT_FILE_ENABLE) begin
//            $readmemh("init_data.mem", mem);
//        end
    end

    // Conflict logic
    wire addr_equal = (local_addr_a == local_addr_b) && valid_a && valid_b;
    assign same_addr     = addr_equal;
    assign ww_conflict   = addr_equal & we_a & we_b;
    assign rw_hazard_ab  = addr_equal & we_a & ~we_b;
    assign rw_hazard_ba  = addr_equal & ~we_a & we_b;

    // Priority: A > B
    wire write_a_allowed = we_a && valid_a;
    wire write_b_allowed = we_b && valid_b && !(we_a && valid_a && (local_addr_a == local_addr_b));

    // Port A Operation
    always @(posedge clk) begin
        if (write_a_allowed)
            mem[local_addr_a] <= wdata_a;
        dout_a <= mem[local_addr_a];

        if (valid_a) begin
//            $display(" (%b%b%b%b%b%b)",
//              we_a, addr_mod_id_a, local_addr_a, pri_a, wdata_a,core_id_a);
            valid_a_out <= 1;
            rpkt_a <= `MAKE_BACK_PACKET(core_id_a,pri_a, (write_a_allowed || ~we_a), dout_a);
           
        end else begin
            valid_a_out <= 0;
        end
    end

    // Port B Operation
    always @(posedge clk) begin
        if (write_b_allowed)
            mem[local_addr_b] <= wdata_b;

        dout_b <= mem[local_addr_b];

        if (valid_b) begin
//             $display(" (we_b=%b addr_mod_id_a=%b local_addr_b=%b pri_b=%b wdata_b=%b core_id_b=%b)",
//              we_b, addr_mod_id_a, local_addr_b, pri_b, wdata_b,core_id_b);
//              $display(" (%b%b%b%b%b%b)",
 //             we_b, addr_mod_id_b, local_addr_b, pri_b, wdata_b,core_id_b);
            valid_b_out <= 1;
            rpkt_b <= `MAKE_BACK_PACKET(core_id_b,pri_b, (write_b_allowed || ~we_b), dout_b);
            
        end else begin
            valid_b_out <= 0;
        end
    end

endmodule
