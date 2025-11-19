`timescale 1ns / 1ps

`include "types.vh"
`define INIT_FILL 2'd2

// butterfly_network 
// Implements a multi-stage Butterfly network
// Routes packets through multiple layers of switch2x2
// Handles packet collisions and drops

module butterfly_network #(
    parameter integer K_LOG2     = `K_LOG2,              // log2(N), number of stages
    parameter integer N          = `N,
    parameter integer DATA_WIDTH = `DATA_WIDTH,
    parameter integer PRI_BITS   = `PRI_BITS,
    parameter integer LOCAL_ADDR_BITS = `LOCAL_ADDR_BITS,
    parameter integer MOD_ID_BITS     = `MOD_ID_BITS,
    parameter integer CORE_ID_BITS    = `CORE_ID_BITS,
    parameter integer PACKET_W        = `PACKET_W,
    parameter integer BACK_PACKET_W   = `BACK_PACKET_W,
    parameter integer TOTAL_SWITCHES  = `TOTAL_SWITCHES,
    parameter integer COLLISION_COUNT_W = `TOTAL_SWITCHES_LOG2
)(
    input  wire                         clk,               // System clock
    input  wire [N*PACKET_W-1:0]        in_flat,           // Flattened array of input packets
    input  wire [N-1:0]                 valid_in,          // Valid bits for inputs
    output wire [N*BACK_PACKET_W-1:0]   out_flat,          // Flattened array of output packets
    output wire [N-1:0]                 valid_back_out,    // Valid bits for outputs
    output wire [N-1:0]                 dropped_core_bus,  // Which cores had packets dropped
    output wire [COLLISION_COUNT_W-1:0] total_collisions   // Total collisions observed
);
    localparam integer STAGES = K_LOG2;
    
    // Number of switches in forward and backward sections
    localparam integer NUM_SWITCHES_FWD = (STAGES - 1) * (N / 2);
    localparam integer NUM_SWITCHES_BWD = STAGES * (N / 2);

    // Internal buses for collisions and drops
    wire [TOTAL_SWITCHES-1:0]   internal_collision_bus;
    wire [TOTAL_SWITCHES-1:0]   switch_drop_flag;   

    // Wire-OR (wor) collects drop signals from all switches into a single bus
    wor  [N-1:0] dropped_core_bus_wor;

    // Valid output bits across stages
    wire [N-1:0] valid_out;

    // Concatenated packet data for each stage
    wire [(STAGES+1)*N*PACKET_W-1:0] stage_bus;
    
    // Concatenated valid bits for each stage
    wire [(STAGES+1)*N-1:0]          valid_bus;



    // Stage 0 inputs
    // Map external inputs into stage_bus and valid_bus
    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : INPUT_STAGE
            assign stage_bus[k*PACKET_W +: PACKET_W] = in_flat[k*PACKET_W +: PACKET_W];
            assign valid_bus[k] = valid_in[k];
        end
    endgenerate


    // FORWARD: Layer 0 (first layer of switches)
    genvar r;
    generate
        for (r = 0; r < N/2; r = r + 1) begin : SWITCH_LAYER_0
            localparam integer k0 = 2*r;        // Index of first input for switch
            localparam integer k1 = 2*r+1;      // Index of second input
            localparam integer switch_id = r;   // Switch index
            
            // Extract input packets and valid bits
            wire [PACKET_W-1:0] pkt_a = stage_bus[k0*PACKET_W +: PACKET_W];
            wire [PACKET_W-1:0] pkt_b = stage_bus[k1*PACKET_W +: PACKET_W];
            wire va = valid_bus[k0];
            wire vb = valid_bus[k1];

            // Extract module IDs from the packets
            wire [MOD_ID_BITS-1:0] mod_id_a = `PKT_MODULE_ID(pkt_a);
            wire [MOD_ID_BITS-1:0] mod_id_b = `PKT_MODULE_ID(pkt_b);
            
            // Decide output direction (sel) based on MSB of Module ID
            wire sel_a = mod_id_a[MOD_ID_BITS - 1];
            wire sel_b = mod_id_b[MOD_ID_BITS - 1];

            // Outputs from the switch
            wire [PACKET_W-1:0] y0, y1;
            wire v0, v1;

            // Drop vector from this switch
            wire [N-1:0] dropped_core_vector_sw;

            switch2x2 #(.wir_W(PACKET_W), .STAGE(0), .INDEX(r)) sw (   // Instantiate a single 2x2 switch
                .clk(clk), .a(pkt_a), .b(pkt_b),
                .sel_a(sel_a), .sel_b(sel_b),
                .y0(y0), .y1(y1),
                .va(va), .vb(vb), .v0(v0), .v1(v1),
                .dropped_core_vector(dropped_core_vector_sw),
                .collision_detected(internal_collision_bus[switch_id])
            );


            // Collect drop signals into global wor bus
            assign dropped_core_bus_wor = dropped_core_vector_sw;

            // Permutation logic for next stage:
            // Reorders outputs (y0, y1) to the correct positions in stage 1
            localparam integer HALF  = 1 << (STAGES - 1);
            localparam integer BLOCK = r / HALF;
            localparam integer POS   = r % HALF;
            localparam integer A     = BLOCK * 2 * HALF + POS;
            localparam integer B     = A + HALF;

            assign stage_bus[(1)*N*PACKET_W + A*PACKET_W +: PACKET_W] = y0;
            assign stage_bus[(1)*N*PACKET_W + B*PACKET_W +: PACKET_W] = y1;
            assign valid_bus[(1)*N + A] = v0;
            assign valid_bus[(1)*N + B] = v1;
        end
    endgenerate

    // FORWARD: middle stages (1 .. STAGES-2)
    genvar i, j;
    generate
        for (i = 1; i < STAGES - 1; i = i + 1) begin : STAGE
            for (j = 0; j < (N/2); j = j + 1) begin : SWITCHES
                localparam integer HALF  = 1 << (STAGES - 1 - i);
                localparam integer BLOCK = j / HALF;
                localparam integer POS   = j % HALF;
                localparam integer A     = BLOCK * 2 * HALF + POS;
                localparam integer B     = A + HALF;
                localparam integer switch_id = i * (N/2) + j;
                
                // Input and output packet signals
                wire [PACKET_W-1:0] pkt_a, pkt_b, y0, y1;
                wire va, vb, v0, v1;
 
                // Select packets from previous stage's stage_bus
                assign pkt_a = stage_bus[(i*N + A)*PACKET_W +: PACKET_W];
                assign pkt_b = stage_bus[(i*N + B)*PACKET_W +: PACKET_W];
                assign va    = valid_bus[i*N + A];
                assign vb    = valid_bus[i*N + B];

                // Extract module IDs
                wire [MOD_ID_BITS-1:0] mod_id_a = `PKT_MODULE_ID(pkt_a);
                wire [MOD_ID_BITS-1:0] mod_id_b = `PKT_MODULE_ID(pkt_b);
                
                // Select output based on stage bit of module_id
                wire sel_a = mod_id_a[STAGES - 1 - i];
                wire sel_b = mod_id_b[STAGES - 1 - i];

                // Drop vector from this switch
                wire [N-1:0] dropped_core_vector_sw;

                switch2x2 #(.wir_W(PACKET_W), .STAGE(i), .INDEX(j)) sw_mid (     // Instantiate switch2x2 for middle stage
                    .clk(clk),
                    .a(pkt_a), .b(pkt_b),
                    .sel_a(sel_a), .sel_b(sel_b),
                    .y0(y0), .y1(y1),
                    .va(va), .vb(vb), .v0(v0), .v1(v1),
                    .dropped_core_vector(dropped_core_vector_sw),
                    .collision_detected(internal_collision_bus[switch_id])
                );

                // Wire-OR drop signals into global bus
                assign dropped_core_bus_wor = dropped_core_vector_sw;
                
                // Connect outputs y0,y1 to next stage
                assign stage_bus[(i+1)*N*PACKET_W + A*PACKET_W +: PACKET_W] = y0;
                assign stage_bus[(i+1)*N*PACKET_W + B*PACKET_W +: PACKET_W] = y1;
                assign valid_bus[(i+1)*N + A] = v0;
                assign valid_bus[(i+1)*N + B] = v1;
            end
        end
    endgenerate


     // VALID signals before RAM stage
  
    generate
        for (k = 0; k < N; k = k + 1) begin : FINAL_STAGE
            assign valid_out[k] = valid_bus[(STAGES - 1)*N + k];
        end
    endgenerate


    // MEMORY BLOCKS (N/2 dual-port RAMs)
    // Each RAM connects to a pair of outputs from the forward network

    wire [N*PACKET_W-1:0] rpkt_flat;       // Flattened response packets
    wire [N-1:0]          valid_from_ram;  // Valid bits after RAM

    genvar p;
    generate
        for (p = 0; p < N/2; p = p + 1) begin : MEM_BLOCKS
            localparam integer k0 = 2*p;     // First port index
            localparam integer k1 = 2*p+1;   // Second port index

            localparam integer HALF  = 1;
            localparam integer BLOCK = p / HALF;
            localparam integer POS   = p % HALF;
            localparam integer A     = BLOCK * 2 * HALF + POS;
            localparam integer B     = A + HALF;
            
            // Compute base indices for stage_bus slice
            localparam integer pkt0_base = ((STAGES - 1)*N + A)*PACKET_W;
            localparam integer pkt1_base = ((STAGES - 1)*N + B)*PACKET_W;
            
            // Extract packets from stage_bus to memory ports
            wire [PACKET_W-1:0] mpkt_a = stage_bus[pkt0_base +: PACKET_W];
            wire [PACKET_W-1:0] mpkt_b = stage_bus[pkt1_base +: PACKET_W];


            // Extract fields for Port A
            wire [CORE_ID_BITS-1:0]    core_id0    = `PKT_CORE_ID(mpkt_a);
            wire [DATA_WIDTH-1:0]      rdata_a     = `PKT_DATA(mpkt_a);
            wire [PRI_BITS-1:0]        pri0        = `PKT_PRIORITY(mpkt_a);
            wire [LOCAL_ADDR_BITS-1:0] local_addr0 = `PKT_LOCAL_ADDR(mpkt_a);
            wire                       rw0         = `PKT_RW(mpkt_a);

            // Extract fields for Port B
            wire [CORE_ID_BITS-1:0]    core_id1    = `PKT_CORE_ID(mpkt_b);
            wire [DATA_WIDTH-1:0]      rdata_b     = `PKT_DATA(mpkt_b);
            wire [PRI_BITS-1:0]        pri1        = `PKT_PRIORITY(mpkt_b);
            wire [LOCAL_ADDR_BITS-1:0] local_addr1 = `PKT_LOCAL_ADDR(mpkt_b);
            wire                       rw1         = `PKT_RW(mpkt_b);

            // Valid signals for memory inputs
            wire valid_a = valid_out[k0];
            wire valid_b = valid_out[k1];
            
            // RAM outputs
            wire [BACK_PACKET_W-1:0] rpkt_a, rpkt_b;
            wire valid_a_out, valid_b_out;

            // Instantiate dual-port RAM (one per pair of inputs)
            dual_port_ram  #(
                .INIT_MODE(`INIT_FILL),
                .INIT_FILL({`DATA_WIDTH{1'b1}})
            ) u_ram (
                .clk(clk),
                // Port A connections
                .we_a(rw0),
                .local_addr_a(local_addr0),
                .pri_a(pri0),
                .wdata_a(rdata_a),
                .core_id_a(core_id0),
                .valid_a(valid_a),
                .valid_a_out(valid_a_out),
                .rpkt_a(rpkt_a),

                 // Port B connections
                .we_b(rw1),
                .local_addr_b(local_addr1),
                .pri_b(pri1),
                .wdata_b(rdata_b),
                .core_id_b(core_id1),
                .valid_b(valid_b),
                .valid_b_out(valid_b_out),
                .rpkt_b(rpkt_b),

                .same_addr(), .ww_conflict(), .rw_hazard_ab(), .rw_hazard_ba()
            );

            // Flatten outputs for backward network
            assign rpkt_flat[k0*BACK_PACKET_W +: BACK_PACKET_W] = rpkt_a;
            assign rpkt_flat[k1*BACK_PACKET_W +: BACK_PACKET_W] = rpkt_b;
            assign valid_from_ram[k0] = valid_a_out;
            assign valid_from_ram[k1] = valid_b_out;
        end
    endgenerate


    // BACKWARD STAGE (same architecture, using BACK_PACKET_W)
    // - Routes response packets from RAMs back to the cores
    // - Uses the same multi-stage butterfly structure as forward
    
    wire [(STAGES+1)*N*BACK_PACKET_W-1:0] stage_bus_back;  // Packet bus for backward stages
    wire [(STAGES+1)*N-1:0]               valid_bus_back;  // Valid signals bus for backward stages

    generate
        for (k = 0; k < N; k = k + 1) begin : BACK_INPUT
            assign stage_bus_back[k*BACK_PACKET_W +: BACK_PACKET_W] = rpkt_flat[k*BACK_PACKET_W +: BACK_PACKET_W];
            assign valid_bus_back[k] = valid_from_ram[k];
        end
    endgenerate

    // BACKWARD: stage 0, First layer of backward switches and routing based on CORE_ID MSB
    generate
        for (j = 0; j < N/2; j = j + 1) begin : BACK_STAGE_0
            localparam integer k0 = 2*j;
            localparam integer k1 = 2*j+1;

            localparam integer switch_id = NUM_SWITCHES_FWD + j;
            
            // Extract input packets
            wire [BACK_PACKET_W-1:0] pkt_a = stage_bus_back[k0*BACK_PACKET_W +: BACK_PACKET_W];
            wire [BACK_PACKET_W-1:0] pkt_b = stage_bus_back[k1*BACK_PACKET_W +: BACK_PACKET_W];
            wire va = valid_bus_back[k0];
            wire vb = valid_bus_back[k1];
            
            // Extract core IDs
            wire [CORE_ID_BITS-1:0] core_id_a = `BACK_PKT_CORE_ID(pkt_a);
            wire [CORE_ID_BITS-1:0] core_id_b = `BACK_PKT_CORE_ID(pkt_b);

            // Route based on MSB of core_id
            wire sel_a = core_id_a[STAGES - 1];
            wire sel_b = core_id_b[STAGES - 1];
            
            // Switch outputs
            wire [BACK_PACKET_W-1:0] y0, y1;
            wire v0, v1;

            // Drop vector from switch
            wire [N-1:0] dropped_core_vector_sw;

            switch2x2 #(.wir_W(BACK_PACKET_W), .STAGE(0), .INDEX(j)) sw_back_0 (   // Instantiate backward switch2x2
                .clk(clk),
                .a(pkt_a), .b(pkt_b),
                .sel_a(sel_a), .sel_b(sel_b),
                .y0(y0), .y1(y1),
                .va(va), .vb(vb), .v0(v0), .v1(v1),
                .dropped_core_vector(dropped_core_vector_sw),
                .collision_detected(internal_collision_bus[switch_id])
            );

             // OR drop vector into global bus
            assign dropped_core_bus_wor = dropped_core_vector_sw;

            // Permutation mapping for next stage
            localparam integer HALF  = 1 << (STAGES - 1);
            localparam integer BLOCK = j / HALF;
            localparam integer POS   = j % HALF;
            localparam integer A     = BLOCK * 2 * HALF + POS;
            localparam integer B     = A + HALF;

            assign stage_bus_back[1*N*BACK_PACKET_W + A*BACK_PACKET_W +: BACK_PACKET_W] = y0;
            assign stage_bus_back[1*N*BACK_PACKET_W + B*BACK_PACKET_W +: BACK_PACKET_W] = y1;
            assign valid_bus_back[1*N + A] = v0;
            assign valid_bus_back[1*N + B] = v1;
        end
    endgenerate

     // BACKWARD: middle stages (1 .. STAGES-2)
     // Works the same way as forward middle stages, but routes
     // using CORE_ID bits instead of Module_ID
    generate
        for (i = 1; i < STAGES - 1; i = i + 1) begin : BACK_STAGE
            for (j = 0; j < (N/2); j = j + 1) begin : BACK_SWITCHES
                localparam integer HALF  = 1 << (STAGES - 1 - i);
                localparam integer BLOCK = j / HALF;
                localparam integer POS   = j % HALF;
                localparam integer A     = BLOCK * 2 * HALF + POS;
                localparam integer B     = A + HALF;
                localparam integer switch_id = NUM_SWITCHES_FWD + i * (N/2) + j;

                wire [BACK_PACKET_W-1:0] pkt_a, pkt_b, y0, y1;
                wire va, vb, v0, v1;

                // Select packets from stage_bus_back
                assign pkt_a = stage_bus_back[(i*N + A)*BACK_PACKET_W +: BACK_PACKET_W];
                assign pkt_b = stage_bus_back[(i*N + B)*BACK_PACKET_W +: BACK_PACKET_W];
                assign va    = valid_bus_back[i*N + A];
                assign vb    = valid_bus_back[i*N + B];
                
                // Extract CORE_IDs
                wire [CORE_ID_BITS-1:0] core_id_a = `BACK_PKT_CORE_ID(pkt_a);
                wire [CORE_ID_BITS-1:0] core_id_b = `BACK_PKT_CORE_ID(pkt_b);
                
                // Routing decision based on CORE_ID bits
                wire sel_a = core_id_a[STAGES - 1 - i];
                wire sel_b = core_id_b[STAGES - 1 - i];

                wire [N-1:0] dropped_core_vector_sw;

                switch2x2 #(.wir_W(BACK_PACKET_W), .STAGE(i), .INDEX(j)) sw_back_mid (     // Instantiate switch2x2 for middle backward stage
                    .clk(clk),
                    .a(pkt_a), .b(pkt_b),
                    .sel_a(sel_a), .sel_b(sel_b),
                    .y0(y0), .y1(y1),
                    .va(va), .vb(vb), .v0(v0), .v1(v1),
                    .dropped_core_vector(dropped_core_vector_sw),
                    .collision_detected(internal_collision_bus[switch_id])
                );

                
                assign dropped_core_bus_wor        = dropped_core_vector_sw;

                assign stage_bus_back[(i+1)*N*BACK_PACKET_W + A*BACK_PACKET_W +: BACK_PACKET_W] = y0;
                assign stage_bus_back[(i+1)*N*BACK_PACKET_W + B*BACK_PACKET_W +: BACK_PACKET_W] = y1;
                assign valid_bus_back[(i+1)*N + A] = v0;
                assign valid_bus_back[(i+1)*N + B] = v1;
            end
        end
    endgenerate

    // BACKWARD: last stage (i = STAGES-1)
    // Routes packets to their final destinations (cores)
    generate
        for (j = 0; j < (N/2); j = j + 1) begin : BACK_LAST_STAGE
            localparam integer k0 = 2*j;
            localparam integer k1 = 2*j+1;

            localparam integer i_last = STAGES - 1;
            localparam integer HALF  = 1 << (STAGES - 1 - i_last);
            localparam integer BLOCK = j / HALF;
            localparam integer POS   = j % HALF;
            localparam integer A     = BLOCK * 2 * HALF + POS;
            localparam integer B     = A + HALF;

            localparam integer switch_id = NUM_SWITCHES_FWD + i_last * (N/2) + j;

            // Input/output wires
            wire [BACK_PACKET_W-1:0] pkt_a, pkt_b, y0, y1;
            wire va, vb, v0, v1;
            
            // Select inputs from previous stage
            assign pkt_a = stage_bus_back[(i_last*N + A)*BACK_PACKET_W +: BACK_PACKET_W];
            assign pkt_b = stage_bus_back[(i_last*N + B)*BACK_PACKET_W +: BACK_PACKET_W];
            assign va    = valid_bus_back[i_last*N + A];
            assign vb    = valid_bus_back[i_last*N + B];
            
            // Extract CORE_IDs
            wire [CORE_ID_BITS-1:0] core_id_a = `BACK_PKT_CORE_ID(pkt_a);
            wire [CORE_ID_BITS-1:0] core_id_b = `BACK_PKT_CORE_ID(pkt_b);
            
            // Routing decision based on LSBs of CORE_ID
            wire sel_a = core_id_a[STAGES - 1 - i_last];
            wire sel_b = core_id_b[STAGES - 1 - i_last];

            wire [N-1:0] dropped_core_vector_sw;

            switch2x2 #(.wir_W(BACK_PACKET_W), .STAGE(i_last), .INDEX(j)) sw_back_last (   // Instantiate last stage switch
                .clk(clk),
                .a(pkt_a), .b(pkt_b),
                .sel_a(sel_a), .sel_b(sel_b),
                .y0(y0), .y1(y1),
                .va(va), .vb(vb), .v0(v0), .v1(v1),
                .dropped_core_vector(dropped_core_vector_sw),
                .collision_detected(internal_collision_bus[switch_id])
            );

            // OR drop vector into global bus
            assign dropped_core_bus_wor = dropped_core_vector_sw;
            
            // Connect outputs directly to final stage bus
            assign stage_bus_back[(i_last+1)*N*BACK_PACKET_W + k0*BACK_PACKET_W +: BACK_PACKET_W] = y0;
            assign stage_bus_back[(i_last+1)*N*BACK_PACKET_W + k1*BACK_PACKET_W +: BACK_PACKET_W] = y1;
            assign valid_bus_back[(i_last+1)*N + k0] = v0;
            assign valid_bus_back[(i_last+1)*N + k1] = v1;
        end
    endgenerate

    // BACKWARD outputs
    generate
        for (k = 0; k < N; k = k + 1) begin : BACK_OUTPUT
            assign out_flat[k*BACK_PACKET_W +: BACK_PACKET_W] = stage_bus_back[(STAGES)*N*BACK_PACKET_W + k*BACK_PACKET_W +: BACK_PACKET_W];
            assign valid_back_out[k] = valid_bus_back[STAGES*N + k];
        end
    endgenerate


    // Collision Counting
    reg [COLLISION_COUNT_W-1:0] collision_sum;
    integer ci;

    always @(*) begin
        collision_sum = {COLLISION_COUNT_W{1'b0}};
        for (ci = 0; ci < TOTAL_SWITCHES; ci = ci + 1) begin
            if (internal_collision_bus[ci])
                collision_sum = collision_sum + 1'b1;
        end
    end

    // Assign the total number of collisions detected across all switches
    assign total_collisions = collision_sum;
    
    // Combine (wire-OR) all dropped_core signals from switches
    // into a single bus that marks which cores experienced drops
    assign dropped_core_bus = dropped_core_bus_wor;

endmodule
