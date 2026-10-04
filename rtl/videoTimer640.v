module videoTimer640(
	input clk,
	input clk_en,
	input [1:0] busCycle,
	output [21:0] videoAddr,
	output reg hsync,
	output reg vsync,
	output _hblank,
	output _vblank,
	output loadPixels
);

	localparam 	kVisibleWidth = 160,
					kTotalWidth = 208,
					kVisibleHeight = 480,
					kTotalHeight = 651,
					kHsyncStart = 166,
					kHsyncEnd = 189,
					kVsyncStart = 490,
					kVsyncEnd = 495,
					kPixelLatency = 1;

	localparam [15:0] kScreenOffset = 16'h0054;

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
	assign _vblank = ~(ypos >= kVisibleHeight);

	wire [15:0] lineOffset = {ypos[8:0], 6'b0} + {2'b0, ypos[8:0], 4'b0};
	assign videoAddr = {6'b0, kScreenOffset + lineOffset + {9'b0, xpos[7:2], 1'b0}};

	assign loadPixels = _vblank == 1'b1 && _hblank == 1'b1 && busCycle == 2'b00;

endmodule
