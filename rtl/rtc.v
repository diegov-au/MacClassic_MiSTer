module rtc (
	input         clk,
	input         reset,

	input  [32:0] timestamp,
	input  [64:0] rtc_bcd,

	input         _cs,
	input         ck,
	input         dat_i,
	output reg    dat_o,

	input   [7:0] ext_addr,
	input         ext_we,
	input   [7:0] ext_wdata,
	output        ext_ready,
	output  [7:0] ext_q,
	output reg    pram_wr
);

localparam [31:0] MAC_EPOCH = 32'd2082844800;
localparam [24:0] ONE_SEC   = 25'd32_499_999;

reg  [7:0] ram[0:255];
reg  [7:0] ram_q;
integer n;
initial begin
	for (n = 0; n < 256; n = n + 1) ram[n] = 8'h00;
end

reg        int_req, int_we;
reg  [7:0] int_addr, int_wdata;

assign ext_ready = ~int_req;
assign ext_q     = ram_q;

always @(posedge clk) begin
	if (int_req) begin
		if (int_we) ram[int_addr] <= int_wdata;
		ram_q <= ram[int_addr];
	end else begin
		if (ext_we) ram[ext_addr] <= ext_wdata;
		ram_q <= ram[ext_addr];
	end
end

reg  [31:0] secs = 32'd0;
reg  [24:0] tick = 25'd0;

reg         ts_t = 1'b0, rtc_t = 1'b0;
reg         rtc_valid = 1'b0;
reg  [15:0] rtc_hm = 16'd0;
reg         seeded = 1'b0;
reg   [2:0] sst = 3'd0;
localparam  S_IDLE = 3'd0, S_WAIT = 3'd1, S_MOD = 3'd2, S_DIV = 3'd3, S_ADD = 3'd4;
reg  [31:0] ts_cap, r;
reg   [4:0] k;
reg  [10:0] ts_min;
reg  [24:0] wait_cnt;
reg         wait_sec;

