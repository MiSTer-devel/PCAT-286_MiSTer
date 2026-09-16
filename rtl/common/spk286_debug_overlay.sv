// SPDX-License-Identifier: GPL-3.0-only
//
// Passive SPK286 bring-up overlay for PCAT-286 MiSTer.
// The clock-domain synchronization and post-credits overlay method is adapted
// from PCXT_MiSTer_devel test/crtc-debug commit f553fb076f102e81c5e58dee4a9c2ea2a2ce9af5.
// This adaptation observes CPU/bridge state only; it never drives READY, HOLD,
// memory, I/O, or any CPU control input.

`timescale 1ns/1ps

module spk286_debug_overlay #(
    parameter integer COLW = 8,
    parameter integer BLANK_WATCHDOG_WIDTH = 18,
    parameter bit     AT_MODE = 1'b0
) (
    input  logic                  rst,
    input  logic                  src_rst,
    input  logic                  src_clk,
    input  logic                  clk,
    input  logic                  pxl_cen,
    input  logic                  HS,
    input  logic                  VS,
    input  logic                  HB,
    input  logic                  VB,
    input  logic [COLW*3-1:0]     rgb_in,
    input  logic [1:0]            page,

    input  logic                  cpu_reset,
    input  logic                  cpu_halted,
    input  logic                  cpu_shutdown,
    input  logic                  cpu_control_error,
    input  logic                  cpu_unsupported_opcode,
    input  logic                  cpu_microcode_fault,
    input  logic                  cpu_operand_blocked,
    input  logic                  cpu_event_completed,
    input  logic [7:0]            cpu_event_vector,
    input  logic [2:0]            cpu_event_kind,
    input  logic [7:0]            cpu_opcode,
    input  logic [15:0]           cpu_cs,
    input  logic [23:0]           cpu_cs_base,
    input  logic [15:0]           cpu_ip,
    input  logic [15:0]           cpu_flags,
    input  logic [127:0]          cpu_gpr,
    input  logic [63:0]           cpu_segments,
    input  logic                  cpu_fetch_blocked,
    input  logic [16:0]           cpu_fetch_cursor,
    input  logic [11:0]           cpu_micro_pc,
    input  logic [11:0]           cpu_micro_entry,
    input  logic [7:0]            cpu_micro_instruction,
    input  logic                  cpu_micro_active,
    input  logic [3:0]            cpu_prefetch_count,
    input  logic [3:0]            cpu_biu_state,

    input  logic [23:0]           cpu_address,
    input  logic [15:0]           cpu_data_out,
    input  logic [15:0]           cpu_data_in,
    input  logic [3:0]            cpu_bus_status,
    input  logic                  cpu_bus_valid,
    input  logic                  cpu_bus_write,
    input  logic                  cpu_bhe_n,
    input  logic                  cpu_bus_lock,
    input  logic                  cpu_hlda,
    input  logic                  cpu_ready,

    input  logic [19:0]           xt_address,
    input  logic [7:0]            xt_data_out,
    input  logic [7:0]            xt_data_in,
    input  logic [2:0]            xt_status,
    input  logic                  xt_valid,
    input  logic                  xt_write,
    input  logic                  xt_io,
    input  logic                  xt_inta,
    input  logic                  xt_code,
    input  logic                  xt_byte_high,
    input  logic                  xt_memory_projection,
    input  logic                  xt_cycle_active,
    input  logic                  xt_ready,
    input  logic                  bridge_idle,
    input  logic                  bridge_error,
    input  logic                  hold_request,
    input  logic [7:0]            biu_detail,

    input  logic [7:0]            last_post,
    input  logic [15:0]           cpu_cycle_count,
    input  logic [15:0]           xt_cycle_count,
    input  logic [31:0]           trace0,
    input  logic [31:0]           trace1,
    input  logic [31:0]           trace2,
    input  logic [31:0]           trace3,
    input  logic [7:0]            keyboard_keycode,
    input  logic                  keyboard_irq,
    input  logic [7:0]            keyboard_port_b,
    input  logic                  keyboard_pic_int,
    input  logic [3:0]            dma_request,
    input  logic [3:0]            dma_acknowledge_n,

    output logic                  HB_out,
    output logic                  VB_out,
    output logic [COLW*3-1:0]     rgb_out
);

    localparam logic [9:0] HOFFSET = 10'd16;
    localparam logic [9:0] VOFFSET = 10'd16;

    // SPK286 state is produced at 50 MHz and displayed in the video domain.
    // A toggle/ack handshake captures one coherent source-domain snapshot per
    // frame. The wide snapshot remains stable while its acknowledgement crosses
    // the clock boundary; it is never used by functional machine logic.
    wire [349:0] cpu_state_async = {
        cpu_reset, cpu_halted, cpu_shutdown, cpu_control_error,
        cpu_unsupported_opcode, cpu_microcode_fault, cpu_operand_blocked,
        cpu_event_completed, cpu_event_vector, cpu_event_kind, cpu_opcode,
        cpu_cs, cpu_cs_base, cpu_ip, cpu_flags, cpu_gpr, cpu_segments,
        cpu_fetch_blocked, cpu_fetch_cursor, cpu_micro_pc, cpu_micro_entry,
        cpu_micro_instruction, cpu_micro_active, cpu_prefetch_count,
        cpu_biu_state
    };

    wire [190:0] bus_state_async = {
        cpu_address, cpu_data_out, cpu_data_in, cpu_bus_status,
        cpu_bus_valid, cpu_bus_write, cpu_bhe_n, cpu_bus_lock, cpu_hlda,
        cpu_ready, xt_address, xt_data_out, xt_data_in, xt_status, xt_valid,
        xt_write, xt_io, xt_inta, xt_code, xt_byte_high,
        xt_memory_projection, xt_cycle_active, xt_ready, bridge_idle,
        bridge_error, hold_request, last_post, cpu_cycle_count, xt_cycle_count,
        keyboard_keycode, keyboard_irq, keyboard_port_b, keyboard_pic_int,
        dma_request, dma_acknowledge_n, biu_detail
    };
    wire [668:0] complete_state_async = {
        cpu_state_async, bus_state_async, trace0, trace1, trace2, trace3
    };
    logic [676:0] source_snapshot = '0;
    logic [676:0] video_snapshot = '0;
    logic [7:0] snapshot_sequence = 8'd0;
    logic snapshot_request = 1'b0;
    logic snapshot_acknowledge = 1'b0;
    logic snapshot_acknowledge_seen = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_request_src1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_request_src2 = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_ack_video1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_ack_video2 = 1'b0;
    logic previous_snapshot_vb = 1'b0;
    logic [1:0] page_sync1 = 2'd0;
    logic [1:0] page_sync2 = 2'd0;
    logic [1:0] page_latched = 2'd0;

    always_ff @(posedge src_clk) begin
        if (src_rst) begin
            snapshot_request_src1 <= 1'b0;
            snapshot_request_src2 <= 1'b0;
            snapshot_acknowledge  <= 1'b0;
            source_snapshot       <= '0;
            snapshot_sequence     <= 8'd0;
        end else begin
            snapshot_request_src1 <= snapshot_request;
            snapshot_request_src2 <= snapshot_request_src1;
            if (snapshot_request_src2 != snapshot_acknowledge) begin
                source_snapshot      <= {
                    snapshot_sequence + 8'd1, complete_state_async
                };
                snapshot_sequence    <= snapshot_sequence + 8'd1;
                snapshot_acknowledge <= snapshot_request_src2;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            snapshot_request          <= 1'b0;
            snapshot_ack_video1       <= 1'b0;
            snapshot_ack_video2       <= 1'b0;
            snapshot_acknowledge_seen <= 1'b0;
            video_snapshot            <= '0;
            previous_snapshot_vb      <= 1'b0;
            page_sync1                <= 2'd0;
            page_sync2                <= 2'd0;
            page_latched              <= 2'd0;
        end else begin
            snapshot_ack_video1  <= snapshot_acknowledge;
            snapshot_ack_video2  <= snapshot_ack_video1;
            previous_snapshot_vb <= VB;
            page_sync1           <= page;
            page_sync2           <= page_sync1;
            if (VB && !previous_snapshot_vb) begin
                // Do not overwrite an outstanding toggle. This matters when
                // the source clock has only just left its hard reset.
                if (snapshot_ack_video2 == snapshot_request)
                    snapshot_request <= ~snapshot_request;
                page_latched <= page_sync2;
            end
            if (snapshot_ack_video2 != snapshot_acknowledge_seen) begin
                video_snapshot            <= source_snapshot;
                snapshot_acknowledge_seen <= snapshot_ack_video2;
            end
        end
    end

    wire [349:0] cpu_state_snapshot;
    wire [190:0] bus_state_snapshot;
    wire [127:0] trace_state_snapshot;
    wire [7:0] d_snapshot_sequence;
    assign {
        d_snapshot_sequence,
        cpu_state_snapshot, bus_state_snapshot,
        trace_state_snapshot
    } = video_snapshot;

    wire        d_cpu_reset;
    wire        d_cpu_halted;
    wire        d_cpu_shutdown;
    wire        d_cpu_control_error;
    wire        d_cpu_unsupported_opcode;
    wire        d_cpu_microcode_fault;
    wire        d_cpu_operand_blocked;
    wire        d_cpu_event_completed;
    wire [7:0]  d_cpu_event_vector;
    wire [2:0]  d_cpu_event_kind;
    wire [7:0]  d_cpu_opcode;
    wire [15:0] d_cpu_cs;
    wire [23:0] d_cpu_cs_base;
    wire [15:0] d_cpu_ip;
    wire [15:0] d_cpu_flags;
    wire [127:0] d_cpu_gpr;
    wire [63:0] d_cpu_segments;
    wire        d_cpu_fetch_blocked;
    wire [16:0] d_cpu_fetch_cursor;
    wire [11:0] d_cpu_micro_pc;
    wire [11:0] d_cpu_micro_entry;
    wire [7:0]  d_cpu_micro_instruction;
    wire        d_cpu_micro_active;
    wire [3:0]  d_cpu_prefetch_count;
    wire [3:0]  d_cpu_biu_state;
    wire [19:0] d_cpu_fetch_cursor_padded = {3'd0, d_cpu_fetch_cursor};

    assign {
        d_cpu_reset, d_cpu_halted, d_cpu_shutdown, d_cpu_control_error,
        d_cpu_unsupported_opcode, d_cpu_microcode_fault,
        d_cpu_operand_blocked, d_cpu_event_completed, d_cpu_event_vector,
        d_cpu_event_kind, d_cpu_opcode, d_cpu_cs, d_cpu_cs_base, d_cpu_ip,
        d_cpu_flags, d_cpu_gpr, d_cpu_segments, d_cpu_fetch_blocked,
        d_cpu_fetch_cursor, d_cpu_micro_pc, d_cpu_micro_entry,
        d_cpu_micro_instruction, d_cpu_micro_active,
        d_cpu_prefetch_count, d_cpu_biu_state
    } = cpu_state_snapshot;

    wire [23:0] d_cpu_address;
    wire [15:0] d_cpu_data_out;
    wire [15:0] d_cpu_data_in;
    wire [3:0]  d_cpu_bus_status;
    wire        d_cpu_bus_valid;
    wire        d_cpu_bus_write;
    wire        d_cpu_bhe_n;
    wire        d_cpu_bus_lock;
    wire        d_cpu_hlda;
    wire        d_cpu_ready;
    wire [19:0] d_xt_address;
    wire [7:0]  d_xt_data_out;
    wire [7:0]  d_xt_data_in;
    wire [2:0]  d_xt_status;
    wire        d_xt_valid;
    wire        d_xt_write;
    wire        d_xt_io;
    wire        d_xt_inta;
    wire        d_xt_code;
    wire        d_xt_byte_high;
    wire        d_xt_memory_projection;
    wire        d_xt_cycle_active;
    wire        d_xt_ready;
    wire        d_bridge_idle;
    wire        d_bridge_error;
    wire        d_hold_request;
    wire [7:0]  d_biu_detail;
    wire [7:0]  d_last_post;
    wire [15:0] d_cpu_cycle_count;
    wire [15:0] d_xt_cycle_count;
    wire [7:0]  d_keyboard_keycode;
    wire        d_keyboard_irq;
    wire [7:0]  d_keyboard_port_b;
    wire        d_keyboard_pic_int;
    wire [3:0]  d_dma_request;
    wire [3:0]  d_dma_acknowledge_n;

    assign {
        d_cpu_address, d_cpu_data_out, d_cpu_data_in, d_cpu_bus_status,
        d_cpu_bus_valid, d_cpu_bus_write, d_cpu_bhe_n, d_cpu_bus_lock,
        d_cpu_hlda, d_cpu_ready, d_xt_address, d_xt_data_out, d_xt_data_in,
        d_xt_status, d_xt_valid, d_xt_write, d_xt_io, d_xt_inta, d_xt_code,
        d_xt_byte_high, d_xt_memory_projection, d_xt_cycle_active,
        d_xt_ready, d_bridge_idle, d_bridge_error, d_hold_request,
        d_last_post, d_cpu_cycle_count, d_xt_cycle_count,
        d_keyboard_keycode, d_keyboard_irq, d_keyboard_port_b, d_keyboard_pic_int,
        d_dma_request, d_dma_acknowledge_n, d_biu_detail
    } = bus_state_snapshot;

    wire [31:0] d_trace0 = trace_state_snapshot[127:96];
    wire [31:0] d_trace1 = trace_state_snapshot[95:64];
    wire [31:0] d_trace2 = trace_state_snapshot[63:32];
    wire [31:0] d_trace3 = trace_state_snapshot[31:0];

    // Architectural order documented by SPK286: AX,CX,DX,BX,SP,BP,SI,DI
    // and ES,CS,SS,DS, with the lowest slice first.
    wire [15:0] d_ax = d_cpu_gpr[15:0];
    wire [15:0] d_cx = d_cpu_gpr[31:16];
    wire [15:0] d_dx = d_cpu_gpr[47:32];
    wire [15:0] d_bx = d_cpu_gpr[63:48];
    wire [15:0] d_sp = d_cpu_gpr[79:64];
    wire [15:0] d_bp = d_cpu_gpr[95:80];
    wire [15:0] d_si = d_cpu_gpr[111:96];
    wire [15:0] d_di = d_cpu_gpr[127:112];
    wire [15:0] d_es = d_cpu_segments[15:0];
    wire [15:0] d_cs = d_cpu_segments[31:16];
    wire [15:0] d_ss = d_cpu_segments[47:32];
    wire [15:0] d_ds = d_cpu_segments[63:48];

    function automatic [6:0] hex_digit(input logic [3:0] value);
        hex_digit = (value < 4'd10)
            ? (7'd48 + {3'd0, value})
            : (7'd55 + {3'd0, value});
    endfunction

    function automatic [6:0] bit_digit(input logic value);
        bit_digit = value ? 7'd49 : 7'd48;
    endfunction

    // String literals are right-aligned in the packed input. Length makes
    // their first character appear at overlay column zero without padding.
    function automatic [6:0] text_at(
        input logic [255:0] text,
        input integer       length,
        input logic [5:0]   index
    );
        integer base;
        logic [7:0] selected;
        begin
            text_at = 7'd32;
            if (index < length) begin
                base = (length - 1 - index) * 8;
                selected = text[base +: 8];
                text_at = selected[6:0];
            end
        end
    endfunction

    function automatic [6:0] trace_at(
        input logic [31:0] trace,
        input logic [6:0]  number,
        input logic [5:0]  index
    );
        integer shift;
        begin
            trace_at = text_at("0 R A:00000 D:00 S:0", 20, index);
            if (index == 0)
                trace_at = number;
            else if (index == 2)
                trace_at = trace[0] ? 7'd87 : 7'd82;
            else if ((index >= 6) && (index <= 10)) begin
                shift = (10 - index) * 4 + 12;
                trace_at = hex_digit(trace[shift +: 4]);
            end else if ((index >= 14) && (index <= 15)) begin
                shift = (15 - index) * 4 + 4;
                trace_at = hex_digit(trace[shift +: 4]);
            end else if (index == 19)
                trace_at = hex_digit({1'b0, trace[3:1]});
        end
    endfunction

    logic [9:0] hpos, vpos;
    logic previous_hb, previous_vb;
    logic previous_hs, previous_vs;
    logic fallback_hs_seen;
    logic [9:0] fallback_hpos, fallback_vpos;
    logic [BLANK_WATCHDOG_WIDTH-1:0] blank_watchdog;

    wire fallback_raster = &blank_watchdog;
    wire fallback_hvisible = (fallback_hpos >= 10'd48) &&
                             (fallback_hpos < 10'd688);
    wire fallback_vvisible = (fallback_vpos >= 10'd35) &&
                             (fallback_vpos < 10'd435);
    wire [9:0] render_hpos = fallback_raster
        ? fallback_hpos - 10'd48 : hpos;
    wire [9:0] render_vpos = fallback_raster
        ? fallback_vpos - 10'd35 : vpos;
    wire render_hb = fallback_raster ? !fallback_hvisible : HB;
    wire render_vb = fallback_raster ? !fallback_vvisible : VB;

    always_ff @(posedge clk) begin
        if (rst) begin
            hpos        <= 10'd0;
            vpos        <= 10'd0;
            previous_hb <= 1'b0;
            previous_vb <= 1'b0;
            previous_hs <= 1'b0;
            previous_vs <= 1'b0;
            fallback_hs_seen <= 1'b0;
            fallback_hpos <= 10'd0;
            fallback_vpos <= 10'd0;
            blank_watchdog <= '0;
        end else if (pxl_cen) begin
            previous_hb <= HB;
            previous_vb <= VB;
            previous_hs <= HS;
            previous_vs <= VS;

            if (!HB && !VB)
                blank_watchdog <= '0;
            else if (!(&blank_watchdog))
                blank_watchdog <= blank_watchdog + 1'b1;

            // The normal video path may be all blank while the machine is
            // held before its first BIOS fetch. HS/VS still provide the
            // monitor timing, so align a diagnostic-only active window to
            // their trailing (rising) edges. If no HS has appeared at all,
            // the 800x449 counters keep the observer deterministic in tests.
            if (VS && !previous_vs)
                fallback_vpos <= 10'd0;
            else if (HS && !previous_hs) begin
                fallback_hs_seen <= 1'b1;
                fallback_vpos <= fallback_vpos + 10'd1;
            end else if (!fallback_hs_seen && (fallback_hpos == 10'd799)) begin
                if (fallback_vpos == 10'd448)
                    fallback_vpos <= 10'd0;
                else
                    fallback_vpos <= fallback_vpos + 10'd1;
            end

            if (HS && !previous_hs)
                fallback_hpos <= 10'd0;
            else if (!fallback_hs_seen && (fallback_hpos == 10'd799))
                fallback_hpos <= 10'd0;
            else
                fallback_hpos <= fallback_hpos + 10'd1;

            if (HB && !previous_hb) begin
                hpos <= 10'd0;
                if (!VB)
                    vpos <= vpos + 10'd1;
            end else if (!HB) begin
                hpos <= hpos + 10'd1;
            end
            if (VB && !previous_vb)
                vpos <= 10'd0;
        end
    end

    wire [9:0] tx = render_hpos - HOFFSET;
    wire [9:0] ty = render_vpos - VOFFSET;
    wire [5:0] col = {1'b0, tx[7:3]};
    wire [3:0] row = ty[6:3];
    wire [2:0] px = tx[2:0];
    wire [2:0] py = ty[2:0];
    wire in_area = (render_hpos >= HOFFSET) &&
                   (render_hpos < HOFFSET + 10'd224) &&
                   (render_vpos >= VOFFSET) &&
                   (render_vpos < VOFFSET + 10'd104);

    logic [6:0] character;
    integer nibble_shift;

    always_comb begin
        character = 7'd32;
        nibble_shift = 0;
        case (page_latched)
            2'd0: begin
                case (row)
                    4'd0: character = text_at("SPK286 CPU", 10, col);
                    4'd2: begin
                        character = text_at("CS:0000 IP:0000", 15, col);
                        if ((col >= 3) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_cpu_cs[nibble_shift +: 4]);
                        end else if ((col >= 11) && (col <= 14)) begin
                            nibble_shift = (14 - col) * 4;
                            character = hex_digit(d_cpu_ip[nibble_shift +: 4]);
                        end
                    end
                    4'd3: begin
                        character = text_at("BASE:000000", 11, col);
                        if ((col >= 5) && (col <= 10)) begin
                            nibble_shift = (10 - col) * 4;
                            character = hex_digit(d_cpu_cs_base[nibble_shift +: 4]);
                        end
                    end
                    4'd4: begin
                        character = text_at("OP:00 UPC:000 BS:0", 18, col);
                        if ((col >= 3) && (col <= 4)) begin
                            nibble_shift = (4 - col) * 4;
                            character = hex_digit(d_cpu_opcode[nibble_shift +: 4]);
                        end else if ((col >= 10) && (col <= 12)) begin
                            nibble_shift = (12 - col) * 4;
                            character = hex_digit(d_cpu_micro_pc[nibble_shift +: 4]);
                        end else if (col == 17)
                            character = hex_digit(d_cpu_biu_state);
                    end
                    4'd5: begin
                        character = text_at("FLAGS:0000 EVT:00/0", 19, col);
                        if ((col >= 6) && (col <= 9)) begin
                            nibble_shift = (9 - col) * 4;
                            character = hex_digit(d_cpu_flags[nibble_shift +: 4]);
                        end else if ((col >= 15) && (col <= 16)) begin
                            nibble_shift = (16 - col) * 4;
                            character = hex_digit(d_cpu_event_vector[nibble_shift +: 4]);
                        end else if (col == 18)
                            character = hex_digit({1'b0, d_cpu_event_kind});
                    end
                    4'd6: begin
                        character = text_at("ACT:0 PF:0 FB:0", 15, col);
                        if (col == 4) character = bit_digit(d_cpu_micro_active);
                        else if (col == 9)
                            character = hex_digit(d_cpu_prefetch_count);
                        else if (col == 14)
                            character = bit_digit(d_cpu_fetch_blocked);
                    end
                    4'd7: begin
                        character = text_at("RST:0 HLT:0 SHD:0 EVT:0", 23, col);
                        if (col == 4) character = bit_digit(d_cpu_reset);
                        else if (col == 10) character = bit_digit(d_cpu_halted);
                        else if (col == 16) character = bit_digit(d_cpu_shutdown);
                        else if (col == 22) character = bit_digit(d_cpu_event_completed);
                    end
                    4'd8: begin
                        character = text_at("ERR C:0 U:0 M:0 O:0 B:0", 23, col);
                        if (col == 6) character = bit_digit(d_cpu_control_error);
                        else if (col == 10) character = bit_digit(d_cpu_unsupported_opcode);
                        else if (col == 14) character = bit_digit(d_cpu_microcode_fault);
                        else if (col == 18) character = bit_digit(d_cpu_operand_blocked);
                        else if (col == 22) character = bit_digit(d_bridge_error);
                    end
                    4'd9: begin
                        character = text_at("FC:00000 ME:000 MI:00", 21, col);
                        if ((col >= 3) && (col <= 7)) begin
                            nibble_shift = (7 - col) * 4;
                            character = hex_digit(d_cpu_fetch_cursor_padded[nibble_shift +: 4]);
                        end else if ((col >= 12) && (col <= 14)) begin
                            nibble_shift = (14 - col) * 4;
                            character = hex_digit(d_cpu_micro_entry[nibble_shift +: 4]);
                        end else if ((col >= 19) && (col <= 20)) begin
                            nibble_shift = (20 - col) * 4;
                            character = hex_digit(d_cpu_micro_instruction[nibble_shift +: 4]);
                        end
                    end
                    4'd10: begin
                        if (AT_MODE)
                            character = text_at("CPU#:0000 AT#:0000", 18, col);
                        else
                            character = text_at("CPU#:0000 XT#:0000", 18, col);
                        if ((col >= 5) && (col <= 8)) begin
                            nibble_shift = (8 - col) * 4;
                            character = hex_digit(d_cpu_cycle_count[nibble_shift +: 4]);
                        end else if ((col >= 14) && (col <= 17)) begin
                            nibble_shift = (17 - col) * 4;
                            character = hex_digit(d_xt_cycle_count[nibble_shift +: 4]);
                        end
                    end
                    4'd11: begin
                        character = text_at("POST:00 RDY:0 VLD:0", 19, col);
                        if ((col >= 5) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_last_post[nibble_shift +: 4]);
                        end else if (col == 12) character = bit_digit(d_cpu_ready);
                        else if (col == 18) character = bit_digit(d_cpu_bus_valid);
                    end
                    4'd12: begin
                        character = text_at("SNAP:00", 7, col);
                        if ((col >= 5) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_snapshot_sequence[nibble_shift +: 4]);
                        end
                    end
                    default: character = 7'd32;
                endcase
            end

            2'd1: begin
                case (row)
                    4'd0: character = text_at("SPK286 REGISTERS", 16, col);
                    4'd2, 4'd3, 4'd4, 4'd5, 4'd7, 4'd8, 4'd10: begin
                        case (row)
                            4'd2: character = text_at("AX:0000 CX:0000", 15, col);
                            4'd3: character = text_at("DX:0000 BX:0000", 15, col);
                            4'd4: character = text_at("SP:0000 BP:0000", 15, col);
                            4'd5: character = text_at("SI:0000 DI:0000", 15, col);
                            4'd7: character = text_at("ES:0000 CS:0000", 15, col);
                            4'd8: character = text_at("SS:0000 DS:0000", 15, col);
                            default: character = text_at("IP:0000 FL:0000", 15, col);
                        endcase
                        if ((col >= 3) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            case (row)
                                4'd2: character = hex_digit(d_ax[nibble_shift +: 4]);
                                4'd3: character = hex_digit(d_dx[nibble_shift +: 4]);
                                4'd4: character = hex_digit(d_sp[nibble_shift +: 4]);
                                4'd5: character = hex_digit(d_si[nibble_shift +: 4]);
                                4'd7: character = hex_digit(d_es[nibble_shift +: 4]);
                                4'd8: character = hex_digit(d_ss[nibble_shift +: 4]);
                                default: character = hex_digit(d_cpu_ip[nibble_shift +: 4]);
                            endcase
                        end else if ((col >= 11) && (col <= 14)) begin
                            nibble_shift = (14 - col) * 4;
                            case (row)
                                4'd2: character = hex_digit(d_cx[nibble_shift +: 4]);
                                4'd3: character = hex_digit(d_bx[nibble_shift +: 4]);
                                4'd4: character = hex_digit(d_bp[nibble_shift +: 4]);
                                4'd5: character = hex_digit(d_di[nibble_shift +: 4]);
                                4'd7: character = hex_digit(d_cs[nibble_shift +: 4]);
                                4'd8: character = hex_digit(d_ds[nibble_shift +: 4]);
                                default: character = hex_digit(d_cpu_flags[nibble_shift +: 4]);
                            endcase
                        end
                    end
                    4'd11: begin
                        character = text_at("BASE:000000", 11, col);
                        if ((col >= 5) && (col <= 10)) begin
                            nibble_shift = (10 - col) * 4;
                            character = hex_digit(d_cpu_cs_base[nibble_shift +: 4]);
                        end
                    end
                    4'd12: begin
                        character = text_at("SNAP:00", 7, col);
                        if ((col >= 5) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_snapshot_sequence[nibble_shift +: 4]);
                        end
                    end
                    default: character = 7'd32;
                endcase
            end

            2'd2: begin
                case (row)
                    4'd0: character = text_at("SPK286 BUS", 10, col);
                    4'd2: begin
                        character = text_at("CPU A:000000 D:0000", 19, col);
                        if ((col >= 6) && (col <= 11)) begin
                            nibble_shift = (11 - col) * 4;
                            character = hex_digit(d_cpu_address[nibble_shift +: 4]);
                        end else if ((col >= 15) && (col <= 18)) begin
                            nibble_shift = (18 - col) * 4;
                            character = hex_digit(d_cpu_data_out[nibble_shift +: 4]);
                        end
                    end
                    4'd3: begin
                        character = text_at("S:0 V:0 W:0 BHE:0 RDY:0", 23, col);
                        if (col == 2) character = hex_digit(d_cpu_bus_status);
                        else if (col == 6) character = bit_digit(d_cpu_bus_valid);
                        else if (col == 10) character = bit_digit(d_cpu_bus_write);
                        else if (col == 16) character = bit_digit(d_cpu_bhe_n);
                        else if (col == 22) character = bit_digit(d_cpu_ready);
                    end
                    4'd4: begin
                        character = text_at("LCK:0 HLD:0 HDA:0", 17, col);
                        if (col == 4) character = bit_digit(d_cpu_bus_lock);
                        else if (col == 10) character = bit_digit(d_hold_request);
                        else if (col == 16) character = bit_digit(d_cpu_hlda);
                    end
                    4'd5: begin
                        character = text_at("CPU IN:0000", 11, col);
                        if ((col >= 7) && (col <= 10)) begin
                            nibble_shift = (10 - col) * 4;
                            character = hex_digit(d_cpu_data_in[nibble_shift +: 4]);
                        end
                    end
                    4'd6: begin
                        if (AT_MODE)
                            character = text_at("AT A:00000 D:00/00", 18, col);
                        else
                            character = text_at("XT A:00000 D:00/00", 18, col);
                        if ((col >= 5) && (col <= 9)) begin
                            nibble_shift = (9 - col) * 4;
                            character = hex_digit(d_xt_address[nibble_shift +: 4]);
                        end else if ((col >= 13) && (col <= 14)) begin
                            nibble_shift = (14 - col) * 4;
                            character = hex_digit(d_xt_data_out[nibble_shift +: 4]);
                        end else if ((col >= 16) && (col <= 17)) begin
                            nibble_shift = (17 - col) * 4;
                            character = hex_digit(d_xt_data_in[nibble_shift +: 4]);
                        end
                    end
                    4'd7: begin
                        character = text_at("S:0 V:0 W:0 IO:0 RDY:0", 22, col);
                        if (col == 2) character = hex_digit({1'b0, d_xt_status});
                        else if (col == 6) character = bit_digit(d_xt_valid);
                        else if (col == 10) character = bit_digit(d_xt_write);
                        else if (col == 15) character = bit_digit(d_xt_io);
                        else if (col == 21) character = bit_digit(d_xt_ready);
                    end
                    4'd8: begin
                        character = text_at("C:0 I:0 HI:0 MAP:0 ACT:0", 24, col);
                        if (col == 2) character = bit_digit(d_xt_code);
                        else if (col == 6) character = bit_digit(d_xt_inta);
                        else if (col == 11) character = bit_digit(d_xt_byte_high);
                        else if (col == 17) character = bit_digit(d_xt_memory_projection);
                        else if (col == 23) character = bit_digit(d_xt_cycle_active);
                    end
                    4'd9: begin
                        character = text_at("KBD:00 I:0 PB:00 P:0", 20, col);
                        if ((col >= 4) && (col <= 5)) begin
                            nibble_shift = (5 - col) * 4;
                            character = hex_digit(d_keyboard_keycode[nibble_shift +: 4]);
                        end else if (col == 9) character = bit_digit(d_keyboard_irq);
                        else if ((col >= 14) && (col <= 15)) begin
                            nibble_shift = (15 - col) * 4;
                            character = hex_digit(d_keyboard_port_b[nibble_shift +: 4]);
                        end else if (col == 19) character = bit_digit(d_keyboard_pic_int);
                    end
                    4'd10: begin
                        // DMA request/ack and BIU ownership detail replace the
                        // less useful POST-only row while diagnosing a stuck
                        // HOLD. Ack is shown in its active-low pin polarity.
                        character = text_at("I:0 R:0000 A:FFFF B:00", 22, col);
                        if (col == 2) character = bit_digit(d_bridge_idle);
                        else if ((col >= 6) && (col <= 8)) begin
                            character = 7'd48;
                        end else if (col == 9) begin
                            character = hex_digit(d_dma_request);
                        end else if ((col >= 13) && (col <= 15)) begin
                            character = 7'd48;
                        end else if (col == 16) begin
                            character = hex_digit(d_dma_acknowledge_n);
                        end else if ((col >= 20) && (col <= 21)) begin
                            nibble_shift = (21 - col) * 4;
                            character = hex_digit(d_biu_detail[nibble_shift +: 4]);
                        end
                    end
                    4'd11: begin
                        if (AT_MODE)
                            character = text_at("CPU#:0000 AT#:0000", 18, col);
                        else
                            character = text_at("CPU#:0000 XT#:0000", 18, col);
                        if ((col >= 5) && (col <= 8)) begin
                            nibble_shift = (8 - col) * 4;
                            character = hex_digit(d_cpu_cycle_count[nibble_shift +: 4]);
                        end else if ((col >= 14) && (col <= 17)) begin
                            nibble_shift = (17 - col) * 4;
                            character = hex_digit(d_xt_cycle_count[nibble_shift +: 4]);
                        end
                    end
                    4'd12: begin
                        character = text_at("SNAP:00", 7, col);
                        if ((col >= 5) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_snapshot_sequence[nibble_shift +: 4]);
                        end
                    end
                    default: character = 7'd32;
                endcase
            end

            default: begin
                case (row)
                    4'd0: begin
                        if (AT_MODE)
                            character = text_at("AT TRACE NEWEST FIRST", 21, col);
                        else
                            character = text_at("XT TRACE NEWEST FIRST", 21, col);
                    end
                    4'd2: character = trace_at(d_trace0, 7'd48, col);
                    4'd3: character = trace_at(d_trace1, 7'd49, col);
                    4'd4: character = trace_at(d_trace2, 7'd50, col);
                    4'd5: character = trace_at(d_trace3, 7'd51, col);
                    4'd7: begin
                        character = text_at("S0 INTA 1 IOR 2 IOW", 19, col);
                    end
                    4'd8: begin
                        character = text_at("S3 HALT 4 CODE 5 MEMR 6 MEMW", 28, col);
                    end
                    4'd10: begin
                        character = text_at("POST:00 AT#:0000", 16, col);
                        if ((col >= 5) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_last_post[nibble_shift +: 4]);
                        end else if ((col >= 12) && (col <= 15)) begin
                            nibble_shift = (15 - col) * 4;
                            character = hex_digit(d_xt_cycle_count[nibble_shift +: 4]);
                        end
                    end
                    4'd11: character = text_at("R/W A:ADDR D:DATA S:STATE", 25, col);
                    4'd12: begin
                        character = text_at("SNAP:00", 7, col);
                        if ((col >= 5) && (col <= 6)) begin
                            nibble_shift = (6 - col) * 4;
                            character = hex_digit(d_snapshot_sequence[nibble_shift +: 4]);
                        end
                    end
                    default: character = 7'd32;
                endcase
            end
        endcase
        if (row == 4'd1) begin
            character = text_at("RASTER:N", 8, col);
            if (col == 7)
                character = fallback_raster ? 7'd70 : 7'd78;
        end
    end

    wire [6:0] font_character = character - 7'd32;
    wire [9:0] font_address = {font_character, py};
    wire [7:0] font_data;

    jtframe_ram #(
        .aw(10),
        .synfile("font0.hex")
    ) u_font (
        .clk(clk),
        .cen(1'b1),
        .data(8'd0),
        .addr(font_address),
        .we(1'b0),
        .q(font_data)
    );

    logic [2:0] px_d0;
    wire pixel_on = font_data[3'd7 - px_d0];
    logic in_d0, in_d1;
    logic hb_d0, hb_d1;
    logic vb_d0, vb_d1;
    logic [COLW*3-1:0] rgb_d0, rgb_d1;
    logic [3:0] row_d0, row_d1;
    logic pixel_d;

    always_ff @(posedge clk) begin
        if (rst) begin
            in_d0  <= 1'b0;
            in_d1  <= 1'b0;
            hb_d0  <= 1'b1;
            hb_d1  <= 1'b1;
            vb_d0  <= 1'b1;
            vb_d1  <= 1'b1;
            rgb_d0 <= '0;
            rgb_d1 <= '0;
            row_d0 <= 4'd0;
            row_d1 <= 4'd0;
            px_d0   <= 3'd0;
            pixel_d <= 1'b0;
            HB_out  <= 1'b1;
            VB_out  <= 1'b1;
            rgb_out <= '0;
        end else if (pxl_cen) begin
            in_d0  <= in_area;
            hb_d0  <= render_hb;
            vb_d0  <= render_vb;
            rgb_d0 <= fallback_raster ? '0 : rgb_in;
            row_d0 <= row;
            px_d0  <= px;

            in_d1  <= in_d0;
            hb_d1  <= hb_d0;
            vb_d1  <= vb_d0;
            rgb_d1 <= rgb_d0;
            row_d1 <= row_d0;
            pixel_d <= pixel_on;

            HB_out <= hb_d1;
            VB_out <= vb_d1;
            if (hb_d1 || vb_d1)
                rgb_out <= '0;
            else if (in_d1 && pixel_d) begin
                if (row_d1 == 4'd0)
                    rgb_out <= {8'hff, 8'hff, 8'h00};
                else if (row_d1 == 4'd8)
                    rgb_out <= {8'hff, 8'h40, 8'h40};
                else
                    rgb_out <= {8'h40, 8'hff, 8'hff};
            end else if (in_d1) begin
                rgb_out <= {
                    rgb_d1[COLW*3-1:COLW*2+2], 2'b00,
                    rgb_d1[COLW*2-1:COLW+2], 2'b00,
                    rgb_d1[COLW-1:2], 2'b00
                };
            end else begin
                rgb_out <= {
                    1'b0, rgb_d1[COLW*3-1:COLW*2+1],
                    1'b0, rgb_d1[COLW*2-1:COLW+1],
                    1'b0, rgb_d1[COLW-1:1]
                };
            end
        end
    end

endmodule
