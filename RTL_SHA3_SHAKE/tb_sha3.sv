`timescale 1ns/1ps

// ============================================================
// SHA3 / Keccak-f[1600] AHB Testbench
// iverilog -g2012 compatible (no array task ports)
// Verified against hashlib NIST test vectors
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
wire        w_busy;
wire        w_done;

integer     r_passcnt;
integer     r_failcnt;
integer     r_i;

reg [31:0]  r_rdata;
reg [31:0]  r_w0;
reg [31:0]  r_w1;
reg [31:0]  r_wtmp;
reg [31:0]  r_out_word0;
reg [31:0]  r_out_word1;
reg [31:0]  r_status_reg;

localparam [31:0] ADDR_CTRL       = 32'h0000_0000;
localparam [31:0] ADDR_STATUS     = 32'h0000_0004;
localparam [31:0] ADDR_ROUNDS     = 32'h0000_0008;
localparam [31:0] ADDR_STATE_BASE = 32'h0000_0040;

// ============================================================
// Global arrays (iverilog: task/function ports cannot be arrays)
// ============================================================

// SHA3-224 Round#0 test
reg [63:0]  g_lane_init [0:24];
reg [63:0]  g_lane_exp  [0:24];
reg [31:0]  g_init_word [0:49];
reg [31:0]  g_exp_word  [0:49];

// SHA3-224 full digest (200 bytes of 0xA3)
reg [63:0]  g_lane_224_block2 [0:24];
reg [31:0]  g_224_block2_word [0:49];
reg [31:0]  g_exp_224_word  [0:6];

// SHA3-256 full digest (200 bytes of 0xA3)
reg [63:0]  g_lane_256_block2 [0:24];
reg [31:0]  g_256_block2_word [0:49];
reg [31:0]  g_exp_256_word  [0:7];

sha3_func_ahb_top dut
(
    .i_HCLK      (r_HCLK),
    .i_HRESETn   (r_HRESETn),
    .i_HSEL      (r_HSEL),
    .i_HADDR     (r_HADDR),
    .i_HTRANS    (r_HTRANS),
    .i_HWRITE    (r_HWRITE),
    .i_HSIZE     (r_HSIZE),
    .i_HBURST    (r_HBURST),
    .i_HPROT     (r_HPROT),
    .i_HWDATA    (r_HWDATA),
    .i_HREADY    (r_HREADY),
    .o_HRDATA    (w_HRDATA),
    .o_HREADYOUT (w_HREADYOUT),
    .o_HRESP     (w_HRESP),
    .o_busy      (w_busy),
    .o_done      (w_done)
);

// -----------------------------
// clock
// -----------------------------
initial begin
    r_HCLK = 1'b0;
end

always #5 r_HCLK = ~r_HCLK;

// -----------------------------
// AHB tasks
// -----------------------------
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
        r_HWDATA = 32'h0000_0000;

        @(posedge r_HCLK);
        #1;
        r_HWDATA = i_data;
        r_HSEL   = 1'b0;
        r_HTRANS = 2'b00;

        @(posedge r_HCLK);
        #1;
        r_HWRITE = 1'b0;
        r_HWDATA = 32'h0000_0000;
        r_HADDR  = 32'h0000_0000;
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

        @(posedge r_HCLK);
        #1;
        r_HSEL   = 1'b0;
        r_HTRANS = 2'b00;

        @(posedge r_HCLK);
        #1;
        o_data   = w_HRDATA;
        r_HADDR  = 32'h0000_0000;
    end
endtask

task write_state_word;
    input [6:0]  i_idx;
    input [31:0] i_data;
    begin
        ahb_write(ADDR_STATE_BASE + {23'd0, i_idx, 2'b00}, i_data);
    end
endtask

task read_state_word;
    input  [6:0]  i_idx;
    output [31:0] o_data;
    begin
        ahb_read(ADDR_STATE_BASE + {23'd0, i_idx, 2'b00}, o_data);
    end
endtask

task clear_state;
    begin
        ahb_write(ADDR_CTRL, 32'h0000_0004);
    end
endtask

task clear_done;
    begin
        ahb_write(ADDR_CTRL, 32'h0000_0002);
    end
endtask

task set_rounds_minus1;
    input [4:0] i_val;
    begin
        ahb_write(ADDR_ROUNDS, {27'd0, i_val});
    end
endtask

task start_core;
    begin
        ahb_write(ADDR_CTRL, 32'h0000_0001);
    end
endtask

task wait_done;
    integer r_timeout;
    reg [31:0] r_stat;
    begin
        r_timeout = 0;
        r_stat    = 32'h0;
        while ((r_stat[1] == 1'b0) && (r_timeout < 200)) begin
            ahb_read(ADDR_STATUS, r_stat);
            r_timeout = r_timeout + 1;
        end

        if (r_stat[1] == 1'b1) begin
            $display("PASS wait_done done observed, status=%08x", r_stat);
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL wait_done timeout, last status=%08x", r_stat);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

task dump_state_8words;
    integer r_k;
    reg [31:0] r_td;
    begin
        $display("---- state[0..7] ----");
        for (r_k = 0; r_k < 8; r_k = r_k + 1) begin
            read_state_word(r_k[6:0], r_td);
            $display("state_word[%0d] = %08x", r_k, r_td);
        end
    end
endtask

// -----------------------------
// Basic tests
// -----------------------------
task test_reset_regs;
    begin
        ahb_read(ADDR_STATUS, r_status_reg);
        if (r_status_reg[1:0] == 2'b00) begin
            $display("PASS reset status clear");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL reset status unexpected: %08x", r_status_reg);
            r_failcnt = r_failcnt + 1;
        end

        ahb_read(ADDR_ROUNDS, r_rdata);
        if (r_rdata[4:0] == 5'd23) begin
            $display("PASS default rounds_minus1 == 23");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL default rounds_minus1 != 23, got %0d", r_rdata[4:0]);
            r_failcnt = r_failcnt + 1;
        end
    end
endtask

task test_one_round_zero;
    begin
        $display("---- test_one_round_zero ----");

        clear_done;
        clear_state;
        set_rounds_minus1(5'd0);
        start_core;
        wait_done;

        ahb_read(ADDR_STATUS, r_status_reg);
        if (r_status_reg[1] == 1'b1) begin
            $display("PASS done_level set after one-round run");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL done_level not set after one-round run");
            r_failcnt = r_failcnt + 1;
        end

        read_state_word(7'd0, r_w0);
        if (r_w0 == 32'h0000_0001) begin
            $display("PASS zero-state one-round word0 == 1");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL zero-state one-round word0 expected 1 got %08x", r_w0);
            r_failcnt = r_failcnt + 1;
        end

        for (r_i = 1; r_i < 50; r_i = r_i + 1) begin
            read_state_word(r_i[6:0], r_wtmp);
            if (r_wtmp == 32'h0000_0000) begin
                r_passcnt = r_passcnt + 1;
            end
            else begin
                $display("FAIL zero-state one-round word[%0d] expected 0 got %08x", r_i, r_wtmp);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

task test_full_round_smoke;
    begin
        $display("---- test_full_round_smoke ----");

        clear_done;
        clear_state;

        write_state_word(7'd0,  32'hDEADBEEF);
        write_state_word(7'd1,  32'h01234567);
        write_state_word(7'd2,  32'h89ABCDEF);
        write_state_word(7'd3,  32'h0F1E2D3C);
        write_state_word(7'd4,  32'h55AA55AA);
        write_state_word(7'd5,  32'hA55AA55A);

        set_rounds_minus1(5'd23);
        start_core;

        ahb_read(ADDR_STATUS, r_status_reg);
        if ((r_status_reg[0] == 1'b1) || (w_busy == 1'b1)) begin
            $display("PASS busy observed after start");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL busy not observed after start");
            r_failcnt = r_failcnt + 1;
        end

        wait_done;
        ahb_read(ADDR_STATUS, r_status_reg);

        if (r_status_reg[1] == 1'b1) begin
            $display("PASS done_level observed after 24-round run");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL done_level missing after 24-round run");
            r_failcnt = r_failcnt + 1;
        end

        read_state_word(7'd0, r_out_word0);
        read_state_word(7'd1, r_out_word1);

        if ((r_out_word0 != 32'hDEADBEEF) || (r_out_word1 != 32'h01234567)) begin
            $display("PASS smoke output changed");
            r_passcnt = r_passcnt + 1;
        end
        else begin
            $display("FAIL smoke output unchanged on first two words");
            r_failcnt = r_failcnt + 1;
        end

        dump_state_8words;
    end
endtask

// ============================================================
// SHA3-224 Round #0 example
// ============================================================

task lanes_to_words_init;
    integer i;
    begin
        for (i = 0; i < 25; i = i + 1) begin
            g_init_word[2*i]   = g_lane_init[i][31:0];
            g_init_word[2*i+1] = g_lane_init[i][63:32];
        end
    end
endtask

task lanes_to_words_exp;
    integer i;
    begin
        for (i = 0; i < 25; i = i + 1) begin
            g_exp_word[2*i]   = g_lane_exp[i][31:0];
            g_exp_word[2*i+1] = g_lane_exp[i][63:32];
        end
    end
endtask

task build_sha3_224_init_lanes;
    integer i;
    begin
        for (i = 0; i < 25; i = i + 1)
            g_lane_init[i] = 64'h0000000000000000;

        g_lane_init[ 0] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 1] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 2] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 3] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 4] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 5] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 6] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 7] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 8] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[ 9] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[10] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[11] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[12] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[13] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[14] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[15] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[16] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[17] = 64'ha3a3a3a3a3a3a3a3;
        g_lane_init[18] = 64'h0000000000000006;
        g_lane_init[19] = 64'h0000000000000000;
        g_lane_init[20] = 64'h0000000000000000;
        g_lane_init[21] = 64'h0000000000000000;
        g_lane_init[22] = 64'h0000000000000000;
        g_lane_init[23] = 64'h0000000000000000;
        g_lane_init[24] = 64'h8000000000000000;
    end
endtask

task build_sha3_224_round0_after_iota_lanes_example;
    integer i;
    begin
        for (i = 0; i < 25; i = i + 1)
            g_lane_exp[i] = 64'h0000000000000000;

        g_lane_exp[0] = 64'h0505050505050504;
        g_lane_exp[1] = 64'hF2F2F2F2F2F2F2F2;
    end
endtask

task test_sha3_224_round0_example;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_224_round0_example ----");

        build_sha3_224_init_lanes;
        build_sha3_224_round0_after_iota_lanes_example;
        lanes_to_words_init;
        lanes_to_words_exp;

        clear_done;
        clear_state;

        for (i = 0; i < 50; i = i + 1)
            write_state_word(i[6:0], g_init_word[i]);

        set_rounds_minus1(5'd0);
        start_core;
        wait_done;

        for (i = 0; i < 4; i = i + 1) begin
            read_state_word(i[6:0], rd);
            if (rd === g_exp_word[i]) begin
                $display("PASS SHA3-224 R0 word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-224 R0 word[%0d]: exp=%08x got=%08x",
                         i, g_exp_word[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ============================================================
// SHA3-224 FULL DIGEST (200 bytes of 0xA3)
// Expected: 9376816ABA503F72F96CE7EB65AC095DEEE3BE4BF9BBC2A1CB7E11E0
// ============================================================

task build_sha3_224_block2_lanes;
    begin
        g_lane_224_block2[ 0] = 64'h4834278535BB995B;
        g_lane_224_block2[ 1] = 64'hCA06E6661F7A2AA7;
        g_lane_224_block2[ 2] = 64'hA6B912D14C4F89B2;
        g_lane_224_block2[ 3] = 64'h73440370A23B4653;
        g_lane_224_block2[ 4] = 64'h4A8A7637461256D6;
        g_lane_224_block2[ 5] = 64'h3EEACC6B9B672762;
        g_lane_224_block2[ 6] = 64'h1062054D54ADC769;
        g_lane_224_block2[ 7] = 64'h0717AA806B76F425;
        g_lane_224_block2[ 8] = 64'h4BA97ADD188B278D;
        g_lane_224_block2[ 9] = 64'hCFF5E41B8CB02D2E;
        g_lane_224_block2[10] = 64'h2A88A8D6A2B58C95;
        g_lane_224_block2[11] = 64'h2BC5A5768E4B031E;
        g_lane_224_block2[12] = 64'h40BC4708962C33AF;
        g_lane_224_block2[13] = 64'hAAD7B3E2C495A09F;
        g_lane_224_block2[14] = 64'h72E2E510135DEB94;
        g_lane_224_block2[15] = 64'h696B56DAD2A21E12;
        g_lane_224_block2[16] = 64'h00160FD139B25EA3;
        g_lane_224_block2[17] = 64'hF53C893B1BA1073F;
        g_lane_224_block2[18] = 64'h98CAB7F5B03706C6;
        g_lane_224_block2[19] = 64'h90486E908CDEE9E9;
        g_lane_224_block2[20] = 64'h61E6C4B136F037AF;
        g_lane_224_block2[21] = 64'hE110F5F37C21EE03;
        g_lane_224_block2[22] = 64'hCA2F0E4994D2B5C7;
        g_lane_224_block2[23] = 64'h1FFBF969D632BDCC;
        g_lane_224_block2[24] = 64'h85F8D46E7687CF97;
    end
endtask

task lanes224_to_words;
    integer i;
    begin
        for (i = 0; i < 25; i = i + 1) begin
            g_224_block2_word[2*i]   = g_lane_224_block2[i][31:0];
            g_224_block2_word[2*i+1] = g_lane_224_block2[i][63:32];
        end
    end
endtask

task build_sha3_224_expected;
    begin
        g_exp_224_word[0] = 32'h6A817693;
        g_exp_224_word[1] = 32'h723F50BA;
        g_exp_224_word[2] = 32'hEBE76CF9;
        g_exp_224_word[3] = 32'h5D09AC65;
        g_exp_224_word[4] = 32'h4BBEE3EE;
        g_exp_224_word[5] = 32'hA1C2BBF9;
        g_exp_224_word[6] = 32'hE0117ECB;
    end
endtask

task test_sha3_224_full_digest;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_224_full_digest ----");

        build_sha3_224_block2_lanes;
        lanes224_to_words;
        build_sha3_224_expected;

        clear_done;
        clear_state;

        for (i = 0; i < 50; i = i + 1)
            write_state_word(i[6:0], g_224_block2_word[i]);

        set_rounds_minus1(5'd23);
        start_core;
        wait_done;

        for (i = 0; i < 7; i = i + 1) begin
            read_state_word(i[6:0], rd);
            if (rd === g_exp_224_word[i]) begin
                $display("PASS SHA3-224 full word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-224 full word[%0d]: exp=%08x got=%08x",
                         i, g_exp_224_word[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// ============================================================
// SHA3-256 FULL DIGEST (200 bytes of 0xA3)
// Expected: 79F38ADEC5C20307A98EF76E8324AFBFD46CFD81B22E3973C65FA1BD9DE31787
// ============================================================

task build_sha3_256_block2_lanes;
    begin
        g_lane_256_block2[ 0] = 64'h843990DE19924D79;
        g_lane_256_block2[ 1] = 64'h61525B169D1A2F3C;
        g_lane_256_block2[ 2] = 64'h1EED4F770CF33CC5;
        g_lane_256_block2[ 3] = 64'hF67B9B9B9CEE7E30;
        g_lane_256_block2[ 4] = 64'h7F3A5D86679BD604;
        g_lane_256_block2[ 5] = 64'hD8BA0AF556875736;
        g_lane_256_block2[ 6] = 64'hD0694D66316E9A68;
        g_lane_256_block2[ 7] = 64'h9FBD85347E7C9972;
        g_lane_256_block2[ 8] = 64'hECEACFE4E9B4B5DD;
        g_lane_256_block2[ 9] = 64'hA479475227751621;
        g_lane_256_block2[10] = 64'h62E4A80832CEDBE9;
        g_lane_256_block2[11] = 64'h4F0314546A2DD285;
        g_lane_256_block2[12] = 64'hD58F03EF430F3959;
        g_lane_256_block2[13] = 64'h2573687FF364D517;
        g_lane_256_block2[14] = 64'hE5E638FBA5A32142;
        g_lane_256_block2[15] = 64'h80F50BC239CF4F2E;
        g_lane_256_block2[16] = 64'h8F1E89D983EE2D2F;
        g_lane_256_block2[17] = 64'hBFE2EAB3A6DEC312;
        g_lane_256_block2[18] = 64'h0C342CE5BDE6111A;
        g_lane_256_block2[19] = 64'h2A38BA62D281D2C7;
        g_lane_256_block2[20] = 64'h0E88386CB3348EE5;
        g_lane_256_block2[21] = 64'h75CA4C391523FE44;
        g_lane_256_block2[22] = 64'h2F0F7368EE6C0DA2;
        g_lane_256_block2[23] = 64'hF0D326F1AA0C9B88;
        g_lane_256_block2[24] = 64'h211E0B7352E9ECCE;
    end
endtask

task lanes256_to_words;
    integer i;
    begin
        for (i = 0; i < 25; i = i + 1) begin
            g_256_block2_word[2*i]   = g_lane_256_block2[i][31:0];
            g_256_block2_word[2*i+1] = g_lane_256_block2[i][63:32];
        end
    end
endtask

task build_sha3_256_expected;
    begin
        g_exp_256_word[0] = 32'hDE8AF379;
        g_exp_256_word[1] = 32'h0703C2C5;
        g_exp_256_word[2] = 32'h6EF78EA9;
        g_exp_256_word[3] = 32'hBFAF2483;
        g_exp_256_word[4] = 32'h81FD6CD4;
        g_exp_256_word[5] = 32'h73392EB2;
        g_exp_256_word[6] = 32'hBDA15FC6;
        g_exp_256_word[7] = 32'h8717E39D;
    end
endtask

task test_sha3_256_full_digest;
    reg [31:0] rd;
    integer i;
    begin
        $display("---- test_sha3_256_full_digest ----");

        build_sha3_256_block2_lanes;
        lanes256_to_words;
        build_sha3_256_expected;

        clear_done;
        clear_state;

        for (i = 0; i < 50; i = i + 1)
            write_state_word(i[6:0], g_256_block2_word[i]);

        set_rounds_minus1(5'd23);
        start_core;
        wait_done;

        for (i = 0; i < 8; i = i + 1) begin
            read_state_word(i[6:0], rd);
            if (rd === g_exp_256_word[i]) begin
                $display("PASS SHA3-256 full word[%0d]: %08x", i, rd);
                r_passcnt = r_passcnt + 1;
            end else begin
                $display("FAIL SHA3-256 full word[%0d]: exp=%08x got=%08x",
                         i, g_exp_256_word[i], rd);
                r_failcnt = r_failcnt + 1;
            end
        end
    end
endtask

// -----------------------------
// tb main
// -----------------------------
initial begin
    $dumpfile("sha3_func_ahb_tb.vcd");
    $dumpvars(0, sha3_func_ahb_tb);

    r_passcnt = 0;
    r_failcnt = 0;

    r_HRESETn = 1'b0;
    r_HSEL    = 1'b0;
    r_HADDR   = 32'h0000_0000;
    r_HTRANS  = 2'b00;
    r_HWRITE  = 1'b0;
    r_HSIZE   = 3'b010;
    r_HBURST  = 3'b000;
    r_HPROT   = 4'b0000;
    r_HWDATA  = 32'h0000_0000;
    r_HREADY  = 1'b1;

    repeat (4) @(posedge r_HCLK);
    r_HRESETn = 1'b1;
    repeat (2) @(posedge r_HCLK);

    $display("==============================================");
    $display("SHA3 AHB TB start");
    $display("==============================================");

    test_reset_regs;
    test_one_round_zero;
    test_full_round_smoke;
    test_sha3_224_round0_example;
    test_sha3_224_full_digest;
    test_sha3_256_full_digest;

    $display("==============================================");
    $display("PASS = %0d", r_passcnt);
    $display("FAIL = %0d", r_failcnt);
    $display("==============================================");

    #20;
    $finish;
end

endmodule
