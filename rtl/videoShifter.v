module videoShifter(
	input clk32,
	input memoryLatch,
	input [15:0] dataIn,
	input loadPixels,
	output pixelOut
    );

	reg [15:0] shiftRegister;

	assign pixelOut = ~shiftRegister[15];

	always @(posedge clk32) begin

		if (loadPixels && memoryLatch) begin
			shiftRegister <= dataIn;
		end
		else begin
			shiftRegister <= { shiftRegister[14:0], 1'b1 };
		end
	end

endmodule
