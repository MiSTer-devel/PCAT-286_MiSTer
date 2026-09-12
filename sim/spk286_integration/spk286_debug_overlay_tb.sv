`timescale 1ns/1ps

module spk286_debug_overlay_tb;
    logic src_clk = 1'b0;
    logic clk = 1'b0;
    always #5 src_clk = ~src_clk;
    always #7 clk = ~clk;

    logic rst = 1'b1;
    logic src_rst = 1'b1;
    logic pxl_cen = 1'b1;
    logic HS = 1'b0;
    logic VS = 1'b0;
    logic HB = 1'b0;
    logic VB = 1'b0;
    logic [23:0] rgb_in = 24'h2569ad;
    logic [1:0] page = 2'd0;
    logic boot_trace_view = 1'b0;
    logic fault_trace_view = 1'b0;
    logic ram_trace_view = 1'b0;
`ifdef TEST_AT_BOOT_TRACE
    localparam bit TEST_AT_MODE = 1'b1;
`else
    localparam bit TEST_AT_MODE = 1'b0;
`endif

    logic cpu_reset = 1'b1;
    logic cpu_halted = 1'b0;
    logic cpu_shutdown = 1'b0;
    logic cpu_control_error = 1'b0;
    logic cpu_unsupported_opcode = 1'b0;
    logic cpu_microcode_fault = 1'b0;
    logic cpu_operand_blocked = 1'b0;
    logic cpu_event_completed = 1'b1;
    logic [7:0] cpu_event_vector = 8'h2a;
    logic [2:0] cpu_event_kind = 3'h5;
    logic [7:0] cpu_opcode = 8'hb8;
    logic [15:0] cpu_cs = 16'hf123;
    logic [23:0] cpu_cs_base = 24'hf12340;
    logic [15:0] cpu_ip = 16'h5678;
    logic [15:0] cpu_flags = 16'ha5a5;
    logic [127:0] cpu_gpr = {
        16'h8888, 16'h7777, 16'h6666, 16'h5555,
        16'h4444, 16'h3333, 16'h2222, 16'h1111
    };
    logic [63:0] cpu_segments = {
        16'hdddd, 16'hcccc, 16'hbbbb, 16'haaaa
    };
    logic cpu_fetch_blocked = 1'b1;
    logic [16:0] cpu_fetch_cursor = 17'h1abcd;
    logic [11:0] cpu_micro_pc = 12'habc;
    logic [11:0] cpu_micro_entry = 12'h789;
    logic [7:0] cpu_micro_instruction = 8'h5e;
    logic cpu_micro_active = 1'b1;
    logic [3:0] cpu_prefetch_count = 4'h6;
    logic [3:0] cpu_biu_state = 4'hd;

    logic [23:0] cpu_address = 24'h123456;
    logic [15:0] cpu_data_out = 16'hcafe;
    logic [15:0] cpu_data_in = 16'hbeef;
    logic [3:0] cpu_bus_status = 4'hd;
    logic cpu_bus_valid = 1'b1;
    logic cpu_bus_write = 1'b1;
    logic cpu_bhe_n = 1'b0;
    logic cpu_bus_lock = 1'b1;
    logic cpu_hlda = 1'b0;
    logic cpu_ready = 1'b1;

    logic [19:0] xt_address = 20'habcde;
    logic [7:0] xt_data_out = 8'h5a;
    logic [7:0] xt_data_in = 8'ha5;
    logic [2:0] xt_status = 3'd6;
    logic xt_valid = 1'b1;
    logic xt_write = 1'b1;
    logic xt_io = 1'b0;
    logic xt_inta = 1'b0;
    logic xt_code = 1'b0;
    logic xt_byte_high = 1'b1;
    logic xt_memory_projection = 1'b1;
    logic xt_cycle_active = 1'b1;
    logic xt_ready = 1'b1;
    logic bridge_idle = 1'b0;
    logic bridge_error = 1'b0;
    logic hold_request = 1'b1;

    logic [7:0] last_post = 8'h42;
    logic [15:0] cpu_cycle_count = 16'h1357;
    logic [15:0] xt_cycle_count = 16'h2468;
    logic [31:0] trace0 = {20'habcde, 8'h5a, 3'd6, 1'b1};
    logic [31:0] trace1 = {20'h12345, 8'ha6, 3'd5, 1'b0};
    logic [31:0] trace2 = {20'h6789a, 8'h3c, 3'd2, 1'b1};
    logic [31:0] trace3 = {20'hfedcb, 8'hc3, 3'd1, 1'b0};

    wire HB_out;
    wire VB_out;
    wire [23:0] rgb_out;

    spk286_debug_overlay #(
        .COLW(8),
        .BLANK_WATCHDOG_WIDTH(4),
        .AT_MODE(TEST_AT_MODE)
    ) dut (
        .rst, .src_rst, .src_clk, .clk, .pxl_cen, .HS, .VS, .HB, .VB,
        .rgb_in, .page, .boot_trace_view, .fault_trace_view, .ram_trace_view,
        .cpu_reset, .cpu_halted, .cpu_shutdown, .cpu_control_error,
        .cpu_unsupported_opcode, .cpu_microcode_fault,
        .cpu_operand_blocked, .cpu_event_completed, .cpu_event_vector,
        .cpu_event_kind, .cpu_opcode, .cpu_cs, .cpu_cs_base, .cpu_ip,
        .cpu_flags, .cpu_gpr, .cpu_segments, .cpu_fetch_blocked,
        .cpu_fetch_cursor, .cpu_micro_pc, .cpu_micro_entry,
        .cpu_micro_instruction, .cpu_micro_active, .cpu_prefetch_count,
        .cpu_biu_state, .cpu_address, .cpu_data_out, .cpu_data_in,
        .cpu_bus_status, .cpu_bus_valid, .cpu_bus_write, .cpu_bhe_n,
        .cpu_bus_lock, .cpu_hlda, .cpu_ready, .xt_address, .xt_data_out,
        .xt_data_in, .xt_status, .xt_valid, .xt_write, .xt_io, .xt_inta,
        .xt_code, .xt_byte_high, .xt_memory_projection, .xt_cycle_active,
        .xt_ready, .bridge_idle, .bridge_error, .hold_request, .last_post,
        .cpu_cycle_count, .xt_cycle_count, .trace0, .trace1, .trace2,
        .trace3, .HB_out, .VB_out, .rgb_out
    );

    task automatic fail(input string message);
        begin
            $display("DEBUG_OVERLAY_FAIL %s", message);
            $fatal(1);
        end
    endtask

    task automatic video_cycles(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1)
                @(posedge clk);
            #1;
        end
    endtask

    task automatic request_snapshot(input logic [1:0] requested_page);
        begin
            page = requested_page;
            VB = 1'b0;
            video_cycles(4);
            VB = 1'b1;
            video_cycles(1);
            VB = 1'b0;
            video_cycles(12);
        end
    endtask

    task expect_character(
        input logic [1:0] requested_page,
        input integer requested_row,
        input integer requested_column,
        input byte expected
    );
        begin
            force dut.page_latched = requested_page;
            force dut.blank_watchdog = '0;
            force dut.hpos = 10'd16 + requested_column * 8;
            force dut.vpos = 10'd16 + requested_row * 8;
            #1;
            if (dut.character !== expected[6:0]) begin
                $display(
                    "character page=%0d row=%0d col=%0d got=%c expected=%c",
                    requested_page, requested_row, requested_column,
                    dut.character, expected
                );
                fail("character extraction");
            end
            release dut.vpos;
            release dut.hpos;
            release dut.blank_watchdog;
            release dut.page_latched;
        end
    endtask

    task forced_pixel(
        input integer requested_x,
        input integer requested_y,
        input logic requested_hb,
        input logic requested_vb,
        input logic [23:0] expected_rgb
    );
        begin
            force dut.page_latched = 2'd0;
            force dut.blank_watchdog = '0;
            force dut.hpos = requested_x;
            force dut.vpos = requested_y;
            HB = requested_hb;
            VB = requested_vb;
            video_cycles(4);
            if (rgb_out !== expected_rgb) begin
                $display("pixel got=%06x expected=%06x", rgb_out, expected_rgb);
                fail("font/RGB pipeline latency");
            end
            release dut.vpos;
            release dut.hpos;
            release dut.blank_watchdog;
            release dut.page_latched;
        end
    endtask

    integer line;
    integer pixel;
    integer fallback_text_pixels;
    integer fallback_active_pixels;
    logic [7:0] first_sequence;

    initial begin
        video_cycles(4);
        src_rst = 1'b0;
        rst = 1'b0;
        video_cycles(4);

        // Capture must remain live while the observed CPU itself is in reset.
        request_snapshot(2'd1);
        if (dut.d_cpu_reset !== 1'b1)
            fail("CPU reset was not observable");
        if (dut.d_ax !== 16'h1111 || dut.d_cx !== 16'h2222 ||
            dut.d_dx !== 16'h3333 || dut.d_bx !== 16'h4444 ||
            dut.d_sp !== 16'h5555 || dut.d_bp !== 16'h6666 ||
            dut.d_si !== 16'h7777 || dut.d_di !== 16'h8888)
            fail("GPR snapshot order");
        if (dut.d_es !== 16'haaaa || dut.d_cs !== 16'hbbbb ||
            dut.d_ss !== 16'hcccc || dut.d_ds !== 16'hdddd)
            fail("segment snapshot order");
        if (dut.d_cpu_cs !== 16'hf123 || dut.d_cpu_cs_base !== 24'hf12340 ||
            dut.d_cpu_ip !== 16'h5678 || dut.d_cpu_flags !== 16'ha5a5 ||
            dut.d_cpu_opcode !== 8'hb8 || dut.d_cpu_micro_pc !== 12'habc ||
            dut.d_cpu_fetch_cursor !== 17'h1abcd ||
            dut.d_cpu_micro_entry !== 12'h789 ||
            dut.d_cpu_micro_instruction !== 8'h5e ||
            !dut.d_cpu_micro_active || dut.d_cpu_prefetch_count !== 4'h6 ||
            !dut.d_cpu_fetch_blocked)
            fail("CPU state snapshot");
        if (dut.d_cpu_address !== 24'h123456 ||
            dut.d_xt_address !== 20'habcde || dut.d_xt_data_out !== 8'h5a ||
            dut.d_cpu_cycle_count !== 16'h1357 ||
            dut.d_xt_cycle_count !== 16'h2468)
            fail("bus state snapshot");
        if (dut.d_trace0 !== trace0 || dut.d_trace1 !== trace1 ||
            dut.d_trace2 !== trace2 || dut.d_trace3 !== trace3)
            fail("trace snapshot order");
        first_sequence = dut.d_snapshot_sequence;
        if (first_sequence == 8'd0)
            fail("snapshot heartbeat did not start");

        // Data and heartbeat must advance on the next acknowledged frame.
        cpu_gpr[15:0] = 16'h9abc;
        cpu_ip = 16'hdef0;
        request_snapshot(2'd1);
        if (dut.d_ax !== 16'h9abc || dut.d_cpu_ip !== 16'hdef0)
            fail("snapshot did not refresh");
        if (dut.d_snapshot_sequence == first_sequence)
            fail("snapshot heartbeat did not advance");

        // A page selection is synchronized but never changes mid-frame.
        page = 2'd2;
        video_cycles(5);
        if (dut.page_latched !== 2'd1)
            fail("page changed outside VBlank");
        request_snapshot(2'd2);
        if (dut.page_latched !== 2'd2)
            fail("page did not change in VBlank");

        // Representative character extraction from every page, including
        // register nibbles and all fields of the newest trace entry.
        expect_character(2'd0, 0, 0, "S");
        expect_character(2'd0, 2, 3, "F");
        expect_character(2'd0, 6, 4, "1");
        expect_character(2'd0, 6, 9, "6");
        expect_character(2'd0, 6, 14, "1");
        expect_character(2'd0, 9, 3, "1");
        expect_character(2'd0, 9, 7, "D");
        expect_character(2'd0, 9, 12, "7");
        expect_character(2'd0, 9, 14, "9");
        expect_character(2'd0, 9, 19, "5");
        expect_character(2'd0, 9, 20, "E");
        expect_character(2'd1, 2, 3, "9");
        expect_character(2'd1, 2, 11, "2");
        expect_character(2'd2, 2, 6, "1");
        expect_character(2'd2, 2, 18, "E");
        expect_character(2'd3, 2, 2, "W");
        expect_character(2'd3, 2, 6, "A");
        expect_character(2'd3, 2, 10, "E");
        expect_character(2'd3, 2, 14, "5");
        expect_character(2'd3, 2, 15, "A");
        expect_character(2'd3, 2, 19, "6");

        // AT raw records preserve every nibble, including the old R/W bit.
        // The same input is explicitly ignored by the XT parameter branch.
        boot_trace_view = 1'b1;
        trace0 = 32'h89ABCDEF;
        trace1 = 32'h01234567;
        cpu_cycle_count = 16'h0020;
        xt_cycle_count = 16'h00EF;
        request_snapshot(2'd3);
        if (TEST_AT_MODE) begin
            if (!dut.d_boot_trace_view) fail("AT raw view CDC bit");
            expect_character(2'd3, 0, 3, "B");
            expect_character(2'd3, 2, 0, "T");
            expect_character(2'd3, 2, 1, "0");
            expect_character(2'd3, 2, 3, "8");
            expect_character(2'd3, 2, 6, "B");
            expect_character(2'd3, 2, 10, "F");
            expect_character(2'd3, 3, 3, "0");
            expect_character(2'd3, 3, 10, "7");
            expect_character(2'd3, 7, 4, "0");
            expect_character(2'd3, 7, 5, "F");
            expect_character(2'd3, 7, 12, "1");
            expect_character(2'd3, 7, 20, "1");
            expect_character(2'd3, 8, 6, "2");
            expect_character(2'd3, 8, 7, "0");
            expect_character(2'd3, 8, 14, "1");
            expect_character(2'd3, 8, 21, "0");
            xt_cycle_count = 16'h0140;
            cpu_cycle_count = 16'h0000;
            request_snapshot(2'd3);
            expect_character(2'd3, 8, 6, "0");
            expect_character(2'd3, 8, 14, "0");
            expect_character(2'd3, 8, 21, "1");
            $display("AT_BOOT_TRACE_OVERLAY_PASS raw_hex_and_pending_header");
        end else if (dut.d_boot_trace_view !== 1'b0)
            fail("XT must ignore the AT raw trace input");
        fault_trace_view = 1'b1;
        repeat (3) begin
            VB = 1'b0; repeat (8) @(posedge clk);
            VB = 1'b1; repeat (24) @(posedge clk);
        end
        if (TEST_AT_MODE && !dut.d_fault_trace_view) fail("AT fault view CDC bit");
        if (TEST_AT_MODE) begin
            expect_character(2'd3,0,3,"F");
            expect_character(2'd3,2,3,"8");
            expect_character(2'd3,2,10,"F");
            expect_character(2'd3,7,0,"T");
            expect_character(2'd3,8,0,"T");
            expect_character(2'd3,10,0,"H");
            $display("AT_FAULT_TRACE_OVERLAY_PASS");
        end
        if (!TEST_AT_MODE && dut.d_fault_trace_view !== 1'b0) fail("XT fault view isolation");
        ram_trace_view = 1'b1;
        xt_cycle_count = 16'h000F;
        cpu_cycle_count = 16'h0123;
        request_snapshot(2'd3);
        if (TEST_AT_MODE) begin
            if (!dut.d_ram_trace_view) fail("RAM trace CDC bit");
            expect_character(2'd3,0,3,"L");
            expect_character(2'd3,7,5,"3");
            expect_character(2'd3,7,13,"1");
            expect_character(2'd3,7,21,"1");
            expect_character(2'd3,8,15,"3");
            expect_character(2'd3,2,3,"8");
            $display("AT_RAM_TRACE_OVERLAY_PASS");
        end else if (dut.d_ram_trace_view !== 1'b0) fail("XT RAM trace isolation");
        ram_trace_view = 1'b0;
        fault_trace_view = 1'b0;
        boot_trace_view = 1'b0;
        request_snapshot(2'd0);

        // Make one glyph row unambiguous and verify the two-stage font/RGB
        // path, blank propagation and background quantization.
        dut.u_font.mem[("S" - 32) * 8] = 8'b1000_0000;
        forced_pixel(16, 16, 1'b0, 1'b0, 24'hffff00);
        forced_pixel(17, 16, 1'b0, 1'b0, 24'h2468ac);
        forced_pixel(17, 16, 1'b1, 1'b0, 24'h000000);
        if (HB_out !== 1'b1)
            fail("HB pipeline latency");

        // Splash-off reproduction: upstream RGB and blanking remain blank,
        // while HS/VS continue. The fallback raster must make text visible.
        rst = 1'b1;
        video_cycles(3);
        rst = 1'b0;
        HB = 1'b1;
        VB = 1'b1;
        HS = 1'b0;
        VS = 1'b1;
        video_cycles(1);
        VS = 1'b0;
        fallback_text_pixels = 0;
        fallback_active_pixels = 0;
        for (line = 0; line < 60; line = line + 1) begin
            HS = 1'b1;
            video_cycles(1);
            HS = 1'b0;
            for (pixel = 0; pixel < 720; pixel = pixel + 1) begin
                video_cycles(1);
                if (!HB_out && !VB_out)
                    fallback_active_pixels = fallback_active_pixels + 1;
                if (rgb_out == 24'hffff00 || rgb_out == 24'h40ffff ||
                    rgb_out == 24'hff4040)
                    fallback_text_pixels = fallback_text_pixels + 1;
            end
        end
        if (!dut.fallback_raster)
            fail("blank-input fallback did not engage");
        if (fallback_active_pixels == 0 || fallback_text_pixels == 0)
            fail("fallback raster did not produce visible debug text");

        $display(
            "DEBUG_OVERLAY_PASS snapshots=%0d active_pixels=%0d text_pixels=%0d",
            dut.d_snapshot_sequence, fallback_active_pixels,
            fallback_text_pixels
        );
        $finish;
    end
endmodule
