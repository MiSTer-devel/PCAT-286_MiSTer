// Production MiSTer ROM download sequencer for the XT-compatible address map.
// Input words arrive through hps_io WIDE=1 and are serialized into byte writes
// for the inherited external bus owner.
`timescale 1ns/1ps

module pcat_rom_loader (
    input  logic        clock,
    input  logic        reset,
    input  logic        sdram_initialized,
    input  logic [1:0]  rom_protect,
    input  logic        processor_ready,
    input  logic        address_direction,
    input  logic        ioctl_download,
    input  logic [7:0]  ioctl_index,
    input  logic        ioctl_wr,
    input  logic [24:0] ioctl_addr,
    input  logic [15:0] ioctl_data,

    output logic        ioctl_wait,
    output logic [2:0]  bios_protect_flag,
    output logic        bios_access_request,
    output logic [19:0] bios_access_address,
    output logic [15:0] bios_write_data,
    output logic        bios_write_n,
    output logic [7:0]  bios_write_wait_count,
    output logic        bios_write_byte_count,
    output logic [4:0]  bios_load_state,
    output logic        main_rom_loaded,
    output logic        ega_rom_loaded,
    output logic        ega_rom_write_protect,
    output logic [1:0]  ega_video_switches
);
    wire select_main = (ioctl_index[5:0] == 0) &&
                       (ioctl_addr[24:16] == 9'b000000000);
    wire select_xtide = ioctl_index == 2;
    wire select_ega = (ioctl_index[5:0] == 3) &&
                      (ioctl_addr[24:16] == 9'b000000000);
    wire ega_download_active = ioctl_download &&
                               (ioctl_index[5:0] == 6'd3);
    wire main_download_active = ioctl_download &&
                                (ioctl_index[5:0] == 6'd0);
    wire ega_write_complete = (bios_load_state == 5'h04) &&
                              bios_write_byte_count && select_ega;
    wire main_write_complete = (bios_load_state == 5'h04) &&
                               bios_write_byte_count && select_main;

    wire [19:0] mapped_address = select_main ?
                                  {4'b1111, ioctl_addr[15:0]} :
                                  select_xtide ?
                                  {6'b111011, ioctl_addr[13:0]} :
                                  select_ega ?
                                  {4'b1100, ioctl_addr[15:0]} :
                                  20'hfffff;
    wire selected_download = ioctl_download &&
                             (select_main || select_xtide || select_ega);

    ega_bios_loaded_latch ega_presence (
        .clock(clock),
        .reset(reset),
        .sdram_initialized(sdram_initialized),
        .download_active(ega_download_active),
        .write_complete(ega_write_complete),
        .loaded(ega_rom_loaded),
        .write_protect(ega_rom_write_protect),
        .video_switches(ega_video_switches)
    );

    rom_presence_latch main_presence (
        .clock(clock),
        .reset(reset),
        .sdram_initialized(sdram_initialized),
        .download_active(main_download_active),
        .write_complete(main_write_complete),
        .loaded(main_rom_loaded)
    );

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            bios_protect_flag <= 3'b011;
            bios_access_request <= 1'b0;
            bios_access_address <= 20'hfffff;
            bios_write_data <= 16'hffff;
            bios_write_n <= 1'b1;
            bios_write_wait_count <= 8'h00;
            bios_write_byte_count <= 1'b0;
            ioctl_wait <= 1'b1;
            bios_load_state <= 5'h00;
        end else if (!sdram_initialized) begin
            bios_protect_flag <= 3'b011;
            bios_access_request <= 1'b0;
            bios_access_address <= 20'hfffff;
            bios_write_data <= 16'hffff;
            bios_write_n <= 1'b1;
            bios_write_wait_count <= 8'h00;
            bios_write_byte_count <= 1'b0;
            ioctl_wait <= 1'b1;
            bios_load_state <= 5'h00;
        end else begin
            case (bios_load_state)
                5'h00: begin
                    bios_protect_flag <= {ega_rom_write_protect,
                                          ~rom_protect};
                    bios_access_address <= 20'hfffff;
                    bios_write_data <= 16'hffff;
                    bios_write_n <= 1'b1;
                    bios_write_wait_count <= 8'h00;
                    bios_write_byte_count <= 1'b0;
                    if (!ioctl_download) begin
                        bios_access_request <= 1'b0;
                        ioctl_wait <= 1'b0;
                    end else begin
                        bios_access_request <= 1'b1;
                        ioctl_wait <= 1'b1;
                    end
                    if (ioctl_download && !processor_ready &&
                        address_direction)
                        bios_load_state <= 5'h01;
                end

                5'h01: begin
                    bios_protect_flag <= 3'b000;
                    bios_access_request <= 1'b1;
                    bios_write_byte_count <= 1'b0;
                    if (!ioctl_download) begin
                        bios_access_address <= 20'hfffff;
                        bios_write_data <= 16'hffff;
                        bios_write_n <= 1'b1;
                        bios_write_wait_count <= 8'h00;
                        ioctl_wait <= 1'b0;
                        bios_load_state <= 5'h00;
                    end else if (!ioctl_wr || !selected_download) begin
                        bios_access_address <= 20'hfffff;
                        bios_write_data <= 16'hffff;
                        bios_write_n <= 1'b1;
                        bios_write_wait_count <= 8'h00;
                        ioctl_wait <= 1'b0;
                    end else begin
                        bios_access_address <= mapped_address;
                        bios_write_data <= ioctl_data;
                        bios_write_n <= 1'b1;
                        bios_write_wait_count <= 8'h00;
                        ioctl_wait <= 1'b1;
                        bios_load_state <= 5'h02;
                    end
                end

                5'h02: begin
                    bios_protect_flag <= 3'b000;
                    bios_access_request <= 1'b1;
                    ioctl_wait <= 1'b1;
                    bios_write_wait_count <= bios_write_wait_count + 8'd1;
                    if (bios_write_wait_count != 8'd20)
                        bios_write_n <= 1'b0;
                    else begin
                        bios_write_n <= 1'b1;
                        bios_load_state <= 5'h03;
                    end
                end

                5'h03: begin
                    bios_protect_flag <= 3'b000;
                    bios_access_request <= 1'b1;
                    bios_write_n <= 1'b1;
                    ioctl_wait <= 1'b1;
                    bios_write_wait_count <= bios_write_wait_count + 8'd1;
                    if (bios_write_wait_count == 8'h40)
                        bios_load_state <= 5'h04;
                end

                5'h04: begin
                    bios_protect_flag <= 3'b000;
                    bios_access_request <= 1'b1;
                    bios_access_address <= bios_access_address + 20'd1;
                    bios_write_data <= {8'hff, bios_write_data[15:8]};
                    bios_write_n <= 1'b1;
                    bios_write_wait_count <= 8'h00;
                    bios_write_byte_count <= ~bios_write_byte_count;
                    ioctl_wait <= 1'b1;
                    if (!bios_write_byte_count)
                        bios_load_state <= 5'h02;
                    else
                        bios_load_state <= 5'h01;
                end

                default: begin
                    bios_protect_flag <= {ega_rom_write_protect, 2'b11};
                    bios_access_request <= 1'b0;
                    bios_access_address <= 20'hfffff;
                    bios_write_data <= 16'hffff;
                    bios_write_n <= 1'b1;
                    bios_write_wait_count <= 8'h00;
                    bios_write_byte_count <= 1'b0;
                    ioctl_wait <= 1'b0;
                    bios_load_state <= 5'h00;
                end
            endcase
        end
    end
endmodule
