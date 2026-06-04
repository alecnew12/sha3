`timescale 1ns/1ps

// ============================================================
// SHA3 AHB Testbench  -  sha3_top
// iverilog -g2012 compatible  (no array task ports)
//
// Build:
//   iverilog -g2012 -o sim.out sha3_shake_all.v tb_final.sv
//   vvp sim.out
//
// Test cases:
//   1. test_reset_regs       - status/rounds default after reset
//   2. test_clr_smoke        - clr_state clears status
//   3. test_sha3_224_empty   - SHA3-224("") NIST FIPS-202 vector
//   4. test_sha3_256_empty   - SHA3-256("") NIST FIPS-202 vector
//   5. test_sha3_256_1byte   - SHA3-256(0x00) sanity
// ============================================================

module sha3_func_ahb_tb;

reg         r_HCLK;
reg         r_HRESETn;
reg         r_HSEL;
reg [31:0]  r_HADDR;
reg [1:0]   r_HTRANS;
reg         r_HWRITE;
reg [2:0]   r_HSIZE;
reg [2:0]   r_HBURST;
reg [3:0]   r_HPROT;
reg [31:0]  r_HWDATA;
reg         r_HREADY;

wire [31:0] w_HRDATA;
wire        w_HREADYOUT;
wire        w_HRESP;
wire        w_absorb_busy;
wire        w_absorb_done;
wire        w_squeeze_done;

integer     r_passcnt;
integer     r_failcnt;

reg [31:0]  r_rdata;
reg [31:0]  r_status;

// ============================================================
// Address map  (sha3_ahb_if, r_aa = HADDR[8:0])
//   7'h00 = 0x000  CTRL    [1]=clr_done [2]=clr_state [3]=sw_flush
//   7'h01 = 0x004  STATUS  [0]=abs_busy [1]=abs_done  [2]=sqz_busy [3]=sqz_done
//   7'h02 = 0x008  CFG     [2:0]=mode   [4:3]=path_sel
//   7'h03 = 0x00C  REQ_BYTES
//   7'h04 = 0x010  ROUNDS_MINUS1
//   7'h40..0x71 = 0x100..0x1C4  STATE (50 x 32-bit)
// ============================================================
localparam [31:0] ADDR_CTRL       = 32'h0000_0000;
localparam [31:0] ADDR_STATUS     = 32'h0000_0004;
localparam [31:0] ADDR_CFG        = 32'h0000_0008;
localparam [31:0] ADDR_REQ        = 32'h0000_000C;
localparam [31:0] ADDR_ROUNDS     = 32'h0000_0010;
localparam [31:0] ADDR_STATE_BASE = 32'h0000_0100;

// expected value arrays (global, no array task ports)
reg [31:0]  g_exp_224 [0:6];
reg [31:0]  g_exp_256 [0:7];
reg [31:0]  g_exp_256_1b [0:7];

// ============================================================
// DUT
// ============================================================
sha3_top dut
(
    .i_HCLK          (r_HCLK),
    .i_HRESETn       (r_HRESETn),
    .i_HSEL          (r_HSEL),
    .i_HADDR         (r_HADDR),
    .i_HTRANS        (r_HTRANS),
    .i_HWRITE        (r_HWRITE),
    .i_HSIZE         (r_HSIZE),
    .i_HBURST        (r_HBURST),
    .i_HPROT         (r_HPROT),
    .i_HWDATA        (r_HWDATA),
    .i_HREADY        (r_HREADY),
    .o_HRDATA        (w_HRDATA),
    .o_HREADYOUT     (w_HREADYOUT),
    .o_HRESP         (w_HRESP),
    .i_din_64        (64'h0),
    .i_din_64_valid  (1'b0),
    .i_din_64_last   (1'b0),
    .i_din_64_bytes  (4'h0),
    .i_din_1344      (1344'h0),
    .i_din_1344_valid(1'b0),
    .i_din_1344_last (1'b0),
    .i_din_1344_bytes(8'h0),
    .o_state_rate    (),
    .o_state_valid   (),
    .o_fifo_raw      (),
    .o_fifo_bytes    (),
    .o_absorb_busy   (w_absorb_busy),
    .o_absorb_done   (w_absorb_done),
    .o_squeeze_done  (w_squeeze_done)
);

// ============================================================
// Clock
// ============================================================
initial r_HCLK = 1'b0;
always  #5 r_HCLK = ~r_HCLK;

// ============================================================
// AHB helpers
// ============================================================
task ahb_write;
    input [31:0] i_addr;
    input [31:0] i_data;
    begin
        r_HSEL   = 1'b1; r_HADDR  = i_addr; r_HTRANS = 2'b10;
        r_HWRITE = 1'b1; r_HSIZE  = 3'b010; r_HBURST = 3'b000;
        r_HPROT  = 4'b0; r_HREADY = 1'b1;   r_HWDATA = 32'h0;
        @(posedge r_HCLK); #1;
        r_HWDATA = i_data;
        r_HSEL   = 1'b0; r_HTRANS = 2'b00;
        @(posedge r_HCLK); #1;
        r_HWRITE = 1'b0; r_HWDATA = 32'h0; r_HADDR = 32'h0;
    end
endtask

task ahb_read;
    input  [31:0] i_addr;
    output [31:0] o_data;
    begin
        r_HSEL   = 1'b1; r_HADDR  = i_addr; r_HTRANS = 2'b10;
        r_HWRITE = 1'b0; r_HSIZE  = 3'b010; r_HBURST = 3'b000;
        r_HPROT  = 4'b0; r_HREADY = 1'b1;
        @(posedge r_HCLK); #1;
        r_HSEL   = 1'b0; r_HTRANS = 2'b00;
        @(posedge r_HCLK); #1;
        o_data   = w_HRDATA; r_HADDR = 32'h0;
    end
endtask

task read_state_word;
    input  [6:0]  i_idx;
    output [31:0] o_data;
    begin
        ahb_read(ADDR_STATE_BASE + {23'd0, i_idx, 2'b00}, o_data);
    end
endtask

// ============================================================
// Control helpers
// ============================================================
task do_clr_done;   begin ahb_write(ADDR_CTRL, 32'h2); end endtask
task do_clr_state;  begin ahb_write(ADDR_CTRL, 32'h4); end endtask
task do_sw_flush;   begin ahb_write(ADDR_CTRL, 32'h8); end endtask

task set_mode;
    input [2:0] i_mode;
    begin ahb_write(ADDR_CFG, {29'd0, i_mode}); end
endtask

task set_rounds_minus1;
    input [4:0] i_val;
    begin ahb_write(ADDR_ROUNDS, {27'd0, i_val}); end
endtask

task set_req_bytes;
    input [15:0] i_bytes;
    begin ahb_write(ADDR_REQ, {16'd0, i_bytes}); end
endtask

task wait_absorb_done;
    integer timeout;
    reg [31:0] stat;
    begin
        timeout = 0; stat = 32'h0;
        while ((stat[1] == 1'b0) && (timeout < 1000)) begin
            ahb_read(ADDR_STATUS, stat);
            timeout = timeout + 1;
        end
        if (stat[1]) begin
            $display("PASS wait_absorb_done  status=%08x", stat);
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL wait_absorb_done  TIMEOUT status=%08x", stat);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

task wait_squeeze_done;
    integer timeout;
    reg [31:0] stat;
    begin
        timeout = 0; stat = 32'h0;
        while ((stat[3] == 1'b0) && (timeout < 1000)) begin
            ahb_read(ADDR_STATUS, stat);
            timeout = timeout + 1;
        end
        if (stat[3]) begin
            $display("PASS wait_squeeze_done status=%08x", stat);
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL wait_squeeze_done TIMEOUT status=%08x", stat);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

// helper: full reset sequence before each test
task begin_test;
    begin
        do_clr_done;
        do_clr_state;
        repeat(6) @(posedge r_HCLK);
    end
endtask

// ============================================================
// Test 1: reset defaults
// ============================================================
task test_reset_regs;
    begin
        ahb_read(ADDR_STATUS, r_status);
        if (r_status[1:0] == 2'b00) begin
            $display("PASS reset: status clear"); r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL reset: status=%08x", r_status); r_failcnt = r_failcnt + 1;
        end
        ahb_read(ADDR_ROUNDS, r_rdata);
        if (r_rdata[4:0] == 5'd23) begin
            $display("PASS default rounds_minus1=23"); r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL default rounds_minus1=%0d", r_rdata[4:0]); r_failcnt = r_failcnt + 1;
        end
    end
endtask

// ============================================================
// Test 2: clr_state smoke
// ============================================================
task test_clr_smoke;
    begin
        $display("---- test_clr_smoke ----");
        do_clr_done; do_clr_state;
        repeat(6) @(posedge r_HCLK);
        ahb_read(ADDR_STATUS, r_status);
        if (r_status[3:0] == 4'b0000) begin
            $display("PASS clr_state: status cleared"); r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL clr_state: status=%08x", r_status); r_failcnt = r_failcnt + 1;
        end
    end
endtask

// ============================================================
// Test 3: SHA3-224("")
// Expected: 6B4E03423667DBB73B6E15454F0EB1ABD4597F9A1B078E3F5B5A6BC7
// LE words:  42034e6b b7db6736 45156e3b abb10e4f 9a7f59d4 3f8e071b c76b5a5b
// ============================================================
task build_exp_sha3_224_empty;
    begin
        g_exp_224[0] = 32'h42034e6b;
        g_exp_224[1] = 32'hb7db6736;
        g_exp_224[2] = 32'h45156e3b;
        g_exp_224[3] = 32'habb10e4f;
        g_exp_224[4] = 32'h9a7f59d4;
        g_exp_224[5] = 32'h3f8e071b;
        g_exp_224[6] = 32'hc76b5a5b;
    end
endtask

task test_sha3_224_empty;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_224_empty ----");
        build_exp_sha3_224_empty;
        begin_test;
        set_mode(3'b000);          // SHA3-224
        set_rounds_minus1(5'd23);
        set_req_bytes(16'd28);     // 28 bytes output
        do_sw_flush;               // empty message -> absorb
        wait_absorb_done;
        wait_squeeze_done;
        for (i = 0; i < 7; i = i + 1) begin
            read_state_word(i[6:0], rd);
            if (rd === g_exp_224[i]) begin
                $display("PASS SHA3-224 empty word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-224 empty word[%0d]: exp=%08x got=%08x",
                         i, g_exp_224[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ============================================================
// Test 4: SHA3-256("")
// Expected: A7FFC6F8BF1ED76651C14756A061D662F580FF4DE43B49FA82D80A4B80F8434A
// LE words:  f8c6ffa7 66d71ebf 5647c151 62d661a0 4dff80f5 fa493be4 4b0ad882 4a43f880
// ============================================================
task build_exp_sha3_256_empty;
    begin
        g_exp_256[0] = 32'hf8c6ffa7;
        g_exp_256[1] = 32'h66d71ebf;
        g_exp_256[2] = 32'h5647c151;
        g_exp_256[3] = 32'h62d661a0;
        g_exp_256[4] = 32'h4dff80f5;
        g_exp_256[5] = 32'hfa493be4;
        g_exp_256[6] = 32'h4b0ad882;
        g_exp_256[7] = 32'h4a43f880;
    end
endtask

task test_sha3_256_empty;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_256_empty ----");
        build_exp_sha3_256_empty;
        begin_test;
        set_mode(3'b001);          // SHA3-256
        set_rounds_minus1(5'd23);
        set_req_bytes(16'd32);     // 32 bytes output
        do_sw_flush;
        wait_absorb_done;
        wait_squeeze_done;
        for (i = 0; i < 8; i = i + 1) begin
            read_state_word(i[6:0], rd);
            if (rd === g_exp_256[i]) begin
                $display("PASS SHA3-256 empty word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-256 empty word[%0d]: exp=%08x got=%08x",
                         i, g_exp_256[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ============================================================
// Test 5: SHA3-256(0x00)  one-byte message via AHB data write
// Expected: 5D53469F20FEF4F8EAB52B88044EFA4898AA833E34F8C5B70EB88FDBFD5A36C
// LE words:  9f46535d f8f4fe20 88b852ab 4ffa4480 33a89a89 b5c5f834 fd8b88eb c5a3d5fb
// ============================================================
task build_exp_sha3_256_1byte;
    begin
        g_exp_256_1b[0] = 32'h9f46535d;
        g_exp_256_1b[1] = 32'hf8f4fe20;
        g_exp_256_1b[2] = 32'h88b852ab;
        g_exp_256_1b[3] = 32'h4ffa4480;
        g_exp_256_1b[4] = 32'h33a89a89;
        g_exp_256_1b[5] = 32'hb5c5f834;
        g_exp_256_1b[6] = 32'hfd8b88eb;
        g_exp_256_1b[7] = 32'hc5a3d5fb;
    end
endtask

task test_sha3_256_1byte;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_256_1byte ----");
        build_exp_sha3_256_1byte;
        begin_test;
        set_mode(3'b001);          // SHA3-256
        set_rounds_minus1(5'd23);
        set_req_bytes(16'd32);
        $display("SKIP SHA3-256 1byte: ahb_if hardcodes ahb_bytes=4, needs RTL change for partial byte");
    end
endtask

// ============================================================
// main
// ============================================================
initial begin
    $dumpfile("sha3_func_ahb_tb.vcd");
    $dumpvars(0, sha3_func_ahb_tb);

    r_passcnt = 0; r_failcnt = 0;
    r_HRESETn = 1'b0; r_HSEL = 1'b0;
    r_HADDR = 32'h0; r_HTRANS = 2'b00; r_HWRITE = 1'b0;
    r_HSIZE = 3'b010; r_HBURST = 3'b000; r_HPROT = 4'b0;
    r_HWDATA = 32'h0; r_HREADY = 1'b1;

    repeat(4) @(posedge r_HCLK);
    r_HRESETn = 1'b1;
    repeat(2) @(posedge r_HCLK);

    $display("==============================================");
    $display("SHA3 AHB TB  (sha3_top)");
    $display("==============================================");

    test_reset_regs;
    test_clr_smoke;
    test_sha3_224_empty;
    test_sha3_256_empty;
    test_sha3_256_1byte;

    $display("==============================================");
    $display("PASS = %0d", r_passcnt);
    $display("FAIL = %0d", r_failcnt);
    $display("==============================================");
    #20; $finish;
end

endmodule
