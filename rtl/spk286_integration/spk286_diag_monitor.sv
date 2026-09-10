// Passive observer for the project-owned diagnostic ROM's architectural
// port-write signatures. It never acknowledges or modifies a bus transfer.
`timescale 1ns/1ps

module spk286_diag_monitor (
    input  logic        clk,
    input  logic        reset,
    input  logic        accepted_io_write,
    input  logic [15:0] port_address,
    input  logic [7:0]  write_data,
    output logic        diagnostic_pass,
    output logic        diagnostic_failure,
    output logic [2:0]  progress
);
    always_ff @(posedge clk) begin
        if (reset) begin
            diagnostic_pass <= 1'b0;
            diagnostic_failure <= 1'b0;
            progress <= 3'd0;
        end else if (accepted_io_write) begin
            if (port_address == 16'h0081)
                diagnostic_failure <= 1'b1;

            if (port_address == 16'h0080 && !diagnostic_pass) begin
                case (progress)
                    3'd0: progress <= (write_data == 8'h70) ? 3'd1 : 3'd0;
                    3'd1: progress <= (write_data == 8'h72) ? 3'd2 :
                                     (write_data == 8'h70) ? 3'd1 : 3'd0;
                    3'd2: progress <= (write_data == 8'h71) ? 3'd3 :
                                     (write_data == 8'h70) ? 3'd1 : 3'd0;
                    3'd3: begin
                        if (write_data == 8'h86) begin
                            diagnostic_pass <= 1'b1;
                            progress <= 3'd4;
                        end else
                            progress <= (write_data == 8'h70) ? 3'd1 : 3'd0;
                    end
                    default: progress <= progress;
                endcase
            end
        end
    end
endmodule
