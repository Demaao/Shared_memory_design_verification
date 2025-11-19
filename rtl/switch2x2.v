`timescale 1ns/1ps
`include "types.vh"



// Accepts 2 input packets (a, b) with valid bits
// Each packet has a destination select bit (sel_a, sel_b)
// Routes packets to outputs y0 or y1
// Handles collisions by buffering and priority bumping
// Can drop packets if both compete for the same output

module switch2x2 #(
    parameter integer wir_W = `PACKET_W,   // Width of a packet
    parameter integer STAGE = 0,           // Network stage index
    parameter integer INDEX = 0,           // Switch index in stage
    parameter integer N = `N               // Total number of cores
)(
    input  wire clk,

    input  wire [wir_W-1:0] a,
    input  wire [wir_W-1:0] b,
    input  wire             sel_a,         // Desired output for packet a
    input  wire             sel_b,         // Desired output for packet b
    output reg  [wir_W-1:0] y0,            // Output port 0
    output reg  [wir_W-1:0] y1,            // Output port 1

    // Valid bits
    input  wire             va,            // Valid input for a
    input  wire             vb,            // Valid input for b
    output reg              v0,            // Valid output for y0
    output reg              v1,            // Valid output for y1
    
    // Drop & collision signals
    output reg [N-1:0]   dropped_core_vector,  // Mark which core got dropped
    output reg           collision_detected    // Collision occurred this cycle
);

    localparam integer IS_BACKWARD = (wir_W == `PACKET_W) ? 0 : 1;
    
    // Internal buffer to store a packet if conflict occurs
    reg [wir_W-1:0] buffer;
    reg             buffer_valid = 0;
    reg             buffer_sel;
    reg [1:0]       buffer_pri = 0;
    
    // Extract Core IDs
    wire [`CORE_ID_BITS-1:0] core_id_a = IS_BACKWARD ? `BACK_PKT_CORE_ID(a) : `PKT_CORE_ID(a);
    wire [`CORE_ID_BITS-1:0] core_id_b = IS_BACKWARD ? `BACK_PKT_CORE_ID(b) : `PKT_CORE_ID(b);
    
    // Extract Priorities
    wire [1:0] pri_a = IS_BACKWARD ? `BACK_PKT_PRIORITY(a) : `PKT_PRIORITY(a);
    wire [1:0] pri_b = IS_BACKWARD ? `BACK_PKT_PRIORITY(b) : `PKT_PRIORITY(b);
    
    // Detect if both inputs target the same output
    wire both_valid_same_sel = va && vb && sel_a == sel_b;
    
    // Buffer output condition: release when destination is free
    wire buffer_output_ready =
        (buffer_sel == 0 && (!va || sel_a != 0)) ||
        (buffer_sel == 1 && (!vb || sel_b != 1));
        
    // Detect if new inputs conflict with buffer
    wire conflict_a_next = va && (sel_a == buffer_sel);
    wire conflict_b_next = vb && (sel_b == buffer_sel);
    
    // Increment priority (with saturation at max=3)
    function [1:0] bump_priority(input [1:0] pri);
        bump_priority = (pri < 2'b11) ? pri + 1 : pri;
    endfunction

    // Decide which packet wins if both want same output
    function [1:0] select_packets;
        input [1:0] pa, pb;
        begin
            if (pa > pb) select_packets = 2'b10;
            else if (pb > pa) select_packets = 2'b01;
            else select_packets = 2'b10;
        end
    endfunction

    wire [1:0] sel_decision = select_packets(pri_a, pri_b);

    // Combinational Routing Logic
    // Determines outputs y0, y1 and their valid bits
    always @(*) begin
        y0 = 0; y1 = 0;
        v0 = 0; v1 = 0;

        // Send buffered packet first
        if (buffer_valid) begin
            if (buffer_sel == 0) begin y0 = buffer; v0 = 1; end
            else                begin y1 = buffer; v1 = 1; end

            // If inputs can go to the opposite output of buffer
            if ((va && sel_a != buffer_sel) && (vb && sel_b != buffer_sel) && (sel_a == sel_b)) begin
                // Both want same output (not buffer's)so we pick by priority
                if (pri_a >= pri_b) begin
                    if (sel_a == 0 && v0 == 0) begin y0 = a; v0 = 1; end
                    if (sel_a == 1 && v1 == 0) begin y1 = a; v1 = 1; end
                end else begin
                    if (sel_b == 0 && v0 == 0) begin y0 = b; v0 = 1; end
                    if (sel_b == 1 && v1 == 0) begin y1 = b; v1 = 1; end
                end
            end
              // Only a can be sent
            else if (va && sel_a != buffer_sel) begin
                if (sel_a == 0 && v0 == 0) begin y0 = a; v0 = 1; end
                if (sel_a == 1 && v1 == 0) begin y1 = a; v1 = 1; end
            end
            // Only b can be sent
            else if (vb && sel_b != buffer_sel) begin
                if (sel_b == 0 && v0 == 0) begin y0 = b; v0 = 1; end
                if (sel_b == 1 && v1 == 0) begin y1 = b; v1 = 1; end
            end
        end else if (both_valid_same_sel) begin
           // Both want same output -> resolve by priority
            if (sel_decision == 2'b10) begin
                if (sel_a == 0) begin y0 = a; v0 = 1; end
                else            begin y1 = a; v1 = 1; end
            end else begin
                if (sel_b == 0) begin y0 = b; v0 = 1; end
                else            begin y1 = b; v1 = 1; end
            end
        end else if (va && vb && sel_a != sel_b) begin
           // No conflict: send each packet to its selected output
            y0 = (sel_a == 0) ? a : b; v0 = 1;
            y1 = (sel_b == 1) ? b : a; v1 = 1;
        end else if (va && sel_a == 0 && (!vb || sel_b != 0)) begin
            y0 = a; v0 = 1;
        end else if (vb && sel_b == 0 && (!va || sel_a != 0)) begin
            y0 = b; v0 = 1;
        end else if (va && sel_a == 1 && (!vb || sel_b != 1)) begin
            y1 = a; v1 = 1;
        end else if (vb && sel_b == 1 && (!va || sel_a != 1)) begin
            y1 = b; v1 = 1;
        end
    end

    // Sequential Logic (buffer management + collision detect)
    always @(posedge clk) begin
        dropped_core_vector <= {N{1'b0}};  // Reset drops
        
        // both want same output & buffer empty
        if (!buffer_valid && both_valid_same_sel) begin
            if (sel_decision == 2'b10) begin
                // a wins & store b in buffer
                buffer <= b; buffer_sel <= sel_b; buffer_pri <= bump_priority(pri_b);
                if (IS_BACKWARD)
                    buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_b);
                else
                    buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_b);
            end else begin
                // b wins & store a in buffer
                buffer <= a; buffer_sel <= sel_a; buffer_pri <= bump_priority(pri_a);
                if (IS_BACKWARD)
                    buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_a);
                else
                    buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_a);
            end
            buffer_valid <= 1;
        end else if (buffer_valid) begin
            // Buffer already occupied
            if (buffer_output_ready) begin
                if (vb && sel_b == buffer_sel && (!va || sel_a != buffer_sel)) begin
                    buffer <= b; buffer_sel <= sel_b; buffer_pri <= bump_priority(pri_b);
                    if (IS_BACKWARD)
                        buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_b);
                    else
                        buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_b);
                    buffer_valid <= 1;
                end else if (va && sel_a == buffer_sel && (!vb || sel_b != buffer_sel)) begin
                    buffer <= a; buffer_sel <= sel_a; buffer_pri <= bump_priority(pri_a);
                    if (IS_BACKWARD)
                        buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_a);
                    else
                        buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_a);
                    buffer_valid <= 1;
                end else if (va && vb && sel_a == sel_b) begin
                    // Both want same so we choose by priority
                    if (sel_decision == 2'b10) begin
                        buffer <= b; buffer_sel <= sel_b; buffer_pri <= bump_priority(pri_b);
                        if (IS_BACKWARD)
                            buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_b);
                        else
                            buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_b);
                    end else begin
                        buffer <= a; buffer_sel <= sel_a; buffer_pri <= bump_priority(pri_a);
                        if (IS_BACKWARD)
                            buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_a);
                        else
                            buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_a);
                    end
                    buffer_valid <= 1;
                end else begin
                    buffer_valid <= 0; // Buffer cleared
                end
            end else if (conflict_a_next && !conflict_b_next) begin
             // Only a conflicts with buffer
                buffer <= a; buffer_sel <= sel_a; buffer_pri <= bump_priority(pri_a);
                if (IS_BACKWARD)
                    buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_a);
                else
                    buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_a);
                buffer_valid <= 1;
            end else if (!conflict_a_next && conflict_b_next) begin
               // Only b conflicts with buffer
                buffer <= b; buffer_sel <= sel_b; buffer_pri <= bump_priority(pri_b);
                if (IS_BACKWARD)
                    buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_b);
                else
                    buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_b);
                buffer_valid <= 1;
            end else if (conflict_a_next && conflict_b_next) begin
                // Both conflict with buffer -> keep a, drop b
                buffer <= a; buffer_sel <= sel_a; buffer_pri <= bump_priority(pri_a);
                if (IS_BACKWARD)
                    buffer[`BACK_PKT_PRI_MSB:`BACK_PKT_PRI_LSB] <= bump_priority(pri_a);
                else
                    buffer[`PKT_PRI_MSB:`PKT_PRI_LSB] <= bump_priority(pri_a);
                dropped_core_vector[core_id_b] <= 1;
                buffer_valid <= 1;
            end
        end

        // Collision Detection Logic 
        collision_detected <= 0;
        if (
            (va && vb && sel_a == sel_b) || // a & b want same output
            (buffer_valid && va && sel_a == buffer_sel) ||
            (buffer_valid && vb && sel_b == buffer_sel)
        ) begin
            collision_detected <= 1;
        end
    end

    // DEBUG DISPLAY 
    reg [7:0] dbg_cycle = 0;
    always @(posedge clk) begin
        dbg_cycle <= dbg_cycle + 1;

//        $display("=== switch2x2 [stage=%0d index=%0d] @ %0t ===", STAGE, INDEX, $time);
//        $display("  Inputs : va=%b a=%b | vb=%b b=%b", va, a, vb, b);
//        $display("  Select : sel_a=%b sel_b=%b", sel_a, sel_b);
//        $display("  Buffer : valid=%b sel=%b prio=%b data=%b", buffer_valid, buffer_sel, buffer_pri, buffer);
//        $display("  Outputs: v0=%b y0=%b | v1=%b y1=%b", v0, y0, v1, y1);
//        $display("==========================================\\n");
    end

endmodule