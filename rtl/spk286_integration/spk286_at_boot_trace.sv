// Passive first-fetch recorder for the AT profile.
// One entry spans a native CPU code request through its actual READY edge,
// including both serialized SDRAM byte beats for an aligned 16-bit fetch.
// This module has no machine-control outputs. RAM is written only on CPU
// completion; reset invalidates entries by count without resetting the RAM.
`timescale 1ns/1ps

module spk286_at_boot_trace (
    input logic clk,
    input logic reset,
    input logic cpu_valid,
    input logic cpu_write,
    input logic [3:0] cpu_status,
    input logic [23:0] cpu_address,
    input logic cpu_ready,
    input logic [15:0] cpu_data_in,
    input logic cpu_halted,
    input logic [15:0] cpu_cs,
    input logic [15:0] cpu_ip,
    input logic [23:0] cpu_cs_base,
    input logic [7:0] cpu_opcode,
    input logic backend_valid,
    input logic backend_command_valid,
    input logic backend_code,
    input logic backend_write,
    input logic backend_accept,
    input logic backend_ready,
    input logic backend_read_valid,
    input logic [23:0] backend_address,
    input logic [1:0] backend_byte_enable,
    input logic [15:0] backend_read_data,
    input logic [23:0] kf_address,
    input logic [15:0] kf_data,
    input logic kf_read_request,
    input logic kf_read_flag,
    input logic [3:0] owner_state,
    input logic sdram_read_command,
    input logic [1:0] sdram_dqm,
    input logic [4:0] select_index,
    input logic select_detail,
    output logic [127:0] selected_words,
    output logic selected_valid,
    output logic [5:0] capture_count,
    output logic full,
    output logic capture_pending
);
    // Word order is the overlay order T0..T3, low 32 bits first.
    // View 0:
    // T0: {start_flags[7:0], CPU byte address[23:0]}
    //     flags={CPU_VLD, CPU_RDY, RST, HLT, CPU status[3:0]}.
    // T1: {response_flags[7:0], first KF physical word address[23:0]}
    //     flags={CPU_RDY, backend RVALID seen, backend READY seen,
    //            KF read_request seen, KF read_flag seen, data mismatch,
    //            SDRAM read sample count[1:0]}.
    // T2: {CS at request[15:0], IP at request[15:0]}.
    // T3: {word accepted by CPU[15:0], total wait clocks[15:0]}.
    // View 1:
    // T0: {opcode at request[7:0], CS hidden base[23:0]}.
    // T1: {first KF sample[15:0], last KF sample[15:0]}.
    // T2: {first backend byte address[23:0], first BE[1:0], last BE[1:0],
    //      owner flags at last sample[3:0]}.
    // T3: {DQM first READ[1:0], last READ[1:0], first sample[1:0],
    //      last sample[1:0], opcode at completion[7:0], first sample clocks}.
    // The opcode fields are contemporaneous decoder snapshots; prefetch means
    // they must not be interpreted as the opcode decoded from this entry.
    logic [255:0] entries [0:31];
    logic [255:0] selected_entry_q;
    logic [255:0] pending_entry_q;
    logic selected_pending_q;
    logic detail_q;
    logic active_q, in_code_beat_q;
    logic [7:0] start_flags_q;
    logic [23:0] cpu_address_q, backend_address_q, kf_address_q, cs_base_q;
    logic [15:0] cs_q, ip_q, latency_q, first_latency_q;
    logic [7:0] opcode_q;
    logic [15:0] first_data_q, last_data_q;
    logic [1:0] first_be_q, last_be_q;
    logic [1:0] first_read_dqm_q, last_read_dqm_q;
    logic [1:0] first_sample_dqm_q, last_sample_dqm_q;
    logic [1:0] sample_count_q;
    logic request_seen_q, read_command_seen_q;
    logic read_request_seen_q, read_valid_seen_q, ready_seen_q, mismatch_q;
    logic [3:0] sample_owner_state_q;
    wire code_accept = backend_valid && backend_command_valid &&
                       backend_code && !backend_write && backend_accept;
    wire code_complete = in_code_beat_q && backend_ready && backend_read_valid;
    wire sample = in_code_beat_q && kf_read_flag;
    wire [7:0] response_flags = {cpu_ready, read_valid_seen_q, ready_seen_q,
                                read_request_seen_q, (sample_count_q != 0),
                                mismatch_q, sample_count_q};
    wire [255:0] completed_entry = {
        first_read_dqm_q, last_read_dqm_q, first_sample_dqm_q,
        last_sample_dqm_q, cpu_opcode, first_latency_q,
        backend_address_q, first_be_q, last_be_q,
        ((active_q && !cpu_ready) ? owner_state : sample_owner_state_q),
        first_data_q, last_data_q,
        opcode_q, cs_base_q,
        cpu_data_in, latency_q,
        cs_q, ip_q,
        response_flags, kf_address_q,
        start_flags_q, cpu_address_q
    };

    assign full = capture_count == 6'd32;
    assign capture_pending = active_q;
    wire [255:0] selected_record = selected_pending_q ? pending_entry_q :
                                                       selected_entry_q;
    assign selected_words = !selected_valid ? 128'd0 :
                            (detail_q ? selected_record[255:128] :
                                        selected_record[127:0]);

    // Synchronous read keeps the 32-entry selection out of a combinational
    // machine path and allows an ordinary FPGA simple dual-port RAM.
    always_ff @(posedge clk) begin
        selected_entry_q <= entries[select_index];
        // The in-progress slot remains visible even if SDRAM/READY never
        // completes the first fetch. This snapshot is separate from RAM;
        // its CPU_RDY response flag is zero and capture_count excludes it.
        pending_entry_q <= completed_entry;
        selected_pending_q <= !reset && active_q && !full &&
                              ({1'b0, select_index} == capture_count);
        detail_q <= select_detail;
        selected_valid <= !reset && (({1'b0, select_index} < capture_count) ||
                          (active_q && !full &&
                           ({1'b0, select_index} == capture_count)));
        if (!reset && active_q && cpu_valid && cpu_ready)
            entries[capture_count[4:0]] <= completed_entry;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            capture_count <= 6'd0;
            active_q <= 1'b0;
            in_code_beat_q <= 1'b0;
            start_flags_q <= 8'd0;
            cpu_address_q <= 24'd0;
            backend_address_q <= 24'd0;
            kf_address_q <= 24'd0;
            cs_base_q <= 24'd0;
            cs_q <= 16'd0;
            ip_q <= 16'd0;
            latency_q <= 16'd0;
            first_latency_q <= 16'd0;
            opcode_q <= 8'd0;
            first_data_q <= 16'd0;
            last_data_q <= 16'd0;
            first_be_q <= 2'd0;
            last_be_q <= 2'd0;
            first_read_dqm_q <= 2'd0;
            last_read_dqm_q <= 2'd0;
            first_sample_dqm_q <= 2'd0;
            last_sample_dqm_q <= 2'd0;
            sample_count_q <= 2'd0;
            request_seen_q <= 1'b0;
            read_command_seen_q <= 1'b0;
            read_request_seen_q <= 1'b0;
            read_valid_seen_q <= 1'b0;
            ready_seen_q <= 1'b0;
            mismatch_q <= 1'b0;
            sample_owner_state_q <= 4'd0;
        end else if (!active_q) begin
            if (!full && cpu_valid && !cpu_write && cpu_status == 4'hD) begin
                active_q <= 1'b1;
                in_code_beat_q <= 1'b0;
                start_flags_q <= {cpu_valid, cpu_ready, reset, cpu_halted,
                                  cpu_status};
                cpu_address_q <= cpu_address;
                backend_address_q <= 24'd0;
                kf_address_q <= 24'd0;
                cs_base_q <= cpu_cs_base;
                cs_q <= cpu_cs;
                ip_q <= cpu_ip;
                opcode_q <= cpu_opcode;
                latency_q <= 16'd1;
                first_latency_q <= 16'd0;
                first_data_q <= 16'd0;
                last_data_q <= 16'd0;
                first_be_q <= 2'd0;
                last_be_q <= 2'd0;
                first_read_dqm_q <= 2'd0;
                last_read_dqm_q <= 2'd0;
                first_sample_dqm_q <= 2'd0;
                last_sample_dqm_q <= 2'd0;
                sample_count_q <= 2'd0;
                request_seen_q <= 1'b0;
                read_command_seen_q <= 1'b0;
                read_request_seen_q <= 1'b0;
                read_valid_seen_q <= 1'b0;
                ready_seen_q <= 1'b0;
                mismatch_q <= 1'b0;
                sample_owner_state_q <= 4'd0;
            end
        end else begin
            if (latency_q != 16'hFFFF)
                latency_q <= latency_q + 16'd1;
            if (code_accept) begin
                in_code_beat_q <= 1'b1;
                request_seen_q <= 1'b1;
                last_be_q <= backend_byte_enable;
                if (!request_seen_q) begin
                    backend_address_q <= backend_address;
                    kf_address_q <= kf_address;
                    first_be_q <= backend_byte_enable;
                end
                if (kf_read_request)
                    read_request_seen_q <= 1'b1;
            end
            if (in_code_beat_q && sdram_read_command) begin
                last_read_dqm_q <= sdram_dqm;
                read_command_seen_q <= 1'b1;
                if (!read_command_seen_q)
                    first_read_dqm_q <= sdram_dqm;
            end
            if (sample) begin
                last_data_q <= kf_data;
                last_sample_dqm_q <= sdram_dqm;
                sample_owner_state_q <= owner_state;
                if (sample_count_q != 2'd3)
                    sample_count_q <= sample_count_q + 2'd1;
                if (sample_count_q == 0) begin
                    first_data_q <= kf_data;
                    first_sample_dqm_q <= sdram_dqm;
                    first_latency_q <= latency_q;
                end
            end
            if (in_code_beat_q && backend_ready)
                ready_seen_q <= 1'b1;
            if (in_code_beat_q && backend_read_valid)
                read_valid_seen_q <= 1'b1;
            if (code_complete) begin
                in_code_beat_q <= 1'b0;
                if (backend_read_data != last_data_q)
                    mismatch_q <= 1'b1;
            end
            if (cpu_valid && cpu_ready) begin
                active_q <= 1'b0;
                capture_count <= capture_count + 6'd1;
            end
        end
    end
endmodule
