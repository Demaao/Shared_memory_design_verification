`timescale 1ns/1ps
`include "types.vh"

module tb_butterfly_network;

    // PARAMETERS
    parameter K_LOG2           = `K_LOG2;
    parameter N                = (1 << K_LOG2);
    parameter PRI_BITS         = `PRI_BITS;
    parameter MOD_ID_BITS      = `MOD_ID_BITS;
    parameter CORE_ID_BITS     = `CORE_ID_BITS;
    parameter LOCAL_ADDR_BITS  = `LOCAL_ADDR_BITS;
    parameter ADDR_WIDTH       = `ADDR_WIDTH;
    parameter PACKET_W         = `PACKET_W;
    parameter BACK_PACKET_W    = `BACK_PACKET_W; 
    parameter DATA_WIDTH       = `DATA_WIDTH;
    parameter TOTAL_SWITCHES   = `TOTAL_SWITCHES;
    parameter COLLISION_COUNT_W = `TOTAL_SWITCHES_LOG2;
    
    parameter K_REQ_PER_CORE   = 20;   // Number of requests per core
    
    // Global counters
    integer dropp_count = 0;                
    integer module_collisions_count = 0;    
    integer switch_collisions_sum = 0;      

    // DUT SIGNALS 
    reg  clk;
    reg  [N*PACKET_W-1:0] in_flat;
    reg  [N-1:0] valid_in;
    wire [N*BACK_PACKET_W-1:0] out_flat;
    wire [N-1:0] valid_back_out;
    
    wire [N-1:0] dropped_core_bus;                  
    wire [COLLISION_COUNT_W-1:0] total_collisions;  
    
    integer max_latency [0:N-1];                    

    // DUT 
    butterfly_network dut (
        .clk(clk),
        .in_flat(in_flat),
        .valid_in(valid_in),
        .out_flat(out_flat),
        .valid_back_out(valid_back_out),
        .dropped_core_bus(dropped_core_bus),
        .total_collisions(total_collisions)
    );    

    // CLOCK GENERATION
    initial clk = 0;
    always #5 clk = ~clk;     

    // Packet Tables
    reg [PACKET_W-1:0] packet_table [0:N-1][0:K_REQ_PER_CORE-1];
    reg [PACKET_W-1:0] last_pkt [0:N-1];
    integer req_count [0:N-1];
    reg waiting_for_response [0:N-1];
    integer success_count [0:N-1];
    integer drop_count [0:N-1];
    integer send_cycle [0:N-1];
    integer total_latency [0:N-1];
                            
    // Helper function to increase priority 
    function [1:0] bump_priority(input [1:0] pri);
        bump_priority = (pri < 2'b11) ? pri + 1 : pri;
    endfunction
    
    // Hash function for distributing requests across modules
    function [MOD_ID_BITS-1:0] xor_shift_hash(input [ADDR_WIDTH-1:0] addr);
        reg [ADDR_WIDTH-1:0] mixed;
        begin
            mixed = addr ^ (addr >> 5) ^ (addr >> 11);
            xor_shift_hash = mixed[MOD_ID_BITS-1:0];
        end
    endfunction

    reg [ADDR_WIDTH-1:0] addr_i;
    reg [MOD_ID_BITS-1:0] modid_i;
    reg [LOCAL_ADDR_BITS-1:0] local_addr_i;

    integer i, j, s, base_addr;
    reg rw;

    // ====================================================
    // TEST MODE CONFIGURATION
    // ====================================================
    reg [3:0] TEST_MODE;          
    reg [80*8:1] TEST_TYPE;       

    initial begin
    // Select which test mode to run
        TEST_MODE = 4;
        
         // Assign a string name to each test mode
        case (TEST_MODE)
            0: TEST_TYPE = "HASHED_READS";
            1: TEST_TYPE = "SAME_ADDR_WRITES";
            2: TEST_TYPE = "WRITE_ONLY";
            3: TEST_TYPE = "READ_ONLY";
            4: TEST_TYPE = "MIXED_RW";
        default: begin
         // Invalid test mode handling
            TEST_TYPE = "UNKNOWN";
            $display("ERROR: Invalid TEST_MODE selected (%0d). Must be 0-4.", TEST_MODE);
            $finish;
        end
    endcase

        // Display test information
        $display("\n==========================================");
        $display(" Running Shared Memory Testbench");
        $display(" TEST_TYPE: %0s", TEST_TYPE);
        $display("==========================================\n");
    end

    initial begin
        base_addr = 0;
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < K_REQ_PER_CORE; j = j + 1) begin

               case (TEST_MODE)
0: begin
        // HASHED_READS - random read addresses
        addr_i  = $urandom % 1024;         // random address
        modid_i = xor_shift_hash(addr_i);  // map to module
        rw = 1'b0;                         // read
    end

    1: begin
        // SAME_ADDR_WRITES - all cores write to same address
        addr_i  = 0;
        modid_i = 0;
        rw = 1'b1;                         // write
    end

    2: begin
        // WRITE_ONLY - each core writes to sequential addresses
        addr_i  = base_addr + i;
        modid_i = xor_shift_hash(addr_i);
        rw = 1'b1;                         // write
    end

    3: begin
        // READ_ONLY - each core reads from distant addresses
        addr_i  = base_addr + (i * 32);
        modid_i = xor_shift_hash(addr_i);
        rw = 1'b0;                         // read
    end

    4: begin
        // MIXED_RW - half read, half write to nearby addresses
        addr_i  = base_addr + (i * 2);
        modid_i = xor_shift_hash(addr_i);
        rw = (i % 2 == 0);                 // even = read, odd = write
    end
endcase

                local_addr_i = addr_i[ADDR_WIDTH-1 -: LOCAL_ADDR_BITS];
                packet_table[i][j] = {
                    rw,
                    modid_i,
                    local_addr_i,
                    {PRI_BITS{1'b0}},
                    {DATA_WIDTH{1'b0}},
                    i[CORE_ID_BITS-1:0]
                };

                base_addr = base_addr + 1;
            end

        switch_collisions_sum = 0;
        for (i = 0; i < N; i = i + 1) begin
            req_count[i] = 0;
            waiting_for_response[i] = 0;
            success_count[i] = 0;
            drop_count[i] = 0;
            total_latency[i] = 0;
            max_latency[i] = 0;
        end
    end
   
    // MAIN LOGIC
    reg [BACK_PACKET_W-1:0] ret_pkt;
    reg ret_v, suc, dropped;
    reg [PACKET_W-1:0] pkt;
    reg [MOD_ID_BITS-1:0] modid;
    reg [LOCAL_ADDR_BITS-1:0] addr;
    reg [PRI_BITS-1:0] pri;
    reg [DATA_WIDTH-1:0] data;
    reg [CORE_ID_BITS-1:0] core_id;
    integer latency_now;
    reg [BACK_PACKET_W-1:0] temp_pkt;

    always @(posedge clk) begin
        in_flat  = 0;
        valid_in = 0;
        for (i = 0; i < N; i = i + 1) begin
            ret_pkt = out_flat[i*BACK_PACKET_W +: BACK_PACKET_W];
            ret_v   = valid_back_out[i];
            suc     = `BACK_PKT_SUC(ret_pkt);
            dropped = dropped_core_bus[i];

            if (!waiting_for_response[i] && req_count[i] < K_REQ_PER_CORE) begin
                pkt = packet_table[i][req_count[i]];
                in_flat[i*PACKET_W +: PACKET_W] = pkt;
                valid_in[i] = 1;
                last_pkt[i] = pkt;
                waiting_for_response[i] = 1;
                req_count[i] = req_count[i] + 1;
                send_cycle[i] = $time / 10;  
            end else if (ret_v && suc && req_count[i] < K_REQ_PER_CORE) begin
                pkt = packet_table[i][req_count[i]];
                in_flat[i*PACKET_W +: PACKET_W] = pkt;
                valid_in[i] = 1;
                last_pkt[i] = pkt;
                waiting_for_response[i] = 1;
                req_count[i] = req_count[i] + 1;
                latency_now = ($time / 10) - send_cycle[i];
                total_latency[i] = total_latency[i] + latency_now; 
                if (latency_now > max_latency[i])
                    max_latency[i] = latency_now;
                send_cycle[i] = $time / 10; 
            end else if ((ret_v && !suc) || (!ret_v && dropped)) begin
                rw      = `PKT_RW(last_pkt[i]);
                modid   = `PKT_MODULE_ID(last_pkt[i]);
                addr    = `PKT_LOCAL_ADDR(last_pkt[i]);
                pri     = bump_priority(`PKT_PRIORITY(last_pkt[i]));
                data    = `PKT_DATA(last_pkt[i]);
                core_id = `PKT_CORE_ID(last_pkt[i]);
                pkt = `MAKE_PACKET(rw, modid, addr, pri, data, core_id);
                in_flat[i*PACKET_W +: PACKET_W] = pkt;
                valid_in[i] = 1;
                last_pkt[i] = pkt;
            end else if (ret_v && suc) begin
                waiting_for_response[i] = 0;
                latency_now = ($time / 10) - send_cycle[i];
                total_latency[i] = total_latency[i] + latency_now;  
                if (latency_now > max_latency[i])
                    max_latency[i] = latency_now;
            end
        end
    end

    // Count successes & drops
    always @(posedge clk) begin
        if (^total_collisions !== 1'bx)
            switch_collisions_sum = switch_collisions_sum + total_collisions;

        for (i = 0; i < N; i = i + 1) begin
            temp_pkt = out_flat[i*BACK_PACKET_W +: BACK_PACKET_W];
            if (valid_back_out[i] && `BACK_PKT_SUC(temp_pkt))
                success_count[i] = success_count[i] + 1;
        end

        for (i = 0; i < N; i = i + 1)
            if (dropped_core_bus[i])
                drop_count[i] = drop_count[i] + 1;
    end

    always @(posedge clk) begin
        for (i = 0; i < N; i = i + 1) begin
            temp_pkt = out_flat[i*BACK_PACKET_W +: BACK_PACKET_W];
            if (valid_back_out[i] && !`BACK_PKT_SUC(temp_pkt)) begin
                dropp_count = dropp_count + 1;
                module_collisions_count = module_collisions_count + 1;
            end
        end
        for (i = 0; i < N; i = i + 1)
            if (dropped_core_bus[i])
                dropp_count = dropp_count + 1;
    end

    // Simulation End
    reg done;
    integer global_total_latency = 0;
    integer global_total_success = 0;
    integer global_max_latency = 0;

    always @(posedge clk) begin
        done = 1;
        for (i = 0; i < N; i = i + 1)
            if (success_count[i] < K_REQ_PER_CORE)
                done = 0;

        if (done) begin
            $display("\n===== SIMULATION DONE EARLY AT T=%0t =====", $time);
            for (i = 0; i < N; i = i + 1) begin
                global_total_latency = global_total_latency + total_latency[i];
                global_total_success = global_total_success + success_count[i];
                if (max_latency[i] > global_max_latency)
                    global_max_latency = max_latency[i];
            end
            $display("Total dropp: %0d", dropp_count);
            $display("Global Average Latency = %0f cycles",global_total_latency * 1.0 / global_total_success);
            $display("Global Max Latency = %0d cycles", global_max_latency);
            $display("Total switch collisions: %0d", switch_collisions_sum);
            $display("Avr. switch collisions: %0f", (switch_collisions_sum* 1.0/TOTAL_SWITCHES));
            $display("Total memory collisions: %0d", module_collisions_count);
            $display("Avr. memory collisions: %0f", module_collisions_count* 1.0/(N/2));
            $finish;
        end
    end

endmodule
