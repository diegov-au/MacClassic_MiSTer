//============================================================================
//  Macintosh Plus
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0; 
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_USER  = dio_download || ldr_int_busy || ldr_ext_busy || wr_int_busy || wr_ext_busy || (disk_act ^ |diskMotor);
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire [1:0] ar = status[8:7];
// M4: Resolution, 0 = Original 512x342, 1 = 640x480. Latched at reset like
// Memory (below): the ROM patch, the VRAM map and the video timer all switch
// together.
reg        status_res640 = 0;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),

	// Original: 512:342 square pixels; 640x480 mode (M4): 4:3.
	.ARX((!ar) ? (status_res640 ? 12'd4 : 12'd256) : (ar - 1'd1)),
	.ARY((!ar) ? (status_res640 ? 12'd3 : 12'd171) : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[12:11])
);

`include "build_id.v" 
localparam CONF_STR = {
	"MacClassic;UART115200;",
	"-;",
	"S2,DSK,Mount Floppy;",
	// Second entry, under the floppy it belongs to (user, 2026-09-30). Was
	// "O6,Floppy Write,Off,On" then "O6,Write Protect Floppy,On,Off". Same bit,
	// same default: 0 = On = protected. Covers GCR and MFM alike.
	"O6,Floppy Write Protect,On,Off;",
	// NOT A CLASSIC: second drive. The Classic has one internal drive.
	//"S3,DSK,Mount Sec Floppy;",
	"-;",
	// User, 2026-09-29: slot 0 = the internal hard disk (SCSI ID 0), slot 1 =
	// an external drive (ID 5). Were "Mount SCSI-6" / "Mount SCSI-5" (IDs 6, 5);
	// see ncr5380.sv. Main remembers mounts per slot, so existing mounts keep.
	// VHD only (user, 2026-10-02): "IMGVHD" put "*.IMG" after the label and
	// cut it off. A raw .img is the same format; rename it to .vhd.
	"SC0,VHD,Mount Internal HDD;",
	"SC1,VHD,Mount External SCSI;",
	// CD-ROM support removed by the user's decision, 2026-09-28: the "SC4 Mount
	// CD-ROM", "OI CD-ROM Drive" and "OFG CD Volume" entries (bits 15, 16, 18,
	// now free). The MacPlus core's CD target, rtl/cd_audio.sv and
	// rtl/cd_mix.v are in git history before this change.
	// PRAM (M2): the .nvr save image, the MacLC core's way ("SC2,NVR"). "SC":
	// Main remembers the mount (config/MacClassic.s3) and re-mounts it at every
	// core start, so after the first mount it loads with no user action;
	// rtl/pram_nvr.sv loads it and saves it back once the Mac's PRAM writes
	// settle, or at once from "Save PRAM" below. (Main auto-mounts only files
	// named boot0..3.vhd, so a .nvr needs this entry - user: .nvr, not .vhd.)
	"SC3,NVR,Mount PRAM;",
	"-;",
	// M4 (user, 2026-09-28): a larger 1-bit screen, not true to the Classic.
	// Applies at Reset, like Memory. Bit 19: never used by this core or the
	// MacPlus core (whose last option bit was 18), so no saved setting has it.
	"OJ,Resolution,Original,640x480;",
	// Bits 20-21 were the temporary "640x480 Speed" (build 20261002f, now fixed
	// at Low), "640x480 Mouse" (build 20261003) and "Original Mouse" (build
	// 20261003b); both mice now fixed at /2. Free.
	"O78,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OBC,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	// NOT A CLASSIC: model, speed and CPU options (bits 9, 5, 13-14).
	//"O9,Model,Plus,SE;",
	//"O5,Speed,8MHz,16MHz;",
	//"ODE,CPU,68000,68010,68020;",
	// (O6 Floppy Write Protect moved up under Mount Floppy, 2026-09-30.)
	// Bit 5 was Speed. 1 MB is the stock Classic; 2 and 4 MB are the
	// expansion card. Was "O4,Memory,1MB,4MB;".
	"O45,Memory,1MB,2MB,4MB;",
	// ROM-DISK INJECTOR (removed, user 2026-09-29): hold Command-Option-X-O
	// on the keyboard instead, as on a real Classic. Bit 9 is free.
	//"O9,Boot ROM disk,On,Off;",
	// "Save PRAM" hidden (user, 2026-09-30): PRAM auto-saves ~2 s after the
	// Mac's last PRAM write and on OSD open (confirmed on hardware, build i).
	// pram_nvr's save_req is tied off below. Bit 13 stays free.
	//"TD,Save PRAM;",
	"-;",
	//"OA,Serial,Off,On;",
	//"-;",
	// Was "R0,Reset & Apply Memory" (user, 2026-09-30: just "Reset"). Every reset
	// still applies the Memory setting: status_mem is latched during reset.
	"R0,Reset;",
	// v,1: option meanings changed from the MacPlus core, so saved settings reset.
	"v,1;", // [optional] config version 0-99.
	        // If CONF_STR options are changed in incompatible way, then change version number too,
			// so all options will get default values on first start.
	"V,v",`BUILD_DATE
};

// NOT A CLASSIC: 16 MHz turbo was status[5]; bit 5 is now Memory's high bit.
//wire status_turbo = status[5];
// M4 (user, 2026-10-02): the 640x480 mode runs the CPU at 16 MHz, so its 1.75x
// larger screen redraws as fast as Original's; no separate OSD entry. Original
// stays a Classic at 8 MHz. Harness at 16 MHz: System 6 HDD boot, a Finder copy
// with ~6 ms SD write latency (the BUG-012 case), Disk605 floppy boot and the
// 640x480 ROM-disk Finder all pass (STATUS 2026-10-02).
wire status_turbo = status_res640;

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_mem;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk_mem),
	.outclk_1(clk_sys),
	.locked(pll_locked)
);

reg [1:0] status_mem;   // 0 = 1MB, 1 = 2MB, 2 = 4MB (3 reads as 4MB)
// (status_res640, M4, is declared above video_freak, its first use.)
// NOT A CLASSIC: CPU and model selects.
//reg [1:0] status_cpu;
//reg       status_mod;
reg       n_reset = 0;
// PRAM (M2): hold the Mac until pram_nvr has the PRAM in (or knows there is
// none), and reset it once if a load lands after it started. The restart pulse
// is one clk_sys; this block samples on clk8_en_p, so it is latched until taken.
wire      pram_ready, pram_restart;
reg       pram_rst_req = 0;
// pram_nvr <-> rtc.v (via dataController_top); instantiated further down,
// declared here ahead of every use.
wire  [7:0] pram_ext_addr, pram_ext_wdata, pram_ext_q;
wire        pram_ext_we, pram_ext_ready, pram_wr;
wire        pram_sd_rd, pram_sd_wr;
reg         rom_loaded = 1'b0;   // boot0.rom has loaded (set below, at DOWNLOADING)
// ROM-DISK INJECTOR (removed 2026-09-29): reg romkeys_hold = 1'b0;
always @(posedge clk_sys) begin
	reg [15:0] rst_cnt;

	if (pram_restart) pram_rst_req <= 1'b1;

	if (clk8_en_p) begin
		// various sources can reset the mac
		// Held until boot0.rom AND the PRAM are in (user, 2026-10-03: as on
		// a real Classic, both are there at power-on). Only the hold: build
		// n's version also cleared WarmStart, forcing the RAM test.
		if(~pll_locked || status[0] || buttons[1] || RESET || ~_cpuReset_o || ~rom_loaded || ~pram_ready || pram_rst_req) begin
			pram_rst_req <= 1'b0;
			rst_cnt <= '1;
			n_reset <= 0;
			// Also during the hold, so a cold start's wait for the ROM and
			// PRAM already shows the 640x480 grey cover, not Original's view
			// of uninitialised RAM (user, 2026-10-04). The CPU is held.
			status_res640 <= status[19];
		end
		else if(rst_cnt) begin
			rst_cnt    <= rst_cnt - 1'd1;
			status_mem <= status[5:4];
			status_res640 <= status[19];
			//status_cpu <= status[14:13];   // NOT A CLASSIC
			//status_mod <= status[9];       // NOT A CLASSIC
		end
		else begin
			n_reset <= 1;
		end
	end
