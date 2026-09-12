// Passive first-fault capture, independent of the live debug page.
`timescale 1ns/1ps
module spk286_at_fault_trace (
    input logic clk,
    input logic reset,
    input logic [18:0] sources,
    input logic [15:0] cpu_cs, cpu_ip,
    input logic [23:0] cpu_address,
    input logic [7:0] cpu_opcode,
    input logic [12:0] bus_flags,
    output logic captured,
    output wire [127:0] words
);
    logic [18:0] first_sources;
    logic [31:0] first_csip;
    logic [31:0] first_access;
    logic [12:0] first_flags;
    always_ff @(posedge clk) begin
        if (reset) begin
            captured <= 1'b0;
            first_sources <= '0;
            first_csip <= '0;
            first_access <= '0;
            first_flags <= '0;
        end else if (!captured && (|sources)) begin
            captured <= 1'b1;
            first_sources <= sources;
            first_csip <= {cpu_cs,cpu_ip};
            first_access <= {cpu_opcode,cpu_address};
            first_flags <= bus_flags;
        end
    end
    // T0 first source mask; T1 CS:IP; T2 opcode/address;
    // T3 captured bus flags [31:19] and current source mask [18:0].
    assign words = {first_flags,sources,first_access,first_csip,13'd0,first_sources};
endmodule
