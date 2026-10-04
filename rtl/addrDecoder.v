module addrDecoder(
	input [1:0] configROMSize,
	input [23:0] address,
	input _cpuAS,
	input memoryOverlayOn,
	output reg selectRAM,
	output reg selectROM,
	output reg selectSCSI,
	output reg selectSCC,
	output reg selectIWM,
	output reg selectVIA,
	output reg selectSEOverlay
);

	always @(*) begin
		selectRAM = 0;
		selectROM = 0;
		selectSCSI = 0;
		selectSCC = 0;
		selectIWM = 0;
		selectVIA = 0;
		selectSEOverlay = 0;

		casez (address[23:20])
			4'b00??: begin
				if (memoryOverlayOn == 0)
					selectRAM = !_cpuAS;
				else begin
					if (address[23:20] == 0) begin

						selectROM = !_cpuAS;
					end
				end
			end
			4'b0100: begin
				if(configROMSize[1] || address[17] == 1'b0)
					selectROM = !_cpuAS;
				selectSEOverlay = !_cpuAS;
			end
			4'b0101: begin
				if (address[19])
					selectSCSI = !_cpuAS;
				selectSEOverlay = !_cpuAS;
			end
			4'b0110:
				if (memoryOverlayOn)
					selectRAM = !_cpuAS;
			4'b10?1:
				selectSCC = !_cpuAS;
			4'b1100:
				if (!configROMSize[1])
					selectIWM = !_cpuAS;
			4'b1101:
				selectIWM = !_cpuAS;
			4'b1110:
				if (address[19])
					selectVIA = !_cpuAS;
			default:
				;
		endcase
	end
endmodule
