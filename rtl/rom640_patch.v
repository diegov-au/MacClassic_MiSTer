module rom640_patch(
	input             res640,
	input             mirror,
	input      [18:1] addr,
	input      [15:0] din,
	output     [15:0] dout
);

	reg        hit;
	reg [15:0] val;

	always @(*) begin
		hit = 1'b1;
		if (mirror) case ({addr, 1'b0})

			19'h7FF80: val = 16'h20FC;
			19'h7FF82: val = 16'h0085;
			19'h7FF84: val = 16'h0060;
			19'h7FF86: val = 16'h20BC;
			19'h7FF88: val = 16'h0103;
			19'h7FF8A: val = 16'h0220;
			19'h7FF8C: val = 16'h5988;
			19'h7FF8E: val = 16'h4EB9;
			19'h7FF90: val = 16'h0040;
			19'h7FF92: val = 16'h1588;
			19'h7FF94: val = 16'h08F8;
			19'h7FF96: val = 16'h0007;
			19'h7FF98: val = 16'h03F8;
			19'h7FF9A: val = 16'h2F3C;
			19'h7FF9C: val = 16'h0045;
			19'h7FF9E: val = 16'h0040;
			19'h7FFA0: val = 16'hA877;
			19'h7FFA2: val = 16'h4E75;

			19'h7FFA4: val = 16'h554F;
			19'h7FFA6: val = 16'h2038;
			19'h7FFA8: val = 16'h0830;
			19'h7FFAA: val = 16'h2055;
			19'h7FFAC: val = 16'h2050;
			19'h7FFAE: val = 16'hD068;
			19'h7FFB0: val = 16'h000A;
			19'h7FFB2: val = 16'h4840;
			19'h7FFB4: val = 16'hD068;
			19'h7FFB6: val = 16'h0008;
			19'h7FFB8: val = 16'h4840;
			19'h7FFBA: val = 16'h2F00;
			19'h7FFBC: val = 16'h2F0B;
			19'h7FFBE: val = 16'hA8AD;
			19'h7FFC0: val = 16'h101F;
			19'h7FFC2: val = 16'h4E75;
			default:   begin hit = 1'b0; val = 16'h0000; end
		endcase
		else case ({addr, 1'b0})

			19'h005CA: val = 16'h21FA;
			19'h005CC: val = 16'h1C5A;
			19'h005D2: val = 16'h0050;

			19'h0060A: val = 16'h01E0;
			19'h0060E: val = 16'h0280;

			19'h008CC: val = 16'h01E0;
			19'h008CE: val = 16'h0280;

			19'h00F4C: val = 16'h0054;
			19'h00F4E: val = 16'h43AA;
			19'h00F5E: val = 16'h0054;
			19'h00F60: val = 16'h485B;

			19'h010A2: val = 16'h0054;
			19'h010A4: val = 16'h0054;
			19'h010A8: val = 16'h01E0;
			19'h010AC: val = 16'h0280;
			19'h010B0: val = 16'h0050;
			19'h010B4: val = 16'h0000;
			19'h010B6: val = 16'h9600;

			19'h0118A: val = 16'h0054;
			19'h0118C: val = 16'h43AA;
			19'h01198: val = 16'h0054;
			19'h0119A: val = 16'h458B;

			19'h01566: val = 16'h4EF9;
			19'h01568: val = 16'h004F;
			19'h0156A: val = 16'hFF80;

			19'h01640: val = 16'h4EF9;
			19'h01642: val = 16'h004F;
			19'h01644: val = 16'hFFA4;

			19'h01666: val = 16'h008B;
			19'h01668: val = 16'h0066;

			19'h011B0: val = 16'h0050;
			19'h011D8: val = 16'h0050;
			19'h011EA: val = 16'h0050;

			19'h01C68: val = 16'h6008;

			19'h18E02: val = 16'h7050;

			19'h18E7A: val = 16'h0260;
			19'h18E80: val = 16'h0260;
			19'h18EA0: val = 16'h01D0;
			19'h18EA6: val = 16'h01E0;
			19'h18EC4: val = 16'h7A50;

			19'h18F9A: val = 16'h01E0;
			19'h18FA0: val = 16'h0280;
			19'h18FB4: val = 16'h01E0;
			default:   begin hit = 1'b0; val = 16'h0000; end
		endcase
	end

	assign dout = (res640 && hit) ? val : din;

endmodule
