`timescale 1ns/1ps
// ============================================================
// tb_sha3.sv  --  sha3_top 전용 TB (sha3_shake_all.v 기반)
// ============================================================
// 레지스터 맵 (HADDR[8:0] 기준):
//   0x000  CTRL    W  [1]=clr_done  [2]=clr_state  [3]=sw_flush
//   0x004  STATUS  R  [0]=abs_busy  [1]=abs_done   [2]=sqz_busy  [3]=sqz_done
//   0x008  CONFIG  W  [2:0]=mode    [4:3]=path_sel
//   0x00C  REQ_BYTES W [15:0]
//   0x010  ROUNDS  W  [4:0]
//   0x100~ STATE   R/W  idx*4  (core_state 32bit slice, AHB path write -> fifo)
//
// 동작 시퀀스:
//   clr_state -> set_mode -> write_msg_words(STATE addr)
//   -> sw_flush -> wait absorb_done(STATUS[1])
//   -> wait squeeze_done(STATUS[3]) -> read STATE[0x100+]
// ============================================================

module tb_sha3;

// ---------------------------------------------------------------
// 포트
// ---------------------------------------------------------------
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

wire [31:0]   w_HRDATA;
wire          w_HREADYOUT;
wire          w_HRESP;
wire [1343:0] w_state_rate;
wire          w_state_valid;
wire [1343:0] w_fifo_raw;
wire [7:0]    w_fifo_bytes;
wire          w_absorb_busy;
wire          w_absorb_done;
wire          w_squeeze_done;

// ---------------------------------------------------------------
// 레지스터 주소
// ---------------------------------------------------------------
localparam [31:0] ADDR_CTRL       = 32'h0000_0000;
localparam [31:0] ADDR_STATUS     = 32'h0000_0004;
localparam [31:0] ADDR_CONFIG     = 32'h0000_0008;
localparam [31:0] ADDR_REQ_BYTES  = 32'h0000_000C;
localparam [31:0] ADDR_ROUNDS     = 32'h0000_0010;
localparam [31:0] ADDR_STATE_BASE = 32'h0000_0100;

// CTRL 비트
localparam [31:0] CTRL_CLR_DONE  = 32'h0000_0002;
localparam [31:0] CTRL_CLR_STATE = 32'h0000_0004;
localparam [31:0] CTRL_SW_FLUSH  = 32'h0000_0008;

// ---------------------------------------------------------------
// 카운터
// ---------------------------------------------------------------
integer r_passcnt, r_failcnt, r_i;
reg [31:0] r_rdata, r_wtmp;

// ---------------------------------------------------------------
// 전역 배열 (iverilog: task port로 배열 불가)
// ---------------------------------------------------------------
reg [31:0] g_exp_224_word [0:6];
reg [31:0] g_exp_256_word [0:7];

// ---------------------------------------------------------------
// DUT
// ---------------------------------------------------------------
sha3_top dut (
    .i_HCLK           (r_HCLK),
    .i_HRESETn        (r_HRESETn),
    .i_HSEL           (r_HSEL),
    .i_HADDR          (r_HADDR),
    .i_HTRANS         (r_HTRANS),
    .i_HWRITE         (r_HWRITE),
    .i_HSIZE          (r_HSIZE),
    .i_HBURST         (r_HBURST),
    .i_HPROT          (r_HPROT),
    .i_HWDATA         (r_HWDATA),
    .i_HREADY         (r_HREADY),
    .o_HRDATA         (w_HRDATA),
    .o_HREADYOUT      (w_HREADYOUT),
    .o_HRESP          (w_HRESP),
    .i_din_64         (64'h0),
    .i_din_64_valid   (1'b0),
    .i_din_64_last    (1'b0),
    .i_din_64_bytes   (4'h0),
    .i_din_1344       (1344'b0),
    .i_din_1344_valid (1'b0),
    .i_din_1344_last  (1'b0),
    .i_din_1344_bytes (8'h0),
    .o_state_rate     (w_state_rate),
    .o_state_valid    (w_state_valid),
    .o_fifo_raw       (w_fifo_raw),
    .o_fifo_bytes     (w_fifo_bytes),
    .o_absorb_busy    (w_absorb_busy),
    .o_absorb_done    (w_absorb_done),
    .o_squeeze_done   (w_squeeze_done)
);

// ---------------------------------------------------------------
// 클럭
// ---------------------------------------------------------------
initial r_HCLK = 1'b0;
always #5 r_HCLK = ~r_HCLK;

// ---------------------------------------------------------------
// AHB 기본 태스크
// ---------------------------------------------------------------
task ahb_write;
    input [31:0] i_addr;
    input [31:0] i_data;
    begin
        r_HSEL   = 1'b1;
        r_HADDR  = i_addr;
        r_HTRANS = 2'b10;
        r_HWRITE = 1'b1;
        r_HSIZE  = 3'b010;
        r_HBURST = 3'b000;
        r_HPROT  = 4'b0000;
        r_HREADY = 1'b1;
        @(posedge r_HCLK); #1;
        r_HWDATA = i_data;
        r_HSEL   = 1'b0;
        r_HTRANS = 2'b00;
        @(posedge r_HCLK); #1;
        r_HWRITE = 1'b0;
        r_HWDATA = 32'h0;
        r_HADDR  = 32'h0;
    end
endtask

task ahb_read;
    input  [31:0] i_addr;
    output [31:0] o_data;
    begin
        r_HSEL   = 1'b1;
        r_HADDR  = i_addr;
        r_HTRANS = 2'b10;
        r_HWRITE = 1'b0;
        r_HSIZE  = 3'b010;
        r_HBURST = 3'b000;
        r_HPROT  = 4'b0000;
        r_HREADY = 1'b1;
        @(posedge r_HCLK); #1;
        r_HSEL   = 1'b0;
        r_HTRANS = 2'b00;
        @(posedge r_HCLK); #1;
        o_data  = w_HRDATA;
        r_HADDR = 32'h0;
    end
endtask

// ---------------------------------------------------------------
// 제어 태스크
// ---------------------------------------------------------------
task do_clr_state;
    begin ahb_write(ADDR_CTRL, CTRL_CLR_STATE); end
endtask

task do_clr_done;
    begin ahb_write(ADDR_CTRL, CTRL_CLR_DONE); end
endtask

task do_sw_flush;
    begin ahb_write(ADDR_CTRL, CTRL_SW_FLUSH); end
endtask

task set_mode;
    input [2:0] i_mode;
    input [1:0] i_path_sel;
    begin
        ahb_write(ADDR_CONFIG, {27'd0, i_path_sel, i_mode});
    end
endtask

task set_rounds;
    input [4:0] i_val;
    begin ahb_write(ADDR_ROUNDS, {27'd0, i_val}); end
endtask

task set_req_bytes;
    input [15:0] i_val;
    begin ahb_write(ADDR_REQ_BYTES, {16'd0, i_val}); end
endtask

task write_msg_word;
    input [6:0]  i_idx;
    input [31:0] i_data;
    begin
        ahb_write(ADDR_STATE_BASE + {23'd0, i_idx, 2'b00}, i_data);
    end
endtask

task read_state;
    input  [6:0]  i_idx;
    output [31:0] o_data;
    begin
        ahb_read(ADDR_STATE_BASE + {23'd0, i_idx, 2'b00}, o_data);
    end
endtask

// ---------------------------------------------------------------
// wait 태스크
// ---------------------------------------------------------------
task wait_absorb_done;
    integer cnt;
    reg [31:0] s;
    begin
        cnt = 0; s = 32'h0;
        while ((s[1] == 1'b0) && (cnt < 500)) begin
            ahb_read(ADDR_STATUS, s);
            cnt = cnt + 1;
        end
        if (s[1]) begin
            $display("PASS wait_absorb_done  status=%08x", s);
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL wait_absorb_done timeout status=%08x", s);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

task wait_squeeze_done;
    integer cnt;
    reg [31:0] s;
    begin
        cnt = 0; s = 32'h0;
        while ((s[3] == 1'b0) && (cnt < 500)) begin
            ahb_read(ADDR_STATUS, s);
            cnt = cnt + 1;
        end
        if (s[3]) begin
            $display("PASS wait_squeeze_done status=%08x", s);
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL wait_squeeze_done timeout status=%08x", s);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

// ---------------------------------------------------------------
// 기본 초기화 확인
// ---------------------------------------------------------------
task test_reset_regs;
    reg [31:0] s;
    begin
        ahb_read(ADDR_STATUS, s);
        if (s[3:0] == 4'b0000) begin
            $display("PASS reset: status clear");
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL reset: status=%08x", s);
            r_failcnt = r_failcnt + 1;
        end
        ahb_read(ADDR_ROUNDS, r_rdata);
        if (r_rdata[4:0] == 5'd23) begin
            $display("PASS default rounds_minus1 == 23");
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL default rounds_minus1 != 23, got %0d", r_rdata[4:0]);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

// ---------------------------------------------------------------
// clr_state smoke
// ---------------------------------------------------------------
task test_clr_state_smoke;
    reg [31:0] s;
    begin
        $display("---- test_clr_state_smoke ----");
        do_clr_done;
        do_clr_state;
        @(posedge r_HCLK); @(posedge r_HCLK);
        ahb_read(ADDR_STATUS, s);
        if (s[3:0] == 4'b0000) begin
            $display("PASS clr_state: status cleared");
            r_passcnt = r_passcnt + 1;
        end else begin
            $display("FAIL clr_state: status=%08x", s);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

// ---------------------------------------------------------------
// SHA3-224: 빈 메시지 테스트
// Expected: 6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7
// ---------------------------------------------------------------
task test_sha3_224_empty;
    reg [31:0] rd;
    reg [31:0] exp [0:6];
    integer i;
    begin
        $display("---- test_sha3_224_empty ----");
        exp[0] = 32'h42034E6B;
        exp[1] = 32'hB7DB6736;
        exp[2] = 32'h45156E3B;
        exp[3] = 32'hABB10E4F;
        exp[4] = 32'h9A7F59D4;
        exp[5] = 32'h3F8E071B;
        exp[6] = 32'hC76B5A5B;

        do_clr_done;
        do_clr_state;
        set_mode(3'b000, 2'b00);
        set_rounds(5'd23);
        set_req_bytes(16'd28);

        // 빈 메시지: 데이터 없이 바로 sw_flush
        do_sw_flush;

        wait_absorb_done;
        wait_squeeze_done;

        for (i = 0; i < 7; i = i + 1) begin
            read_state(i[6:0], rd);
            if (rd === exp[i]) begin
                $display("PASS SHA3-224 empty word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-224 empty word[%0d]: exp=%08x got=%08x",
                         i, exp[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ---------------------------------------------------------------
// SHA3-224: 200바이트 0xA3
// Expected: 9376816aba503f72f96ce7eb65ac095deee3be4bf9bbc2a1cb7e11e0
// rate=144B=36words  block1=36words(auto-flush) block2=14words(sw_flush)
// ---------------------------------------------------------------
task test_sha3_224_200xa3;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_224_200xa3 ----");

        g_exp_224_word[0] = 32'h6A817693;
        g_exp_224_word[1] = 32'h723F50BA;
        g_exp_224_word[2] = 32'hEBE76CF9;
        g_exp_224_word[3] = 32'h5D09AC65;
        g_exp_224_word[4] = 32'h4BBEE3EE;
        g_exp_224_word[5] = 32'hA1C2BBF9;
        g_exp_224_word[6] = 32'hE0117ECB;

        do_clr_done;
        do_clr_state;
        set_mode(3'b000, 2'b00);
        set_rounds(5'd23);
        set_req_bytes(16'd28);

        // Block1: 36 words x 4B = 144B (full rate -> auto flush)
        for (i = 0; i < 36; i = i + 1)
            write_msg_word(i[6:0], 32'hA3A3A3A3);

        // Block1 keccak 완료 대기 (약 30 클럭)
        repeat (80) @(posedge r_HCLK);

        // Block2: 14 words x 4B = 56B (partial -> sw_flush + padding)
        for (i = 0; i < 14; i = i + 1)
            write_msg_word(i[6:0], 32'hA3A3A3A3);

        do_sw_flush;

        wait_absorb_done;
        wait_squeeze_done;

        for (i = 0; i < 7; i = i + 1) begin
            read_state(i[6:0], rd);
            if (rd === g_exp_224_word[i]) begin
                $display("PASS SHA3-224 word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-224 word[%0d]: exp=%08x got=%08x",
                         i, g_exp_224_word[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ---------------------------------------------------------------
// SHA3-256: 200바이트 0xA3
// Expected: 79f38adec5c20307a98ef76e8324afbfd46cfd81b22e3973c65fa1bd9de31787
// rate=136B=34words  block1=34words(auto-flush) block2=16words(sw_flush)
// ---------------------------------------------------------------
task test_sha3_256_200xa3;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_256_200xa3 ----");

        g_exp_256_word[0] = 32'hDE8AF379;
        g_exp_256_word[1] = 32'h0703C2C5;
        g_exp_256_word[2] = 32'h6EF78EA9;
        g_exp_256_word[3] = 32'hBFAF2483;
        g_exp_256_word[4] = 32'h81FD6CD4;
        g_exp_256_word[5] = 32'h73392EB2;
        g_exp_256_word[6] = 32'hBDA15FC6;
        g_exp_256_word[7] = 32'h8717E39D;

        do_clr_done;
        do_clr_state;
        set_mode(3'b001, 2'b00);
        set_rounds(5'd23);
        set_req_bytes(16'd32);

        // Block1: 34 words x 4B = 136B (full rate -> auto flush)
        for (i = 0; i < 34; i = i + 1)
            write_msg_word(i[6:0], 32'hA3A3A3A3);

        repeat (80) @(posedge r_HCLK);

        // Block2: 16 words x 4B = 64B (partial -> sw_flush + padding)
        for (i = 0; i < 16; i = i + 1)
            write_msg_word(i[6:0], 32'hA3A3A3A3);

        do_sw_flush;

        wait_absorb_done;
        wait_squeeze_done;

        for (i = 0; i < 8; i = i + 1) begin
            read_state(i[6:0], rd);
            if (rd === g_exp_256_word[i]) begin
                $display("PASS SHA3-256 word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-256 word[%0d]: exp=%08x got=%08x",
                         i, g_exp_256_word[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ---------------------------------------------------------------
// main
// ---------------------------------------------------------------
initial begin
    $dumpfile("sha3_tb.vcd");
    $dumpvars(0, tb_sha3);

    r_passcnt = 0; r_failcnt = 0;
    r_HRESETn = 1'b0;
    r_HSEL    = 1'b0; r_HADDR  = 32'h0; r_HTRANS = 2'b00;
    r_HWRITE  = 1'b0; r_HSIZE  = 3'b010; r_HBURST = 3'b000;
    r_HPROT   = 4'b0; r_HWDATA = 32'h0; r_HREADY = 1'b1;

    repeat (4) @(posedge r_HCLK);
    r_HRESETn = 1'b1;
    repeat (2) @(posedge r_HCLK);

    $display("==============================================");
    $display("SHA3 TB start  (sha3_top)");
    $display("==============================================");

    test_reset_regs;
    test_clr_state_smoke;
    test_sha3_224_empty;
    test_sha3_224_200xa3;
    test_sha3_256_200xa3;

    $display("==============================================");
    $display("PASS = %0d", r_passcnt);
    $display("FAIL = %0d", r_failcnt);
    $display("==============================================");

    #20; $finish;
end

endmodule
