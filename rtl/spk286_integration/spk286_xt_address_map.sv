// Initial XT_COMPAT address policy. The CPU retains its native 24-bit trace;
// each emitted byte beat is projected independently onto the XT bus.
`timescale 1ns/1ps

module spk286_xt_address_map (
    input  logic [23:0] cpu_address,
    input  logic        cycle_is_io,
    output logic [19:0] xt_address,
    output logic        memory_projection
);
    always_comb begin
        // I/O retains the observed 17th-bit carry (for example the second
        // physical transfer after port FFFF) within the 20-bit XT boundary.
        // Memory deliberately aliases every 1 MiB in the initial XT profile.
        xt_address = cpu_address[19:0];
        memory_projection = !cycle_is_io && (cpu_address[23:20] != 4'd0);
    end
endmodule
