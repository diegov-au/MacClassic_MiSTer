module dataController_top(

	input clk32,
	input clk8_en_p,
	input clk8_en_n,
	input clk16_en_n,
	input E_rising,
	input E_falling,

	input machineType,
	input turbo,
	input _systemReset,

	output _cpuReset,
	output [2:0] _cpuIPL,

	input [15:0] cpuDataIn,

	output        scsi_bus_hold,

	output signed [15:0] cd_snd_l,
	output signed [15:0] cd_snd_r,

	input [3:0] cpuAddrRegHi,
	input [2:0] cpuAddrRegMid,
	input [1:0] cpuAddrRegLo,
	input _cpuUDS,
	input _cpuLDS,
	input _cpuRW,
	output [15:0] cpuDataOut,

	input selectSCSI,
	input selectSCC,
	input selectIWM,
	input selectVIA,
	input selectSEOverlay,
	input _cpuVMA,

	input videoBusControl,
	input cpuBusControl,
	input [15:0] memoryDataIn,
	output [15:0] memoryDataOut,
	input memoryLatch,

	input [10:0] ps2_key,
	output capslock,

	input [24:0] ps2_mouse,
	input        mouse_accum,
	input  [6:0] mouse_scale,

	input serialIn,
	output serialOut,
	input serialCTS,
	output serialRTS,

	input [32:0] timestamp,
	input [64:0] rtc_bcd,
	input  [7:0] pram_ext_addr,
	input        pram_ext_we,
	input  [7:0] pram_ext_wdata,
	output       pram_ext_ready,
	output [7:0] pram_ext_q,
	output       pram_wr,

	output pixelOut,
	input _hblank,
	input _vblank,
	input loadPixels,
	output vid_alt,

	output [10:0] audioOut,
	output snd_alt,
	input loadSound,
	input snd_advance,

	output memoryOverlayOn,
	input [1:0] insertDisk,
	input [1:0] diskSides,
	input [1:0] mediaSides,
	input [1:0] diskMFM,
	input [1:0] diskHD,
	output [1:0] diskEject,
	output [1:0] diskMotor,
	output [1:0] diskAct,

	output [21:0] dskReadAddrInt,
	input dskReadAckInt,
	output [21:0] dskReadAddrExt,
	input dskReadAckExt,

	input [1:0] writeProtect,

	output [21:0] dskWriteAddrInt,
	output [15:0] dskWriteDataInt,
	output        dskWriteReqInt,
	input         dskWriteAckInt,
	output [21:0] dskWriteAddrExt,
	output [15:0] dskWriteDataExt,
	output        dskWriteReqExt,
	input         dskWriteAckExt,

	output        dskCommitDoneInt,
	output [21:0] dskCommitAddrInt,
	output        dskCommitBufWrInt,
	output [7:0]  dskCommitBufAddrInt,
	output [15:0] dskCommitBufDataInt,
	output        dskCommitDoneExt,
	output [21:0] dskCommitAddrExt,
	output        dskCommitBufWrExt,
	output [7:0]  dskCommitBufAddrExt,
	output [15:0] dskCommitBufDataExt,

	input   [SCSI_DEVS-1:0] img_mounted,
	input            [31:0] img_size,
	input                   cd_enable,
	output           [31:0] io_lba[SCSI_DEVS],
	output  [SCSI_DEVS-1:0] io_rd,
	output  [SCSI_DEVS-1:0] io_wr,
	input   [SCSI_DEVS-1:0] io_ack,
	input             [7:0] sd_buff_addr,
	input             [4:0] sd_buff_addr_hi,
	input            [15:0] sd_buff_dout,
	output           [15:0] sd_buff_din[SCSI_DEVS],
	input                   sd_buff_wr
);

	parameter SCSI_DEVS = 2;

	parameter SCSI_CD_DEV = SCSI_DEVS;

	assign audioOut = $signed(audio_latch) * $signed({1'b0, snd_vol});

	reg loadSoundD;
	always @(posedge clk32)
		if (clk8_en_n) loadSoundD <= loadSound;

	reg [7:0] audio_prebuf;
	reg [7:0] audio_sample;

	always @(posedge clk32) begin

		if(clk8_en_p && loadSoundD)
			audio_prebuf <= memoryDataIn[15:8] - 8'd128;

		if(clk8_en_p && snd_advance)
			audio_sample <= audio_prebuf;
	end

	wire [7:0] audio_latch = snd_ena ? 8'h7f : audio_sample;

	reg [19:0] resetDelay;
	wire isResetting = resetDelay != 0;

	initial begin

		resetDelay <= 20'hFFFFF;
	end

	always @(posedge clk32 or negedge _systemReset) begin
		if (_systemReset == 1'b0) begin
			resetDelay <= 20'hFFFFF;
		end
		else if (clk8_en_p && isResetting) begin
			resetDelay <= resetDelay - 1'b1;
		end
	end
	assign _cpuReset = isResetting ? 1'b0 : 1'b1;

	wire SEL;
	wire _viaIrq, _sccIrq, sccWReq;
	wire [15:0] viaDataOut;
	wire [15:0] iwmDataOut;
	wire [7:0] sccDataOut;
	wire [7:0] scsiDataOut;
	wire mouseX1, mouseX2, mouseY1, mouseY2, mouseButton;

	assign _cpuIPL =
		!_viaIrq?3'b110:
		!_sccIrq?3'b101:
		3'b111;

	reg [15:0] cpu_data;
	always @(posedge clk32) if (cpuBusControl && memoryLatch) cpu_data <= memoryDataIn;

	assign cpuDataOut = selectIWM ? iwmDataOut :
							  selectVIA ? viaDataOut :
							  selectSCC ? { sccDataOut, 8'hEF } :
							  selectSCSI ? { scsiDataOut, 8'hEF } :
							  (cpuBusControl && memoryLatch) ? memoryDataIn : cpu_data;

	assign memoryDataOut = cpuDataIn;

	ncr5380 #(.DEVS(SCSI_DEVS), .CD_DEV(SCSI_CD_DEV)) scsi(
		.clk(clk32),
		.reset(!_cpuReset),
		.bus_cs(selectSCSI),
		.bus_rs(cpuAddrRegMid),
		.ior(!_cpuUDS),
		.iow(!_cpuLDS),
		.dack(cpuAddrRegHi[0]),
		.bus_hold(scsi_bus_hold),
		.cd_snd_l(cd_snd_l),
		.cd_snd_r(cd_snd_r),
		.wdata(cpuDataIn[15:8]),
		.rdata(scsiDataOut),

		.img_mounted( img_mounted ),
		.img_size( img_size ),
		.cd_enable( cd_enable ),
		.io_lba ( io_lba ),
		.io_rd ( io_rd ),
		.io_wr ( io_wr ),
		.io_ack ( io_ack ),

		.sd_buff_addr(sd_buff_addr),
		.sd_buff_addr_hi(sd_buff_addr_hi),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr)
	);

	reg [5:0] vblankCount;
	reg _lastVblank;
	always @(posedge clk32) begin
		if (clk8_en_n) begin
			_lastVblank <= _vblank;
			if (_vblank == 1'b0 && _lastVblank == 1'b1) begin
				if (vblankCount != 59) begin
					vblankCount <= vblankCount + 1'b1;
				end
				else begin
					vblankCount <= 6'h0;
				end
			end
		end
	end
	wire onesec = vblankCount == 59;

	reg  SEOverlay;
	always @(posedge clk32) begin
		if (!_cpuReset)
			SEOverlay <= 1;
		else if (selectSEOverlay)
			SEOverlay <= 0;
	end

	wire [2:0] snd_vol;
	wire snd_ena;
	wire driveSel;

	wire [7:0] via_pa_i, via_pa_o, via_pa_oe;
	wire [7:0] via_pb_i, via_pb_o, via_pb_oe;
	wire viaIrq;

	assign _viaIrq = ~viaIrq;

	assign via_pa_i = {sccWReq, ~via_pa_oe[6:4] | via_pa_o[6:4],
	                   via_pa_oe[3] & via_pa_o[3],
	                   ~via_pa_oe[2:0] | via_pa_o[2:0]};
	assign snd_vol = ~via_pa_oe[2:0] | via_pa_o[2:0];
	assign snd_alt = machineType ? 1'b0 : ~(~via_pa_oe[3] | via_pa_o[3]);

	assign driveSel = 1'b1;
	assign memoryOverlayOn = machineType ? SEOverlay : ~via_pa_oe[4] | via_pa_o[4];
	assign SEL = ~via_pa_oe[5] | via_pa_o[5];
	assign vid_alt = ~via_pa_oe[6] | via_pa_o[6];

	assign via_pb_i = {1'b1, {3{machineType}} | {_hblank, mouseY2, mouseX2}, machineType ? _ADBint : mouseButton, 2'b11, rtcdat_o};
	assign snd_ena = ~via_pb_oe[7] | via_pb_o[7];

	assign viaDataOut[7:0] = 8'hEF;

	via6522 via(
		.clock      (clk32),
		.rising     (E_rising),
		.falling    (E_falling),
		.reset      (!_cpuReset),

		.addr       (cpuAddrRegHi),
		.wen        (selectVIA && !_cpuVMA && !_cpuRW),
		.ren        (selectVIA && !_cpuVMA &&  _cpuRW),
		.data_in    (cpuDataIn[15:8]),
		.data_out   (viaDataOut[15:8]),

		.phi2_ref   (),

		.port_a_o   (via_pa_o),
		.port_a_t   (via_pa_oe),
		.port_a_i   (via_pa_i),

		.port_b_o   (via_pb_o),
		.port_b_t   (via_pb_oe),
		.port_b_i   (via_pb_i),

		.ca1_i      (_vblank),
		.ca2_i      (onesec),

		.cb1_i      (kbdclk),
		.cb2_i      (cb2_i),
		.cb2_o      (cb2_o),
		.cb2_t      (cb2_t),

		.irq        (viaIrq)
	);

	wire _rtccs   = ~via_pb_oe[2] | via_pb_o[2];
	wire rtcck    = ~via_pb_oe[1] | via_pb_o[1];
	wire rtcdat_i = ~via_pb_oe[0] | via_pb_o[0];
	wire rtcdat_o;

	rtc pram (
		.clk        (clk32),
		.reset      (!_cpuReset),
		.timestamp  (timestamp),
		.rtc_bcd    (rtc_bcd),
		._cs        (_rtccs),
		.ck         (rtcck),
		.dat_i      (rtcdat_i),
		.dat_o      (rtcdat_o),
		.ext_addr   (pram_ext_addr),
		.ext_we     (pram_ext_we),
		.ext_wdata  (pram_ext_wdata),
		.ext_ready  (pram_ext_ready),
		.ext_q      (pram_ext_q),
		.pram_wr    (pram_wr)
	);

	wire _ADBint;
	wire ADBST0 = ~via_pb_oe[4] | via_pb_o[4];
	wire ADBST1 = ~via_pb_oe[5] | via_pb_o[5];

	wire kbdclk;
	wire kbddata_o;
	wire cb2_i = kbddata_o;
	wire cb2_o, cb2_t;
	wire kbddat_i = ~cb2_t | cb2_o;
	wire adb_busy;
	wire [7:0] adb_din, adb_dout;
	wire       adb_din_strobe, adb_dout_strobe;

	reg [2:0] via_sr_mode;
	always @(posedge clk32) begin
		if (!_cpuReset) via_sr_mode <= 3'b000;
		else if (E_falling && selectVIA && !_cpuVMA && !_cpuRW && cpuAddrRegHi == 4'hB)
			via_sr_mode <= cpuDataIn[12:10];
	end

	adb_xcvr adbx(
		.clk(clk32),
		.clk_en(clk8_en_p),
		.reset(!_cpuReset),
		.sr_wr(selectVIA && !_cpuVMA && !_cpuRW && cpuAddrRegHi == 4'hA),
		.sr_mode(via_sr_mode),
		.data_i(kbddat_i),
		.clk_o(kbdclk),
		.data_o(kbddata_o),
		.dout(adb_dout),
		.dout_strobe(adb_dout_strobe),
		.din(adb_din),
		.din_strobe(adb_din_strobe),
		.busy(adb_busy)
	);

	wire [7:0] kbd_out_data = 8'h00;
	wire       kbd_out_strobe = 1'b0;

	swim sw(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		._reset(_cpuReset),
		.selectSWIM(selectIWM),
		._cpuRW(_cpuRW),
		._cpuLDS(_cpuLDS),
		.dataIn(cpuDataIn),
		.cpuAddrRegHi(cpuAddrRegHi),
		.SEL(SEL),
		.driveSel(driveSel),
		.dataOut(iwmDataOut),
		.insertDisk(insertDisk),
		.diskEject(diskEject),
		.diskSides(diskSides),
		.mediaSides(mediaSides),
		.diskMFM(diskMFM),
		.diskHD(diskHD),
		.writeProtect(writeProtect),

		.wrSdAddr(dskWriteAddrInt),
		.wrSdData(dskWriteDataInt),
		.wrSdReq(dskWriteReqInt),
		.wrSdAck(dskWriteAckInt),
		.wrCommitDone(dskCommitDoneInt),
		.wrCommitAddr(dskCommitAddrInt),
		.wrSdBufAddr(dskCommitBufAddrInt),
		.wrSdBufData(dskCommitBufDataInt),
		.wrSdBufWr(dskCommitBufWrInt),

		.diskMotor(diskMotor),
		.diskAct(diskAct),

		.dskReadAddrInt(dskReadAddrInt),
		.dskReadAckInt(dskReadAckInt),
		.dskReadAddrExt(dskReadAddrExt),
		.dskReadAckExt(dskReadAckExt),
		.dskReadData(memoryDataIn[7:0]),

		.mfm_wr_byte(), .mfm_wr_mark(), .mfm_wr_stb(), .mfm_wr_active(),
		.dbg_ism_flpe(), .dbg_flp_byte_cnt(), .dbg_flp_miss_cnt(),
		.dbg_flp_disk_data(), .dbg_flp_track(), .dbg_flp_side(),
		.dbg_flp_step_cnt(), .dbg_iwm_latch(), .dbg_flp_byte_stb(),
		.dbg_flp_raw(), .dbg_ism_state(), .dbg_flp_strb_cnt(),
		.dbg_flp_strb_en_cnt(), .dbg_flp_strb_last(), .dbg_flp_rej_step(),
		.dbg_flp_status(), .dbg_flp_media(), .dbg_flp_gcr_addr(),
		.dbg_ism_verdict(), .dbg_ism_unrlatch(), .dbg_ism_scan(),
		.dbg_mfm_stall()
	);

	assign dskWriteAddrExt     = 22'd0;
	assign dskWriteDataExt     = 16'd0;
	assign dskWriteReqExt      = 1'b0;
	assign dskCommitDoneExt    = 1'b0;
	assign dskCommitAddrExt    = 22'd0;
	assign dskCommitBufWrExt   = 1'b0;
	assign dskCommitBufAddrExt = 8'd0;
	assign dskCommitBufDataExt = 16'd0;

	scc s(
		.clk(clk32),
		.cep(clk8_en_p),
		.cen(clk8_en_n),
		.reset_hw(~_cpuReset),
		.cs(selectSCC && (_cpuLDS == 1'b0 || _cpuUDS == 1'b0)),

		.we(!_cpuLDS),
		.rs(cpuAddrRegLo),
		.wdata(cpuDataIn[15:8]),
		.rdata(sccDataOut),
		._irq(_sccIrq),
		.dcd_a(mouseX1),
		.dcd_b(mouseY1),
		.wreq(sccWReq),
		.txd(serialOut),
		.rxd(serialIn),
		.cts(serialCTS),
		.rts(serialRTS)
		);

	videoShifter vs(
		.clk32(clk32),
		.memoryLatch(memoryLatch),
		.dataIn(memoryDataIn),
		.loadPixels(loadPixels),
		.pixelOut(pixelOut));

	ps2_mouse mouse(
		.clk(clk32),
		.ce(clk8_en_p),
		.reset(~_cpuReset),
		.ps2_mouse(ps2_mouse),
		.x1(mouseX1),
		.y1(mouseY1),
		.x2(mouseX2),
		.y2(mouseY2),
		.button(mouseButton));

	wire [7:0] kbd_in_data;
	wire kbd_in_strobe;

	ps2_kbd kbd(
		.clk(clk32),
		.ce(clk8_en_p),
		.reset(~_cpuReset),
		.ps2_key(ps2_key),
		.data_out(kbd_out_data),
		.strobe_out(kbd_out_strobe),
		.data_in(kbd_in_data),
		.strobe_in(kbd_in_strobe),
		.capslock(capslock)
		);

	adb adb(
		.clk(clk32),
		.clk_en(clk8_en_p),
		.reset(~_cpuReset),
		.st({ADBST1, ADBST0}),
		._int(_ADBint),
		.viaBusy(adb_busy),
		.listen(),
		.adb_din(adb_din),
		.adb_din_strobe(adb_din_strobe),
		.adb_dout(adb_dout),
		.adb_dout_strobe(adb_dout_strobe),

		.ps2_mouse(ps2_mouse),
		.ps2_key(ps2_key),

		.mouse_accum(mouse_accum),
		.mouse_scale(mouse_scale)

	);

endmodule
