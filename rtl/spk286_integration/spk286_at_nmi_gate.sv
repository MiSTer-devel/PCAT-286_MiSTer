// Functional AT NMI source/mask boundary.
//
// Port 70h bit 7 is the AT NMI mask.  The initial state is masked so reset
// cannot inject an asynchronous event into the CPU.  Each source is edge
// qualified; a held source produces one NMI pulse until it is withdrawn.
`timescale 1ns/1ps

module spk286_at_nmi_gate (
    input  logic        clk,
    input  logic        reset,

    input  logic        request_valid,
    input  logic        request_command_valid,
    input  logic        request_write,
    input  logic        request_io,
    input  logic [23:0] request_address,
    input  logic [1:0]  request_byte_enable,
    input  logic [15:0] request_data_out,

    input  logic        parity_event,
    input  logic        channel_check_event,
    input  logic        external_event,

    output logic        nmi,
    output logic        nmi_masked,
    output logic        request_accept,
    output logic        request_ready,
    output logic [15:0] request_read_data,
    output logic        request_read_data_valid,
    output logic        protocol_error
);
    logic request_target_valid;
    logic transaction_done_q;
    logic transaction_read_q;
    logic nmi_mask_q;
    logic source_active_q;
    logic [7:0] read_data_q;

    assign request_target_valid = request_valid && request_command_valid &&
                                  request_io && !request_write &&
                                  (request_address[15:0] == 16'h0070) &&
                                  (request_byte_enable == 2'b01);
    assign request_accept = !transaction_done_q &&
                            (request_target_valid ||
                             (request_valid && request_command_valid &&
                              request_io && request_write &&
                              (request_address[15:0] == 16'h0070) &&
                              (request_byte_enable == 2'b01)));
    assign request_ready = transaction_done_q;
    assign request_read_data = {8'h00, read_data_q};
    assign request_read_data_valid = transaction_done_q && transaction_read_q;
    assign nmi_masked = nmi_mask_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            transaction_done_q <= 1'b0;
            transaction_read_q <= 1'b0;
            nmi_mask_q <= 1'b1;
            source_active_q <= 1'b0;
            read_data_q <= 8'h80;
            nmi <= 1'b0;
            protocol_error <= 1'b0;
        end else begin
            nmi <= (parity_event || channel_check_event || external_event) &&
                   !source_active_q && !nmi_mask_q;
            source_active_q <= parity_event || channel_check_event ||
                               external_event;

            if (transaction_done_q)
                transaction_done_q <= 1'b0;

            if (request_accept) begin
                transaction_done_q <= 1'b1;
                transaction_read_q <= !request_write;
                if (request_write) begin
                    nmi_mask_q <= request_data_out[7];
                    read_data_q <= {request_data_out[7], 7'b0};
                end else begin
                    read_data_q <= {nmi_mask_q, 7'b0};
                end
            end

            if (request_valid && request_command_valid && request_io &&
                (request_address[15:0] == 16'h0070) &&
                (request_byte_enable != 2'b01))
                protocol_error <= 1'b1;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset)
            assert (!(request_read_data_valid && !request_ready))
                else $error("AT NMI gate returned data outside READY");
    end
`endif
endmodule