wire [32:0] mod_sub = 33'd86400 << k;
wire [16:0] div_sub = 17'd60 << k[3:0];
wire  [7:0] rtc_h   = rtc_hm[15:12] * 4'd10 + rtc_hm[11:8];
wire  [7:0] rtc_m   = rtc_hm[7:4]   * 4'd10 + rtc_hm[3:0];
wire [11:0] rtc_min = rtc_h * 6'd60 + rtc_m;
wire signed [12:0] dmin_raw = $signed({1'b0, rtc_min}) - $signed({2'b00, ts_min});
wire signed [12:0] dmin = (dmin_raw < -13'sd720) ? dmin_raw + 13'sd1440 :
                          (dmin_raw >= 13'sd720) ? dmin_raw - 13'sd1440 : dmin_raw;
wire signed [31:0] dsec = dmin * 32'sd60;

`ifdef VERILATOR
wire ts_new = (ts_t != timestamp[32]) ||
              (!seeded && sst == S_IDLE && timestamp[31:0] != 32'd0);
`else
wire ts_new = (ts_t != timestamp[32]);
`endif

reg   [2:0] bit_cnt;
reg         ck_d;
reg   [7:0] din;
reg   [1:0] byte_idx;
reg   [7:0] cmd0;
reg   [4:0] cmd1_addr;
reg         sending;
reg   [7:0] dout;
reg         wp = 1'b1;
reg   [1:0] rd_pend;
`ifdef VERILATOR

reg         rtc_log = 1'b0;
initial rtc_log = $test$plusargs("rtclog");

reg         xpram_m1 = 1'b0;
initial xpram_m1 = $test$plusargs("xpram_m1");

reg         rtc_nowp = 1'b0, rtc_seednow = 1'b0;
initial begin rtc_nowp = $test$plusargs("rtc_nowp"); rtc_seednow = $test$plusargs("rtc_seednow"); end
wire        wp_eff = wp & ~rtc_nowp;
`else
wire        wp_eff = wp;
`endif

wire  [7:0] b      = {din[6:0], dat_i};
wire        is_ext = (cmd0[6:3] == 4'b0111);
wire  [4:0] scmd0  = cmd0[6:2];
wire  [4:0] scmdb  = b[6:2];

function [8:0] legacy_addr(input [4:0] s);
	legacy_addr = (s >= 5'h08 && s <= 5'h0B) ? {1'b1, 3'b000, s} :
	              (s >= 5'h10)               ? {1'b1, 3'b000, s} : 9'd0;
endfunction

always @(posedge clk) begin
	int_req <= 1'b0;
	int_we  <= 1'b0;
	pram_wr <= 1'b0;

	ts_t  <= timestamp[32];
	rtc_t <= rtc_bcd[64];
	if (rtc_t != rtc_bcd[64]) begin rtc_valid <= 1'b1; rtc_hm <= rtc_bcd[23:8]; end

	if (tick == ONE_SEC) begin tick <= 25'd0; secs <= secs + 1'd1; end
	else tick <= tick + 1'd1;

	case (sst)
	S_IDLE:
`ifdef VERILATOR
		if (!seeded && rtc_seednow && timestamp[31:0] != 32'd0) begin
			secs <= timestamp[31:0] + MAC_EPOCH; seeded <= 1'b1;
		end else
`endif
		if (!seeded && ts_new) begin
		ts_cap <= timestamp[31:0]; wait_cnt <= 25'd0; wait_sec <= 1'b0; sst <= S_WAIT;
	end
	S_WAIT:
		if (rtc_valid) begin r <= ts_cap; k <= 5'd15; sst <= S_MOD; end
		else if (wait_cnt == ONE_SEC) begin

			secs <= ts_cap + MAC_EPOCH + 32'd1; seeded <= 1'b1; sst <= S_IDLE;
		end else wait_cnt <= wait_cnt + 1'd1;
	S_MOD: begin
		if ({1'b0, r} >= mod_sub) r <= r - mod_sub[31:0];
		if (k == 5'd0) begin k <= 5'd10; ts_min <= 11'd0; sst <= S_DIV; end
		else k <= k - 1'd1;
	end
	S_DIV: begin
		if (r[16:0] >= div_sub) begin r <= r - div_sub; ts_min[k[3:0]] <= 1'b1; end
		if (k == 5'd0) sst <= S_ADD;
		else k <= k - 1'd1;
	end
	S_ADD: begin
		secs <= ts_cap + MAC_EPOCH + dsec + {31'd0, wait_sec};
		seeded <= 1'b1; sst <= S_IDLE;
	end
	default: sst <= S_IDLE;
	endcase

	if (rd_pend == 2'd2) rd_pend <= 2'd1;
	else if (rd_pend == 2'd1) begin
		dout <= ram_q; rd_pend <= 2'd0;
`ifdef VERILATOR
		if (rtc_log) $display("rtc: read  pram[%02X] = %02X", int_addr, ram_q);
`endif
	end
`ifdef VERILATOR
	if (rtc_log && int_req && int_we) $display("rtc: write pram[%02X] = %02X", int_addr, int_wdata);
`endif

	if (reset) begin
		bit_cnt <= 0; byte_idx <= 0; sending <= 0; dat_o <= 1; rd_pend <= 0;
	end else if (_cs) begin
		bit_cnt <= 0; byte_idx <= 0; sending <= 0; dat_o <= 1;
	end else begin
		ck_d <= ck;

		if (ck_d & ~ck & sending) dat_o <= dout[7 - bit_cnt];

		if (~ck_d & ck) begin
			bit_cnt <= bit_cnt + 1'd1;
			if (!sending) din <= {din[6:0], dat_i};

			if (bit_cnt == 3'd7 && !sending) begin
				case (byte_idx)
				2'd0: begin
					cmd0 <= b;
					if (b[6:3] == 4'b0111) byte_idx <= 2'd1;
					else if (b[7]) begin
						sending <= 1'b1;
						case (scmdb)
						5'h00, 5'h04: dout <= secs[7:0];
						5'h01, 5'h05: dout <= secs[15:8];
						5'h02, 5'h06: dout <= secs[23:16];
						5'h03, 5'h07: dout <= secs[31:24];
						default:
							if (legacy_addr(scmdb) != 9'd0) begin
								int_req <= 1'b1; int_addr <= legacy_addr(scmdb);
								rd_pend <= 2'd2;
							end else dout <= 8'h00;
						endcase
					end
					else byte_idx <= 2'd1;
				end
				2'd1: if (is_ext) begin
					if (cmd0[7]) begin
						sending <= 1'b1;
`ifdef VERILATOR
						if (xpram_m1) dout <= 8'h00; else
`endif
						begin
						int_req <= 1'b1; int_addr <= {cmd0[2:0], b[6:2]};
						rd_pend <= 2'd2;
						end
					end
					else begin cmd1_addr <= b[6:2]; byte_idx <= 2'd2; end
				end
				else begin
					byte_idx <= 2'd3;
					case (scmd0)
					5'h00, 5'h04: secs[7:0]   <= b;
					5'h01, 5'h05: secs[15:8]  <= b;
					5'h02, 5'h06: secs[23:16] <= b;
					5'h03, 5'h07: secs[31:24] <= b;
					5'h0D:        wp <= b[7];
					default:
						if (legacy_addr(scmd0) != 9'd0 && !wp_eff) begin
							int_req <= 1'b1; int_we <= 1'b1;
							int_addr <= legacy_addr(scmd0); int_wdata <= b;
							pram_wr <= 1'b1;
						end
					endcase
				end
				2'd2: begin
					byte_idx <= 2'd3;
					if (!wp_eff
`ifdef VERILATOR
					    && !xpram_m1
`endif
					) begin
						int_req <= 1'b1; int_we <= 1'b1;
						int_addr <= {cmd0[2:0], cmd1_addr};
						int_wdata <= b; pram_wr <= 1'b1;
					end
				end
				default: ;
				endcase
			end
		end
	end
end

endmodule
