`timescale 1ns / 1ps


// Top level lightweight wrapper module for the butterfly network
// Parameters are configurable for N cores, packet width...

module top_board_lite #(
    parameter integer N = `N,
    parameter integer STAGES = `K_LOG2,                         // Number of stages in the butterfly network = log2(N)
    parameter integer PACKET_W = `PACKET_W,                     // Width of forward packet
    parameter integer BACK_PACKET_W = `BACK_PACKET_W,           // Width of backward packet
    parameter integer COLLISION_COUNT_W = `TOTAL_SWITCHES_LOG2  // Bit width to count total collisions
)(
    input wire clk,
    input  wire [N*PACKET_W-1:0] in_flat,                 // Flattened vector of all input packets
    input  wire [N-1:0]          valid_in,                // Valid bits for each input packet
    output wire [N*BACK_PACKET_W-1:0] out_flat,           // Flattened vector of all output packets (backward network)
    output wire [N-1:0]          valid_back_out,          // Valid bits for each output packet
    output wire [N-1:0]          dropped_core_bus,        // One-hot vector indicating dropped packets per core
    output wire [COLLISION_COUNT_W-1:0] total_collisions  // Counter of total collisions in the network
);


    // Local function to compute clog2, Used for consistency checks
    function integer clog2; 
        input integer v; 
        integer i; 
        begin
            v = v - 1; 
            for (i = 0; v > 0; i = i + 1) 
                v = v >> 1; 
            clog2 = i;
        end 
    endfunction

    // Sanity check: verify that STAGES == log2(N), If not, stop the simulation
    initial if (STAGES != clog2(N)) begin
        $display("STAGES must equal clog2(N)"); $finish;
    end

    //Instantiate the butterfly network design 
    butterfly_network dut  (
        .clk(clk),
        .in_flat(in_flat),
        .valid_in(valid_in),
        .out_flat(out_flat),
        .valid_back_out(valid_back_out),
        .dropped_core_bus(dropped_core_bus),
        .total_collisions(total_collisions)
    );

endmodule
