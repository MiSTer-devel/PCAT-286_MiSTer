`timescale 1ns/1ps

module spk286_at_nmi_gate_tb;
    logic        clk = 1'b0;
    logic        reset = 1'b1;
    logic        request_valid = 1'b0;
    logic        request_command_valid = 1'b0;
    logic        request_write = 1'b0;
    logic        request_io = 1'b0;
    logic [23:0] request_address = 24'h0;
    logic [1:0]  request_byte_enable = 2'b00;
    logic [15:0] request_data_out = 16'h0;
    logic        parity_event = 1'b0;
    logic        channel_check_event = 1'b0;
    logic        external_event = 1'b0;
    wire         nmi;
    wire         nmi_masked;
    wire         request_accept;
    wire         request_ready;
    wire [15:0]  request_read_data;
    wire         request_read_data_valid;
    wire         protocol_error;

    always #5 clk = ~clk;

    spk286_at_nmi_gate dut (
        .clk                         (clk),
        .reset                       (reset),
        .request_valid               (request_valid),
        .request_command_valid       (request_command_valid),
        .request_write               (request_write),
        .request_io                  (request_io),
        .request_address             (request_address),
        .request_byte_enable         (request_byte_enable),
        .request_data_out            (request_data_out),
        .parity_event                (parity_event),
        .channel_check_event         (channel_check_event),
        .external_event              (external_event),
        .nmi                         (nmi),
        .nmi_masked                  (nmi_masked),
        .request_accept              (request_accept),
        .request_ready               (request_ready),
        .request_read_data           (request_read_data),
        .request_read_data_valid     (request_read_data_valid),
        .protocol_error              (protocol_error)
    );

    task automatic clear_request;
        begin
            request_valid = 1'b0;
            request_command_valid = 1'b0;
            request_write = 1'b0;
            request_io = 1'b0;
            request_address = 24'h0;
            request_byte_enable = 2'b00;
            request_data_out = 16'h0;
        end
    endtask

    task automatic write_nmi_mask(input logic value);
        integer cycles;
        logic found;
        begin
            @(negedge clk);
            request_valid = 1'b1;
            request_command_valid = 1'b1;
            request_write = 1'b1;
            request_io = 1'b1;
            request_address = 24'h70;
            request_byte_enable = 2'b01;
            request_data_out = {8'h00, {value, 7'b0}};
            #1;
            if (!request_accept)
                $fatal(1, "A3 NMI mask write was not accepted");
            found = 1'b0;
            for (cycles = 0; cycles < 6 && !found; cycles = cycles + 1) begin
                @(posedge clk);
                #1;
                if (request_ready) begin
                    found = 1'b1;
                end
            end
            if (!found)
                $fatal(1, "A3 NMI mask write did not complete");
            clear_request();
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        reset = 1'b0;

        if (!nmi_masked || nmi)
            $fatal(1, "A3 NMI reset policy mismatch");

        parity_event = 1'b1;
        @(posedge clk);
        #1;
        if (nmi)
            $fatal(1, "A3 masked parity event produced NMI");
        parity_event = 1'b0;
        @(posedge clk);
        #1;

        write_nmi_mask(1'b0);
        if (nmi_masked)
            $fatal(1, "A3 NMI enable write did not clear mask");

        // Held source is edge-qualified to one pulse.
        channel_check_event = 1'b1;
        @(posedge clk);
        #1;
        if (!nmi)
            $fatal(1, "A3 unmasked channel-check event did not produce NMI");
        @(posedge clk);
        #1;
        if (nmi)
            $fatal(1, "A3 held channel-check source retriggered NMI");
        channel_check_event = 1'b0;
        @(posedge clk);
        #1;

        write_nmi_mask(1'b1);
        external_event = 1'b1;
        @(posedge clk);
        #1;
        if (nmi)
            $fatal(1, "A3 remasked source produced NMI");
        external_event = 1'b0;

        if (protocol_error)
            $fatal(1, "A3 NMI gate reported a protocol error");

        $display("A3_AT_NMI_PASS mask_policy=edge_qualified");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "A3 NMI test timeout");
    end
endmodule
