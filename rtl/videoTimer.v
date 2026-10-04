module videoTimer(
	input clk,
	input clk_en,
	input [1:0] busCycle,
	input vid_alt,
	output [21:0] videoAddr,
	output reg hsync,
	output reg vsync,
	output _hblank,
	output _vblank,
	output loadPixels
);

	localparam 	kVisibleWidth = 128,
					kTotalWidth = 168,
					kVisibleHeightStart = 42,
					kVisibleHeightEnd = 725,
					kTotalHeight = 806,
					kHsyncStart = 131,
					kHsyncEnd = 147,
					kVsyncStart = 771,
					kVsyncEnd = 776,
					kPixelLatency = 1;

	localparam kScreenBufferBase = 22'h3FA700;
	localparam startAddr = kVisibleHeightStart/2 * kVisibleWidth/2;

	reg [7:0] xpos;
	reg [9:0] ypos;

	wire endline = (xpos == kTotalWidth-1);

	always @(posedge clk) begin
		if (clk_en) begin
			if (endline)
				xpos <= 0;
			else if (xpos == 0 && busCycle != 0)

				xpos <= 0;
			else
				xpos <= xpos + 1'b1;
		end
	end

	always @(posedge clk) begin
		if (clk_en) begin
			if (endline) begin
				if (ypos == kTotalHeight-1)
					ypos <= 0;
				else
					ypos <= ypos + 1'b1;
			end
		end
	end

	always @(posedge clk) begin
		if (clk_en) begin
			hsync <= ~(xpos >= kHsyncStart+kPixelLatency && xpos <= kHsyncEnd+kPixelLatency);
			vsync <= ~(ypos >= kVsyncStart && ypos <= kVsyncEnd);
		end
	end

	assign _hblank = ~(xpos >= kVisibleWidth+kPixelLatency);
	assign _vblank = ~(ypos < kVisibleHeightStart || ypos > kVisibleHeightEnd);

	assign videoAddr = kScreenBufferBase - (vid_alt ? 16'h0 : 16'h8000) -
							 startAddr[21:0] +
							 { ypos[9:1], xpos[6:2], 1'b0 };

	assign loadPixels = _vblank == 1'b1 && _hblank == 1'b1 && busCycle == 2'b00;

endmodule
