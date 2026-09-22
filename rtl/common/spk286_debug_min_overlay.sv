// SPDX-License-Identifier: GPL-3.0-only
//
// Compact hardware observer for PCAT-286. It keeps only the state needed to
// identify a stopped BIOS path and one completed AT transfer.

`timescale 1ns/1ps

module spk286_debug_min_overlay #(
    parameter integer COLW = 8,
    parameter integer BLANK_WATCHDOG_WIDTH = 18,
    parameter integer SNAPSHOT_TIMER_WIDTH = 20,
    parameter logic CPU_DIV2 = 1'b0
) (
    input  logic              rst,
    input  logic              src_rst,
    input  logic              src_clk,
    input  logic              clk,
    input  logic              pxl_cen,
    input  logic              HS,
    input  logic              VS,
    input  logic              HB,
    input  logic              VB,
    input  logic [COLW*3-1:0] rgb_in,

    input  logic              cpu_reset,
    input  logic              cpu_halted,
    input  logic              cpu_shutdown,
    input  logic              cpu_control_error,
    input  logic              cpu_unsupported_opcode,
    input  logic              cpu_microcode_fault,
    input  logic              cpu_operand_blocked,
    input  logic              bridge_error,
    input  logic [7:0]        cpu_opcode,
    input  logic [15:0]       cpu_cs,
    input  logic [15:0]       cpu_ip,
    input  logic [15:0]       cpu_flags,
    input  logic [15:0]       cpu_cx,
    input  logic [11:0]       cpu_micro_pc,
    input  logic [3:0]        cpu_biu_state,
    input  logic              cpu_fetch_blocked,
    input  logic              cpu_ready,
    input  logic              cpu_bus_valid,
    input  logic              cpu_hlda,
    input  logic              instruction_retired,
    input  logic              irq8,
    input  logic              cpu_intr,
    input  logic [7:0]        last_post,
    input  logic [31:0]       trace0,
    input  logic [19:0]       at_address,
    input  logic [7:0]        at_data_out,
    input  logic [7:0]        at_data_in,
    input  logic [2:0]        at_status,
    input  logic              at_valid,
    input  logic              at_write,
    input  logic              at_io,
    input  logic              at_ready,
    input  logic              at_read_data_valid,
    input  logic              bridge_idle,
    input  logic [3:0]        bridge_state,
    input  logic              hold_request,
    input  logic              dma_request,
    input  logic              refresh_request,
    input  logic              dma_grant,
    input  logic              refresh_grant,
    input  logic [4:0]        memory_port_state,
    input  logic [4:0]        read_buffer_state,
    input  logic [7:0]        sdram_owner_state,
    input  logic [7:0]        biu_detail,

    output logic              HB_out,
    output logic              VB_out,
    output logic [COLW*3-1:0] rgb_out
);
    localparam logic [9:0] HOFFSET = 10'd16;
    localparam logic [9:0] VOFFSET = 10'd16;

    typedef struct packed {
        logic        cpu_reset;
        logic        cpu_halted;
        logic        cpu_shutdown;
        logic [4:0]  errors;
        logic [7:0]  cpu_opcode;
        logic [15:0] cpu_cs;
        logic [15:0] cpu_ip;
        logic [15:0] cpu_flags;
        logic [15:0] cpu_cx;
        logic [11:0] cpu_micro_pc;
        logic [3:0]  cpu_biu_state;
        logic        cpu_fetch_blocked;
        logic        cpu_ready;
        logic        cpu_bus_valid;
        logic        cpu_hlda;
        logic [15:0] instruction_count;
        logic        irq8;
        logic        cpu_intr;
        logic [7:0]  last_post;
        logic [31:0] trace0;
        logic [19:0] at_address;
        logic [7:0]  at_data_out;
        logic [7:0]  at_data_in;
        logic [2:0]  at_status;
        logic        at_valid;
        logic        at_write;
        logic        at_io;
        logic        at_ready;
        logic        at_read_data_valid;
        logic        bridge_idle;
        logic [3:0]  bridge_state;
        logic        hold_request;
        logic        dma_request;
        logic        refresh_request;
        logic        dma_grant;
        logic        refresh_grant;
        logic [4:0]  memory_port_state;
        logic [4:0]  read_buffer_state;
        logic [7:0]  sdram_owner_state;
        logic [7:0]  biu_detail;
    } debug_state_t;

    debug_state_t state_async;
    debug_state_t source_snapshot = '0;
    debug_state_t video_snapshot = '0;
    logic [7:0] source_sequence = 8'd0;
    logic [7:0] video_sequence = 8'd0;
    logic [15:0] instruction_count = 16'd0;

    always_comb begin
        state_async.cpu_reset         = cpu_reset;
        state_async.cpu_halted        = cpu_halted;
        state_async.cpu_shutdown      = cpu_shutdown;
        state_async.errors            = {
            bridge_error, cpu_operand_blocked, cpu_microcode_fault,
            cpu_unsupported_opcode, cpu_control_error
        };
        state_async.cpu_opcode        = cpu_opcode;
        state_async.cpu_cs            = cpu_cs;
        state_async.cpu_ip            = cpu_ip;
        state_async.cpu_flags         = cpu_flags;
        state_async.cpu_cx            = cpu_cx;
        state_async.cpu_micro_pc      = cpu_micro_pc;
        state_async.cpu_biu_state     = cpu_biu_state;
        state_async.cpu_fetch_blocked = cpu_fetch_blocked;
        state_async.cpu_ready         = cpu_ready;
        state_async.cpu_bus_valid     = cpu_bus_valid;
        state_async.cpu_hlda          = cpu_hlda;
        state_async.instruction_count = instruction_count;
        state_async.irq8              = irq8;
        state_async.cpu_intr          = cpu_intr;
        state_async.last_post         = last_post;
        state_async.trace0            = trace0;
        state_async.at_address        = at_address;
        state_async.at_data_out       = at_data_out;
        state_async.at_data_in        = at_data_in;
        state_async.at_status         = at_status;
        state_async.at_valid          = at_valid;
        state_async.at_write          = at_write;
        state_async.at_io             = at_io;
        state_async.at_ready          = at_ready;
        state_async.at_read_data_valid = at_read_data_valid;
        state_async.bridge_idle       = bridge_idle;
        state_async.bridge_state      = bridge_state;
        state_async.hold_request      = hold_request;
        state_async.dma_request       = dma_request;
        state_async.refresh_request   = refresh_request;
        state_async.dma_grant         = dma_grant;
        state_async.refresh_grant     = refresh_grant;
        state_async.memory_port_state = memory_port_state;
        state_async.read_buffer_state = read_buffer_state;
        state_async.sdram_owner_state = sdram_owner_state;
        state_async.biu_detail        = biu_detail;
    end

    logic snapshot_request = 1'b0;
    logic snapshot_acknowledge = 1'b0;
    logic snapshot_acknowledge_seen = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_request_src1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_request_src2 = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_ack_video1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) logic snapshot_ack_video2 = 1'b0;
    logic [SNAPSHOT_TIMER_WIDTH-1:0] snapshot_timer = '0;

    always_ff @(posedge src_clk) begin
        if (src_rst) begin
            snapshot_request_src1 <= 1'b0;
            snapshot_request_src2 <= 1'b0;
            snapshot_acknowledge  <= 1'b0;
            source_snapshot       <= '0;
            source_sequence       <= 8'd0;
            instruction_count     <= 16'd0;
        end else begin
            if (instruction_retired)
                instruction_count <= instruction_count + 16'd1;
            snapshot_request_src1 <= snapshot_request;
            snapshot_request_src2 <= snapshot_request_src1;
            if (snapshot_request_src2 != snapshot_acknowledge) begin
                source_snapshot       <= state_async;
                source_sequence       <= source_sequence + 8'd1;
                snapshot_acknowledge  <= snapshot_request_src2;
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
            video_sequence            <= 8'd0;
            snapshot_timer            <= '0;
        end else begin
            snapshot_ack_video1  <= snapshot_acknowledge;
            snapshot_ack_video2  <= snapshot_ack_video1;
            // Keep diagnostic sampling alive even while BIOS video setup
            // suppresses or corrupts vertical blanking.  A VB-triggered
            // mailbox can otherwise freeze on an arbitrary bus phase and
            // make a display failure look like a stopped CPU transaction.
            if (snapshot_ack_video2 == snapshot_request) begin
                if (&snapshot_timer) begin
                    snapshot_request <= ~snapshot_request;
                    snapshot_timer   <= '0;
                end else
                    snapshot_timer <= snapshot_timer + 1'b1;
            end else
                snapshot_timer <= '0;
            if (snapshot_ack_video2 != snapshot_acknowledge_seen) begin
                video_snapshot            <= source_snapshot;
                video_sequence            <= source_sequence;
                snapshot_acknowledge_seen <= snapshot_ack_video2;
            end
        end
    end

    function automatic [6:0] hex_digit(input logic [3:0] value);
        hex_digit = (value < 4'd10)
            ? (7'd48 + {3'd0, value})
            : (7'd55 + {3'd0, value});
    endfunction

    function automatic [6:0] bit_digit(input logic value);
        bit_digit = value ? 7'd49 : 7'd48;
    endfunction

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
            hpos <= 10'd0;
            vpos <= 10'd0;
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

            if (VS && !previous_vs)
                fallback_vpos <= 10'd0;
            else if (HS && !previous_hs) begin
                fallback_hs_seen <= 1'b1;
                fallback_vpos <= fallback_vpos + 10'd1;
            end else if (!fallback_hs_seen &&
                         (fallback_hpos == 10'd799)) begin
                if (fallback_vpos == 10'd448)
                    fallback_vpos <= 10'd0;
                else
                    fallback_vpos <= fallback_vpos + 10'd1;
            end

            if (HS && !previous_hs)
                fallback_hpos <= 10'd0;
            else if (!fallback_hs_seen &&
                     (fallback_hpos == 10'd799))
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
                   (render_vpos < VOFFSET + 10'd128);

    logic [6:0] character;
    integer nibble_shift;

    always_comb begin
        character = 7'd32;
        nibble_shift = 0;
        case (row)
            4'd0: character = CPU_DIV2
                ? text_at("SPK286 MIN DEBUG /2", 19, col)
                : text_at("SPK286 MIN DEBUG", 16, col);
            4'd1: begin
                character = text_at("RASTER:N", 8, col);
                if (col == 7)
                    character = fallback_raster ? 7'd70 : 7'd78;
            end
            4'd2: begin
                character = text_at("CS:0000 IP:0000", 15, col);
                if ((col >= 3) && (col <= 6)) begin
                    nibble_shift = (6 - col) * 4;
                    character = hex_digit(video_snapshot.cpu_cs[nibble_shift +: 4]);
                end else if ((col >= 11) && (col <= 14)) begin
                    nibble_shift = (14 - col) * 4;
                    character = hex_digit(video_snapshot.cpu_ip[nibble_shift +: 4]);
                end
            end
            4'd3: begin
                character = text_at("OP:00 UPC:000 BS:0", 18, col);
                if ((col >= 3) && (col <= 4)) begin
                    nibble_shift = (4 - col) * 4;
                    character = hex_digit(video_snapshot.cpu_opcode[nibble_shift +: 4]);
                end else if ((col >= 10) && (col <= 12)) begin
                    nibble_shift = (12 - col) * 4;
                    character = hex_digit(video_snapshot.cpu_micro_pc[nibble_shift +: 4]);
                end else if (col == 17)
                    character = hex_digit(video_snapshot.cpu_biu_state);
            end
            4'd4: begin
                character = text_at("FLAGS:0000 CX:0000 FB:0", 23, col);
                if ((col >= 6) && (col <= 9)) begin
                    nibble_shift = (9 - col) * 4;
                    character = hex_digit(video_snapshot.cpu_flags[nibble_shift +: 4]);
                end else if ((col >= 14) && (col <= 17)) begin
                    nibble_shift = (17 - col) * 4;
                    character = hex_digit(video_snapshot.cpu_cx[nibble_shift +: 4]);
                end else if (col == 22)
                    character = bit_digit(video_snapshot.cpu_fetch_blocked);
            end
            4'd5: begin
                character = text_at("RST:0 HLT:0 SHD:0", 17, col);
                if (col == 4) character = bit_digit(video_snapshot.cpu_reset);
                else if (col == 10) character = bit_digit(video_snapshot.cpu_halted);
                else if (col == 16) character = bit_digit(video_snapshot.cpu_shutdown);
            end
            4'd6: begin
                character = text_at("ERR C:0 U:0 M:0 O:0 B:0", 23, col);
                if (col == 6) character = bit_digit(video_snapshot.errors[0]);
                else if (col == 10) character = bit_digit(video_snapshot.errors[1]);
                else if (col == 14) character = bit_digit(video_snapshot.errors[2]);
                else if (col == 18) character = bit_digit(video_snapshot.errors[3]);
                else if (col == 22) character = bit_digit(video_snapshot.errors[4]);
            end
            4'd7: begin
                character = text_at("POST:00 RDY:0 VLD:0 RET:0000", 28, col);
                if ((col >= 5) && (col <= 6)) begin
                    nibble_shift = (6 - col) * 4;
                    character = hex_digit(video_snapshot.last_post[nibble_shift +: 4]);
                end else if (col == 12)
                    character = bit_digit(video_snapshot.cpu_ready);
                else if (col == 18)
                    character = bit_digit(video_snapshot.cpu_bus_valid);
                else if ((col >= 24) && (col <= 27)) begin
                    nibble_shift = (27 - col) * 4;
                    character = hex_digit(video_snapshot.instruction_count[nibble_shift +: 4]);
                end
            end
            4'd8: begin
                character = text_at("AT A:00000 S:0 V:0", 18, col);
                if ((col >= 5) && (col <= 9)) begin
                    nibble_shift = (9 - col) * 4;
                    character = hex_digit(video_snapshot.at_address[nibble_shift +: 4]);
                end else if (col == 13)
                    character = hex_digit({1'b0, video_snapshot.at_status});
                else if (col == 17)
                    character = bit_digit(video_snapshot.at_valid);
            end
            4'd9: begin
                character = text_at("W:0 IO:0 RDY:0 I:0 H:0", 22, col);
                if (col == 2) character = bit_digit(video_snapshot.at_write);
                else if (col == 7) character = bit_digit(video_snapshot.at_io);
                else if (col == 13) character = bit_digit(video_snapshot.at_ready);
                else if (col == 17) character = bit_digit(video_snapshot.bridge_idle);
                else if (col == 21) character = bit_digit(video_snapshot.hold_request);
            end
            4'd10: begin
                character = text_at("D:00/00 BIU:00", 14, col);
                if ((col >= 2) && (col <= 3)) begin
                    nibble_shift = (3 - col) * 4;
                    character = hex_digit(video_snapshot.at_data_out[nibble_shift +: 4]);
                end else if ((col >= 5) && (col <= 6)) begin
                    nibble_shift = (6 - col) * 4;
                    character = hex_digit(video_snapshot.at_data_in[nibble_shift +: 4]);
                end else if ((col >= 12) && (col <= 13)) begin
                    nibble_shift = (13 - col) * 4;
                    character = hex_digit(video_snapshot.biu_detail[nibble_shift +: 4]);
                end
            end
            4'd11: begin
                character = text_at("IRQ8:0 INT:0 HLDA:0", 19, col);
                if (col == 5)
                    character = bit_digit(video_snapshot.irq8);
                else if (col == 11)
                    character = bit_digit(video_snapshot.cpu_intr);
                else if (col == 18)
                    character = bit_digit(video_snapshot.cpu_hlda);
            end
            4'd12: begin
                character = text_at("DMA:0/0 REF:0/0 BR:0 DV:0", 25, col);
                if (col == 4)
                    character = bit_digit(video_snapshot.dma_request);
                else if (col == 6)
                    character = bit_digit(video_snapshot.dma_grant);
                else if (col == 12)
                    character = bit_digit(video_snapshot.refresh_request);
                else if (col == 14)
                    character = bit_digit(video_snapshot.refresh_grant);
                else if (col == 19)
                    character = hex_digit(video_snapshot.bridge_state);
                else if (col == 24)
                    character = bit_digit(video_snapshot.at_read_data_valid);
            end
            4'd13: begin
                character = text_at("LAST R A:00000 D:00 S:0", 23, col);
                if (col == 5)
                    character = video_snapshot.trace0[0] ? 7'd87 : 7'd82;
                else if ((col >= 9) && (col <= 13)) begin
                    nibble_shift = (13 - col) * 4 + 12;
                    character = hex_digit(video_snapshot.trace0[nibble_shift +: 4]);
                end else if ((col >= 17) && (col <= 18)) begin
                    nibble_shift = (18 - col) * 4 + 4;
                    character = hex_digit(video_snapshot.trace0[nibble_shift +: 4]);
                end else if (col == 22)
                    character = hex_digit({1'b0, video_snapshot.trace0[3:1]});
            end
            4'd14: begin
                character = text_at("MP A:0 K:0 O:0 C:0 BF:0/0/0", 27, col);
                if (col == 5)
                    character = bit_digit(video_snapshot.memory_port_state[4]);
                else if (col == 9)
                    character = bit_digit(video_snapshot.memory_port_state[3]);
                else if (col == 13)
                    character = hex_digit({2'b00, video_snapshot.memory_port_state[2:1]});
                else if (col == 17)
                    character = bit_digit(video_snapshot.memory_port_state[0]);
                else if (col == 22)
                    character = hex_digit({2'b00, video_snapshot.read_buffer_state[4:3]});
                else if (col == 24)
                    character = bit_digit(video_snapshot.read_buffer_state[2]);
                else if (col == 26)
                    character = bit_digit(video_snapshot.read_buffer_state[1]);
            end
            4'd15: begin
                character = text_at("SD:0/0/0 K:0 F:0 SNAP:00", 24, col);
                if (col == 3)
                    character = bit_digit(video_snapshot.sdram_owner_state[7]);
                else if (col == 5)
                    character = bit_digit(video_snapshot.sdram_owner_state[6]);
                else if (col == 7)
                    character = bit_digit(video_snapshot.sdram_owner_state[5]);
                else if (col == 11)
                    character = bit_digit(video_snapshot.sdram_owner_state[3]);
                else if (col == 15)
                    character = hex_digit({1'b0, video_snapshot.sdram_owner_state[2:0]});
                else if ((col >= 22) && (col <= 23)) begin
                    nibble_shift = (23 - col) * 4;
                    character = hex_digit(video_sequence[nibble_shift +: 4]);
                end
            end
            default: character = 7'd32;
        endcase
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
            in_d0 <= 1'b0;
            in_d1 <= 1'b0;
            hb_d0 <= 1'b1;
            hb_d1 <= 1'b1;
            vb_d0 <= 1'b1;
            vb_d1 <= 1'b1;
            rgb_d0 <= '0;
            rgb_d1 <= '0;
            row_d0 <= 4'd0;
            row_d1 <= 4'd0;
            px_d0 <= 3'd0;
            pixel_d <= 1'b0;
            HB_out <= 1'b1;
            VB_out <= 1'b1;
            rgb_out <= '0;
        end else if (pxl_cen) begin
            in_d0 <= in_area;
            hb_d0 <= render_hb;
            vb_d0 <= render_vb;
            rgb_d0 <= fallback_raster ? '0 : rgb_in;
            row_d0 <= row;
            px_d0 <= px;

            in_d1 <= in_d0;
            hb_d1 <= hb_d0;
            vb_d1 <= vb_d0;
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
                else if (row_d1 == 4'd6)
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
