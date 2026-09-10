// Runtime external ownership requires a real SPK286 grant and a drained bridge.
// Reset-held initial loading is a separate owner and never waits for CPU HLDA.
`timescale 1ns/1ps

module spk286_xt_ownership (
    input  logic external_request,
    input  logic loader_reset_owner,
    input  logic cpu_hlda,
    input  logic cpu_lock,
    input  logic bridge_idle,
    output logic cpu_hold_request,
    output logic external_grant
);
    always_comb begin
        cpu_hold_request = external_request && !loader_reset_owner;
        external_grant = external_request &&
                         (loader_reset_owner ||
                          (cpu_hlda && bridge_idle && !cpu_lock));
    end
endmodule
