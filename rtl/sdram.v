// Copyright (c) 2015 Till Harbaum <till@harbaum.org>

// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

module sdram
(

	output              sd_clk,
	inout  reg [15:0]   sd_data,
	output reg [12:0]   sd_addr,
	output     [1:0]    sd_dqm,
	output reg [1:0]    sd_ba,
	output              sd_cs,
	output              sd_we,
	output              sd_ras,
	output              sd_cas,

	input               init,
	input               clk_64,
	input               clk_8,

	input [15:0]        din,
	output reg [15:0]   dout,
	input [23:0]        addr,
	input [1:0]         ds,
	input               oe,
	input               we
);

localparam RASCAS_DELAY   = 3'd2;
localparam BURST_LENGTH   = 3'b000;
localparam ACCESS_TYPE    = 1'b0;
localparam CAS_LATENCY    = 3'd2;
localparam OP_MODE        = 2'b00;
localparam NO_WRITE_BURST = 1'b1;

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

localparam STATE_FIRST     = 3'd0;
localparam STATE_CMD_START = 3'd0;
localparam STATE_CMD_CONT  = STATE_CMD_START  + RASCAS_DELAY;
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 4'd1;
localparam STATE_LAST      = 3'd7;

reg [2:0] t;
always @(posedge clk_64) begin

	if(((t == STATE_LAST)  && ( clk_8 == 0)) ||
		((t == STATE_FIRST) && ( clk_8 == 1)) ||
		((t != STATE_LAST) && (t != STATE_FIRST)))
			t <= t + 3'd1;
end

reg [4:0] reset;
always @(posedge clk_64) begin
	if(init)	reset <= 5'h1f;
	else if((t == STATE_LAST) && (reset != 0))
		reset <= reset - 5'd1;
end

initial reset = 5'h1F;

localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [3:0] sd_cmd;

assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];
assign sd_dqm = sd_addr[12:11];

reg oe_latch, we_latch;

always @(posedge clk_64) begin
	sd_cmd <= CMD_INHIBIT;
	sd_data <= 16'bZZZZZZZZZZZZZZZZ;

	if(reset != 0) begin

		if(t == STATE_CMD_START) begin

			if(reset == 13) begin
				sd_cmd <= CMD_PRECHARGE;
				sd_addr[10] <= 1'b1;
			end

			if(reset == 2) begin
				sd_cmd <= CMD_LOAD_MODE;
				sd_addr <= MODE;
			end

		end
	end else begin

		if(t == STATE_CMD_START) begin
			{oe_latch, we_latch} <= {oe, we};
			if (we || oe) begin
				sd_cmd <= CMD_ACTIVE;
				sd_addr <= { 1'b0, addr[19:8] };
				sd_ba <= addr[21:20];
			end

			else begin
				sd_cmd <= CMD_AUTO_REFRESH;
			end
		end

		if(t == STATE_CMD_CONT && (we_latch || oe_latch)) begin
			sd_cmd <= we_latch?CMD_WRITE:CMD_READ;
			if (we_latch) sd_data <= din;

			sd_addr <= { we_latch ? ~ds : 2'b00, 2'b10, addr[22], addr[7:0] };
		end

		if (t == STATE_READ && oe_latch) dout <= sd_data;

	end
end

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_64),
	.dataout(sd_clk),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
