module swim
#(

	parameter [8:0] WR_VOID_PERIOD = 9'd259
)
(
	input clk,
	input cep,
	input cen,

	input _reset,
	input selectSWIM,
	input _cpuRW,
	input _cpuLDS,
	input [15:0] dataIn,
	input [3:0] cpuAddrRegHi,
	input SEL,
	input driveSel,
	output [15:0] dataOut,
	input [1:0] insertDisk,
	output [1:0] diskEject,
	input [1:0] diskSides,

	input [1:0] mediaSides,
	input [1:0] diskMFM,

	output [21:0] wrSdAddr,
	output [15:0] wrSdData,
	output        wrSdReq,
	input         wrSdAck,
	output        wrCommitDone,
	output [21:0] wrCommitAddr,

	output  [7:0] wrSdBufAddr,
	output [15:0] wrSdBufData,
	output        wrSdBufWr,
	input [1:0] writeProtect,

	input [1:0] diskHD,

	output [1:0] diskMotor,
	output [1:0] diskAct,

	output [21:0] dskReadAddrInt,
	input dskReadAckInt,
	output [21:0] dskReadAddrExt,
	input dskReadAckExt,
	input [7:0] dskReadData,

	output    [7:0] mfm_wr_byte,
	output          mfm_wr_mark,
	output          mfm_wr_stb,
	output          mfm_wr_active,

	output [31:0] dbg_ism_flpe,
	output [15:0] dbg_flp_byte_cnt,
	output [15:0] dbg_flp_miss_cnt,
	output [7:0]  dbg_flp_disk_data,
	output [6:0]  dbg_flp_track,
	output        dbg_flp_side,
	output [15:0] dbg_flp_step_cnt,
	output [7:0]  dbg_iwm_latch,
	output        dbg_flp_byte_stb,
	output [7:0]  dbg_flp_raw,

	output [31:0] dbg_ism_state,
	output [15:0] dbg_flp_strb_cnt,
	output [15:0] dbg_flp_strb_en_cnt,
	output [23:0] dbg_flp_strb_last,
	output [8:0]  dbg_flp_rej_step,
	output [7:0]  dbg_flp_status,

	output [31:0] dbg_flp_media,
	output [21:0] dbg_flp_gcr_addr,

	output [31:0] dbg_ism_verdict,

	output [31:0] dbg_ism_unrlatch,

	output [31:0] dbg_ism_scan,

	output [23:0] dbg_mfm_stall
);

	wire [7:0] dataInLo = dataIn[7:0];
	reg [7:0] dataOutLo;

	assign dataOut = { 8'hBE, dataOutLo };

	reg        ism_mode;
	reg [7:0]  ism_mode_reg;
	reg [7:0]  ism_setup;
	reg [7:0]  ism_error;

	(* ramstyle = "MLAB" *) reg [7:0]  ism_param[0:15];
	reg [3:0]  ism_param_idx;
	reg [15:0] ism_fifo[0:1];
	reg [1:0]  ism_fifo_pos;

	(* ramstyle = "MLAB" *) reg [15:0] ism_stage[0:15];
	reg [3:0]  ism_stage_rd, ism_stage_wr;
	reg [4:0]  ism_stage_cnt;
	reg [1:0]  iwm_to_ism_counter;

	reg  [4:0] ism_anchor_sector;
	reg        ism_anchor_ok;
	reg        ism_write_arm_d;

	localparam FIFO_B_MARK = 8;
	localparam FIFO_B_CRC  = 9;
	localparam FIFO_B_CRC0 = 10;

	reg ca0, ca1, ca2, lstrb, selectExternalDrive, q6, q7;
	reg ca0Next, ca1Next, ca2Next, lstrbNext, selectExternalDriveNext, q6Next, q7Next;
	wire advanceDriveHead;
	reg [7:0] readDataLatch;
	assign dbg_iwm_latch = readDataLatch;

	wire writeBusyInt, writeUnderrunInt;
	wire writeBusyExt, writeUnderrunExt;
	wire _iwmBusy       = ~(selectExternalDrive ? writeBusyExt : writeBusyInt);
	wire _writeUnderrun = ~(selectExternalDrive ? writeUnderrunExt : writeUnderrunInt);

	reg diskEnableExt, diskEnableInt;
	reg diskEnableExtNext, diskEnableIntNext;

	wire dataRegWrite = (_cpuRW == 1'b0) && selectSWIM && (_cpuLDS == 1'b0) &&
	                    !ism_mode && ({q7Next, q6Next} == 2'b11) &&
	                    (diskEnableExt | diskEnableInt);
	wire writeReqInt = cen && dataRegWrite && !selectExternalDriveNext;
	wire writeReqExt = cen && dataRegWrite &&  selectExternalDriveNext;

	wire iwmWriteMode = q7 && !ism_mode;
	wire newByteReadyInt;
	wire [7:0] readDataInt;
	wire senseInt = readDataInt[7];
	wire newByteReadyExt;
	wire [7:0] readDataExt;

`ifdef ONE_DRIVE
	wire senseExt = 1'b1;
`else
	wire senseExt = readDataExt[7];
`endif

	wire [7:0] mfm_byte_int, mfm_byte_ext;
	wire [4:0] mfm_sector_int, mfm_sector_ext;
	wire mfm_mark_int, mfm_mark_ext, mfm_crc0_int, mfm_crc0_ext;
	wire mfm_stb_int, mfm_stb_ext;

	wire ism_drive_sel  = ism_mode_reg[1] && !ism_mode_reg[2];
	wire ism_devsel_int = ism_mode && ism_mode_reg[7] && ism_drive_sel;
	wire ism_devsel_ext = ism_mode && ism_mode_reg[7] && ism_mode_reg[2];

	wire ism_selonly_int = ism_mode && ism_drive_sel;
	wire ism_selonly_ext = ism_mode && ism_mode_reg[2];

	wire       swim_acc = selectSWIM && (_cpuLDS == 1'b0);
	reg        swim_acc_d;
	reg  [3:0] acc_addr_l;
	reg        acc_rw_l;
	reg  [7:0] acc_data_l;
	wire       acc_end = swim_acc_d && !swim_acc;

	reg  [3:0] ism_phase_oe;

	reg [2:0] dbg_err_d = 0;
	reg       dbg_ra_d = 0;
	reg [7:0] dbg_flpe_ovr = 0, dbg_flpe_unr = 0, dbg_flpe_arm = 0;
	reg        mfm_synced;

	reg        ism_arm_d;

	wire effSEL = SEL;

	floppy floppyInt
	(
		.clk(clk),
		.cep(cep),
		.cen(cen),

		._reset(_reset),
		.ca0(ca0),
		.ca1(ca1),
		.ca2(ca2),
		.SEL(effSEL),
		.lstrb(lstrb),
		._enable(ism_mode ? ~ism_selonly_int : ~(diskEnableInt & driveSel)),
		.writeData(dataInLo),
		.writeReq(writeReqInt),
		.writeMode(iwmWriteMode),
		.writeProtect(writeProtect[0]),
		.writeBusy(writeBusyInt),
		.writeUnderrun(writeUnderrunInt),
		.wrSecValid(),
		.wrSecNum(),
		.wrSecAddr(),
		.wrSdAddr(wrSdAddr),
		.wrSdData(wrSdData),
		.wrSdReq(wrSdReq),
		.wrSdAck(wrSdAck),
		.wrCommitDone(wrCommitDone),
		.wrCommitAddr(wrCommitAddr),
		.wrSdBufAddr(wrSdBufAddr),
		.wrSdBufData(wrSdBufData),
		.wrSdBufWr(wrSdBufWr),
		.readData(readDataInt),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyInt),
		.insertDisk(insertDisk[0]),
		.diskSides(diskSides[0]),
		.mediaSides(mediaSides[0]),
		.diskEject(diskEject[0]),

		.motor(diskMotor[0]),
		.act(diskAct[0]),

		.dskReadAddr(dskReadAddrInt),
		.dskReadAck(dskReadAckInt),
		.dskReadData(dskReadData),
		.ism_active(ism_mode),
		.ism_action(ism_mode && ism_mode_reg[3]),
		.ism_sel(ism_devsel_int),
		.mfm_disk(diskMFM[0]),
		.mfm_hd(diskHD[0]),
		.mfm_byte(mfm_byte_int),
		.mfm_sector(mfm_sector_int),
		.mfm_wr_byte(mfm_wr_byte),
		.mfm_wr_mark(mfm_wr_mark),

		.mfm_wr_stb(mfm_wr_stb && !ism_devsel_ext),
		.mfm_wr_anchor(ism_anchor_sector),
		.mfm_wr_anchor_ok(ism_anchor_ok),
		.mfm_mark(mfm_mark_int),
		.mfm_crc0(mfm_crc0_int),
		.mfm_stb(mfm_stb_int),

		.dbg_byte_cnt(dbg_flp_byte_cnt),
		.dbg_miss_cnt(dbg_flp_miss_cnt),
		.dbg_disk_image_data(dbg_flp_disk_data),
		.dbg_drive_track(dbg_flp_track),
		.dbg_drive_side(dbg_flp_side),
		.dbg_step_cnt(dbg_flp_step_cnt),
		.dbg_byte_stb(dbg_flp_byte_stb),
		.dbg_raw_byte(dbg_flp_raw),
		.dbg_gcr_addr(dbg_flp_gcr_addr),
		.dbg_strb_cnt(dbg_flp_strb_cnt),
		.dbg_strb_en_cnt(dbg_flp_strb_en_cnt),
		.dbg_strb_last(dbg_flp_strb_last),
		.dbg_rej_step(dbg_flp_rej_step),
		.dbg_status(dbg_flp_status),
		.dbg_media(dbg_flp_media),
		.dbg_mfm_stall_us(dbg_mfm_stall[23:8]),
		.dbg_mfm_stall_cnt(dbg_mfm_stall[7:0])
	);

	floppy #(.WRITE_SUPPORT(0)) floppyExt
	(
		.clk(clk),
		.cep(cep),
		.cen(cen),

		._reset(_reset),
		.ca0(ca0),
		.ca1(ca1),
		.ca2(ca2),
		.SEL(effSEL),
		.lstrb(lstrb),
		._enable(ism_mode ? ~ism_selonly_ext : ~diskEnableExt),
		.writeData(dataInLo),
		.writeReq(writeReqExt),

		.writeMode(1'b0),
		.writeProtect(writeProtect[1]),
		.writeBusy(writeBusyExt),
		.writeUnderrun(writeUnderrunExt),
		.wrSecValid(),
		.wrSecNum(),
		.wrSecAddr(),
		.wrSdAddr(),
		.wrSdData(),
		.wrSdReq(),
		.wrSdAck(1'b0),
		.wrCommitDone(),
		.wrCommitAddr(),
		.wrSdBufAddr(),
		.wrSdBufData(),
		.wrSdBufWr(),
		.readData(readDataExt),
		.advanceDriveHead(advanceDriveHead),
		.newByteReady(newByteReadyExt),
		.insertDisk(insertDisk[1]),
		.diskSides(diskSides[1]),
		.mediaSides(mediaSides[1]),
		.diskEject(diskEject[1]),

		.motor(diskMotor[1]),
		.act(diskAct[1]),

		.dskReadAddr(dskReadAddrExt),
		.dskReadAck(dskReadAckExt),
		.dskReadData(dskReadData),
		.ism_active(ism_mode),
		.ism_action(ism_mode && ism_mode_reg[3]),
		.ism_sel(ism_devsel_ext),
		.mfm_disk(diskMFM[1]),
		.mfm_hd(diskHD[1]),
		.mfm_byte(mfm_byte_ext),
		.mfm_sector(mfm_sector_ext),

		.mfm_wr_byte(8'h00),
		.mfm_wr_mark(1'b0),
		.mfm_wr_stb(1'b0),
		.mfm_wr_anchor(5'd1),
		.mfm_wr_anchor_ok(1'b0),
		.mfm_mark(mfm_mark_ext),
		.mfm_crc0(mfm_crc0_ext),
		.mfm_stb(mfm_stb_ext)
	);

	wire [7:0] readData = selectExternalDrive ? readDataExt : readDataInt;
	wire newByteReady = selectExternalDrive ? newByteReadyExt : newByteReadyInt;

	wire [7:0] mfm_byte_sel = ism_devsel_ext ? mfm_byte_ext : mfm_byte_int;
	wire mfm_mark_sel = ism_devsel_ext ? mfm_mark_ext : mfm_mark_int;
	wire mfm_crc0_sel = ism_devsel_ext ? mfm_crc0_ext : mfm_crc0_int;
	wire mfm_stb_sel  = ism_devsel_ext ? mfm_stb_ext  : mfm_stb_int;
	wire [4:0] mfm_sector_sel = ism_devsel_ext ? mfm_sector_ext : mfm_sector_int;
	wire ism_sense    = ism_devsel_ext ? senseExt : senseInt;

	wire ism_arm = ism_mode && ism_mode_reg[3] && !ism_mode_reg[4];

	wire ism_read_active = ism_arm && !ism_setup[2];

	wire ism_write_arm    = ism_mode && ism_mode_reg[3] && ism_mode_reg[4];
	wire ism_write_active = ism_write_arm && !ism_setup[6];
	assign mfm_wr_active  = ism_write_active;

	reg  ism_wr_stb_d;
	always @(posedge clk) ism_wr_stb_d <= mfm_stb_sel;

	wire ism_sel_mfm = ism_devsel_ext ? diskMFM[1] : diskMFM[0];
	wire ism_void    = ism_write_active && !ism_sel_mfm;
	reg  [8:0] ism_void_timer;
	reg        ism_void_tick;
	always @(posedge clk) begin
		ism_void_tick <= 1'b0;
		if (!ism_void)
			ism_void_timer <= WR_VOID_PERIOD;
		else if (cep) begin
			if (ism_void_timer != 9'd0)
				ism_void_timer <= ism_void_timer - 9'd1;
			else begin
				ism_void_timer <= WR_VOID_PERIOD;
				ism_void_tick  <= 1'b1;
			end
		end
	end
	wire ism_wr_tick = ism_write_active &&
	                   ((mfm_stb_sel && !ism_wr_stb_d) || ism_void_tick);

	wire        ism_wr_pop;
	wire        ism_wr_underrun;

	reg  ism_wr_pop_p, ism_wr_unr_p;
	always @(posedge clk) begin
		ism_wr_pop_p <= cen ? 1'b0 : (ism_wr_pop_p | ism_wr_pop);
		ism_wr_unr_p <= cen ? 1'b0 : (ism_wr_unr_p | ism_wr_underrun);
	end
	wire ism_wr_pop_now = ism_wr_pop      | ism_wr_pop_p;
	wire ism_wr_unr_now = ism_wr_underrun | ism_wr_unr_p;
	ism_write_engine ism_wr (
		.clk(clk), .rst(~_reset),
		.active(ism_write_active),
		.tick(ism_wr_tick),
		.q_word(ism_fifo[0]),
		.q_empty(ism_fifo_pos == 2'd0),
		.q_pop(ism_wr_pop),
		.o_byte(mfm_wr_byte), .o_mark(mfm_wr_mark), .o_stb(mfm_wr_stb),
		.underrun(ism_wr_underrun)
	);

	always @(posedge clk) begin
		dbg_err_d <= ism_error;
		dbg_ra_d  <= ism_read_active;
		if (~dbg_err_d[0] & ism_error[0] & (dbg_flpe_ovr != 8'hFF)) dbg_flpe_ovr <= dbg_flpe_ovr + 1'd1;
		if (~dbg_err_d[2] & ism_error[2] & (dbg_flpe_unr != 8'hFF)) dbg_flpe_unr <= dbg_flpe_unr + 1'd1;
		if (~dbg_ra_d  & ism_read_active & (dbg_flpe_arm != 8'hFF)) dbg_flpe_arm <= dbg_flpe_arm + 1'd1;
	end
	assign dbg_ism_flpe = {5'b0, ism_error, dbg_flpe_arm, dbg_flpe_ovr, dbg_flpe_unr};

	wire hs_read_now = acc_end && ism_mode && acc_rw_l && (acc_addr_l[2:0] == 3'h7);

	wire hs_poison_now = (ism_fifo_pos == 2'd2) &&
	                      ism_fifo[0][FIFO_B_CRC0] &&
	                     ~ism_fifo[1][FIFO_B_CRC0];
	reg [15:0] dbg_hs_b1 = 0, dbg_hs_b5 = 0;
	always @(posedge clk) begin
		if (cen) begin
			if (hs_read_now && hs_poison_now && dbg_hs_b1 != 16'hFFFF)
				dbg_hs_b1 <= dbg_hs_b1 + 1'd1;
			if (hs_read_now && (ism_error != 0) && dbg_hs_b5 != 16'hFFFF)
				dbg_hs_b5 <= dbg_hs_b5 + 1'd1;
		end
	end
	assign dbg_ism_verdict = {dbg_hs_b1, dbg_hs_b5};

	wire unr_pop_now  = ism_pop_req  && (ism_fifo_pos == 2'd0);
	wire unr_push_now = ism_cpu_push && (ism_fifo_pos == 2'd2);
	reg [31:0] dbg_unr_latch = 32'd0;
	always @(posedge clk) begin
		if (cen && (unr_pop_now || unr_push_now)) begin
			if (dbg_unr_latch[31:28] == 4'd0)
				dbg_unr_latch[27:0] <= {unr_push_now, ism_arm, mfm_synced,
				                        ism_stage_cnt[4], ism_mode_reg,
				                        acc_addr_l, ism_stage_cnt[3:0],
				                        ism_fifo_pos, 6'b0};
			if (dbg_unr_latch[31:28] != 4'hF)
				dbg_unr_latch[31:28] <= dbg_unr_latch[31:28] + 1'd1;
		end
	end
	assign dbg_ism_unrlatch = dbg_unr_latch;

	reg [1:0]  scw_mark_run;
	reg [2:0]  scw_phase;
	reg [6:0]  scw_fbrun;
	reg [7:0]  scw_run;
	reg [1:0]  scw_par;
	reg [7:0]  scw_hunt_ms;
	reg [13:0] scw_gap_us;
	reg [2:0]  scw_pre_us;
	reg [9:0]  scw_pre_ms;
	always @(posedge clk or negedge _reset) begin
		if (!_reset) begin
			scw_mark_run <= 2'd0; scw_phase <= 3'd0; scw_fbrun <= 7'd0;
			scw_run <= 8'd0;      scw_par <= 2'd0;
			scw_hunt_ms <= 8'd0;  scw_gap_us <= 14'd0;
			scw_pre_us <= 3'd0;   scw_pre_ms <= 10'd0;
		end
		else if (cen) begin
			scw_pre_us <= scw_pre_us + 3'd1;

			if (ism_arm && !ism_arm_d) begin
				scw_hunt_ms <= 8'd0;
				scw_pre_ms  <= 10'd0;
			end
			else if (ism_arm && scw_pre_us == 3'd7) begin
				scw_pre_ms <= scw_pre_ms + 10'd1;
				if (scw_pre_ms == 10'd1023 && scw_hunt_ms != 8'hFF)
					scw_hunt_ms <= scw_hunt_ms + 8'd1;
			end

			if (ism_gen_push)
				scw_gap_us <= 14'd0;
			else if (ism_arm && mfm_synced && scw_pre_us == 3'd7 &&
			         scw_gap_us != 14'h3FFF)
				scw_gap_us <= scw_gap_us + 14'd1;

			if (ism_gen_push) begin
				if (mfm_mark_sel && mfm_byte_sel == 8'hA1) begin
					if (scw_mark_run != 2'd3) scw_mark_run <= scw_mark_run + 2'd1;
					scw_phase <= 3'd0;
					scw_fbrun <= 7'd0;
				end
				else begin
					if (scw_mark_run == 2'd3 && mfm_byte_sel == 8'hFE) begin
						scw_phase <= 3'd1;
						scw_fbrun <= 7'd0;
						if (scw_run != 8'hFF) scw_run <= scw_run + 8'd1;
					end
					else if (scw_mark_run == 2'd3 && mfm_byte_sel == 8'hFB) begin
						scw_fbrun <= 7'd1;
					end
					else begin
						if (scw_phase != 3'd0) begin
							if (scw_phase == 3'd3)
								scw_par <= scw_par |
								           {mfm_byte_sel[0], ~mfm_byte_sel[0]};
							scw_phase <= (scw_phase == 3'd4) ? 3'd0
							                                 : scw_phase + 3'd1;
						end
						if (scw_fbrun != 7'd0) begin
							if (scw_fbrun == 7'd64) begin
								scw_run   <= 8'd0;
								scw_par   <= 2'd0;
								scw_fbrun <= 7'd0;
							end else
								scw_fbrun <= scw_fbrun + 7'd1;
						end
					end
					scw_mark_run <= 2'd0;
				end
			end
		end
	end
	assign dbg_ism_scan = {scw_run, scw_hunt_ms, scw_par, scw_gap_us};
	assign dbg_ism_state = {ism_mode_reg, ism_setup, 8'b0,
	                        diskEnableInt, driveSel, ism_devsel_int, ism_devsel_ext,
	                        ism_selonly_int, ism_mode, diskEnableExt, 1'b0};

	wire ism_pop_req  = acc_end && ism_mode && acc_rw_l && ism_mode_reg[3] &&
	                    (acc_addr_l[2:0] == 3'h0 || acc_addr_l[2:0] == 3'h1);
	wire ism_cpu_push = acc_end && ism_mode && !acc_rw_l &&
	                    (acc_addr_l[2:0] == 3'h0 || acc_addr_l[2:0] == 3'h1 ||
	                     acc_addr_l[2:0] == 3'h2);
	wire ism_gen_push = ism_read_active && mfm_stb_sel &&
	                    (mfm_synced || mfm_mark_sel);
	wire [15:0] ism_gen_word = {mfm_sector_sel, mfm_crc0_sel, 1'b0, mfm_mark_sel, mfm_byte_sel};

	wire stage_push  = ism_gen_push && (ism_stage_cnt != 5'd16);

	wire stage_drain = (ism_stage_cnt != 5'd0) && (ism_fifo_pos < 2'd2) &&
	                   !acc_end && !ism_write_arm;
	wire [15:0] ism_cpu_word = (acc_addr_l[2:0] == 3'h2) ? 16'h0200 :
	                           (acc_addr_l[2:0] == 3'h1) ? {7'b0, 1'b1, acc_data_l} :
	                                                       {8'b0, acc_data_l};

`ifdef SIMULATION
	reg [7:0]  dbg_arm_cnt = 0;
	reg [15:0] dbg_pop_cnt = 0;
	reg [15:0] dbg_hs_cnt = 0;
	reg [7:0]  dbg_hs_last = 0;
	reg [15:0] dbg_hs_rpt = 0;
	reg [15:0] dbg_mode_cnt = 0;
	reg [7:0]  dbg_err_cnt = 0;

	wire [7:0] dbg_hs_now = {
		ism_mode_reg[4] ? (ism_fifo_pos <= 1) : (ism_fifo_pos != 0),
		ism_mode_reg[4] ? (ism_fifo_pos == 0) : (ism_fifo_pos == 2),
		(ism_error != 0),
		1'b0,
		ism_sense,
		1'b0,
		(ism_fifo_pos != 0) && ~ism_fifo[(ism_fifo_pos == 2'd2) ? 1 : 0][FIFO_B_CRC0],
		(ism_fifo_pos != 0) &&  ism_fifo[(ism_fifo_pos == 2'd2) ? 1 : 0][FIFO_B_MARK]};
`endif

	reg [4:0] iwmMode;

	wire [2:0] ism_reg_addr = cpuAddrRegHi[2:0];

	always @(*) begin
		ca0Next <= ca0;
		ca1Next <= ca1;
		ca2Next <= ca2;
		lstrbNext <= lstrb;
		diskEnableExtNext <= diskEnableExt;
		diskEnableIntNext <= diskEnableInt;
		selectExternalDriveNext <= selectExternalDrive;
		q6Next <= q6;
		q7Next <= q7;

		if (!ism_mode && selectSWIM == 1'b1 && _cpuLDS == 1'b0) begin
			case (cpuAddrRegHi[3:1])
				3'h0:
					ca0Next <= cpuAddrRegHi[0];
				3'h1:
					ca1Next <= cpuAddrRegHi[0];
				3'h2:
					ca2Next <= cpuAddrRegHi[0];
				3'h3:
					lstrbNext <= cpuAddrRegHi[0];
				3'h4:
					if (selectExternalDrive)
						diskEnableExtNext <= cpuAddrRegHi[0];
					else
						diskEnableIntNext <= cpuAddrRegHi[0];
				3'h5:
					selectExternalDriveNext <= cpuAddrRegHi[0];
				3'h6:
					q6Next <= cpuAddrRegHi[0];
				3'h7:
					q7Next <= cpuAddrRegHi[0];
			endcase
		end
	end

	always @(*) begin
		dataOutLo = 8'hEF;

		if (ism_mode) begin

			case (ism_reg_addr)

				3'h0, 3'h1:
					dataOutLo = (!ism_mode_reg[3] || ism_fifo_pos == 0)
					            ? 8'hFF : ism_fifo[0][7:0];
				3'h2:
					dataOutLo = ism_error;
				3'h3:
					dataOutLo = ism_param[ism_param_idx];
				3'h4:

					dataOutLo = {ism_phase_oe, lstrb, ca2, ca1, ca0};
				3'h5:
					dataOutLo = ism_setup;
				3'h6:
					dataOutLo = ism_mode_reg;

				3'h7:
					dataOutLo = {
						ism_mode_reg[4] ? (ism_fifo_pos <= 1) : (ism_fifo_pos != 0),
						ism_mode_reg[4] ? (ism_fifo_pos == 0) : (ism_fifo_pos == 2),
						(ism_error != 0),
						1'b0,
						ism_sense,
						1'b0,
						(ism_fifo_pos != 0) && ~ism_fifo[(ism_fifo_pos == 2'd2) ? 1 : 0][FIFO_B_CRC0],
						(ism_fifo_pos != 0) &&  ism_fifo[(ism_fifo_pos == 2'd2) ? 1 : 0][FIFO_B_MARK]};
			endcase
		end
		else begin

			case ({q7Next,q6Next})
				2'b00:

					dataOutLo <= (diskEnableExt | diskEnableInt) ? readDataLatch : 8'hFF;
				2'b01:

					dataOutLo <= { (selectExternalDriveNext ? senseExt : senseInt), 1'b0, diskEnableExt | diskEnableInt, iwmMode };
				2'b10:
					dataOutLo <= { _iwmBusy, _writeUnderrun, 6'b000000 };
				2'b11:
					dataOutLo <= 0;
			endcase
		end
	end

	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			iwmMode <= 0;
			ism_mode <= 0;
			ism_mode_reg <= 0;
			ism_setup <= 0;
			ism_error <= 0;
			ism_param_idx <= 0;
			ism_fifo_pos <= 0;
			ism_stage_rd <= 0; ism_stage_wr <= 0; ism_stage_cnt <= 0;
			iwm_to_ism_counter <= 0;
			ism_fifo[0] <= 0;
			ism_fifo[1] <= 0;
			ism_anchor_sector <= 5'd1;
			ism_anchor_ok     <= 1'b0;
			ism_write_arm_d   <= 1'b0;

			ca0 <= 0;
			ca1 <= 0;
			ca2 <= 0;
			lstrb <= 0;
			diskEnableExt <= 0;
			diskEnableInt <= 0;
			selectExternalDrive <= 0;
			q6 <= 0;
			q7 <= 0;
			swim_acc_d <= 1'b0;
			acc_addr_l <= 4'h0;
			acc_rw_l <= 1'b1;
			acc_data_l <= 8'h00;
			ism_phase_oe <= 4'h0;
			mfm_synced <= 1'b0;
			ism_arm_d <= 1'b0;
		end
		else if(cen) begin

			ca0 <= ca0Next;
			ca1 <= ca1Next;
			ca2 <= ca2Next;
			lstrb <= lstrbNext;
			diskEnableExt <= diskEnableExtNext;
			diskEnableInt <= diskEnableIntNext;
			selectExternalDrive <= selectExternalDriveNext;
			q6 <= q6Next;
			q7 <= q7Next;

			if (_cpuRW == 0 && selectSWIM == 1'b1 && _cpuLDS == 1'b0 && !ism_mode) begin
				if ({q7Next,q6Next} == 2'b11) begin

					if (!(diskEnableExt | diskEnableInt))
						iwmMode <= dataInLo[4:0];
				end
			end

			swim_acc_d <= swim_acc;
			if (swim_acc) begin
				acc_addr_l <= cpuAddrRegHi;
				acc_rw_l   <= _cpuRW;
				acc_data_l <= dataInLo;

				if (!ism_mode && cpuAddrRegHi != 4'hF) iwm_to_ism_counter <= 0;
			end

			if (ism_wr_unr_now) begin
				if (ism_error == 8'd0) ism_error[0] <= 1'b1;
				ism_mode_reg[3] <= 1'b0;
			end

			ism_stage_cnt <= ism_stage_cnt + {4'd0, stage_push} - {4'd0, stage_drain};
			if (stage_push) begin
				ism_stage[ism_stage_wr] <= ism_gen_word;
				ism_stage_wr <= ism_stage_wr + 4'd1;
			end
			if (ism_gen_push && ism_stage_cnt == 5'd16)
				ism_error[0] <= 1'b1;

			if (stage_drain) begin
				ism_fifo[ism_fifo_pos[0]] <= ism_stage[ism_stage_rd];
				ism_fifo_pos <= ism_fifo_pos + 2'd1;
				ism_stage_rd <= ism_stage_rd + 4'd1;
			end

			if (ism_pop_req) begin
				if (ism_fifo_pos != 0) begin
					ism_fifo[0]  <= ism_fifo[1];
					ism_fifo_pos <= ism_fifo_pos - 2'd1;

					ism_anchor_sector <= ism_fifo[0][15:11];
					ism_anchor_ok     <= 1'b1;
					if (acc_addr_l[2:0] == 3'h0 && ism_fifo[0][FIFO_B_MARK]) ism_error[1] <= 1'b1;
				end else
					ism_error[2] <= 1'b1;
			end
			else if (ism_wr_pop_now && ism_cpu_push) begin

				ism_fifo[0] <= ism_fifo[1];
				ism_fifo[ism_fifo_pos - 2'd1] <= ism_cpu_word;
			end
			else if (ism_wr_pop_now) begin
				ism_fifo[0]  <= ism_fifo[1];
				ism_fifo_pos <= ism_fifo_pos - 2'd1;
			end
			else if (ism_cpu_push) begin
				if (ism_fifo_pos < 2'd2) begin
					ism_fifo[ism_fifo_pos[0]] <= ism_cpu_word;
					ism_fifo_pos <= ism_fifo_pos + 2'd1;
				end else
					ism_error[2] <= 1'b1;
			end

			if (ism_read_active && mfm_stb_sel && !mfm_synced && mfm_mark_sel)
				mfm_synced <= 1'b1;

			if (acc_end && ism_mode) begin
				if (!acc_rw_l) begin
					case (acc_addr_l[2:0])

						3'h3: begin
							ism_param[ism_param_idx] <= acc_data_l;
							ism_param_idx <= ism_param_idx + 1'b1;
						end
						3'h4: begin

							ca0   <= acc_data_l[0];
							ca1   <= acc_data_l[1];
							ca2   <= acc_data_l[2];
							lstrb <= acc_data_l[3];
							ism_phase_oe <= acc_data_l[7:4];
						end
						3'h5:
							ism_setup <= acc_data_l;
						3'h6: begin
							ism_mode_reg  <= ism_mode_reg & ~acc_data_l;
							ism_param_idx <= 0;
							if (acc_data_l[6]) begin
								ism_mode <= 0;
								iwm_to_ism_counter <= 0;
`ifdef SIMULATION
								$display("SWIM: ISM -> IWM (ModeClr %02x) @%0t", acc_data_l, $time);
`endif
							end
							if ((ism_mode_reg & ~acc_data_l) & 8'h01) begin
								ism_fifo_pos <= 0;
								ism_stage_rd <= 0; ism_stage_wr <= 0; ism_stage_cnt <= 0;
							end
						end
						3'h7: begin
							ism_mode_reg <= ism_mode_reg | acc_data_l;
							if ((ism_mode_reg | acc_data_l) & 8'h01) begin
								ism_fifo_pos <= 0;
								ism_stage_rd <= 0; ism_stage_wr <= 0; ism_stage_cnt <= 0;
							end
						end
						default: ;
					endcase
				end
				else begin

					if (acc_addr_l[2:0] == 3'h2) ism_error <= 0;
					if (acc_addr_l[2:0] == 3'h3) ism_param_idx <= ism_param_idx + 1'b1;
				end
			end

			if (acc_end && !ism_mode) begin
				if (acc_addr_l == 4'hF) begin
					if (acc_rw_l ? 1'b0 : acc_data_l[6]) begin
						case (iwm_to_ism_counter)
							2'd0: iwm_to_ism_counter <= 2'd1;
							2'd1: iwm_to_ism_counter <= 2'd0;
							2'd2: iwm_to_ism_counter <= 2'd3;
							2'd3: begin
								ism_mode      <= 1;
								ism_mode_reg  <= 8'h40;
								ism_error     <= 0;
								ism_fifo_pos  <= 0;
								ism_param_idx <= 0;
								mfm_synced    <= 1'b0;
								iwm_to_ism_counter <= 0;
`ifdef SIMULATION
								$display("SWIM: switched to ISM mode @%0t", $time);
`endif
							end
						endcase
					end else
						iwm_to_ism_counter <= (iwm_to_ism_counter == 2'd1) ? 2'd2 : 2'd0;
				end
				else
					iwm_to_ism_counter <= 0;
			end

			ism_arm_d <= ism_arm;

			if (ism_arm && !ism_arm_d) ism_anchor_ok <= 1'b0;

			ism_write_arm_d <= ism_write_arm;
			if (ism_write_arm && !ism_write_arm_d) begin
				ism_stage_rd  <= 4'd0;
				ism_stage_wr  <= 4'd0;
				ism_stage_cnt <= 5'd0;
			end
			if (ism_arm && !ism_arm_d) begin
				mfm_synced   <= 1'b0;
				ism_fifo_pos <= 0;
				ism_stage_rd <= 0; ism_stage_wr <= 0; ism_stage_cnt <= 0;
			end

`ifdef SIMULATION
			if (ism_arm && !ism_arm_d && dbg_arm_cnt < 8'd80) begin
				dbg_arm_cnt <= dbg_arm_cnt + 1'd1;
				$display("SWIM-ISM: read ARM mode=%02x setup=%02x dev={e%b,i%b} @%0t",
				         ism_mode_reg, ism_setup, ism_devsel_ext, ism_devsel_int, $time);
			end
			if (ism_read_active && mfm_stb_sel && !mfm_synced && mfm_mark_sel && dbg_arm_cnt < 8'd80)
				$display("SWIM-ISM: mark-sync @%0t", $time);
			if (ism_pop_req && ism_fifo_pos != 0 && dbg_pop_cnt < 16'd4000) begin
				dbg_pop_cnt <= dbg_pop_cnt + 1'd1;
				$display("SWIM-ISM: pop %02x m=%b c0=%b pos=%0d",
				         ism_fifo[0][7:0], ism_fifo[0][FIFO_B_MARK], ism_fifo[0][FIFO_B_CRC0], ism_fifo_pos);
			end
			if (ism_pop_req && ism_fifo_pos == 0 && dbg_err_cnt < 8'd60) begin
				dbg_err_cnt <= dbg_err_cnt + 1'd1;
				$display("SWIM-ISM: POP-EMPTY (underrun) @%0t", $time);
			end
			if (acc_end && ism_mode && acc_rw_l && acc_addr_l[2:0] == 3'h4)
				$display("SWIM-ISM: phases rd -> %02x", {ism_phase_oe, lstrb, ca2, ca1, ca0});

			if (acc_end && ism_mode && acc_rw_l && acc_addr_l[2:0] == 3'h7) begin
				if (dbg_hs_now != dbg_hs_last) begin
					if (dbg_hs_cnt < 16'd20000) begin
						dbg_hs_cnt <= dbg_hs_cnt + 1'd1;
						$display("SWIM-ISM: HS %02x (x%0d) -> %02x pos=%0d @%0t",
						         dbg_hs_last, dbg_hs_rpt, dbg_hs_now, ism_fifo_pos, $time);
					end
					dbg_hs_last <= dbg_hs_now;
					dbg_hs_rpt  <= 16'd1;
				end else if (dbg_hs_rpt != 16'hFFFF)
					dbg_hs_rpt <= dbg_hs_rpt + 1'd1;
			end

			if (acc_end && ism_mode && !acc_rw_l &&
			    (acc_addr_l[2:0] == 3'h6 || acc_addr_l[2:0] == 3'h7) && dbg_mode_cnt < 16'd1200) begin
				dbg_mode_cnt <= dbg_mode_cnt + 1'd1;
				$display("SWIM-ISM: Mode%s %02x -> mode=%02x @%0t",
				         (acc_addr_l[2:0] == 3'h6) ? "Clr" : "Set", acc_data_l,
				         (acc_addr_l[2:0] == 3'h6) ? (ism_mode_reg & ~acc_data_l)
				                                   : (ism_mode_reg | acc_data_l), $time);
			end
			if (acc_end && ism_mode && !acc_rw_l && acc_addr_l[2:0] == 3'h5)
				$display("SWIM-ISM: Setup <= %02x @%0t", acc_data_l, $time);
			if (acc_end && ism_mode && acc_rw_l && acc_addr_l[2:0] == 3'h2 && ism_error != 0 && dbg_err_cnt < 8'd60) begin
				dbg_err_cnt <= dbg_err_cnt + 1'd1;
				$display("SWIM-ISM: Error rd -> %02x (cleared) @%0t", ism_error, $time);
			end
`endif
		end
	end

	wire iwmRead = (_cpuRW == 1'b1 && selectSWIM == 1'b1 && _cpuLDS == 1'b0 && !ism_mode);

	reg  iwmRead_d = 1'b0;
	always @(posedge clk) if (cen) iwmRead_d <= iwmRead;
	wire iwmReadEnd = iwmRead_d && !iwmRead;
	wire anyDiskEnable = diskEnableExt | diskEnableInt;
	reg [3:0] readLatchClearTimer;
	reg [11:0] readDataArmDelay;
	reg anyDiskEnableD;
	wire readDataArmed = (readDataArmDelay == 12'd0);
	always @(posedge clk or negedge _reset) begin
		if (_reset == 1'b0) begin
			readDataLatch <= 0;
			readLatchClearTimer <= 0;
			readDataArmDelay <= 0;
			anyDiskEnableD <= 0;
		end
		else if(cen) begin
			anyDiskEnableD <= anyDiskEnable;

			if (readDataArmDelay != 0) begin
				readDataArmDelay <= readDataArmDelay - 1'b1;
			end

			if (readLatchClearTimer != 0) begin
				readLatchClearTimer <= readLatchClearTimer - 1'b1;
			end

			if (anyDiskEnable && !anyDiskEnableD) begin
				readDataLatch <= 0;
				readLatchClearTimer <= 0;
				readDataArmDelay <= 12'h400;
			end

			else if (iwmRead && readDataLatch[7]) begin
				readLatchClearTimer <= 4'hD;
			end

			if (anyDiskEnable && readDataArmed && newByteReady) begin
				readDataLatch <= readData;
			end
			else if (readLatchClearTimer == 1'b1) begin
				readDataLatch <= 0;
			end
		end
	end
	assign advanceDriveHead = readLatchClearTimer == 1'b1;
endmodule

module ism_write_engine (
	input             clk,
	input             rst,

	input             active,
	input             tick,

	input      [15:0] q_word,
	input             q_empty,
	output            q_pop,

	output reg  [7:0] o_byte,
	output reg        o_mark,
	output reg        o_stb,

	output reg        underrun
);

	localparam Q_B_MARK = 8;
	localparam Q_B_CRC  = 9;
	localparam [15:0] CRC_SEED = 16'hCDB4;

	function [15:0] crc16;
		input [15:0] c;
		input  [7:0] d;
		integer i;
		reg [15:0] cc;
		begin
			cc = c ^ {d, 8'h00};
			for (i = 0; i < 8; i = i + 1)
				cc = cc[15] ? ((cc << 1) ^ 16'h1021) : (cc << 1);
			crc16 = cc;
		end
	endfunction

	reg [15:0] crc;
	reg        crc_2nd;

	reg q_pop_r;
	assign q_pop = q_pop_r;
	wire consume = active && tick && !crc_2nd && !q_empty;

	always @(posedge clk) begin
		o_stb    <= 1'b0;
		underrun <= 1'b0;
		q_pop_r  <= consume;

		if (rst) begin
			q_pop_r <= 1'b0;
			crc     <= CRC_SEED;
			crc_2nd <= 1'b0;
			o_byte  <= 8'h00;
			o_mark  <= 1'b0;
		end else if (!active) begin

			crc     <= CRC_SEED;
			crc_2nd <= 1'b0;
		end else if (tick) begin
			if (crc_2nd) begin

				o_byte  <= crc[15:8];
				o_mark  <= 1'b0;
				o_stb   <= 1'b1;
				crc     <= crc16(crc, crc[15:8]);
				crc_2nd <= 1'b0;
			end else if (q_empty) begin

				underrun <= 1'b1;
			end else if (q_word[Q_B_CRC]) begin
				o_byte  <= crc[15:8];
				o_mark  <= 1'b0;
				o_stb   <= 1'b1;
				crc     <= crc16(crc, crc[15:8]);
				crc_2nd <= 1'b1;
			end else if (q_word[Q_B_MARK]) begin
				o_byte <= q_word[7:0];
				o_mark <= 1'b1;
				o_stb  <= 1'b1;
				crc    <= CRC_SEED;
			end else begin
				o_byte <= q_word[7:0];
				o_mark <= 1'b0;
				o_stb  <= 1'b1;
				crc    <= crc16(crc, q_word[7:0]);
			end
		end
	end

endmodule
