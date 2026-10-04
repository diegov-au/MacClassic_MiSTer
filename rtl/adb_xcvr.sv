module adb_xcvr
(
	input            clk,
	input            clk_en,
	input            reset,

	input            sr_wr,
	input      [2:0] sr_mode,

	input            data_i,
	output reg       clk_o = 1'b1,
	output reg       data_o,

	input      [7:0] dout,
	input            dout_strobe,
	output reg [7:0] din,
	output reg       din_strobe,

	output           busy
);

reg  [7:0] clk_count;
reg        transmitting, receiving;
reg  [2:0] bitcnt;
reg  [7:0] out_data;
reg  [7:0] to_mac;
reg        sr_wr_d;

assign busy = transmitting | receiving;

wire start_tx = sr_wr && !sr_wr_d && sr_mode == 3'b111;

always @(posedge clk) begin
	if (clk_en) begin
		if (start_tx) begin
			clk_count <= 0;
			clk_o <= 1'b1;
		end else if (transmitting || receiving) begin
			clk_count <= clk_count + 1'd1;
			if (clk_count == 8'd80) begin
				clk_o <= ~clk_o;
				clk_count <= 0;
				if (clk_o) begin

					if (transmitting) out_data <= {out_data[6:0], data_i};
					if (receiving)    data_o   <= to_mac[7 - bitcnt];
				end
			end
		end else begin
			clk_count <= 0;
			clk_o <= 1'b1;
		end
	end
end

reg clk_d;
always @(posedge clk) begin
	if (reset) begin
		bitcnt       <= 0;
		transmitting <= 0;
		receiving    <= 0;
		sr_wr_d      <= 0;
	end else if (clk_en) begin
		if (dout_strobe) begin
			to_mac    <= dout;
			receiving <= 1;
		end

		din_strobe <= 0;
		clk_d      <= clk_o;
		sr_wr_d    <= sr_wr;

		if (~clk_d & clk_o) begin
			bitcnt <= bitcnt + 1'd1;
			if (bitcnt == 3'd7) begin
				if (transmitting) begin
					din_strobe   <= 1;
					din          <= out_data;
					transmitting <= 0;
				end
				if (receiving) receiving <= 0;
			end
		end

		if (start_tx) begin
			transmitting <= 1;
			receiving    <= 0;
			bitcnt       <= 0;
			din_strobe   <= 0;
			clk_d        <= 1'b1;
		end
	end
end

endmodule
