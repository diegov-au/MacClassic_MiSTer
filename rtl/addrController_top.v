module addrController_top(

	input clk,
	output clk8,
	output clk8_en_p,
	output clk8_en_n,
	output clk16_en_p,
	output clk16_en_n,

	input turbo,
	input [1:0] configROMSize,
	input [1:0] configRAMSize,

	input [23:0] cpuAddr,
	input _cpuUDS,
	input _cpuLDS,
	input _cpuRW,
	input _cpuAS,

	output [21:0] memoryAddr,
	output _memoryUDS,
	output _memoryLDS,
	output _romOE,
	output _ramOE,
	output _ramWE,
	output videoBusControl,
	output dioBusControl,
	output cpuBusControl,
	output memoryLatch,

	output selectSCSI,
	output selectSCC,
	output selectIWM,
	output selectVIA,
	output selectRAM,
	output selectROM,
	output selectSEOverlay,

	output hsync,
	output vsync,
	output _hblank,
	output _vblank,
	output loadPixels,
	input  vid_alt,

	input  res640,

	output vramAccess,

	input  snd_alt,
	output loadSound,
	output snd_advance,

	input memoryOverlayOn,

	input [21:0] dskReadAddrInt,
	output dskReadAckInt,
	input [21:0] dskReadAddrExt,
	output dskReadAckExt,

	input [21:0] dskLoadAddrInt,
	input dskLoadReqInt,
	output dskLoadAckInt,
	input [21:0] dskLoadAddrExt,
	input dskLoadReqExt,
	output dskLoadAckExt,
	output dskLoadWrEn,

	output dskLoadSelExt
);

	assign loadSound = sndReadAck;

	reg sndAdvance;
	assign snd_advance = sndAdvance;

	localparam [17:0] SND_SIZE = 18'd135408;
	localparam [17:0] SND_STEP = 18'd370;

	reg [21:0] audioAddr;
	reg [17:0] snd_div;

	wire [17:0] snd_div_next = snd_div + SND_STEP;

	reg vblankD;
	always @(posedge clk) begin
		if (clk8_en_p) begin
			vblankD <= _vblank;
			sndAdvance <= 1'b0;

			if (vblankD && !_vblank) begin
				audioAddr <= snd_alt ? 22'h3FA100 : 22'h3FFD00;
				snd_div <= 18'd0;
				sndAdvance <= 1'b1;
			end else if (snd_div_next >= SND_SIZE) begin
				snd_div <= snd_div_next - SND_SIZE;
				audioAddr <= audioAddr + 22'd2;
				sndAdvance <= 1'b1;
			end else begin
				snd_div <= snd_div_next;
			end
		end
	end

	assign dioBusControl = extraBusControl;

	reg [1:0] busCycle;
	reg [1:0] busPhase;
	reg [1:0] extra_slot_count;

	always @(posedge clk) begin
		busPhase <= busPhase + 1'd1;
		if (busPhase == 2'b11)
			busCycle <= busCycle + 2'd1;
	end
	assign memoryLatch = busPhase == 2'd3;
	assign clk8 = !busPhase[1];
	assign clk8_en_p = busPhase == 2'b11;
	assign clk8_en_n = busPhase == 2'b01;
	assign clk16_en_p = !busPhase[0];
	assign clk16_en_n = busPhase[0];

	reg extra_slot_advance;
	always @(posedge clk)
		if (clk8_en_n) extra_slot_advance <= (busCycle == 2'b11);

	always @(posedge clk) begin
		if(clk8_en_p && extra_slot_advance) begin
			extra_slot_count <= extra_slot_count + 2'd1;
		end
	end

	assign videoBusControl = (busCycle == 2'b00);

	assign cpuBusControl = (busCycle == 2'b01) || (busCycle == 2'b11);

	wire extraBusControl = (busCycle == 2'b10);

	wire [21:0] videoAddr;

	wire videoControlActive = _hblank;

	assign _romOE = ~(cpuBusControl && selectROM && _cpuRW);

	wire selectVRAM = res640 && cpuAddr[23:16] == 8'h54 && !_cpuAS;
	assign vramAccess = res640 && ((cpuBusControl && selectVRAM) || videoBusControl);

	wire extraRamRead = sndReadAck;
	assign _ramOE = ~((videoBusControl && videoControlActive) || (extraRamRead) ||
						(cpuBusControl && (selectRAM || selectVRAM) && _cpuRW));
	assign _ramWE = ~(cpuBusControl && (selectRAM || selectVRAM) && !_cpuRW);

	assign _memoryUDS = cpuBusControl ? _cpuUDS : 1'b0;
	assign _memoryLDS = cpuBusControl ? _cpuLDS : 1'b0;
	wire [21:0] addrMux = sndReadAck ? audioAddr : videoBusControl ? videoAddr : cpuAddr[21:0];
	wire [21:0] macAddr;
	assign macAddr[15:0] = addrMux[15:0];

	wire ram_access = (cpuBusControl && selectRAM) || videoBusControl || sndReadAck;
	wire rom_access = (cpuBusControl && selectROM);

	assign macAddr[16] = rom_access && configROMSize == 2'b00 ? 1'b0 :
									addrMux[16];
	assign macAddr[17] = ram_access && configRAMSize == 2'b00 ? 1'b0 :
									rom_access && configROMSize == 2'b01 ? 1'b0 :
									rom_access && configROMSize == 2'b00 ? 1'b1 :
									addrMux[17];
	assign macAddr[18] = ram_access && configRAMSize == 2'b00 ? 1'b0 :
	                     rom_access && configROMSize != 2'b11 ? 1'b0 :
									addrMux[18];

	assign macAddr[19] = ram_access && configRAMSize == 2'b00 ? 1'b0 :
									rom_access ? 1'b0 :
									addrMux[19];
	assign macAddr[20] = ram_access && configRAMSize[0] == 1'b0 ? 1'b0 :
									rom_access ? 1'b0 :
									addrMux[20];
	assign macAddr[21] = ram_access && configRAMSize != 2'b11 ? 1'b0 :
									rom_access ? 1'b0 :
									addrMux[21];

	assign dskReadAckInt = (extraBusControl == 1'b1) && (extra_slot_count == 0);
	assign dskReadAckExt = (extraBusControl == 1'b1) && (extra_slot_count == 1);

	wire sndReadAck    = (extraBusControl == 1'b1) && (extra_slot_count == 2);

	reg dskLoadReqIntR, dskLoadReqExtR;
	always @(posedge clk) if (busPhase == 2'b11) begin
		dskLoadReqIntR <= dskLoadReqInt;
		dskLoadReqExtR <= dskLoadReqExt;
	end

	assign dskLoadSelExt = ~dskLoadReqIntR & dskLoadReqExtR;
	wire dskLoadGrant  = (extraBusControl == 1'b1) && (extra_slot_count == 3) && (dskLoadReqIntR | dskLoadReqExtR);
	wire dskLoadAck    = dskLoadGrant && (busPhase == 2'b11);
	assign dskLoadAckInt = dskLoadAck & ~dskLoadSelExt;
	assign dskLoadAckExt = dskLoadAck &  dskLoadSelExt;
	assign dskLoadWrEn   = dskLoadGrant;

	assign memoryAddr =
		dskReadAckInt ? dskReadAddrInt + 22'h100000:
		dskReadAckExt ? dskReadAddrExt + 22'h280000:
		dskLoadGrant  ? (dskLoadSelExt ? dskLoadAddrExt + 22'h280000 : dskLoadAddrInt + 22'h100000) :
		vramAccess    ? {6'd0, addrMux[15:0]} :
		macAddr;

	addrDecoder ad(
		.configROMSize(configROMSize),
		.address(cpuAddr),
		._cpuAS(_cpuAS),
		.memoryOverlayOn(memoryOverlayOn),
		.selectRAM(selectRAM),
		.selectROM(selectROM),
		.selectSCSI(selectSCSI),
		.selectSCC(selectSCC),
		.selectIWM(selectIWM),
		.selectVIA(selectVIA),
		.selectSEOverlay(selectSEOverlay));

	wire [21:0] videoAddrO, videoAddr640;
	wire hsyncO, vsyncO, _hblankO, _vblankO, loadPixelsO;
	wire hsync640, vsync640, _hblank640, _vblank640, loadPixels640;

	videoTimer vt(
		.clk(clk),
		.clk_en(clk8_en_p),
		.busCycle(busCycle),
		.vid_alt(vid_alt),
		.videoAddr(videoAddrO),
		.hsync(hsyncO),
		.vsync(vsyncO),
		._hblank(_hblankO),
		._vblank(_vblankO),
		.loadPixels(loadPixelsO));

	videoTimer640 vt640(
		.clk(clk),
		.clk_en(clk8_en_p),
		.busCycle(busCycle),
		.videoAddr(videoAddr640),
		.hsync(hsync640),
		.vsync(vsync640),
		._hblank(_hblank640),
		._vblank(_vblank640),
		.loadPixels(loadPixels640));

	assign videoAddr  = res640 ? videoAddr640  : videoAddrO;
	assign hsync      = res640 ? hsync640      : hsyncO;
	assign vsync      = res640 ? vsync640      : vsyncO;
	assign _hblank    = res640 ? _hblank640    : _hblankO;
	assign _vblank    = res640 ? _vblank640    : _vblankO;
	assign loadPixels = res640 ? loadPixels640 : loadPixelsO;

endmodule