end

///////////////////////////////////////////////////

// SCSI targets: index 0/1 are the disks at IDs 6/5. No CD-ROM (removed
// 2026-09-28): SCSI_CD_DEV = SCSI_DEVS is ncr5380's "no CD target".
localparam SCSI_DEVS   = 2;
localparam SCSI_CD_DEV = SCSI_DEVS;
// VDNUM: slots 0/1 = SCSI disks, slot 2 = the floppy, slot 3 = the PRAM image
// (M2). Slot 3 was the second floppy's, which had no OSD entry (NOT A
// CLASSIC); its loader and writer are now tied off (ext_img_mounted below).
localparam VDNUM = 4;
localparam VD_PRAM = 3;

// the status register is controlled by the on screen display (OSD)
wire [31:0] status;
wire  [1:0] buttons;
wire [31:0] sd_lba[VDNUM];
wire  [VDNUM-1:0] sd_rd;
wire  [VDNUM-1:0] sd_wr;
wire  [VDNUM-1:0] sd_ack;
// 13 bits: hps_io drives [AW:0] with AW = WIDE ? 12 : 13. Every transfer is a
// 512-byte block = 256 words, so consumers slice [7:0] at their port.
wire           [12:0] sd_buff_addr;
wire           [15:0] sd_buff_dout;
wire           [15:0] sd_buff_din[VDNUM];
wire                  sd_buff_wr;
wire  [VDNUM-1:0] img_mounted;
wire           [63:0] img_size;
wire                  img_readonly;

// SCSI (dataController_top) sees slots 0/1 of the arrays above: its own
// narrower view, as each floppy_loader below gets scalar per-slot ports.
// SCSI device index = hps_io slot: 0 (disk, ID 6), 1 (disk, ID 5).
wire [31:0] scsi_sd_lba[SCSI_DEVS];
wire [15:0] scsi_sd_buff_din[SCSI_DEVS];
wire [SCSI_DEVS-1:0] scsi_sd_rd, scsi_sd_wr;
assign sd_lba[0] = scsi_sd_lba[0];
assign sd_lba[1] = scsi_sd_lba[1];
assign sd_buff_din[0] = scsi_sd_buff_din[0];
assign sd_buff_din[1] = scsi_sd_buff_din[1];

// sd_buff_din[2]/[3] driven below by each drive's floppy_sd_writer -
// only ever consulted by hps_io during a sd_wr session for that slot, which
// only the writer ever asserts, so no mux against the loader is needed here.

wire        ioctl_write;
reg         ioctl_wait = 0;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire        capslock;

wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;

wire [32:0] TIMESTAMP;
wire [64:0] RTC;        // BCD local time with DST; corrects TIMESTAMP in rtc.v

