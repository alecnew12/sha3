`timescale 1ns / 1ps

// ============================================================
// sha3_shake_all.v
// SHA3 / SHAKE Unified RTL - Verilog-2001
// ============================================================

// ------------------------------------------------------------
// sha3_keccak_round_const
// ------------------------------------------------------------
module sha3_keccak_round_const
(
    input  wire [4:0]  i_round,
    output reg  [63:0] o_rc
);
always @(*) begin
    case (i_round)
        5'd0 : o_rc = 64'h0000000000000001;
        5'd1 : o_rc = 64'h0000000000008082;
        5'd2 : o_rc = 64'h800000000000808A;
        5'd3 : o_rc = 64'h8000000080008000;
        5'd4 : o_rc = 64'h000000000000808B;
        5'd5 : o_rc = 64'h0000000080000001;
        5'd6 : o_rc = 64'h8000000080008081;
        5'd7 : o_rc = 64'h8000000000008009;
        5'd8 : o_rc = 64'h000000000000008A;
        5'd9 : o_rc = 64'h0000000000000088;
        5'd10: o_rc = 64'h0000000080008009;
        5'd11: o_rc = 64'h000000008000000A;
        5'd12: o_rc = 64'h000000008000808B;
        5'd13: o_rc = 64'h800000000000008B;
        5'd14: o_rc = 64'h8000000000008089;
        5'd15: o_rc = 64'h8000000000008003;
        5'd16: o_rc = 64'h8000000000008002;
        5'd17: o_rc = 64'h8000000000000080;
        5'd18: o_rc = 64'h000000000000800A;
        5'd19: o_rc = 64'h800000008000000A;
        5'd20: o_rc = 64'h8000000080008081;
        5'd21: o_rc = 64'h8000000000008080;
        5'd22: o_rc = 64'h0000000080000001;
        5'd23: o_rc = 64'h8000000080008008;
        default: o_rc = 64'h0000000000000000;
    endcase
end
endmodule

// ------------------------------------------------------------
// sha3_keccak_round
// ------------------------------------------------------------
module sha3_keccak_round
(
    input  wire [1599:0] i_state,
    input  wire [63:0]   i_rc,
    output reg  [1599:0] o_state
);
function [63:0] rol64;
    input [63:0] x;
    input integer n;
    begin
        if (n == 0) rol64 = x;
        else        rol64 = (x << n) | (x >> (64 - n));
    end
endfunction

wire [63:0] w_a [0:4][0:4];
genvar gx, gy;
generate
    for (gy = 0; gy < 5; gy = gy + 1) begin : GY
        for (gx = 0; gx < 5; gx = gx + 1) begin : GX
            assign w_a[gx][gy] = i_state[(gx + 5*gy)*64 +: 64];
        end
    end
endgenerate

reg [63:0] r_c [0:4];
reg [63:0] r_d [0:4];
reg [63:0] r_a_t [0:4][0:4];
integer tx, ty;

always @(*) begin
    for (tx = 0; tx < 5; tx = tx + 1)
        r_c[tx] = w_a[tx][0] ^ w_a[tx][1] ^ w_a[tx][2] ^ w_a[tx][3] ^ w_a[tx][4];
    for (tx = 0; tx < 5; tx = tx + 1)
        r_d[tx] = r_c[(tx+4)%5] ^ rol64(r_c[(tx+1)%5], 1);
    for (ty = 0; ty < 5; ty = ty + 1)
        for (tx = 0; tx < 5; tx = tx + 1)
            r_a_t[tx][ty] = w_a[tx][ty] ^ r_d[tx];
end

reg [63:0] r_b [0:4][0:4];
always @(*) begin
    r_b[0][0] = rol64(r_a_t[0][0],  0); r_b[1][0] = rol64(r_a_t[1][0],  1);
    r_b[2][0] = rol64(r_a_t[2][0], 62); r_b[3][0] = rol64(r_a_t[3][0], 28);
    r_b[4][0] = rol64(r_a_t[4][0], 27);
    r_b[0][1] = rol64(r_a_t[0][1], 36); r_b[1][1] = rol64(r_a_t[1][1], 44);
    r_b[2][1] = rol64(r_a_t[2][1],  6); r_b[3][1] = rol64(r_a_t[3][1], 55);
    r_b[4][1] = rol64(r_a_t[4][1], 20);
    r_b[0][2] = rol64(r_a_t[0][2],  3); r_b[1][2] = rol64(r_a_t[1][2], 10);
    r_b[2][2] = rol64(r_a_t[2][2], 43); r_b[3][2] = rol64(r_a_t[3][2], 25);
    r_b[4][2] = rol64(r_a_t[4][2], 39);
    r_b[0][3] = rol64(r_a_t[0][3], 41); r_b[1][3] = rol64(r_a_t[1][3], 45);
    r_b[2][3] = rol64(r_a_t[2][3], 15); r_b[3][3] = rol64(r_a_t[3][3], 21);
    r_b[4][3] = rol64(r_a_t[4][3],  8);
    r_b[0][4] = rol64(r_a_t[0][4], 18); r_b[1][4] = rol64(r_a_t[1][4],  2);
    r_b[2][4] = rol64(r_a_t[2][4], 61); r_b[3][4] = rol64(r_a_t[3][4], 56);
    r_b[4][4] = rol64(r_a_t[4][4], 14);
end

reg [63:0] r_e [0:4][0:4];
integer cx, cy;
always @(*) begin
    for (cy = 0; cy < 5; cy = cy + 1)
        for (cx = 0; cx < 5; cx = cx + 1)
            r_e[cx][cy] = r_b[cx][cy] ^ ((~r_b[(cx+1)%5][cy]) & r_b[(cx+2)%5][cy]);
    begin : ASSEMBLE
        integer ax, ay;
        o_state = 1600'b0;
        for (ay = 0; ay < 5; ay = ay + 1)
            for (ax = 0; ax < 5; ax = ax + 1)
                o_state[(ax + 5*ay)*64 +: 64] = r_e[ax][ay];
    end
    o_state[63:0] = r_e[0][0] ^ i_rc;
end
endmodule

// ------------------------------------------------------------
// sha3_keccak_fsm
// ------------------------------------------------------------
module sha3_keccak_fsm
(
    input  wire       i_clk,
    input  wire       i_resetn,
    input  wire       i_clear,
    input  wire       i_start,
    input  wire [4:0] i_rounds_minus1,
    output reg        o_load_init,
    output reg        o_run_round,
    output reg        o_busy,
    output reg        o_done_pulse,
    output reg  [4:0] o_round
);
localparam [1:0] ST_IDLE = 2'd0, ST_LOAD = 2'd1, ST_RUN = 2'd2, ST_DONE = 2'd3;
reg [1:0] r_state;
reg [4:0] r_round;

always @(posedge i_clk or negedge i_resetn) begin
    if (!i_resetn || i_clear) begin
        r_state <= ST_IDLE; r_round <= 5'd0;
        o_load_init <= 1'b0; o_run_round <= 1'b0;
        o_busy <= 1'b0; o_done_pulse <= 1'b0; o_round <= 5'd0;
    end
    else begin
        o_load_init <= 1'b0; o_run_round <= 1'b0; o_done_pulse <= 1'b0;
        case (r_state)
            ST_IDLE: begin
                o_busy <= 1'b0; r_round <= 5'd0;
                if (i_start) begin
                    r_state <= ST_LOAD;
                    o_load_init <= 1'b1;
                    o_busy <= 1'b1;
                end
            end
            ST_LOAD: begin
                o_busy <= 1'b1;
                o_run_round <= 1'b1;
                o_round <= 5'd0;
                r_round <= 5'd0;
                r_state <= ST_RUN;
            end
            ST_RUN: begin
                o_busy <= 1'b1;
                if (r_round == i_rounds_minus1) begin
                    r_state <= ST_DONE;
                    o_run_round <= 1'b0;
                end else begin
                    r_round <= r_round + 5'd1;
                    o_round <= r_round + 5'd1;
                    o_run_round <= 1'b1;
                end
            end
            ST_DONE: begin
                o_done_pulse <= 1'b1;
                o_busy <= 1'b0;
                r_state <= ST_IDLE;
                r_round <= 5'd0;
                o_round <= 5'd0;
            end
            default: r_state <= ST_IDLE;
        endcase
    end
end
endmodule

// ------------------------------------------------------------
// sha3_keccak_core
// ------------------------------------------------------------
module sha3_keccak_core
(
    input  wire          i_clk,
    input  wire          i_resetn,
    input  wire          i_clear,
    input  wire          i_start,
    input  wire [4:0]    i_rounds_minus1,
    input  wire [1599:0] i_init_state,
    output wire [1599:0] o_state,
    output wire          o_busy,
    output wire          o_done_pulse
);
wire w_load, w_run;
wire [4:0]    w_round;
wire [63:0]   w_rc;
wire [1599:0] w_round_out;
reg  [1599:0] r_state;

sha3_keccak_fsm u_fsm (
    .i_clk          (i_clk),
    .i_resetn       (i_resetn),
    .i_clear        (i_clear),
    .i_start        (i_start),
    .i_rounds_minus1(i_rounds_minus1),
    .o_load_init    (w_load),
    .o_run_round    (w_run),
    .o_busy         (o_busy),
    .o_done_pulse   (o_done_pulse),
    .o_round        (w_round)
);

sha3_keccak_round_const u_rc (
    .i_round(w_round),
    .o_rc   (w_rc)
);

sha3_keccak_round u_round (
    .i_state(r_state),
    .i_rc   (w_rc),
    .o_state(w_round_out)
);

always @(posedge i_clk or negedge i_resetn) begin
    if (!i_resetn || i_clear) r_state <= 1600'b0;
    else if (w_load)          r_state <= i_init_state;
    else if (w_run)           r_state <= w_round_out;
end

assign o_state = r_state;
endmodule

// ------------------------------------------------------------
// sha3_pad
// ------------------------------------------------------------
module sha3_pad
(
    input  wire [2:0]    i_mode,
    input  wire [1343:0] i_block,
    input  wire [7:0]    i_valid_bytes,
    input  wire          i_is_last,
    output reg  [1343:0] o_block,
    output reg  [7:0]    o_rate_bytes,
    output reg  [7:0]    o_pad_suffix
);
reg [7:0] r_rate_bytes;
reg [7:0] r_pad_suffix;
reg [7:0] r_in  [0:167];
reg [7:0] r_out [0:167];
integer pi;

always @(*) begin
    case (i_mode)
        3'b000: begin r_rate_bytes = 8'd144; r_pad_suffix = 8'h06; end // SHA3-224
        3'b001: begin r_rate_bytes = 8'd136; r_pad_suffix = 8'h06; end // SHA3-256
        3'b010: begin r_rate_bytes = 8'd104; r_pad_suffix = 8'h06; end // SHA3-384
        3'b011: begin r_rate_bytes = 8'd72;  r_pad_suffix = 8'h06; end // SHA3-512
        3'b100: begin r_rate_bytes = 8'd168; r_pad_suffix = 8'h1F; end // SHAKE128
        3'b101: begin r_rate_bytes = 8'd136; r_pad_suffix = 8'h1F; end // SHAKE256
        default:begin r_rate_bytes = 8'd136; r_pad_suffix = 8'h06; end
    endcase
    o_rate_bytes = r_rate_bytes;
    o_pad_suffix = r_pad_suffix;

    for (pi = 0; pi < 168; pi = pi + 1)
        r_in[pi] = i_block[pi*8 +: 8];

    for (pi = 0; pi < 168; pi = pi + 1) begin
        if (!i_is_last)
            r_out[pi] = (pi < r_rate_bytes) ? r_in[pi] : 8'h00;
        else if (pi < i_valid_bytes)
            r_out[pi] = r_in[pi];
        else if (pi == i_valid_bytes)
            r_out[pi] = r_pad_suffix;
        else if (pi == (r_rate_bytes - 8'd1))
            r_out[pi] = 8'h80;
        else if (pi < r_rate_bytes)
            r_out[pi] = 8'h00;
        else
            r_out[pi] = 8'h00;
    end

    if (i_is_last && (i_valid_bytes == (r_rate_bytes - 8'd1)))
        r_out[r_rate_bytes - 8'd1] = r_pad_suffix | 8'h80;

    for (pi = 0; pi < 168; pi = pi + 1)
        o_block[pi*8 +: 8] = r_out[pi];
end
endmodule

// ------------------------------------------------------------
// sha3_xor_inject
// ------------------------------------------------------------
module sha3_xor_inject
(
    input  wire [1599:0] i_state,
    input  wire [1343:0] i_flush_block,
    input  wire [7:0]    i_rate_bytes,
    output reg  [1599:0] o_state
);
integer xi;
always @(*) begin
    o_state = i_state;
    for (xi = 0; xi < 168; xi = xi + 1)
        if (xi < i_rate_bytes)
            o_state[xi*8 +: 8] = i_state[xi*8 +: 8] ^ i_flush_block[xi*8 +: 8];
end
endmodule

// ------------------------------------------------------------
// sha3_absorb_ctrl
// ------------------------------------------------------------
module sha3_absorb_ctrl
(
    input  wire i_clk,
    input  wire i_resetn,
    input  wire i_clear,
    input  wire i_flush_pulse,
    input  wire i_flush_is_last,
    input  wire i_core_done,
    output reg  o_xor_en,
    output reg  o_core_start,
    output reg  o_absorb_done,
    output wire o_busy
);
localparam [1:0] ST_IDLE=2'd0, ST_XOR=2'd1, ST_PERM=2'd2, ST_DONE=2'd3;
reg [1:0] r_st;
reg       r_last_pend;

always @(posedge i_clk or negedge i_resetn) begin
    if (!i_resetn || i_clear) begin
        r_st <= ST_IDLE; r_last_pend <= 1'b0;
        o_xor_en <= 1'b0; o_core_start <= 1'b0; o_absorb_done <= 1'b0;
    end
    else begin
        o_xor_en <= 1'b0; o_core_start <= 1'b0;
        case (r_st)
            ST_IDLE: begin
                o_absorb_done <= 1'b0;
                if (i_flush_pulse) begin
                    r_last_pend <= i_flush_is_last;
                    o_xor_en    <= 1'b1;
                    r_st        <= ST_XOR;
                end
            end
            ST_XOR:  begin o_core_start <= 1'b1; r_st <= ST_PERM; end
            ST_PERM: if (i_core_done) begin
                if (r_last_pend) begin o_absorb_done <= 1'b1; r_st <= ST_DONE; end
                else r_st <= ST_IDLE;
            end
            ST_DONE: o_absorb_done <= 1'b1;
            default: r_st <= ST_IDLE;
        endcase
    end
end
assign o_busy = (r_st == ST_XOR) || (r_st == ST_PERM);
endmodule

// ------------------------------------------------------------
// sha3_absorb_fifo
// FIX1: w_sw_flush_go 조건에서 (r_byte_ptr > 0) 제거
//       -> empty 메시지도 sw_flush 가능
// FIX2: sw_flush 전용 pad 인스턴스 추가 (i_is_last=1 고정)
//       -> sw_flush 시 올바른 패딩 삽입
// ------------------------------------------------------------
module sha3_absorb_fifo
(
    input  wire          i_clk,
    input  wire          i_resetn,
    input  wire [2:0]    i_mode,
    input  wire [1:0]    i_path_sel,
    input  wire [7:0]    i_rate_bytes,
    input  wire [31:0]   i_ahb_data,
    input  wire          i_ahb_wr,
    input  wire          i_ahb_last,
    input  wire [2:0]    i_ahb_bytes,
    input  wire [63:0]   i_din_64,
    input  wire          i_din_64_valid,
    input  wire          i_din_64_last,
    input  wire [3:0]    i_din_64_bytes,
    input  wire [1343:0] i_din_1344,
    input  wire          i_din_1344_valid,
    input  wire          i_din_1344_last,
    input  wire [7:0]    i_din_1344_bytes,
    input  wire          i_sw_flush,
    output reg           o_flush_pulse,
    output reg  [1343:0] o_flush_block,
    output reg           o_flush_is_last,
    output wire          o_fifo_ready,
    output wire [7:0]    o_fifo_bytes,
    output wire [1343:0] o_fifo_raw
);
reg [1343:0] r_fifo;
reg [7:0]    r_byte_ptr;
reg [1343:0] w_wr_data;
reg [7:0]    w_wr_bytes;
reg          w_wr_valid;
reg          w_wr_last;
reg          w_is_atomic;

always @(*) begin
    w_wr_data = 1344'b0; w_wr_bytes = 8'd0;
    w_wr_valid = 1'b0;   w_wr_last  = 1'b0; w_is_atomic = 1'b0;
    case (i_path_sel)
        2'b00: begin
            w_wr_valid = i_ahb_wr; w_wr_last = i_ahb_last;
            w_wr_bytes = {5'd0, i_ahb_bytes};
            w_wr_data  = {{(1344-32){1'b0}}, i_ahb_data} << {r_byte_ptr, 3'b000};
        end
        2'b01: begin
            w_wr_valid = i_din_64_valid; w_wr_last = i_din_64_last;
            w_wr_bytes = {4'd0, i_din_64_bytes};
            w_wr_data  = {{(1344-64){1'b0}}, i_din_64} << {r_byte_ptr, 3'b000};
        end
        2'b10: begin
            w_wr_valid = i_din_1344_valid; w_wr_last = i_din_1344_last;
            w_wr_bytes = i_din_1344_bytes; w_wr_data = i_din_1344; w_is_atomic = 1'b1;
        end
        default:;
    endcase
end

wire [1343:0] w_fifo_merged = r_fifo | w_wr_data;

// pad instance for normal write path (i_is_last = w_wr_last)
wire [1343:0] w_pad_block;
wire [7:0]    w_pad_rate_unused;
wire [7:0]    w_pad_suf_unused;

sha3_pad u_pad (
    .i_mode       (i_mode),
    .i_block      (w_fifo_merged),
    .i_valid_bytes(r_byte_ptr + w_wr_bytes),
    .i_is_last    (w_wr_last),
    .o_block      (w_pad_block),
    .o_rate_bytes (w_pad_rate_unused),
    .o_pad_suffix (w_pad_suf_unused)
);

// FIX2: dedicated pad instance for sw_flush path (i_is_last always 1)
wire [1343:0] w_swflush_pad_block;
wire [7:0]    w_swflush_rate_unused;
wire [7:0]    w_swflush_suf_unused;

sha3_pad u_pad_swflush (
    .i_mode       (i_mode),
    .i_block      (r_fifo),
    .i_valid_bytes(r_byte_ptr),
    .i_is_last    (1'b1),
    .o_block      (w_swflush_pad_block),
    .o_rate_bytes (w_swflush_rate_unused),
    .o_pad_suffix (w_swflush_suf_unused)
);

wire w_flush_needed = w_wr_valid & (w_is_atomic | w_wr_last |
                      ((r_byte_ptr + w_wr_bytes) >= i_rate_bytes));
// FIX1: allow sw_flush even when r_byte_ptr == 0 (empty message)
wire w_sw_flush_go  = i_sw_flush;

always @(posedge i_clk or negedge i_resetn) begin
    if (!i_resetn) begin
        r_fifo <= 1344'b0; r_byte_ptr <= 8'd0;
        o_flush_pulse <= 1'b0; o_flush_block <= 1344'b0; o_flush_is_last <= 1'b0;
    end
    else begin
        o_flush_pulse <= 1'b0; o_flush_is_last <= 1'b0;
        if (w_flush_needed) begin
            o_flush_pulse   <= 1'b1;
            o_flush_block   <= w_pad_block;
            o_flush_is_last <= w_wr_last;
            r_fifo          <= 1344'b0;
            r_byte_ptr      <= 8'd0;
        end else if (w_wr_valid) begin
            r_fifo     <= w_fifo_merged;
            r_byte_ptr <= r_byte_ptr + w_wr_bytes;
        end else if (w_sw_flush_go) begin
            // FIX2: use sw_flush dedicated pad block (i_is_last=1 applied)
            o_flush_pulse   <= 1'b1;
            o_flush_is_last <= 1'b1;
            o_flush_block   <= w_swflush_pad_block;
            r_fifo          <= 1344'b0;
            r_byte_ptr      <= 8'd0;
        end
    end
end

assign o_fifo_ready = ~o_flush_pulse;
assign o_fifo_bytes = r_byte_ptr;
assign o_fifo_raw   = r_fifo;
endmodule

// ------------------------------------------------------------
// sha3_squeeze_ctrl
// ------------------------------------------------------------
module sha3_squeeze_ctrl
(
    input  wire        i_clk,
    input  wire        i_resetn,
    input  wire        i_clear,
    input  wire [7:0]  i_rate_bytes,
    input  wire [15:0] i_req_bytes,
    input  wire        i_is_shake,
    input  wire        i_squeeze_start,
    output reg         o_core_start,
    input  wire        i_core_done,
    output reg  [15:0] o_bytes_rem,
    output reg         o_out_valid,
    output reg         o_done,
    output wire        o_busy
);
localparam [1:0] ST_IDLE=2'd0, ST_OUT=2'd1, ST_PERM=2'd2, ST_DONE=2'd3;
reg [1:0] r_st;

always @(posedge i_clk or negedge i_resetn) begin
    if (!i_resetn || i_clear) begin
        r_st <= ST_IDLE; o_core_start <= 1'b0;
        o_out_valid <= 1'b0; o_done <= 1'b0; o_bytes_rem <= 16'd0;
    end
    else begin
        o_core_start <= 1'b0; o_out_valid <= 1'b0;
        case (r_st)
            ST_IDLE: begin
                o_done <= 1'b0;
                if (i_squeeze_start) begin
                    o_bytes_rem <= i_req_bytes;
                    o_out_valid <= 1'b1;
                    r_st        <= ST_OUT;
                end
            end
            ST_OUT: begin
                o_out_valid <= 1'b1;
                if (o_bytes_rem <= {8'd0, i_rate_bytes}) begin
                    o_out_valid <= 1'b0; o_bytes_rem <= 16'd0;
                    o_done <= 1'b1; r_st <= ST_DONE;
                end else if (i_is_shake) begin
                    o_bytes_rem <= o_bytes_rem - {8'd0, i_rate_bytes};
                    o_out_valid <= 1'b0; o_core_start <= 1'b1; r_st <= ST_PERM;
                end else begin
                    o_out_valid <= 1'b0; o_bytes_rem <= 16'd0;
                    o_done <= 1'b1; r_st <= ST_DONE;
                end
            end
            ST_PERM: if (i_core_done) begin o_out_valid <= 1'b1; r_st <= ST_OUT; end
            ST_DONE: o_done <= 1'b1;
            default: r_st <= ST_IDLE;
        endcase
    end
end
assign o_busy = (r_st == ST_PERM);
endmodule

// ------------------------------------------------------------
// sha3_ahb_if
// ------------------------------------------------------------
module sha3_ahb_if
(
    input  wire          i_HCLK,
    input  wire          i_HRESETn,
    input  wire          i_HSEL,
    input  wire [31:0]   i_HADDR,
    input  wire [1:0]    i_HTRANS,
    input  wire          i_HWRITE,
    input  wire [2:0]    i_HSIZE,
    input  wire [2:0]    i_HBURST,
    input  wire [3:0]    i_HPROT,
    input  wire [31:0]   i_HWDATA,
    input  wire          i_HREADY,
    output reg  [31:0]   o_HRDATA,
    output wire          o_HREADYOUT,
    output wire          o_HRESP,
    output reg  [4:0]    o_rounds_minus1,
    output reg  [2:0]    o_mode,
    output reg  [1:0]    o_path_sel,
    output reg  [15:0]   o_req_bytes,
    output reg           o_clr_state,
    output reg           o_clr_done,
    output reg           o_sw_flush,
    output reg  [31:0]   o_ahb_din,
    output reg           o_ahb_wr,
    output reg           o_ahb_last,
    output reg  [2:0]    o_ahb_bytes,
    input  wire          i_absorb_busy,
    input  wire          i_absorb_done,
    input  wire          i_squeeze_busy,
    input  wire          i_squeeze_done,
    input  wire [1599:0] i_core_state
);
reg         r_av, r_aw;
reg [8:0]   r_aa;
reg         r_abs_done_lat, r_sqz_done_lat;

always @(posedge i_HCLK or negedge i_HRESETn) begin
    if (!i_HRESETn) begin
        r_av <= 1'b0; r_aw <= 1'b0; r_aa <= 9'd0;
        r_abs_done_lat <= 1'b0; r_sqz_done_lat <= 1'b0;
    end else begin
        r_av <= i_HSEL & i_HREADY & i_HTRANS[1];
        r_aw <= i_HWRITE; r_aa <= i_HADDR[8:0];
        if (i_absorb_done)  r_abs_done_lat <= 1'b1;
        if (i_squeeze_done) r_sqz_done_lat <= 1'b1;
        if (o_clr_done) begin r_abs_done_lat <= 1'b0; r_sqz_done_lat <= 1'b0; end
    end
end

wire [6:0] w_state_idx = r_aa[8:2] - 7'h10;
wire       w_is_state  = (r_aa[8:2] >= 7'h40) && (r_aa[8:2] <= 7'h71);

function [31:0] frd;
    input [1599:0] s;
    input [5:0]    i;
    begin frd = s[i*32 +: 32]; end
endfunction

always @(*) begin
    o_HRDATA = 32'h0;
    casez (r_aa[8:2])
        7'h00: o_HRDATA = 32'h0;
        7'h01: o_HRDATA = {28'd0, r_sqz_done_lat, i_squeeze_busy,
                                   r_abs_done_lat, i_absorb_busy};
        7'h02: o_HRDATA = {28'd0, o_path_sel, o_mode};
        7'h03: o_HRDATA = {16'd0, o_req_bytes};
        7'h04: o_HRDATA = {27'd0, o_rounds_minus1};
        default: if (w_is_state)
            o_HRDATA = frd(i_core_state, {r_aa[7:2] - 6'h40});
    endcase
end

always @(posedge i_HCLK or negedge i_HRESETn) begin
    if (!i_HRESETn) begin
        o_rounds_minus1 <= 5'd23; o_mode <= 3'b001; o_path_sel <= 2'b00;
        o_req_bytes <= 16'd32; o_clr_state <= 1'b0; o_clr_done <= 1'b0;
        o_sw_flush <= 1'b0; o_ahb_wr <= 1'b0; o_ahb_last <= 1'b0;
        o_ahb_din <= 32'h0; o_ahb_bytes <= 3'd4;
    end else begin
        o_clr_state <= 1'b0; o_clr_done <= 1'b0; o_sw_flush <= 1'b0;
        o_ahb_wr    <= 1'b0; o_ahb_last  <= 1'b0;
        if (r_av && r_aw) begin
            casez (r_aa[8:2])
                7'h00: begin
                    if (i_HWDATA[1]) o_clr_done  <= 1'b1;
                    if (i_HWDATA[2]) o_clr_state <= 1'b1;
                    if (i_HWDATA[3]) o_sw_flush  <= 1'b1;
                end
                7'h02: begin o_mode <= i_HWDATA[2:0]; o_path_sel <= i_HWDATA[4:3]; end
                7'h03: o_req_bytes     <= i_HWDATA[15:0];
                7'h04: o_rounds_minus1 <= i_HWDATA[4:0];
                default: if (w_is_state && (o_path_sel == 2'b00) && !i_absorb_busy) begin
                    o_ahb_wr    <= 1'b1;
                    o_ahb_din   <= i_HWDATA;
                    o_ahb_bytes <= 3'd4;
                end
            endcase
        end
    end
end

assign o_HREADYOUT = 1'b1;
assign o_HRESP     = 1'b0;
endmodule

// ------------------------------------------------------------
// sha3_top
// ------------------------------------------------------------
module sha3_top
(
    input  wire          i_HCLK,
    input  wire          i_HRESETn,
    input  wire          i_HSEL,
    input  wire [31:0]   i_HADDR,
    input  wire [1:0]    i_HTRANS,
    input  wire          i_HWRITE,
    input  wire [2:0]    i_HSIZE,
    input  wire [2:0]    i_HBURST,
    input  wire [3:0]    i_HPROT,
    input  wire [31:0]   i_HWDATA,
    input  wire          i_HREADY,
    output wire [31:0]   o_HRDATA,
    output wire          o_HREADYOUT,
    output wire          o_HRESP,
    input  wire [63:0]   i_din_64,
    input  wire          i_din_64_valid,
    input  wire          i_din_64_last,
    input  wire [3:0]    i_din_64_bytes,
    input  wire [1343:0] i_din_1344,
    input  wire          i_din_1344_valid,
    input  wire          i_din_1344_last,
    input  wire [7:0]    i_din_1344_bytes,
    output wire [1343:0] o_state_rate,
    output wire          o_state_valid,
    output wire [1343:0] o_fifo_raw,
    output wire [7:0]    o_fifo_bytes,
    output wire          o_absorb_busy,
    output wire          o_absorb_done,
    output wire          o_squeeze_done
);
wire [4:0]  w_rounds;
wire [2:0]  w_mode;
wire [1:0]  w_psel;
wire [15:0] w_req;
wire        w_clr_st, w_clr_dn, w_sw_flush;
wire [31:0] w_ahb_din;
wire        w_ahb_wr, w_ahb_last;
wire [2:0]  w_ahb_bytes;
wire [7:0]  w_rate_bytes;
wire [7:0]  w_pad_suf_unused;
wire [1343:0] w_pad_unused;
wire        w_flush;
wire [1343:0] w_flush_blk;
wire        w_flush_last;
wire        w_xor_en, w_abs_cs;
wire        w_abs_done, w_abs_busy;
wire [1599:0] w_core_st;
wire        w_core_busy, w_core_done;
wire [1599:0] w_xor_st;
wire        w_sqz_cs;
wire [15:0] w_sqz_rem;
wire        w_sqz_out, w_sqz_done, w_sqz_busy;

wire        w_is_shake  = w_mode[2];
wire        w_cs_mux    = w_abs_cs | w_sqz_cs;
wire [1599:0] w_core_init = w_xor_en ? w_xor_st : w_core_st;

sha3_pad u_pad_dec (
    .i_mode       (w_mode),
    .i_block      (1344'b0),
    .i_valid_bytes(8'd0),
    .i_is_last    (1'b0),
    .o_block      (w_pad_unused),
    .o_rate_bytes (w_rate_bytes),
    .o_pad_suffix (w_pad_suf_unused)
);

sha3_ahb_if u_ahb (
    .i_HCLK        (i_HCLK),      .i_HRESETn     (i_HRESETn),
    .i_HSEL        (i_HSEL),      .i_HADDR        (i_HADDR),
    .i_HTRANS      (i_HTRANS),    .i_HWRITE       (i_HWRITE),
    .i_HSIZE       (i_HSIZE),     .i_HBURST       (i_HBURST),
    .i_HPROT       (i_HPROT),     .i_HWDATA       (i_HWDATA),
    .i_HREADY      (i_HREADY),    .o_HRDATA       (o_HRDATA),
    .o_HREADYOUT   (o_HREADYOUT), .o_HRESP        (o_HRESP),
    .o_rounds_minus1(w_rounds),   .o_mode         (w_mode),
    .o_path_sel    (w_psel),      .o_req_bytes    (w_req),
    .o_clr_state   (w_clr_st),    .o_clr_done     (w_clr_dn),
    .o_sw_flush    (w_sw_flush),
    .o_ahb_din     (w_ahb_din),   .o_ahb_wr       (w_ahb_wr),
    .o_ahb_last    (w_ahb_last),  .o_ahb_bytes    (w_ahb_bytes),
    .i_absorb_busy (w_abs_busy),  .i_absorb_done  (w_abs_done),
    .i_squeeze_busy(w_sqz_busy),  .i_squeeze_done (w_sqz_done),
    .i_core_state  (w_core_st)
);

sha3_absorb_fifo u_fifo (
    .i_clk          (i_HCLK),     .i_resetn       (i_HRESETn),
    .i_mode         (w_mode),     .i_path_sel     (w_psel),
    .i_rate_bytes   (w_rate_bytes),
    .i_ahb_data     (w_ahb_din),  .i_ahb_wr       (w_ahb_wr),
    .i_ahb_last     (w_ahb_last), .i_ahb_bytes    (w_ahb_bytes),
    .i_din_64       (i_din_64),   .i_din_64_valid (i_din_64_valid),
    .i_din_64_last  (i_din_64_last),.i_din_64_bytes(i_din_64_bytes),
    .i_din_1344     (i_din_1344), .i_din_1344_valid(i_din_1344_valid),
    .i_din_1344_last(i_din_1344_last),.i_din_1344_bytes(i_din_1344_bytes),
    .i_sw_flush     (w_sw_flush),
    .o_flush_pulse  (w_flush),    .o_flush_block  (w_flush_blk),
    .o_flush_is_last(w_flush_last),
    .o_fifo_ready   (),           .o_fifo_bytes   (o_fifo_bytes),
    .o_fifo_raw     (o_fifo_raw)
);

sha3_absorb_ctrl u_abs_ctrl (
    .i_clk         (i_HCLK),    .i_resetn      (i_HRESETn),
    .i_clear       (w_clr_st),
    .i_flush_pulse (w_flush),   .i_flush_is_last(w_flush_last),
    .i_core_done   (w_core_done),
    .o_xor_en      (w_xor_en),  .o_core_start  (w_abs_cs),
    .o_absorb_done (w_abs_done),.o_busy         (w_abs_busy)
);

sha3_xor_inject u_xor (
    .i_state      (w_core_st),
    .i_flush_block(w_flush_blk),
    .i_rate_bytes (w_rate_bytes),
    .o_state      (w_xor_st)
);

sha3_keccak_core u_core (
    .i_clk         (i_HCLK),    .i_resetn      (i_HRESETn),
    .i_clear       (w_clr_st),
    .i_start       (w_cs_mux),
    .i_rounds_minus1(w_rounds),
    .i_init_state  (w_core_init),
    .o_state       (w_core_st),
    .o_busy        (w_core_busy),.o_done_pulse  (w_core_done)
);

sha3_squeeze_ctrl u_sqz (
    .i_clk         (i_HCLK),    .i_resetn      (i_HRESETn),
    .i_clear       (w_clr_st),
    .i_rate_bytes  (w_rate_bytes),.i_req_bytes  (w_req),
    .i_is_shake    (w_is_shake),
    .i_squeeze_start(w_abs_done),
    .o_core_start  (w_sqz_cs),
    .i_core_done   (w_core_done),
    .o_bytes_rem   (w_sqz_rem),
    .o_out_valid   (w_sqz_out),
    .o_done        (w_sqz_done),.o_busy         (w_sqz_busy)
);

assign o_state_rate  = w_core_st[1343:0];
assign o_state_valid = w_sqz_out;
assign o_absorb_busy = w_abs_busy;
assign o_absorb_done = w_abs_done;
assign o_squeeze_done= w_sqz_done;
endmodule
