module CoolGirl #	(
		parameter USE_VRC2 = 1,
		parameter USE_CHEETAHMEN2 = 1
	)
	(
	input	m2,
	input romsel,
	input cpu_rw_in,
	input [14:0] cpu_addr_in,
	input [7:0] cpu_data_in,
	output [26:13] cpu_addr_out,
	output flash_we,
	output flash_oe,
	output sram_ce,
	output sram_we,
	output sram_oe,
		
	input ppu_rd_in,
	input ppu_wr_in,
	input [13:0] ppu_addr_in,
	output [17:10] ppu_addr_out,
	output ppu_rd_out,
	output ppu_wr_out,
	output reg ppu_ciram_a10,
	output ppu_ciram_ce,
		
	output irq
);
	reg [26:14] cpu_base;
	reg [18:14] cpu_mask;
	reg [17:13] chr_mask;
	reg [1:0] sram_page;
	reg [4:0] mapper;
	reg [2:0] flags;
	reg sram_enabled;
	reg chr_write_enabled;
	reg prg_write_enabled;
	reg mirroring;
	reg lockout;

	reg [18:13] cpu_addr_mapped;
	assign cpu_addr_out[26:13] = romsel == 0 ? {cpu_base[26:14] | (cpu_addr_mapped[18:14] & ~cpu_mask[18:14]), cpu_addr_mapped[13]} : sram_page[1:0];
	reg [17:10] ppu_addr_mapped;
	assign ppu_addr_out[17:10] = {ppu_addr_mapped[17:13] & ~chr_mask[17:13], ppu_addr_mapped[12:10]};
	
	// some common registers for all mappers
	reg [7:0] r0;
	reg [7:0] r1;
	reg [7:0] r2;
	reg [7:0] r3;
	reg [7:0] r4;
	reg [7:0] r5;
	reg [7:0] r6;
	reg [7:0] r7;
	reg [7:0] r8;
	reg [7:0] r9;

	reg [7:0] irq_scanline_counter;
	reg [2:0] a12_low_time;
	reg irq_scanline_reload;
	reg irq_scanline_reload_clear;
	reg irq_scanline_enabled;
	reg irq_scanline_value;
	reg irq_scanline_ready;	
	reg irq_scanline_out;
	
	// for MMC1
	/*
	r0 - load register
	r1 - control
	r2 - chr0_bank
	r3 - chr1_bank
	r4 - prg_bank
	*/
	// for MMC3
	/*
	r8[2:0] - bank_select
	r8[3] - PRG mode
	r8[4] - CHR mode
	r8[5] - mirroring
	r8[7:6] - RAM protect
	r9 - IRQ latch
	*/
	// for VRC
	assign vrc_2b_hi = cpu_addr_in[1] | cpu_addr_in[3] | cpu_addr_in[5] | cpu_addr_in[7];
	assign vrc_2b_low = cpu_addr_in[0] | cpu_addr_in[2] | cpu_addr_in[4] | cpu_addr_in[6];
	/*
	r0[4:0] - PRG0 bank 
	r1[4:0] - PRG1 bank 
	r0[7:6] - mirroring
	r2 - CHR0
	r3 - CHR1
	r4 - CHR2
	r5 - CHR3
	r6 - CHR4
	r7 - CHR5
	r8 - CHR6
	r9 - CHR7
	*/
	// for mapper #228 - Cheetahmen II :)
	/*
	r0[5:0] - CHR bank
	r1[0] - PRG mode
	r2[4:0] - PRG bank
	r3[1:0] - PRG chip... unused by Cheetahmen II
	r4[0] - mirroring
	*/	
	
	assign flash_we = cpu_rw_in | romsel | ~prg_write_enabled;
	assign flash_oe = ~cpu_rw_in | romsel;
	assign sram_ce = !(cpu_addr_in[14] & cpu_addr_in[13] & m2 & romsel & sram_enabled);
	assign sram_we = cpu_rw_in;
	assign sram_oe = ~cpu_rw_in;
	assign ppu_rd_out = ppu_rd_in | ppu_addr_in[13];
	assign ppu_wr_out = ppu_wr_in | ppu_addr_in[13] | ~chr_write_enabled;
	assign irq = !irq_scanline_out ? 1'bZ : 1'b0;
	assign ppu_ciram_ce = 1'bZ; // for backward compatibility
	
	always @ (negedge m2)
	begin
		if (cpu_rw_in == 0) // write
		begin
			if (romsel == 1) // $0000-$7FFF
			begin
				if ((cpu_addr_in[14:12] == 3'b101) && (lockout == 0)) // $5000-5FFF & lockout is off
				begin
					if (cpu_addr_in[2:0] == 3'b000) // $5xx0
						cpu_base[26:22] = cpu_data_in[4:0]; // CPU base address A26-A22
					if (cpu_addr_in[2:0] == 3'b001) // $5xx1
						cpu_base[21:14] = cpu_data_in[7:0]; // CPU base address A21-A14
					if (cpu_addr_in[2:0] == 3'b010) // $5xx2
						cpu_mask[18:14] = cpu_data_in[4:0]; // CPU mask A18-A14
					if (cpu_addr_in[2:0] == 3'b011) // $5xx3
						r0[7:0] = cpu_data_in[7:0];			// direct r0 access for mapper #0 CHR bank
					if (cpu_addr_in[2:0] == 3'b100) // $5xx4
						chr_mask[17:13] = cpu_data_in[4:0];	// CHR mask A17-A13
					if (cpu_addr_in[2:0] == 3'b101) // $5xx5
						sram_page = cpu_data_in[1:0];			// current SRAM page 0-3
					if (cpu_addr_in[2:0] == 3'b110) // $5xx6
					begin
						mapper = cpu_data_in[4:0];				// mapper
						flags[2:0] = cpu_data_in[7:5];		// some flags
						if (mapper == 5'b00001) // MMC1 power-on state
						begin
							r0[5:0] = 6'b100000;
							r1[3:2] = 2'b11;
						end
					end
					if (cpu_addr_in[2:0] == 3'b111) // $5xx7
						// some other parameters
						{lockout, mirroring, prg_write_enabled, chr_write_enabled, sram_enabled} = {cpu_data_in[7], cpu_data_in[3:0]};
				end
			end else begin // $8000-$FFFF
				// Mapper #1 - MMC1
				if (mapper == 5'b00001)
				begin
					if (cpu_data_in[7] == 1) // reset
					begin
						r0[5:0] = 6'b100000;
						r1[3:2] = 2'b11;
					end else begin				
						r0[5:0] = {cpu_data_in[0], r0[5:1]};
						if (r0[0] == 1)
						begin
							case (cpu_addr_in[14:13])
								2'b00: r1[4:0] = r0[5:1]; // $8000- $9FFF
								2'b01: r2[4:0] = r0[5:1]; // $A000- $BFFF
								2'b10: r3[4:0] = r0[5:1]; // $C000- $DFFF
								2'b11: r4[4:0] = r0[5:1]; // $E000- $FFFF
							endcase
							r0[5:0] = 6'b100000;
						end
					end					
				end				
				// Mapper #2 - UxROM
				if (mapper == 5'b00010)
				begin
					r0 = cpu_data_in;
				end				
				// Mapper #3 - CNROM
				if (mapper == 5'b00011)
				begin
					r0 = cpu_data_in;
				end
				// Mapper #4 - MMC3/MMC6
				if (mapper == 5'b00100)
				begin
					case ({cpu_addr_in[14:13], cpu_addr_in[0]})
						3'b000: {r8[4], r8[3], r8[2:0]} = {cpu_data_in[7], cpu_data_in[6], cpu_data_in[2:0]};// $8000-$9FFE, even
						3'b001: begin // $8001-$9FFF, odd
							case (r8[2:0])
								3'b000: r0 = cpu_data_in;
								3'b001: r1 = cpu_data_in;
								3'b010: r2 = cpu_data_in;
								3'b011: r3 = cpu_data_in;
								3'b100: r4 = cpu_data_in;
								3'b101: r5 = cpu_data_in;
								3'b110: r6 = cpu_data_in;
								3'b111: r7 = cpu_data_in;
							endcase
						end
						3'b010: r8[5] = cpu_data_in[0]; // $A000-$BFFE, even
						3'b011: r8[7:6] = cpu_data_in[7:6]; // $A001-$BFFF, odd
						3'b100: r9 = cpu_data_in; // $C000-$DFFE, even (IRQ latch)
						3'b101: irq_scanline_reload = 1; // $C001-$DFFF, odd
						3'b110: irq_scanline_enabled = 0; // $E000-$FFFE, even
						3'b111: irq_scanline_enabled = 1; // $E001-$FFFF, odd
					endcase					
				end				
				// Mapper #7 - AxROM
				if (mapper == 5'b00111)
				begin
					r0 = cpu_data_in;
				end	
				// Mapper #23 - VRC2b
				if (USE_VRC2 == 1 && mapper == 5'b10111)
				begin
					// flags[0] to shift lines
					case ({cpu_addr_in[14:12], flags[0] ? vrc_2b_low : vrc_2b_hi, flags[0] ? vrc_2b_hi : vrc_2b_low}) 
						5'b00000, // $8000
						5'b00001, // $8001
						5'b00010, // $8002
						5'b00011: r0[4:0] = cpu_data_in[4:0];  // $8003, PRG0
						5'b00100, // $9000
						5'b00101, // $9001
						5'b00110, // $9002
						5'b00111: r0[7:6] = cpu_data_in[1:0];  // $A003, mirroring
						5'b01000, // $A000
						5'b01001, // $A001
						5'b01010, // $A002
						5'b01011: r1[4:0] = cpu_data_in[4:0];  // $A003, PRG1
						5'b01100: r2[3:0] = cpu_data_in[3:0];  // $B000, CHR0 low						
						5'b01101: r2[7:4] = cpu_data_in[3:0];  // $B001, CHR0 hi
						5'b01110: r3[3:0] = cpu_data_in[3:0];  // $B002, CHR1 low						
						5'b01111: r3[7:4] = cpu_data_in[3:0];  // $B003, CHR1 hi
						5'b10000: r4[3:0] = cpu_data_in[3:0];  // $C000, CHR2 low						
						5'b10001: r4[7:4] = cpu_data_in[3:0];  // $C001, CHR2 hi
						5'b10010: r5[3:0] = cpu_data_in[3:0];  // $C002, CHR3 low						
						5'b10011: r5[7:4] = cpu_data_in[3:0];  // $C003, CHR3 hi
						5'b10100: r6[3:0] = cpu_data_in[3:0];  // $D000, CHR4 low						
						5'b10101: r6[7:4] = cpu_data_in[3:0];  // $D001, CHR4 hi
						5'b10110: r7[3:0] = cpu_data_in[3:0];  // $D002, CHR5 low						
						5'b10111: r7[7:4] = cpu_data_in[3:0];  // $D003, CHR5 hi
						5'b11000: r8[3:0] = cpu_data_in[3:0];  // $E000, CHR6 low
						5'b11001: r8[7:4] = cpu_data_in[3:0];  // $E001, CHR6 hi
						5'b11010: r9[3:0] = cpu_data_in[3:0];  // $E002, CHR7 low
						5'b11011: r9[7:4] = cpu_data_in[3:0];  // $E003, CHR7 hi						
					endcase
				end
				// Mapper #228 - Cheetahmen II
				if (USE_CHEETAHMEN2 == 1 && mapper == 5'b11111)
				begin
					r0[5:0] = {cpu_addr_in[3:0], cpu_data_in[1:0]};	// CHR bank
					r1[0] = cpu_addr_in[5];									// PRG mode
					r2[4:0] = cpu_addr_in[10:6];							// PRG bank
					//r3[1:0] = cpu_addr_in[12:11];							// PRG chip
					r4[0] = cpu_addr_in[13];								// mirroring
				end
			end // romsel
		end // write
		
		// some IRQ stuff
		if (irq_scanline_reload_clear)
			irq_scanline_reload = 0;
	end

	always @ (*)
	begin
		// Mapper #0 - NROM
		if (mapper == 5'b00000)
		begin
			cpu_addr_mapped = cpu_addr_in[14:13];
			ppu_addr_mapped = {r0[4:0], ppu_addr_in[12:10]};		
			ppu_ciram_a10 = !mirroring ? ppu_addr_in[10] : ppu_addr_in[11]; // vertical / horizontal			
		end
		// Mapper #1 - MMC1
		if (mapper == 5'b00001)
		begin
			if (romsel == 0) // accessing $8000-$FFFF
			begin
				case (r1[3:2])			
					2'b00,
					2'b01: cpu_addr_mapped = {r4[3:1], cpu_addr_in[14:13]}; // 32KB bank mode
					2'b10: if (cpu_addr_in[14] == 0) // $8000-$BFFF
							cpu_addr_mapped = cpu_addr_in[13]; // fixed to the first bank
						else // $C000-$FFFF
							cpu_addr_mapped = {r4[3:0], cpu_addr_in[13]};  // 16KB bank selected
					2'b11: if (cpu_addr_in[14] == 0) // $8000-$BFFF
							cpu_addr_mapped = {r4[3:0], cpu_addr_in[13]};  // 16KB bank selected
						else // $C000-$FFFF
							cpu_addr_mapped = {4'b1111, cpu_addr_in[13]};	// fixed to the last bank
				endcase
			end
			case (r1[4])
				0: ppu_addr_mapped = {r2[4:1], ppu_addr_in[12:10]}; // 8KB bank mode
				1: if (ppu_addr_in[12] == 0) // 4KB bank mode
						ppu_addr_mapped = {r2[4:0], ppu_addr_in[11:10]}; // first bank
					else
						ppu_addr_mapped = {r3[4:0], ppu_addr_in[11:10]}; // second bank
			endcase
			case (r1[1:0])
				2'b00: ppu_ciram_a10 = 0;
				2'b01: ppu_ciram_a10 = 1;
				2'b10: ppu_ciram_a10 = ppu_addr_in[10]; // verical mirroring
				2'b11: ppu_ciram_a10 = ppu_addr_in[11]; // horizontal mirroring
			endcase
		end
		// Mapper #2 - UxROM
		if (mapper == 5'b00010)
		begin
			cpu_addr_mapped = {(cpu_addr_in[14] ? 5'b11111 : r0[4:0]), cpu_addr_in[13]};
			ppu_addr_mapped = ppu_addr_in[12:10];		
			ppu_ciram_a10 = !mirroring ? ppu_addr_in[10] : ppu_addr_in[11]; // vertical / horizontal			
		end
		// Mapper #3 - CNROM
		if (mapper == 5'b00011)
		begin
			cpu_addr_mapped = {cpu_addr_in[14:13]};
			ppu_addr_mapped = {r0[4:0], ppu_addr_in[12:10]};		
			ppu_ciram_a10 = !mirroring ? ppu_addr_in[10] : ppu_addr_in[11]; // vertical / horizontal			
		end
		// Mapper #4 - MMC3/MMC6
		if (mapper == 5'b00100)
		begin
			if (romsel == 0) // accessing $8000-$FFFF
			begin
				case ({cpu_addr_in[14:13], r8[3] /*PRG mode*/})
					3'b000: cpu_addr_mapped = r6[5:0];
					3'b001: cpu_addr_mapped = 6'b111110;
					3'b010,
					3'b011: cpu_addr_mapped = r7[5:0];
					3'b100: cpu_addr_mapped = 6'b111110;
					3'b101: cpu_addr_mapped = r6[5:0];
					default: cpu_addr_mapped = 6'b111111;
				endcase
			end
			if (ppu_addr_in[12] == r8[4] /*CHR mode*/)	
			begin
				case (ppu_addr_in[11])
					1'b0: ppu_addr_mapped = {r0[7:1], ppu_addr_in[10]};
					1'b1: ppu_addr_mapped = {r1[7:1], ppu_addr_in[10]};
				endcase				
			end else begin
				case (ppu_addr_in[11:10])
					2'b00: ppu_addr_mapped = r2;
					2'b01: ppu_addr_mapped = r3;
					2'b10: ppu_addr_mapped = r4;
					2'b11: ppu_addr_mapped = r5;
				endcase
			end
			ppu_ciram_a10 = r8[5] /* mirroring */ ? ppu_addr_in[11] : ppu_addr_in[10];
		end
		// Mapper #7 - AxROM
		if (mapper == 5'b00111)
		begin
			cpu_addr_mapped = {r0[2:0], cpu_addr_in[14:13]};
			ppu_addr_mapped = ppu_addr_in[12:10];		
			ppu_ciram_a10 = r0[4];
		end
		// Mapper #23 - VRC2b
		if (USE_VRC2 == 1 && mapper == 5'b10111)
		begin
			cpu_addr_mapped = cpu_addr_in[14] ? {5'b11111, cpu_addr_in[13]} : {1'b0, !cpu_addr_in[13] ? r0[4:0] : r1[4:0]};
			if (!flags[1]) // on VRC2a the low bit is ignored
			begin
				case (ppu_addr_in[12:10])
					3'b000: ppu_addr_mapped = r2;
					3'b001: ppu_addr_mapped = r3;
					3'b010: ppu_addr_mapped = r4;
					3'b011: ppu_addr_mapped = r5;
					3'b100: ppu_addr_mapped = r6;
					3'b101: ppu_addr_mapped = r7;
					3'b110: ppu_addr_mapped = r8;
					3'b111: ppu_addr_mapped = r9;
				endcase
			end else begin
				case (ppu_addr_in[12:10])
					3'b000: ppu_addr_mapped = {1'b0, r2[7:1]};
					3'b001: ppu_addr_mapped = {1'b0, r3[7:1]};
					3'b010: ppu_addr_mapped = {1'b0, r4[7:1]};
					3'b011: ppu_addr_mapped = {1'b0, r5[7:1]};
					3'b100: ppu_addr_mapped = {1'b0, r6[7:1]};
					3'b101: ppu_addr_mapped = {1'b0, r7[7:1]};
					3'b110: ppu_addr_mapped = {1'b0, r8[7:1]};
					3'b111: ppu_addr_mapped = {1'b0, r9[7:1]};
				endcase
			end
			ppu_ciram_a10 = r0[7] ? r0[6] : (r0[6] ? ppu_addr_in[11] : ppu_addr_in[10]);
		end
		// Mapper #228 - Cheetahmen II
		if (USE_CHEETAHMEN2 == 1 && mapper == 5'b11111)
		begin
			if (cpu_addr_in[14] == 0 || r1[0])
				cpu_addr_mapped = {r2[4:0], cpu_addr_in[13]};
			else
				cpu_addr_mapped = {r2[4:0] | 1, cpu_addr_in[13]};
			ppu_addr_mapped = {r0[5:0], ppu_addr_in[12:10]};
			ppu_ciram_a10 = !r4[0] ? ppu_addr_in[10] : ppu_addr_in[11];
		end
	end

	// reenable IRQ only when PPU A12 is low
	always @ (*)
	begin
		if (!irq_scanline_enabled)
		begin
			irq_scanline_ready = 0;
			irq_scanline_out = 0;
		end else if (irq_scanline_enabled && !irq_scanline_value)
			irq_scanline_ready = 1;
		else if (irq_scanline_ready && irq_scanline_value)
			irq_scanline_out = 1;
	end
	
	// IRQ counter
	always @ (posedge ppu_addr_in[12])
	begin
		if (a12_low_time == 3)
		begin
			//irq_scanline_counter_last = irq_scanline_counter;
			if ((irq_scanline_reload && !irq_scanline_reload_clear) || (irq_scanline_counter == 0))
			begin
				irq_scanline_counter = r9;
				if (irq_scanline_reload) irq_scanline_reload_clear = 1;
			end else
				irq_scanline_counter = irq_scanline_counter-1;
			if (irq_scanline_counter == 0 && irq_scanline_enabled)
				irq_scanline_value = 1;
			else
				irq_scanline_value = 0;
		end
		if (!irq_scanline_reload) irq_scanline_reload_clear = 0;		
	end
	
	// A12 must be low for 3 rises of M2
	always @ (posedge m2, posedge ppu_addr_in[12])
	begin
		if (ppu_addr_in[12])
			a12_low_time = 0;
		else if (a12_low_time < 3)
			a12_low_time = a12_low_time + 1;
	end
	
endmodule
