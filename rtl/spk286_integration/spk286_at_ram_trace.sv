// Passive observer for Supersoft Landmark 1.2 AT, F000:9F14 memory routine.
// No control outputs. Capture the first failed CMP (or a taken error path)
// and hold across BIOS repetitions and CPU-only resets until a core reset.
`timescale 1ns/1ps
module spk286_at_ram_trace (
    input logic clk, reset, cpu_reset,
    input logic retired,
    input logic [15:0] instruction_ip, cpu_cs, cpu_flags,
    input logic [23:0] cpu_cs_base,
    input logic [7:0] cpu_opcode,
    input logic [127:0] cpu_gpr,
    input logic [63:0] cpu_segments,
    input logic [95:0] cpu_segment_bases,
    input logic cpu_valid, cpu_ready, cpu_write, cpu_bhe_n,
    input logic [3:0] cpu_status,
    input logic [23:0] cpu_address,
    input logic [15:0] cpu_data_in,
    input logic backend_accept, backend_ready, backend_read_valid,
    input logic backend_code, backend_write,
    input logic [1:0] backend_owner, backend_be,
    input logic [23:0] backend_address,
    input logic [15:0] backend_data_in, backend_data_out,
    input logic [23:0] kf_address,
    input logic [15:0] kf_data,
    input logic kf_read_request, kf_read_flag, sdram_read_command,
    input logic [3:0] owner_state,
    input logic [1:0] sdram_dqm, select_page,
    output logic [127:0] selected_words,
    output logic captured, armed,
    output logic [15:0] comparisons
);
    logic [511:0] frozen_q;
    logic comparison_valid_q, reading_q;
    logic [31:0] native_address_q, backend_address_q, kf_address_q;
    logic [15:0] native_data_q, backend_data_q, sample_q;
    logic [31:0] write_address_q;
    logic [15:0] write_data_q;
    logic [23:0] pending_kf_address_q;
    logic request_seen_q, sample_seen_q, command_seen_q;
    logic [1:0] read_dqm_q, sample_dqm_q, last_be_q;
    logic [3:0] sample_owner_q;
    logic [31:0] physical_detail_q;
    wire in_rom = cpu_cs == 16'hF000 && cpu_cs_base == 24'h0F0000;
    wire entry_retired = retired && in_rom && instruction_ip == 16'h9F14 && cpu_opcode == 8'hFC;
    wire cmp_retired = armed && retired && in_rom && instruction_ip == 16'h9F37 && cpu_opcode == 8'h3A;
    wire error_path = armed && retired && in_rom &&
        ((instruction_ip == 16'h9F3B && cpu_opcode == 8'h33) ||
         (instruction_ip == 16'h9F4D && cpu_opcode == 8'hE4));
    wire [7:0] native_byte = native_address_q[0] ? native_data_q[15:8] : native_data_q[7:0];
    // Little-word order: page 0 is bits 127:0, T0 is its low word.
    wire [511:0] live_comparison = {
        write_data_q, cpu_gpr[64 +: 16],                        // P3 T3: last write / SP
        write_address_q,                                     // P3 T2: flags / last write byte address
        cpu_gpr[32 +: 16], cpu_gpr[80 +: 16],                  // P3 T1: DX / BP
        cpu_gpr[0 +: 16], cpu_gpr[48 +: 16],                   // P3 T0: AX / BX
        8'd0, cpu_segment_bases[72 +: 24],                    // P2 T3: DS base
        8'd0, cpu_segment_bases[0 +: 24],                     // P2 T2: ES base
        cpu_segments[0 +: 16], cpu_segments[48 +: 16],        // P2 T1: ES / DS
        physical_detail_q,                                  // P2 T0: KF data / DQM / BE / owner
        native_data_q, backend_data_q,                       // P1 T3: native / backend read words
        kf_address_q,                                       // P1 T2: KF flags / physical word address
        backend_address_q,                                  // P1 T1: flags / backend byte address
        native_address_q,                                   // P1 T0: flags / CPU byte address
        cpu_flags, cpu_gpr[96 +: 16],                        // P0 T3: FLAGS / SI
        cpu_gpr[16 +: 16], cpu_gpr[112 +: 16],                // P0 T2: CX / DI (already incremented)
        cpu_cs, instruction_ip,                             // P0 T1: CS / comparison IP
        8'hC1, cpu_gpr[8 +: 8], cpu_gpr[48 +: 8], native_byte // P0 T0: format / AH expected / BL read / bus byte
    };
    always_ff @(posedge clk) begin
        // Registered selection stays outside the CPU/memory data path.
        case (select_page)
            0: selected_words <= captured ? frozen_q[127:0] : 128'd0;
            1: selected_words <= captured ? frozen_q[255:128] : 128'd0;
            2: selected_words <= captured ? frozen_q[383:256] : 128'd0;
            3: selected_words <= captured ? frozen_q[511:384] : 128'd0;
        endcase
        if (reset) begin
            selected_words <= 0;
            captured <= 0; armed <= 0; comparisons <= 0;
            comparison_valid_q <= 0; reading_q <= 0;
            frozen_q <= 0;
            native_address_q <= 0; backend_address_q <= 0; kf_address_q <= 0;
            native_data_q <= 0; backend_data_q <= 0; sample_q <= 0;
            write_address_q <= 0; write_data_q <= 0;
            pending_kf_address_q <= 0;
            request_seen_q <= 0; sample_seen_q <= 0; command_seen_q <= 0;
            read_dqm_q <= 0; sample_dqm_q <= 0; last_be_q <= 0;
            sample_owner_q <= 0; physical_detail_q <= 0;
        end else if (!captured) begin
            if (cpu_reset) begin
                armed <= 0; comparison_valid_q <= 0; reading_q <= 0;
            end else begin
                if (entry_retired) begin
                    armed <= 1;
                    comparison_valid_q <= 0;
                end
                if (cmp_retired) begin
                    frozen_q <= live_comparison;
                    comparison_valid_q <= 1;
                    if (comparisons != 16'hFFFF) comparisons <= comparisons + 16'd1;
                    if (!cpu_flags[6]) begin
                        captured <= 1;
                    end
                end
                if (error_path && comparison_valid_q) begin
                    // C2 = data-error path despite previous ZF=1; C3 = parity path.
                    frozen_q[31:24] <= instruction_ip == 16'h9F3B ? 8'hC2 : 8'hC3;
                    captured <= 1;
                end
                if (cpu_valid && cpu_ready && !cpu_write && cpu_status == 4'h5) begin
                    native_address_q <= {1'b1, cpu_valid, cpu_ready, cpu_bhe_n, cpu_status, cpu_address};
                    native_data_q <= cpu_data_in;
                end
                if (backend_accept && backend_owner == 0 && !backend_code && !backend_write) begin
                    reading_q <= 1;
                    pending_kf_address_q <= kf_address;
                    request_seen_q <= kf_read_request;
                    sample_seen_q <= 0; command_seen_q <= 0;
                    read_dqm_q <= 0; sample_dqm_q <= 0; sample_owner_q <= 0;
                    sample_q <= 0;
                    last_be_q <= backend_be;
                end
                if (reading_q && sdram_read_command) begin
                    command_seen_q <= 1;
                    read_dqm_q <= sdram_dqm;
                end
                if (reading_q && kf_read_flag) begin
                    sample_seen_q <= 1; sample_q <= kf_data;
                    sample_dqm_q <= sdram_dqm; sample_owner_q <= owner_state;
                end
                if (reading_q && backend_ready && backend_read_valid) begin
                    reading_q <= 0;
                    backend_address_q <= {1'b1, backend_ready, backend_read_valid, backend_write, backend_be, backend_owner, backend_address};
                    backend_data_q <= backend_data_in;
                    kf_address_q <= {request_seen_q, sample_seen_q, command_seen_q, sample_owner_q, 1'b0, pending_kf_address_q};
                    physical_detail_q <= {sample_q, read_dqm_q, sample_dqm_q, last_be_q, sample_owner_q, 6'd0};
                end
                if (backend_ready && backend_owner == 0 && backend_write && !backend_code) begin
                    write_address_q <= {6'd0, backend_be, backend_address};
                    write_data_q <= backend_data_out;
                end
            end
        end
    end
endmodule
