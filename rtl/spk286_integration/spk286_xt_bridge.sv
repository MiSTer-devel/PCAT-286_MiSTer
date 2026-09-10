// Retained SPK286 normalized-transfer to byte-wide XT transaction adapter.
// The downstream frontend supplies actual-cycle and completion observations;
// idle READY is never interpreted as a completed transfer.
`timescale 1ns/1ps

module spk286_xt_bridge (
    input  logic         clk,
    input  logic         reset,

    input  logic         cpu_bus_valid,
    input  logic [23:0]  cpu_address,
    input  logic [15:0]  cpu_data_out,
    input  logic         cpu_data_oe,
    input  logic         cpu_bus_write,
    input  logic         cpu_bus_bhe_n,
    input  logic [3:0]   cpu_bus_status,
    input  logic         cpu_bus_lock,
    output logic         cpu_ready,
    output logic [15:0]  cpu_data_in,

    // Assert at a safe legacy CPU phase to launch a new 8288 transaction.
    input  logic         xt_start,
    // Assert at the legacy phase where read data or write completion is safe.
    input  logic         xt_sample,
    // True only after the downstream command strobe is active.
    input  logic         xt_cycle_active,
    input  logic         xt_ready,
    input  logic [7:0]   xt_data_in,
    output logic         xt_valid,
    output logic [19:0]  xt_address,
    output logic [7:0]   xt_data_out,
    output logic [2:0]   xt_status,
    output logic         xt_write,
    output logic         xt_io,
    output logic         xt_inta,
    output logic         xt_code,
    output logic         xt_byte_high,
    output logic         xt_memory_projection,
    output logic         xt_lock_n,
    output logic         xt_accepted,

    output logic         bridge_idle,
    output logic         protocol_error
);
    localparam logic [2:0] STATE_IDLE     = 3'd0;
    localparam logic [2:0] STATE_ARMED    = 3'd1;
    localparam logic [2:0] STATE_ACTIVE   = 3'd2;
    localparam logic [2:0] STATE_GAP      = 3'd3;
    localparam logic [2:0] STATE_COMPLETE = 3'd4;

    logic [2:0]  state_q;
    logic [23:0] request_address_q;
    logic [15:0] request_data_q;
    logic        request_data_oe_q;
    logic        request_write_q;
    logic        request_bhe_n_q;
    logic [3:0]  request_status_q;
    logic        request_lock_q;
    logic        request_two_beats_q;
    logic        beat_high_q;
    logic        sample_edge_seen_q;
    logic [15:0] read_data_q;

    logic [23:0] beat_address;
    logic        request_is_io;
    logic        request_is_inta;
    logic        request_is_code;
    logic        request_is_read;
    logic        request_status_valid;
    logic        request_lane_valid;
    logic        request_direction_valid;
    logic        live_request_valid;

    always_comb begin
        request_status_valid = 1'b1;
        case (cpu_bus_status)
            4'h0, 4'h5, 4'h6, 4'h9, 4'ha, 4'hd: ;
            default: request_status_valid = 1'b0;
        endcase

        request_lane_valid = (cpu_bus_status == 4'h0) ||
                             !((cpu_address[0] == 1'b1) && cpu_bus_bhe_n);
        case (cpu_bus_status)
            4'h6, 4'ha:
                request_direction_valid = cpu_bus_write && cpu_data_oe;
            4'h0, 4'h5, 4'h9, 4'hd:
                request_direction_valid = !cpu_bus_write && !cpu_data_oe;
            default:
                request_direction_valid = 1'b0;
        endcase
        live_request_valid = request_status_valid && request_lane_valid &&
                             request_direction_valid;
    end

    assign request_is_io = (request_status_q == 4'h9) ||
                           (request_status_q == 4'ha);
    assign request_is_inta = (request_status_q == 4'h0);
    assign request_is_code = (request_status_q == 4'hd);
    assign request_is_read = !request_write_q;
    assign beat_address = request_address_q + (beat_high_q ? 24'd1 : 24'd0);

    spk286_xt_address_map address_map (
        .cpu_address(beat_address),
        .cycle_is_io(request_is_io),
        .xt_address(xt_address),
        .memory_projection(xt_memory_projection)
    );

    always_comb begin
        case (request_status_q)
            4'h0: xt_status = 3'b000;
            4'h9: xt_status = 3'b001;
            4'ha: xt_status = 3'b010;
            4'hd: xt_status = 3'b100; // MUTATION_ANCHOR_CODE_STATUS
            4'h5: xt_status = 3'b101;
            4'h6: xt_status = 3'b110;
            default: xt_status = 3'b111;
        endcase
    end

    assign xt_valid = (state_q == STATE_ACTIVE);
    assign xt_write = request_write_q;
    assign xt_io = request_is_io;
    assign xt_inta = request_is_inta;
    assign xt_code = request_is_code;
    assign xt_byte_high = !request_is_inta &&
                          (beat_high_q || request_address_q[0]);
    assign xt_data_out = xt_byte_high ? request_data_q[15:8] :
                                          request_data_q[7:0];
    assign xt_lock_n = ~(cpu_bus_lock ||
                         ((state_q != STATE_IDLE) && request_lock_q));
    assign cpu_ready = (state_q == STATE_COMPLETE);
    assign bridge_idle = (state_q == STATE_IDLE);
    assign xt_accepted = (state_q == STATE_ACTIVE) &&
                         sample_edge_seen_q && xt_sample &&
                         xt_cycle_active && xt_ready;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= STATE_IDLE;
            request_address_q <= 24'd0;
            request_data_q <= 16'd0;
            request_data_oe_q <= 1'b0;
            request_write_q <= 1'b0;
            request_bhe_n_q <= 1'b1;
            request_status_q <= 4'hf;
            request_lock_q <= 1'b0;
            request_two_beats_q <= 1'b0;
            beat_high_q <= 1'b0;
            sample_edge_seen_q <= 1'b0;
            read_data_q <= 16'd0;
            cpu_data_in <= 16'd0;
            protocol_error <= 1'b0;
        end else begin
            case (state_q)
                STATE_IDLE: begin
                    sample_edge_seen_q <= 1'b0;
                    if (cpu_bus_valid) begin
                        request_address_q <= cpu_address;
                        request_data_q <= cpu_data_out;
                        request_data_oe_q <= cpu_data_oe;
                        request_write_q <= cpu_bus_write;
                        request_bhe_n_q <= cpu_bus_bhe_n;
                        request_status_q <= cpu_bus_status;
                        request_lock_q <= cpu_bus_lock;
                        request_two_beats_q <= (cpu_bus_status != 4'h0) &&
                                               !cpu_address[0] &&
                                               !cpu_bus_bhe_n;
                        beat_high_q <= 1'b0;
                        read_data_q <= 16'd0;
                        cpu_data_in <= 16'd0;
                        if (live_request_valid) begin
                            state_q <= STATE_ARMED;
                        end else begin
                            protocol_error <= 1'b1;
                            state_q <= STATE_COMPLETE;
                        end
                    end
                end

                STATE_ARMED: begin
                    sample_edge_seen_q <= 1'b0;
                    if (xt_start && !xt_cycle_active)
                        state_q <= STATE_ACTIVE;
                end

                STATE_ACTIVE: begin
                    // READY is generated for the legacy CPU timing model and
                    // can still contain the idle value when an 8288 command
                    // first becomes active. Sample it, and the shared data
                    // bus, only on the configured legacy sample edge. This is
                    // the point where the original CPU consumes both.
                    // The first sample edge after the 8288 command appears
                    // can still carry READY from the preceding idle phase.
                    // Use it only to arm the completion window; later sample
                    // edges see READY after the inherited two-edge pipeline.
                    if (xt_sample && xt_cycle_active)
                        sample_edge_seen_q <= 1'b1;
                    if (xt_accepted) begin
                        if (request_is_read) begin
                            if (request_is_inta) begin
                                read_data_q <= {8'd0, xt_data_in};
                                cpu_data_in <= {8'd0, xt_data_in};
                            end else if (xt_byte_high) begin
                                read_data_q[15:8] <= xt_data_in;
                                cpu_data_in <= {xt_data_in, read_data_q[7:0]};
                            end else begin
                                read_data_q[7:0] <= xt_data_in;
                                cpu_data_in <= {read_data_q[15:8], xt_data_in};
                            end
                        end

                        if (request_two_beats_q && !beat_high_q) begin
                            beat_high_q <= 1'b1;
                            state_q <= STATE_GAP;
                        end else begin
                            state_q <= STATE_COMPLETE;
                        end
                        sample_edge_seen_q <= 1'b0;
                    end
                end

                STATE_GAP: begin
                    sample_edge_seen_q <= 1'b0;
                    if (!xt_cycle_active)
                        state_q <= STATE_ARMED;
                end

                STATE_COMPLETE: begin
                    state_q <= STATE_IDLE;
                    sample_edge_seen_q <= 1'b0;
                end

                default: begin
                    state_q <= STATE_IDLE;
                    protocol_error <= 1'b1;
                end
            endcase
        end
    end
endmodule
