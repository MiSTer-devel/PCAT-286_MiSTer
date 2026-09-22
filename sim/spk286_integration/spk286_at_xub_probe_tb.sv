`timescale 1ns/1ps
// Actual instruction CPU and production AT chipset. RAM is a byte-array
// fixture, not SDRAM. Execute the real BIOS IVT initialization and floppy
// parameter handler; unrelated POST/video/keyboard setup is bypassed.
module spk286_at_xub_probe_tb;
    logic clk=0, reset=1;
    always #10 clk=~clk;
    wire counter_clock;
    spk286_at_pit_clock pit_clock(.clk(clk),.reset(reset),.counter_clock(counter_clock));
    wire mem_valid, mem_command, mem_write, mem_accept;
    wire [23:0] mem_addr;
    wire [1:0] mem_be;
    wire [15:0] mem_out;
    logic mem_ready=0;
    logic [15:0] mem_in=0;
    byte unsigned mem [0:1048575];
    byte unsigned rom [0:65535];
    byte unsigned xub [0:16383];
    byte unsigned fixture [0:2047];
    wire [15:0] cs, ip;
    wire fault, protocol_error, shutdown;
    wire [127:0] gpr;
    integer cycles=0, max_cycles=15000000;
    integer trace_file, trace_count=0, trace_limit=0, ide_reads=0, tick_writes=0;
    integer visits [0:65535];
    logic [15:0] history [0:31];
    integer history_index=0;
    logic full_init=0;
    logic saw_xub=0;
    logic expect_missing_int40=0;
    logic [15:0] mgmt_address=0, mgmt_writedata=0;
    logic mgmt_write=0, mgmt_read=0;
    wire [15:0] mgmt_readdata;
    wire [2:0] ide_request;
    integer identify_commands=0, read_commands=0;
    assign mem_accept=mem_valid && mem_command && !mem_ready;
    always @(posedge clk) begin
        mem_ready <= mem_accept;
        if (mem_accept) begin
            mem_in <= {mem[{mem_addr[19:1],1'b1}],mem[{mem_addr[19:1],1'b0}]};
            if (mem_write) begin
                if(mem_be[0]) mem[{mem_addr[19:1],1'b0}] <= mem_out[7:0];
                if(mem_be[1]) mem[{mem_addr[19:1],1'b1}] <= mem_out[15:8];
                if(mem_addr[19:1]==19'h00236) tick_writes<=tick_writes+1;
            end
        end
    end
    spk286_at_machine dut (
        .clk(clk),.clk_cpu(clk),.cpu_sample_edge(1'b1),.reset(reset),.cpu_reset(1'b0),.clk_video(clk),
        .splashscreen(1'b0),.installed_ram_size_osd(3'd0),
        .execute_enable(1'b1),.counter_clock(counter_clock),
        .refresh_enable(1'b0),.keyboard_byte_valid(1'b0),.keyboard_byte(8'd0),
        .periodic_tick(1'b0),.second_tick(1'b0),.parity_event(1'b0),
        .channel_check_event(1'b0),.external_nmi_event(1'b0),
        .mgmt_address(mgmt_address),.mgmt_writedata(mgmt_writedata),.mgmt_write(mgmt_write),
        .mgmt_read(mgmt_read),.mgmt_readdata(mgmt_readdata),.ide_request(ide_request),
        .use_mmc(2'b00),.floppy_write_protect(2'b00),
        .memory_request_valid(mem_valid),.memory_command_valid(mem_command),
        .memory_write(mem_write),.memory_address(mem_addr),
        .memory_byte_enable(mem_be),.memory_data_out(mem_out),
        .memory_accept(mem_accept),.memory_ready(mem_ready),
        .memory_read_data(mem_in),.memory_read_data_valid(mem_ready),
        .dma_memory_accept(1'b0),.dma_memory_ready(1'b0),.dma_memory_data_in(16'd0),
        .refresh_memory_accept(1'b0),.refresh_memory_ready(1'b0),
        .debug_cs(cs),.debug_ip(ip),.debug_gpr(gpr),.cpu_fault(fault),
        .cpu_shutdown(shutdown),.protocol_error(protocol_error)
    );
    always @(negedge clk) if(!reset) begin
        cycles=cycles+1;
        if (dut.at_completed && dut.at_io && !dut.at_write &&
            dut.at_address>=24'h1f0 && dut.at_address<=24'h1f7) ide_reads=ide_reads+1;
        if(dut.u_cpu.cpu.opcode_start) begin
            history[history_index%32]=ip;
            history_index=history_index+1;
            if(trace_count<trace_limit) begin
                $fdisplay(trace_file,"%0d %04h:%04h op=%02h gpr=%h seg=%h flags=%h",
                    cycles,cs,ip,dut.debug_opcode,gpr,dut.debug_segment_selectors,dut.debug_flags);
                trace_count=trace_count+1;
            end
            if(cs==16'hc800) begin
                saw_xub=1;
                visits[ip]=visits[ip]+1;
                if(visits[ip]==1 && (ip==16'h3d7 || ip==16'h498 || ip==16'h505 ||
                   ip==16'h40d || ip==16'h807 || ip==16'h89a || ip==16'ha3c ||
                   ip==16'ha5a || ip==16'hdeb || ip==16'he03 || ip==16'hc3c || ip==16'h534 ||
                   ip==16'h849 || ip==16'h899 || ip==16'h94f || ip==16'h40c ||
                   ip==16'hc4b || ip==16'hc5e || ip==16'hc60 || ip==16'hca1 ||
                   ip==16'h158e || ip==16'h15bc || ip==16'h124c))
                    $display("XUB_STAGE %04h:%04h cycles=%0d gpr=%h seg=%h tick=%02h%02h",
                        cs,ip,cycles,gpr,dut.debug_segment_selectors,mem['h46d],mem['h46c]);
                if(ip==16'hc3c && !full_init) begin
                    full_init=1;
                    $display("AT_XUB_PROBE_INIT_PASS cycles=%0d ide_reads=%0d tick_writes=%0d",cycles,ide_reads,tick_writes);
                    if(!$test$plusargs("CONTINUE_BOOT")) $finish;
                end
                if(ip==16'h807 && $test$plusargs("STOP_AT_DETECTION")) begin
                    if(expect_missing_int40) $fatal(1,"Missing INT40 unexpectedly passed");
                    $display("AT_XUB_INT40_PASS reached_detection=1 int40=%02h%02h:%02h%02h cycles=%0d",
                        mem['h103],mem['h102],mem['h101],mem['h100],cycles);
                    $finish;
                end
            end
            if(cs==0 && ip==16'h7c00 && read_commands>0) begin
                $display("AT_XUB_BOOT_PASS identify=%0d reads=%0d cycles=%0d",identify_commands,read_commands,cycles);
                $finish;
            end
            if(saw_xub && cs==0 && ip<16'h400) begin
                if(!expect_missing_int40) $fatal(1,"XUB jumped through an empty IVT vector csip=%h:%h",cs,ip);
                if(visits['h534]==0) $fatal(1,"Empty-vector jump did not follow XUB INT40");
                $display("AT_XUB_INT40_REPRODUCED banner=1 detect=0 bad_target=%h:%h cycles=%0d",cs,ip,cycles);
                $finish;
            end
        end
        if(fault || shutdown || protocol_error)
            $fatal(1,"XUB_CPU_FAULT csip=%h:%h op=%h flags=%h gpr=%h",cs,ip,dut.debug_opcode,dut.debug_flags,gpr);
        if(cycles>=max_cycles) begin
            for(integer n=0;n<32;n=n+1) $write("%04h ",history[(history_index+n)%32]);
            $display("");
            $fatal(1,"XUB_WATCHDOG csip=%h:%h gpr=%h seg=%h tick=%02h%02h tick_writes=%0d ide_reads=%0d",
                cs,ip,gpr,dut.debug_segment_selectors,mem['h46d],mem['h46c],tick_writes,ide_reads);
        end
    end
    // Optional synthetic HPS disk model. It uses only the management port,
    // not forced IDE state. Two ATA disks, IDENTIFY, reset, setup commands and
    // a single boot sector are sufficient to trace the post-detection path.
    task automatic host_write(input logic [3:0] address, input logic [15:0] data);
        @(negedge clk);
        mgmt_address={12'hf00,address}; mgmt_writedata=data; mgmt_write=1;
        @(negedge clk); mgmt_write=0;
        repeat(2) @(negedge clk);
    endtask
    task automatic host_read(input logic [3:0] address, output logic [15:0] data);
        @(negedge clk); mgmt_address={12'hf00,address}; mgmt_read=1;
        repeat(3) @(negedge clk);
        data=mgmt_readdata; mgmt_read=0;
        repeat(2) @(negedge clk);
    endtask
    function automatic logic [15:0] identify_word(input integer n);
        case(n)
            0: return 16'h0040;
            1,54: return 16'd512;
            3,55: return 16'd16;
            4: return 16'd32256;
            5,21: return 16'd512;
            6,56: return 16'd63;
            20: return 16'd3;
            22: return 16'd4;
            27: return 16'h5350; // SPK286 synthetic disk
            28: return 16'h4b32;
            29: return 16'h3836;
            47: return 16'h8020;
            48: return 16'h0001;
            49,51,52: return 16'h0200;
            50: return 16'h4001;
            53: return 16'h0007;
            57,60: return 16'he000;
            58,61: return 16'h0007;
            59: return 16'h0110;
            80: return 16'h007e;
            default: return (n>=10 && n<=46) ? 16'h2020 : 16'h0000;
        endcase
    endfunction
    logic [15:0] host_taskfile;
    logic [7:0] host_command, host_drive;
    initial begin
        wait(!reset);
        if($test$plusargs("TWO_DISKS")) begin
            host_write(6,16'h0099);
            forever begin
                wait(ide_request!=0);
                host_read(5,host_taskfile);
                host_command=host_taskfile[15:8]; host_drive=host_taskfile[7:0];
                if(ide_request==6) begin
                    host_write(0,0); host_write(1,16'h0101); host_write(2,0);
                    // Main_MiSTer repeatedly services request 6 with BSY.
                    // Its status write clears the request only once the CPU
                    // releases SRST; waiting without another write deadlocks
                    // the host fixture, not the real IDE implementation.
                    do host_write(5,{8'h80,host_drive}); while(ide_request==6);
                    host_write(5,{8'h40,host_drive});
                end else if(ide_request==4) begin
                    $display("HOST_CMD cmd=%02h drive=%02h csip=%04h:%04h cycles=%0d",
                        host_command,host_drive,cs,ip,cycles);
                    case(host_command)
                        8'hec,8'h20,8'h21,8'hc4: begin
                            if(host_command!=8'hec) begin
                                host_read(1,host_taskfile);
                                if(host_taskfile[7:0]!=1)
                                    $fatal(1,"Synthetic boot read must request exactly one sector");
                            end
                            host_write(0,1);
                            for(integer n=0;n<256;n=n+1)
                                host_write(15,host_command==8'hec ? identify_word(n) :
                                    (n==255 ? 16'haa55 : (n==0 ? 16'hfeeb : 16'h0000)));
                            host_write(5,{8'h4e,host_drive}); // RDY, DRQ, IRQ, last block
                            if(host_command==8'hec) identify_commands=identify_commands+1;
                            else read_commands=read_commands+1;
                        end
                        8'h91,8'h10,8'hef,8'hc6: host_write(5,{8'h44,host_drive});
                        8'h70: begin // Main_MiSTer does not implement SEEK
                            host_write(0,16'h0400);
                            host_write(5,{8'h45,host_drive}); // RDY, ERR, IRQ / ABRT
                        end
                        default: $fatal(1,"Unimplemented synthetic host command %02h",host_command);
                    endcase
                end else $fatal(1,"Unexpected synthetic host request %0d",ide_request);
            end
        end
    end
    string rom_path,xub_path,fixture_path,trace_path;
    integer fd,count;
    initial begin
        if(!$value$plusargs("ROM=%s",rom_path) || !$value$plusargs("XUB=%s",xub_path) ||
           !$value$plusargs("FIXTURE=%s",fixture_path)) $fatal(1,"ROM, XUB and FIXTURE are required");
        if($value$plusargs("MAX_CYCLES=%d",max_cycles)) begin end
        if($value$plusargs("TRACE_LIMIT=%d",trace_limit)) begin end
        expect_missing_int40=$test$plusargs("EXPECT_MISSING_INT40");
        if($value$plusargs("TRACE=%s",trace_path)) trace_file=$fopen(trace_path,"w");
        fd=$fopen(rom_path,"rb"); count=$fread(rom,fd); $fclose(fd);
        if(count!=65536) $fatal(1,"ROM must be 64KiB");
        for(integer n=0;n<65536;n=n+1) mem['hf0000+n]=rom[n];
        fd=$fopen(xub_path,"rb"); count=$fread(xub,fd); $fclose(fd);
        if(count!=8192) $fatal(1,"Probe currently expects the r631 8KiB AT ROM");
        for(integer n=0;n<count;n=n+1) mem['hc8000+n]=xub[n];
        fd=$fopen(fixture_path,"rb"); count=$fread(fixture,fd); $fclose(fd);
        for(integer n=0;n<count;n=n+1) mem['hf0000+n]=fixture[n];
        if(mem['hfe198]!=8'h0e || mem['hfe1b0]!=8'hb0)
            $fatal(1,"Unexpected Sergey IVT initialization boundaries");
        mem['hfe1b0]=8'hc3; // return immediately after actual IVT/DS setup
        mem['hffff0]='hea; mem['hffff1]=0; mem['hffff2]=0;
        mem['hffff3]=0; mem['hffff4]='hf0;
        repeat(8) @(negedge clk);
        reset=0;
    end
endmodule