hps_io #(.CONF_STR(CONF_STR), .VDNUM(VDNUM), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ioctl_download(dio_download),
	.ioctl_index(dio_index),
	.ioctl_wr(ioctl_write),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.TIMESTAMP(TIMESTAMP),
	.RTC(RTC),

	.ps2_key(ps2_key),
	.ps2_kbd_led_use(3'b001),
	.ps2_kbd_led_status({2'b00, capslock}),

	.ps2_mouse(ps2_mouse)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1;

// M4: Mac grey from a reset until the ROM has drawn a 640x480 screen
// (vid_blank, set below the turbo DTACK block). Original is never covered.
// Grey, not black, so it does not look like a dead core (user, 2026-10-04):
// the one-pixel checkerboard of the ROM's start-up desktop, which then
// replaces it almost unchanged. One pixel per clk_sys (videoShifter.v); the
// pixel phase restarts on every line, so a line-parity flip gives the check.
reg  vid_blank = 1'b1;
reg  vid_px, vid_ln, vid_hb_d;
always @(posedge clk_sys) begin
	vid_hb_d <= _hblank;
	vid_px   <= _hblank ? ~vid_px : 1'b0;
	if (vid_hb_d & ~_hblank) vid_ln <= ~vid_ln;
	if (~_vblank) vid_ln <= 1'b0;
end
wire vid_pixel = (status_res640 & vid_blank) ? (vid_px ^ vid_ln) : pixelOut;
assign VGA_R  = {8{vid_pixel}};
assign VGA_G  = {8{vid_pixel}};
assign VGA_B  = {8{vid_pixel}};
// _hblank is visible for xpos 0-128 (videoTimer.v: the end is pushed out by
// kPixelLatency), but the shifter's first load of a line lands only at the
// end of xpos 0, so DE on _hblank alone gave 516 pixels with 4 black at the
// left. Starting DE one clk8 (4 clk_sys) later gives exactly the 512.
// Inherited from the MacPlus core; seen as the M0 harness's black strip.
reg [3:0] hblank_sr;
always @(posedge clk_sys) hblank_sr <= {hblank_sr[2:0], _hblank};
assign VGA_DE = _vblank & _hblank & hblank_sr[3];
assign VGA_VS = vsync;
assign VGA_HS = hsync;
assign VGA_F1 = 0;
assign VGA_SL = 0;

wire [10:0] audio;

// `audio` is SIGNED (audio_latch x volume, so +-127*7) and carries a +28,448
// pedestal while sound is DISABLED, deliberately (dataController_top.sv, PR #12
// / bug #7); MiSTer's own DC blocker strips it downstream. With the CD-ROM gone
// (2026-09-28) there is no second source to sum, so this is exactly the path
// rtl/cd_mix.v took with no disc mounted (its correction gain held at 0).
assign AUDIO_L = {audio[10:0], 5'b00000};
assign AUDIO_R = {audio[10:0], 5'b00000};
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;


// ------------------------------ Plus Too Bus Timing ---------------------------------
// for stability and maintainability reasons the whole timing has been simplyfied:
//                00           01             10           11
//    ______ _____________ _____________ _____________ _____________ ___
//    ______X_video_cycle_X__cpu_cycle__X__IO_cycle___X__cpu_cycle__X___
//                        ^      ^    ^                      ^    ^
//                        |      |    |                      |    |
//                      video    | CPU|                      | CPU|
//                       read   write read                  write read



// set the real-world inputs to sane defaults
localparam 	  configROMSize = 1'b1;  // 128K ROM

// addrController_top codes: 2'b10 = 1MB, 2'b01 = 2MB (was 512K), 2'b11 = 4MB.
// NOT A CLASSIC: was status_mem?2'b11:2'b10 (1MB/4MB).
wire [1:0] configRAMSize = status_mem == 2'd0 ? 2'b10 :
                           status_mem == 2'd1 ? 2'b01 : 2'b11;
			  
//
// Serial Ports
//
wire serialOut;
wire serialIn;
wire serialCTS;
wire serialRTS;

/*
assign serialIn = ~status[10] ? 0 : UART_RXD;
assign UART_TXD = serialOut;
assign serialCTS = UART_CTS;
assign UART_RTS = serialRTS;
assign UART_DTR = UART_DSR;
*/

//assign serialIn = ~status[10] ? 0 : UART_RXD;
assign serialIn =  UART_RXD;
assign UART_TXD = serialOut;
//assign UART_RTS = UART_CTS;
assign UART_RTS = serialRTS ;
assign UART_DTR = UART_DSR;

//assign {UART_RTS, UART_TXD, UART_DTR} = 0;
/*
	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,
*/


// interconnects
// CPU
wire clk8, _cpuReset, _cpuReset_o, _cpuUDS, _cpuLDS, _cpuRW, _cpuAS;
wire clk8_en_p, clk8_en_n;
wire clk16_en_p, clk16_en_n;
wire _cpuVMA, _cpuVPA, _cpuDTACK;
wire E_rising, E_falling;
wire [2:0] _cpuIPL;
wire [2:0] cpuFC;
wire [7:0] cpuAddrHi;
wire [23:0] cpuAddr;
wire [15:0] cpuDataOut;

// RAM/ROM
wire _romOE;
wire _ramOE, _ramWE;
wire _memoryUDS, _memoryLDS;
wire videoBusControl;
wire dioBusControl;
wire cpuBusControl;
wire [21:0] memoryAddr;
wire vramAccess;   // M4: VRAM cycle (640x480 mode), from addrController_top
wire [15:0] memoryDataOut;
wire memoryLatch;

// peripherals
wire vid_alt, loadPixels, pixelOut, _hblank, _vblank, hsync, vsync;
wire memoryOverlayOn, selectSCSI, selectSCC, selectIWM, selectVIA, selectRAM, selectROM, selectSEOverlay;
wire        scsi_bus_hold; // SCSI pseudo-DMA back-pressure, see ncr5380.sv
wire [15:0] dataControllerDataOut;

// audio
wire snd_alt;
wire loadSound;
wire snd_advance;

// floppy disk image interface
wire dskReadAckInt;
wire [21:0] dskReadAddrInt;
wire dskReadAckExt;
wire [21:0] dskReadAddrExt;

// floppy image loader (SD-mount -> SDRAM), shared extra-slot-3 port
wire [21:0] ldr_int_wr_addr, ldr_ext_wr_addr;
wire        ldr_int_wr_req,  ldr_ext_wr_req;
wire        ldr_int_wr_ack,  ldr_ext_wr_ack;
wire [15:0] ldr_int_wr_data, ldr_ext_wr_data;
wire        dskLoadWrEn;
wire        dskLoadSelExt;

// floppy write-back (IWM write path -> SDRAM), same shared
// extra-slot-3 port. Combined with the loader's own request below, since
// addrController_top.v's arbiter is only
// ever given ONE request/ack per side - loader and committer share that
// one slot per side with the loader given fixed priority.
wire [21:0] wc_int_wr_addr, wc_ext_wr_addr;
wire        wc_int_wr_req,  wc_ext_wr_req;
wire        wc_int_wr_ack,  wc_ext_wr_ack;
wire [15:0] wc_int_wr_data, wc_ext_wr_data;

// SD persistence tap: mirrors each committed sector so
// floppy_sd_writer can shadow it out to the mounted .dsk over sd_wr.
wire        wc_int_commit_done,   wc_ext_commit_done;
wire [21:0] wc_int_commit_addr,   wc_ext_commit_addr;
wire        wc_int_commit_buf_wr, wc_ext_commit_buf_wr;
wire [7:0]  wc_int_commit_buf_addr, wc_ext_commit_buf_addr;
wire [15:0] wc_int_commit_buf_data, wc_ext_commit_buf_data;

// per-side combined (loader-or-committer) request presented to
// addrController_top.v; loader wins whenever it is requesting, since a
// mount and a write-commit contending for the same side is only possible
// as a rare corner case, never a steady-state situation.
wire [21:0] slot3_int_addr = ldr_int_wr_req ? ldr_int_wr_addr : wc_int_wr_addr;
wire        slot3_int_req  = ldr_int_wr_req | wc_int_wr_req;
wire [15:0] slot3_int_data = ldr_int_wr_req ? ldr_int_wr_data : wc_int_wr_data;
wire        slot3_int_ack, slot3_int_ack_raw, slot3_ext_ack_raw;
// Never ack a write that a download cycle replaced (see addrController_top's
// instance): the request was sampled before the download began.
assign slot3_int_ack  = slot3_int_ack_raw & ~dio_download;
assign ldr_int_wr_ack = slot3_int_ack &  ldr_int_wr_req;
assign wc_int_wr_ack  = slot3_int_ack & ~ldr_int_wr_req;

wire [21:0] slot3_ext_addr = ldr_ext_wr_req ? ldr_ext_wr_addr : wc_ext_wr_addr;
wire        slot3_ext_req  = ldr_ext_wr_req | wc_ext_wr_req;
wire [15:0] slot3_ext_data = ldr_ext_wr_req ? ldr_ext_wr_data : wc_ext_wr_data;
wire        slot3_ext_ack;
assign slot3_ext_ack  = slot3_ext_ack_raw & ~dio_download;
assign ldr_ext_wr_ack = slot3_ext_ack &  ldr_ext_wr_req;
assign wc_ext_wr_ack  = slot3_ext_ack & ~ldr_ext_wr_req;

// OSD write-protect toggle (defaults to protected/status[6]=0), ANDed per
// drive with that drive's own latched img_readonly - see floppy_loader.v.
// M3: MFM (720K / 1.44 MB) images are writable too, under the same two terms
// (user, 2026-09-29); the MacLC core has MFM writes working on hardware.
wire wp_int = ~status[6] | ldr_int_readonly;
wire wp_ext = ~status[6] | ldr_ext_readonly;

// DTACK in turbo (the MacPlus core's, restored for the 640x480 mode, M4): a
// RAM/ROM access waits for the start of the CPU's own bus slot, since the CPU
// now runs twice as fast as the slots. Other devices answer at once, as at
// 8 MHz. The VRAM window ($54xxxx, 640x480 mode) is memory too, so it waits.
//
// Speed throttle (user, 2026-10-02: 16 MHz felt too quick). The clocks stay
// as they are (E exact); memory accesses may only take some of the CPU's bus
// slots, so the CPU waits more. Memory may use 5 of every 8 CPU slots: "Low"
// of the temporary High (8) / Medium (6) / Low (5) OSD entry of build f, the
// user's pick on hardware (2026-10-03). High was 16 MHz unthrottled, ~1.75x.
reg  turbo_dtack_en, cpuBusControl_d;
reg  [2:0] cpu_slot = 3'd0;
wire turbo_slot_ok = !(cpu_slot[0] & (cpu_slot[2:1] != 2'd0)); // 5 of 8
wire turbo_vram = status_res640 && cpuAddr[23:16] == 8'h54;
always @(posedge clk_sys) begin
	if (!_cpuReset) begin
		turbo_dtack_en <= 0;
	end
	else begin
		cpuBusControl_d <= cpuBusControl;
		if (!cpuBusControl_d & cpuBusControl) cpu_slot <= cpu_slot + 1'd1;
		if (_cpuAS) turbo_dtack_en <= 0;
		if (!_cpuAS & ((!cpuBusControl_d & cpuBusControl & turbo_slot_ok) | (!selectROM & !selectRAM & !turbo_vram))) turbo_dtack_en <= 1;
	end
end

// M4 start-up blanking (user, 2026-10-04). The 640x480 screen has its own
// memory, which the ROM's RAM test never touches, so from a reset until the
// ROM's first whole-screen fill the display showed the last session's final
// frame, or uninitialised SDRAM after a cold start. It stays grey until the
// CPU has made 16,384 bus writes to the VRAM window: a whole-screen fill is
// 19,200 (9,600 longs: the grey start-up desktop, or the Sad Mac's black fill
// at ROM $10A2). Original keeps the Classic's behaviour: its screen is in RAM,
// which the RAM test overwrites.
reg [14:0] vram_wr_cnt = 15'd0;
reg        vid_as_d;
always @(posedge clk_sys) begin
	vid_as_d <= _cpuAS;
	if (!n_reset) begin
		vid_blank   <= 1'b1;
		vram_wr_cnt <= 15'd0;
	end
	else if (vid_as_d && !_cpuAS && turbo_vram && !_cpuRW) begin
		if (vram_wr_cnt[14]) vid_blank <= 1'b0;
		else vram_wr_cnt <= vram_wr_cnt + 1'd1;
	end
end

assign      _cpuVPA = (cpuFC == 3'b111) ? 1'b0 : ~(!_cpuAS && cpuAddr[23:21] == 3'b111);
// SCSI back-pressure. Until now the SCSI space acknowledged unconditionally,
// so a target that could not serve the next pseudo-DMA byte had no way to say
// so and the transfer silently took stale data instead. It is the mechanism
// behind the 2026-08-26 CD->disk
// corruption. scsi_bus_hold is already qualified down to a DACK data access
// that cannot be served (see ncr5380.sv), so this only ever stretches the
// pseudo-DMA window; register reads, and every other device, are untouched.
// Bounded by the target's ~516 ms io-stall watchdog, which aborts the command
// and thereby releases the hold.
// Turbo (640x480 mode only) holds DTACK off until the CPU's slot, above.
assign      _cpuDTACK = ~(!_cpuAS && cpuAddr[23:21] != 3'b111) | scsi_bus_hold |
                        (status_turbo & !turbo_dtack_en);

// Turbo (640x480 mode only) runs the CPU on clk16_en_p/_n. E (the VIA clock)
// keeps its Classic rate through fx68k's E_div below, so the VIA timers, the
// tick and ADB are unchanged.
wire        cpu_en_p      = status_turbo ? clk16_en_p : clk8_en_p;
wire        cpu_en_n      = status_turbo ? clk16_en_n : clk8_en_n;

// The Classic's CPU is the 68000, fx68k. NOT A CLASSIC: each of these was
// `is68000 ? fx68_* : tg68_*`, with is68000 = (status_cpu == 0).
assign      _cpuReset_o   = fx68_reset_n;
assign      _cpuRW        = fx68_rw;
assign      _cpuAS        = fx68_as_n;
assign      _cpuUDS       = fx68_uds_n;
assign      _cpuLDS       = fx68_lds_n;
assign      E_falling     = fx68_E_falling;
assign      E_rising      = fx68_E_rising;
assign      _cpuVMA       = fx68_vma_n;
assign      cpuFC[0]      = fx68_fc0;
assign      cpuFC[1]      = fx68_fc1;
assign      cpuFC[2]      = fx68_fc2;
assign      cpuAddr[23:1] = fx68_a;
assign      cpuDataOut    = fx68_dout;

wire        fx68_rw;
wire        fx68_as_n;
wire        fx68_uds_n;
wire        fx68_lds_n;
wire        fx68_E_falling;
wire        fx68_E_rising;
wire        fx68_vma_n;
wire        fx68_fc0;
wire        fx68_fc1;
wire        fx68_fc2;
wire [15:0] fx68_dout;
wire [23:1] fx68_a;
wire        fx68_reset_n;

fx68k fx68k (
	.clk        ( clk_sys ),
	.extReset   ( !_cpuReset ),
	.pwrUp      ( !_cpuReset ),
	.enPhi1     ( cpu_en_p   ),
	.enPhi2     ( cpu_en_n   ),

	.eRWn       ( fx68_rw ),
	.ASn        ( fx68_as_n ),
	.LDSn       ( fx68_lds_n ),
	.UDSn       ( fx68_uds_n ),
	.E          ( ),
	.E_div      ( status_turbo ),
	.E_PosClkEn ( fx68_E_falling ),
	.E_NegClkEn ( fx68_E_rising ),
	.VMAn       ( fx68_vma_n ),
	.FC0        ( fx68_fc0 ),
	.FC1        ( fx68_fc1 ),
	.FC2        ( fx68_fc2 ),
	.BGn        ( ),
	.oRESETn    ( fx68_reset_n ),
	.oHALTEDn   ( ),
	.DTACKn     ( _cpuDTACK ),
	.VPAn       ( _cpuVPA ),
	.HALTn      ( 1'b1 ),
	.BERRn      ( 1'b1 ),
	.BRn        ( 1'b1 ),
	.BGACKn     ( 1'b1 ),
	.IPL0n      ( _cpuIPL[0] ),
	.IPL1n      ( _cpuIPL[1] ),
	.IPL2n      ( _cpuIPL[2] ),
	.iEdb       ( dataControllerDataOut ),
	.oEdb       ( fx68_dout ),
	.eab        ( fx68_a )
);

// NOT A CLASSIC: the 68010/68020 (TG68K). rtl/tg68k/ is kept; to bring it
// back, restore this instance, the is68000 muxes above, status_cpu and the
// CPU OSD option, and TG68K.qip in files.qip.
//wire        tg68_rw;
//wire        tg68_as_n;
//wire        tg68_uds_n;
//wire        tg68_lds_n;
//wire        tg68_E_rising;
//wire        tg68_E_falling;
//wire        tg68_vma_n;
//wire        tg68_fc0;
//wire        tg68_fc1;
//wire        tg68_fc2;
//wire [15:0] tg68_dout;
//wire [31:0] tg68_a;
//wire        tg68_reset_n;
//
//tg68k tg68k (
//	.clk        ( clk_sys      ),
//	.reset      ( !_cpuReset ),
//	.phi1       ( cpu_en_p  ),
//	.phi2       ( cpu_en_n  ),
//	.cpu        ( {status_cpu[1], |status_cpu} ),
//
//	.dtack_n    ( _cpuDTACK  ),
//	.rw_n       ( tg68_rw    ),
//	.as_n       ( tg68_as_n  ),
//	.uds_n      ( tg68_uds_n ),
//	.lds_n      ( tg68_lds_n ),
//	.fc         ( { tg68_fc2, tg68_fc1, tg68_fc0 } ),
//	.reset_n    ( tg68_reset_n ),
//
//	.E          (  ),
//	.E_div      ( status_turbo ),
//	.E_PosClkEn ( tg68_E_falling ),
//	.E_NegClkEn ( tg68_E_rising  ),
//	.vma_n      ( tg68_vma_n ),
//	.vpa_n      ( _cpuVPA ),
//
//	.br_n       ( 1'b1    ),
//	.bg_n       (  ),
//	.bgack_n    ( 1'b1 ),
//
//	.ipl        ( _cpuIPL ),
//	.berr       ( 1'b0 ),
//	.din        ( dataControllerDataOut ),
//	.dout       ( tg68_dout ),
//	.addr       ( tg68_a )
//);

addrController_top ac0
(
	.clk(clk_sys),
	.clk8(clk8),
	.clk8_en_p(clk8_en_p),
	.clk8_en_n(clk8_en_n),
	.clk16_en_p(clk16_en_p),
	.clk16_en_n(clk16_en_n),
	.cpuAddr(cpuAddr), 
	._cpuUDS(_cpuUDS),
	._cpuLDS(_cpuLDS),
	._cpuRW(_cpuRW),
	._cpuAS(_cpuAS),
	.turbo(status_turbo),
	// 512K Classic ROM: A18 passes through, so it repeats across $40_0000-$4F_FFFF
	// (Snow's rom_mask). NOT A CLASSIC: Plus 128K / SE 256K were {status_mod,~status_mod}.
	.configROMSize(2'b11),
	.configRAMSize(configRAMSize), 
	.memoryAddr(memoryAddr),
	.memoryLatch(memoryLatch),
	._memoryUDS(_memoryUDS),
	._memoryLDS(_memoryLDS),
	._romOE(_romOE), 
	._ramOE(_ramOE), 
	._ramWE(_ramWE),
	.videoBusControl(videoBusControl),	
	.dioBusControl(dioBusControl),	
	.cpuBusControl(cpuBusControl),	
	.selectSCSI(selectSCSI),
	.selectSCC(selectSCC),
	.selectIWM(selectIWM),
	.selectVIA(selectVIA),
	.selectRAM(selectRAM),
	.selectROM(selectROM),
	.selectSEOverlay(selectSEOverlay),
	.hsync(hsync), 
	.vsync(vsync),
	._hblank(_hblank),
	._vblank(_vblank),
	.loadPixels(loadPixels),
	.vid_alt(vid_alt),
	.res640(status_res640),
	.vramAccess(vramAccess),
	.memoryOverlayOn(memoryOverlayOn),

	.snd_alt(snd_alt),
	.loadSound(loadSound),
	.snd_advance(snd_advance),

	.dskReadAddrInt(dskReadAddrInt),
	.dskReadAckInt(dskReadAckInt),
	.dskReadAddrExt(dskReadAddrExt),
	.dskReadAckExt(dskReadAckExt),

	// A ROM download outranks the floppy writers, as in the MacLC core
	// (MacLC.sv dl_grant: "a ROM download outranks both"). download_cycle
	// below takes over every dioBusControl slot, so a loader/committer write
	// granted during a download was acked but never written: a floppy mounted
	// while boot0.rom was still arriving loaded as zeros (BUG-004, harness).
	.dskLoadAddrInt(slot3_int_addr),
	.dskLoadReqInt(slot3_int_req & ~dio_download),
	.dskLoadAckInt(slot3_int_ack_raw),
	.dskLoadAddrExt(slot3_ext_addr),
	.dskLoadReqExt(slot3_ext_req & ~dio_download),
	.dskLoadAckExt(slot3_ext_ack_raw),
	.dskLoadWrEn(dskLoadWrEn),
	.dskLoadSelExt(dskLoadSelExt)
);

wire [1:0] diskEject;
wire [1:0] diskMotor, diskAct;

dataController_top #(.SCSI_DEVS(SCSI_DEVS), .SCSI_CD_DEV(SCSI_CD_DEV)) dc0
(
	.clk32(clk_sys), 
	.clk8_en_p(clk8_en_p),
	.clk8_en_n(clk8_en_n),
	.clk16_en_n(clk16_en_n),
	.E_rising(E_rising),
	.E_falling(E_falling),
	// The Classic is an SE to dataController_top: ADB, SE overlay, no sound
	// page 2. NOT A CLASSIC: Plus mode was machineType = status_mod = 0.
	.machineType(1'b1),
	.turbo(status_turbo),
	._systemReset(n_reset),
	._cpuReset(_cpuReset), 
	._cpuIPL(_cpuIPL),
	._cpuUDS(_cpuUDS), 
	._cpuLDS(_cpuLDS), 
	._cpuRW(_cpuRW), 
	._cpuVMA(_cpuVMA),
	.cpuDataIn(cpuDataOut),
	.cpuDataOut(dataControllerDataOut), 	
	.scsi_bus_hold(scsi_bus_hold),
	.cpuAddrRegHi(cpuAddr[12:9]),
	.cpuAddrRegMid(cpuAddr[6:4]),  // for SCSI
	.cpuAddrRegLo(cpuAddr[2:1]),		
	.selectSCSI(selectSCSI),
	.selectSCC(selectSCC),
	.selectIWM(selectIWM),
	.selectVIA(selectVIA),
	.selectSEOverlay(selectSEOverlay),
	.cpuBusControl(cpuBusControl),
	.videoBusControl(videoBusControl),
	.memoryDataOut(memoryDataOut),
	.memoryDataIn(sdram_do),
	.memoryLatch(memoryLatch),

	// peripherals
	.ps2_key(ps2_key), 
	.capslock(capslock),
	.ps2_mouse(ps2_mouse),
	// BUG-016: both modes accumulate, PS/2 counts / 2 (32/64). The user's picks
	// on hardware, 2026-10-03: "Fast" of build 20261003 (640x480) and "1/2" of
	// build 20261003b (Original; HEAD's replace path was too fast). NOTES section 10.
	.mouse_accum(1'b1),
	.mouse_scale(7'd32),
	// ROM-DISK INJECTOR (removed): .romkeys_hold(romkeys_hold),
	// serial uart
	.serialIn(serialIn),
	.serialOut(serialOut),
	.serialCTS(serialCTS),
	.serialRTS(serialRTS),

	// RTC: the MiSTer's time, and the PRAM image port to pram_nvr below
	.timestamp(TIMESTAMP),
	.rtc_bcd(RTC),
	.pram_ext_addr(pram_ext_addr),
	.pram_ext_we(pram_ext_we),
	.pram_ext_wdata(pram_ext_wdata),
	.pram_ext_ready(pram_ext_ready),
	.pram_ext_q(pram_ext_q),
	.pram_wr(pram_wr),

	// video
	._hblank(_hblank),
	._vblank(_vblank), 
	.pixelOut(pixelOut),
	.loadPixels(loadPixels),
	.vid_alt(vid_alt),

	.memoryOverlayOn(memoryOverlayOn),

	.audioOut(audio),
	.snd_alt(snd_alt),
	.loadSound(loadSound),
	.snd_advance(snd_advance),

	// floppy disk interface
	.insertDisk({dsk_ext_ins, dsk_int_ins}),
	.diskSides({dsk_ext_ds, dsk_int_ds}),
	// M3 (swim.v). mediaSides 1 = "unknown", which never lowers the ceiling:
	// MacLC's floppy_sd.v sniffs the volume for it (a 400K volume in an 800K
	// file); our raw loader does not. The external drive never has media.
	.mediaSides(2'b11),
	.diskMFM({1'b0, dsk_int_mfm}),
	.diskHD({1'b0, dsk_int_hd}),
	.diskEject(diskEject),
	.dskReadAddrInt(dskReadAddrInt),
	.dskReadAckInt(dskReadAckInt),
	.dskReadAddrExt(dskReadAddrExt),
	.dskReadAckExt(dskReadAckExt),
	.diskMotor(diskMotor),
	.diskAct(diskAct),

	.writeProtect({wp_ext, wp_int}),
	.dskWriteAddrInt(wc_int_wr_addr),
	.dskWriteDataInt(wc_int_wr_data),
	.dskWriteReqInt(wc_int_wr_req),
	.dskWriteAckInt(wc_int_wr_ack),
	.dskWriteAddrExt(wc_ext_wr_addr),
	.dskWriteDataExt(wc_ext_wr_data),
	.dskWriteReqExt(wc_ext_wr_req),
	.dskWriteAckExt(wc_ext_wr_ack),

	.dskCommitDoneInt(wc_int_commit_done),
	.dskCommitAddrInt(wc_int_commit_addr),
	.dskCommitBufWrInt(wc_int_commit_buf_wr),
	.dskCommitBufAddrInt(wc_int_commit_buf_addr),
	.dskCommitBufDataInt(wc_int_commit_buf_data),
	.dskCommitDoneExt(wc_ext_commit_done),
	.dskCommitAddrExt(wc_ext_commit_addr),
	.dskCommitBufWrExt(wc_ext_commit_buf_wr),
	.dskCommitBufAddrExt(wc_ext_commit_buf_addr),
	.dskCommitBufDataExt(wc_ext_commit_buf_data),

	// block device interface for scsi disk
	.img_mounted(img_mounted[1:0]),
	.img_size(img_size[40:9]),
	.cd_enable(1'b0),                       // no CD target (removed 2026-09-28)
	.io_lba(scsi_sd_lba),
	.io_rd(scsi_sd_rd),
	.io_wr(scsi_sd_wr),
	.io_ack(sd_ack[1:0]),

	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_addr_hi(sd_buff_addr[12:8]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(scsi_sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.cd_snd_l(),
	.cd_snd_r()
);

// sd_rd/sd_wr are consumer OUTPUTS -> hps_io INPUTS, so the SCSI 2-bit view
// above, each floppy_loader's own scalar sd_rd request, and each
// floppy_sd_writer's own scalar sd_wr request must be combined
// into the full VDNUM=4 vectors here. Slot 3 is the PRAM image's; the second
// floppy's ldr_ext_sd_rd / wr_ext_sd_wr are no longer on the bus.
wire ldr_int_sd_rd, ldr_ext_sd_rd;
wire wr_int_sd_wr,  wr_ext_sd_wr;
assign sd_rd = {pram_sd_rd, ldr_int_sd_rd, scsi_sd_rd[1:0]};
assign sd_wr = {pram_sd_wr, wr_int_sd_wr, scsi_sd_wr[1:0]};

// NOT A CLASSIC: the second floppy drive. Its loader and writer stay until M3
// replaces the IWM, but no image ever reaches them: slot 3 is the PRAM's.
wire ext_img_mounted = 1'b0;

// ---- PRAM save image (M2): slot 3, rtl/pram_nvr.sv (MacLC's VD_PRAM FSM) ----
// (Out in builds m-o; back in build p, 2026-09-30, with the XPRAM rtc.v, to
// get a System 6.0.8 failure on every boot to chase.)
pram_nvr pram_nvr
(
	.clk          ( clk_sys                 ),
	.reset        ( !pll_locked             ),
	.rom_loaded   ( rom_loaded              ),
	.mac_reset    ( !n_reset                ),
	.img_mounted  ( img_mounted[VD_PRAM]    ),
	.img_size     ( img_size                ),
	.sd_lba       ( sd_lba[VD_PRAM]         ),
	.sd_rd        ( pram_sd_rd              ),
	.sd_wr        ( pram_sd_wr              ),
	.sd_ack       ( sd_ack[VD_PRAM]         ),
	.sd_buff_addr ( sd_buff_addr[7:0]       ),
	.sd_buff_dout ( sd_buff_dout            ),
	.sd_buff_din  ( sd_buff_din[VD_PRAM]    ),
	.sd_buff_wr   ( sd_buff_wr              ),
	.osd_status   ( OSD_STATUS              ),
	.save_req     ( 1'b0                    ),   // was status[13], "TD,Save PRAM" (hidden)
	.ext_addr     ( pram_ext_addr           ),
	.ext_we       ( pram_ext_we             ),
	.ext_wdata    ( pram_ext_wdata          ),
	.ext_ready    ( pram_ext_ready          ),
	.ext_q        ( pram_ext_q              ),
	.pram_wr      ( pram_wr                 ),
	.ready        ( pram_ready              ),
	.restart      ( pram_restart            )
);

// ---- ROM-DISK INJECTOR (removed, user 2026-09-29) ----
// M2 held Command-Option-X-O over ADB at every reset ("Boot ROM disk", O9).
// Now as on a real Classic: the user holds the keys at start-up, or selects
// the ROM disk in the Startup Disk control panel (saved in PRAM). Measured
// (PLAN M2): the ROM disk driver checks the KeyMap once, at $43F8EA.
//wire ram_prog_fetch = !_cpuAS && cpuFC[1:0] == 2'b10 && selectRAM && !memoryOverlayOn;
//always @(posedge clk_sys) begin
//	if (!n_reset)                          romkeys_hold <= ~status[9];
//	else if (romkeys_hold && ram_prog_fetch) romkeys_hold <= 1'b0;
//end

// sd_lba is likewise shared per slot between the loader (valid while it is
// busy) and the writer (valid the rest of the time) - the writer itself
// never starts while loader_busy is asserted (see floppy_sd_writer.v), so
// this mux can never straddle a genuine simultaneous request.
wire [31:0] ldr_int_sd_lba, ldr_ext_sd_lba;
wire [31:0] wr_int_sd_lba, wr_ext_sd_lba;
assign sd_lba[2] = ldr_int_busy ? ldr_int_sd_lba : wr_int_sd_lba;
// sd_lba[3] and sd_buff_din[3]: driven by pram_nvr (slot 3 is the PRAM's).

wire [15:0] wr_int_sd_buff_din, wr_ext_sd_buff_din;
assign sd_buff_din[2] = wr_int_sd_buff_din;

// wr_*_busy: queued-or-in-flight sd_wr against this slot (see
// floppy_sd_writer.v) - folded into LED_USER below alongside the loader's
// own busy, so the activity light also covers a pending SD flush after a
// write, not just a mount-time load.
wire wr_int_busy, wr_ext_busy;

wire        ldr_int_done, ldr_ext_done;
wire        ldr_int_busy, ldr_ext_busy;
wire [63:0] ldr_int_size, ldr_ext_size;
wire        ldr_int_readonly, ldr_ext_readonly;

floppy_loader ldr_int
(
	.clk_sys(clk_sys),
	.reset(!pll_locked), // power-up only - a Mac "Reset & Apply" must not abort an in-flight mount

	.img_mounted(img_mounted[2]),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(ldr_int_sd_lba),
	.sd_rd(ldr_int_sd_rd),
	.sd_ack(sd_ack[2]),

	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr),

	.wr_addr(ldr_int_wr_addr),
	.wr_data(ldr_int_wr_data),
	.wr_req(ldr_int_wr_req),
	.wr_ack(ldr_int_wr_ack),

	.done(ldr_int_done),
	.loaded_size(ldr_int_size),
	.readonly_latched(ldr_int_readonly),
	.busy(ldr_int_busy)
);

floppy_loader ldr_ext
(
	.clk_sys(clk_sys),
	.reset(!pll_locked),

	.img_mounted(ext_img_mounted),   // NOT A CLASSIC: slot 3 is the PRAM's
	.img_size(img_size),
	.img_readonly(img_readonly),

	.sd_lba(ldr_ext_sd_lba),
	.sd_rd(ldr_ext_sd_rd),
	.sd_ack(1'b0),

	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr),

	.wr_addr(ldr_ext_wr_addr),
	.wr_data(ldr_ext_wr_data),
	.wr_req(ldr_ext_wr_req),
	.wr_ack(ldr_ext_wr_ack),

	.done(ldr_ext_done),
	.loaded_size(ldr_ext_size),
	.readonly_latched(ldr_ext_readonly),
	.busy(ldr_ext_busy)
);

floppy_sd_writer wr_int
(
	.clk(clk_sys),
	.reset(!pll_locked),

	.img_mounted(img_mounted[2]),

	.commit_done(wc_int_commit_done),
	.commit_addr(wc_int_commit_addr),
	.commit_buf_wr(wc_int_commit_buf_wr),
	.commit_buf_addr(wc_int_commit_buf_addr),
	.commit_buf_data(wc_int_commit_buf_data),

	.readonly(ldr_int_readonly),
	.loader_busy(ldr_int_busy),
	// image length in 512-byte blocks; only 400K/800K images ever reach
	// insertDisk (see dsk_int_ss/ds below), so 13 bits covers every case
	// that can produce a commit - 1600 blocks for an 800K image.
	.size_blocks(ldr_int_size[21:9]),

	.sd_lba(wr_int_sd_lba),
	.sd_wr(wr_int_sd_wr),
	.sd_ack(sd_ack[2]),

	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_din(wr_int_sd_buff_din),

	.busy(wr_int_busy)
);

floppy_sd_writer wr_ext
(
	.clk(clk_sys),
	.reset(!pll_locked),

	.img_mounted(ext_img_mounted),   // NOT A CLASSIC: slot 3 is the PRAM's

	.commit_done(wc_ext_commit_done),
	.commit_addr(wc_ext_commit_addr),
	.commit_buf_wr(wc_ext_commit_buf_wr),
	.commit_buf_addr(wc_ext_commit_buf_addr),
	.commit_buf_data(wc_ext_commit_buf_data),

	.readonly(ldr_ext_readonly),
	.loader_busy(ldr_ext_busy),
	.size_blocks(ldr_ext_size[21:9]),

	.sd_lba(wr_ext_sd_lba),
	.sd_wr(wr_ext_sd_wr),
	.sd_ack(1'b0),

	.sd_buff_addr(sd_buff_addr[7:0]),
	.sd_buff_din(wr_ext_sd_buff_din),

	.busy(wr_ext_busy)
);

// word written into SDRAM this cycle when dskLoadWrEn is high - selects
// whichever side (int/ext) addrController_top's arbiter (fixed priority
// int-over-ext) actually granted this cycle, and within that side,
// whichever source (loader/committer) slot3_int_req/slot3_ext_req above
// selected. Must use dskLoadSelExt (held for the whole grant cycle), not
// ldr_ext_wr_ack/dskLoadAckExt - that ack is a late pulse in busPhase 3,
// one phase after sdram.v's CAS phase (busPhase 1) already latched this
// data, so gating on it left every ext (drive 2) write writing int's
// stale data instead of its own.
wire [15:0] slot3_wr_data = dskLoadSelExt ? slot3_ext_data : slot3_int_data;

reg disk_act;
always @(posedge clk_sys) begin
	integer timeout = 0;

	if(timeout) begin
		timeout <= timeout - 1;
		disk_act <= 1;
	end else begin
		disk_act <= 0;
	end

	if(|diskAct) timeout <= 500000;
end

//////////////////////// DOWNLOADING ///////////////////////////

// include ROM download helper
wire dio_download;
wire [23:0] dio_addr = ioctl_addr[24:1];
wire  [7:0] dio_index;

// The first ioctl download to end is boot0.rom (the core's only download).
// The Mac is held in reset until then, and it starts pram_nvr's no-image
// backstop (2026-10-03, see pram_nvr.sv).
always @(posedge clk_sys) begin
	reg old_dl = 0;
	old_dl <= dio_download;
	if (old_dl & ~dio_download) rom_loaded <= 1'b1;
end

// good floppy image sizes: 409600 / 819200 (GCR, the IWM path) and, with the
// SuperDrive (M3), 737280 / 1474560 (MFM 720K / 1.44 MB, the ISM path).
// Raw images only; DC42 is PLAN open question 3 (MacLC's floppy_sd.v loader).
reg dsk_int_ds, dsk_ext_ds;  // double sided image inserted
reg dsk_int_ss, dsk_ext_ss;  // single sided image inserted
reg dsk_int_mfm;             // M3: MFM image (720K or 1.44 MB)
reg dsk_int_hd;              // M3: 1.44 MB HD (vs 720K DD)

// Disk CHANGE is presented as a TRANSITION (after MacLC.sv, 2026-08-05/06):
// the Sony driver learns of media only by polling CSTIN, so it must see the
// disk leave and then arrive to unmount the old volume. Hold the drive EMPTY
// from the mount pulse until DSK_EMPTY_CY (~2.06 s) after the load ends -
// longer than the driver's ~0.8 s media poll. This goes WITH floppy.v's
// SWITCHED register (MacLC's reverted ebbdac6 had the hold without it).
// Only a mount that REPLACES a disk is held: a first insert (empty drive) is
// already an empty-to-disk transition, and holding it put the disk behind the
// ROM's start-up search (harness 2026-09-29: Disk605 loaded ~F250, appeared
// F375, after the ROM's first look at F345 - no boot). MacLC holds every mount.
localparam [25:0] DSK_EMPTY_CY = 26'h3FFFFFF;
reg [25:0] dsk_int_empty_cy = DSK_EMPTY_CY;
reg        dsk_int_swap = 1'b0;     // this mount replaced a disk: hold it
wire dsk_int_empty = (dsk_int_empty_cy != DSK_EMPTY_CY);

// any known type of disk image inserted?
wire dsk_int_ins = !dsk_int_empty && (dsk_int_ds || dsk_int_ss || dsk_int_mfm);
wire dsk_ext_ins = dsk_ext_ds || dsk_ext_ss;

// Floppies are S-type block-device mounts, loaded into SDRAM
// by floppy_loader (see instantiation above) instead of streamed in via
// ioctl_download. insertDisk therefore only goes true once ldr_*_done
// fires - i.e. once the WHOLE image is resident in SDRAM - never at the
// bare img_mounted pulse, so the Mac can never observe a partially-loaded
// disk. Also clear-on-mount (not just on eject/size-mismatch): a remount
// while already inserted must drop insertDisk immediately so nothing reads
// mid-reload, mirroring the SAVE-feature precedent in the UK101 core.
// diskEject is still set by macOS on eject, unchanged.
always @(posedge clk_sys) begin
	if (img_mounted[2] && img_size != 0) begin
		dsk_int_ds  <= 1'b0;
		dsk_int_ss  <= 1'b0;
		dsk_int_mfm <= 1'b0;
		dsk_int_hd  <= 1'b0;
		dsk_int_swap <= dsk_int_ds || dsk_int_ss || dsk_int_mfm;
		if (dsk_int_ds || dsk_int_ss || dsk_int_mfm) dsk_int_empty_cy <= 26'd0;
	end
	else if (ldr_int_busy && dsk_int_swap)
		dsk_int_empty_cy <= 26'd0;
	else if (dsk_int_empty_cy != DSK_EMPTY_CY)
		dsk_int_empty_cy <= dsk_int_empty_cy + 26'd1;

	if (ldr_int_done) begin
		dsk_int_ds  <= (ldr_int_size == 64'd819200);
		dsk_int_ss  <= (ldr_int_size == 64'd409600);
		dsk_int_mfm <= (ldr_int_size == 64'd737280) || (ldr_int_size == 64'd1474560);
		dsk_int_hd  <= (ldr_int_size == 64'd1474560);
	end

	if(diskEject[0]) begin
		dsk_int_ds  <= 0;
		dsk_int_ss  <= 0;
		dsk_int_mfm <= 0;
		dsk_int_hd  <= 0;
	end
end

always @(posedge clk_sys) begin
	if (ext_img_mounted && img_size != 0) begin   // NOT A CLASSIC (slot 3 = PRAM)
		dsk_ext_ds <= 1'b0;
		dsk_ext_ss <= 1'b0;
	end
	else if (ldr_ext_done) begin
		dsk_ext_ds <= (ldr_ext_size == 64'd819200);
		dsk_ext_ss <= (ldr_ext_size == 64'd409600);
	end

	if(diskEject[1]) begin
		dsk_ext_ds <= 0;
		dsk_ext_ss <= 0;
	end
end

// ROM is being stored at word offset 0x00000/0x40000 (normal/alt, bit6-selected).
// Floppy images no longer come through here - see the
// floppy_loader instances above.
reg [20:0] dio_a;
reg [15:0] dio_data;
reg        dio_write;

always @(posedge clk_sys) begin
	reg old_cyc = 0;

	if(ioctl_write) begin
		dio_data <= {ioctl_data[7:0], ioctl_data[15:8]};
		dio_a <= {dio_index[6], dio_addr[17:0]};
		ioctl_wait <= 1;
	end

	old_cyc <= dioBusControl;
	if(~dioBusControl) dio_write <= ioctl_wait;
	if(old_cyc & ~dioBusControl & dio_write) ioctl_wait <= 0;
end

// (Build n's COLD START - hold the Mac through the ROM download, then clear
// WarmStart $CFC so each core load runs the ROM's RAM test - was tried for the
// System 6.0.8 fault and did not fix it; removed 2026-09-30, user: no extra
// boot time. See STATUS.)


// sdram used for ram/rom maps directly into 68k address space
wire download_cycle = dio_download && dioBusControl;

////////////////////////// SDRAM /////////////////////////////////

wire [24:0] sdram_addr = download_cycle ? {4'b0001, dio_a[20:0] } :
                         // The Classic reads ROM slot 0, boot0.rom. A stray
                         // boot1.rom downloads into slot 1 and is never read.
                         // NOT A CLASSIC: Plus/SE read slot status_mod here.
                         ~_romOE        ? {4'b0001, 2'b00, 1'b0, memoryAddr[18:1]} :
                         // M4: VRAM (640x480 mode only) at SDRAM word $400000
                         // (byte 8 MB), clear of RAM, the ROM slots and both
                         // floppy images. memoryAddr is the 64K window offset.
                         vramAccess     ? {3'b001, 1'b0, memoryAddr[21:1]} :
                                          {3'b000, (dskReadAckInt || dskReadAckExt || dskLoadWrEn), memoryAddr[21:1]};

wire [15:0] rom_data;   // M4: ROM word after rom640_patch, below
wire [15:0] sdram_din  = download_cycle ? dio_data  : dskLoadWrEn ? slot3_wr_data : memoryDataOut;
wire  [1:0] sdram_ds   = download_cycle ? 2'b11     : dskLoadWrEn ? 2'b11          : { !_memoryUDS, !_memoryLDS };
wire        sdram_we   = download_cycle ? dio_write : dskLoadWrEn ? 1'b1           : !_ramWE;
wire        sdram_oe   = download_cycle ? 1'b0                  : (!_ramOE || !_romOE || dskReadAckInt || dskReadAckExt);
wire [15:0] sdram_do   = download_cycle ? 16'hffff : (dskReadAckInt || dskReadAckExt) ? extra_rom_data_demux :
                         ~_romOE ? rom_data : sdram_out;

// M4: the 640x480 ROM patches, on the read path only (the ROM in SDRAM is
// never written). With status_res640 off, rom_data is sdram_out unchanged.
rom640_patch rom640_patch
(
	.res640 ( status_res640    ),
	.mirror ( cpuAddr[19]      ),   // $48-$4Fxxxx: patch code (rom640_patch.v)
	.addr   ( memoryAddr[18:1] ),
	.din    ( sdram_out        ),
	.dout   ( rom_data         )
);

// during rom/disk download ffff is returned so the screen is black during download
// "extra rom" is used to hold the disk image. It's expected to be byte wide and
// we thus need to properly demultiplex the word returned from sdram in that case
wire [15:0] extra_rom_data_demux = memoryAddr[0]? {sdram_out[7:0],sdram_out[7:0]}:{sdram_out[15:8],sdram_out[15:8]};
wire [15:0] sdram_out;

assign SDRAM_CKE = 1;

sdram sdram
(
	// system interface
	.init           ( !pll_locked              ),
	.clk_64         ( clk_mem                  ),
	.clk_8          ( clk8                     ),

	.sd_clk         ( SDRAM_CLK                ),
	.sd_data        ( SDRAM_DQ                 ),
	.sd_addr        ( SDRAM_A                  ),
	.sd_dqm         ( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs          ( SDRAM_nCS                ),
	.sd_ba          ( SDRAM_BA                 ),
	.sd_we          ( SDRAM_nWE                ),
	.sd_ras         ( SDRAM_nRAS               ),
	.sd_cas         ( SDRAM_nCAS               ),

	// cpu/chipset interface
	// map rom to sdram word address $200000 - $20ffff
	.din            ( sdram_din                ),
	.addr           ( sdram_addr               ),
	.ds             ( sdram_ds                 ),
	.we             ( sdram_we                 ),
	.oe             ( sdram_oe                 ),
	.dout           ( sdram_out                )
);

`ifdef VERILATOR
// Taps for the Verilator harness (verilator/sim_main.cpp). Quartus does not
// define VERILATOR, so none of this is synthesised.
wire [23:0] sim_cpuAddr     /*verilator public_flat_rd*/ = {cpuAddr[23:1], 1'b0};
wire  [2:0] sim_cpuFC       /*verilator public_flat_rd*/ = cpuFC;
wire        sim_cpuAS       /*verilator public_flat_rd*/ = _cpuAS;
wire        sim_cpuRW       /*verilator public_flat_rd*/ = _cpuRW;
wire        sim_cpuDTACK    /*verilator public_flat_rd*/ = _cpuDTACK;
wire [15:0] sim_cpuDin      /*verilator public_flat_rd*/ = dataControllerDataOut;
wire [15:0] sim_cpuDout     /*verilator public_flat_rd*/ = cpuDataOut;
wire        sim_cpuReset    /*verilator public_flat_rd*/ = _cpuReset;
wire        sim_overlay     /*verilator public_flat_rd*/ = memoryOverlayOn;
wire        sim_hblank_n    /*verilator public_flat_rd*/ = _hblank;
wire        sim_vblank_n    /*verilator public_flat_rd*/ = _vblank;
wire  [2:0] sim_ipl_n       /*verilator public_flat_rd*/ = _cpuIPL;
wire  [7:0] sim_via_pa_o    /*verilator public_flat_rd*/ = dc0.via_pa_o;
wire  [7:0] sim_via_pa_oe   /*verilator public_flat_rd*/ = dc0.via_pa_oe;
wire        sim_selectIWM   /*verilator public_flat_rd*/ = selectIWM;
wire  [1:0] sim_cpuDS_n     /*verilator public_flat_rd*/ = {_cpuUDS, _cpuLDS};
wire  [2:0] sim_ldr_state   /*verilator public_flat_rd*/ = ldr_int.state;
wire [11:0] sim_ldr_sector  /*verilator public_flat_rd*/ = ldr_int.sector;
wire        sim_ldr_ack     /*verilator public_flat_rd*/ = sd_ack[2];
wire  [7:0] sim_iwm_state   /*verilator public_flat_rd*/ =
	{dc0.sw.q7, dc0.sw.q6, dc0.sw.selectExternalDrive, dc0.sw.diskEnableExt,
	 dc0.sw.diskEnableInt, dc0.driveSel, dc0.SEL, dc0.sw.lstrb};
wire  [2:0] sim_iwm_ca      /*verilator public_flat_rd*/ = {dc0.sw.ca2, dc0.sw.ca1, dc0.sw.ca0};
// ADB: last command (cmd, addr), keyboard reg 0, FIFO pointers, keyboardValid
wire [31:0] sim_adb         /*verilator public_flat_rd*/ =
	{dc0.adb.cmd_r, dc0.adb.addr_r, dc0.adb.kbdReg0,
	 dc0.adb.kbdFifoWr, dc0.adb.kbdFifoRd[1:0], 1'b0, dc0.adb.keyboardValid};
// ADB transceiver signal level (ADB_WIN): ST1 ST0, listen, _int, transmitting,
// receiving, SR write seen (sr_wr_d), kbdclk, din strobe, dout strobe, bit count, respCnt
wire [15:0] sim_adb2        /*verilator public_flat_rd*/ =
	{dc0.ADBST1, dc0.ADBST0, dc0.adb.listen, dc0._ADBint,
	 dc0.adbx.transmitting, dc0.adbx.receiving, dc0.adbx.sr_wr_d, dc0.kbdclk,
	 dc0.adb_din_strobe, dc0.adb_dout_strobe, dc0.adbx.bitcnt, dc0.adb.respCnt[2:0]};
// ADB bytes and device addresses (ADB_WIN): din, dout, keyboard address, mouse address
wire [23:0] sim_adb3        /*verilator public_flat_rd*/ =
	{dc0.adb_din, dc0.adb_dout, dc0.adb.kbdReg3[11:8], dc0.adb.mouseReg3[11:8]};
`endif

endmodule
