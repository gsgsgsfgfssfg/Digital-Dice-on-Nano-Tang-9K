// Digital Dice for the Tang Nano 9K (27 MHz system clock).
// All logic uses the system clock; enables control button and LFSR rates.

module top #(
	parameter integer CLOCK_HZ = 27000000,
	parameter integer ROLL_STEP_HZ = 1000,
	parameter integer DEBOUNCE_MS = 20
) (
	input  wire       clk,
	input  wire       btn_roll_n,
	input  wire       btn_reset_n,
	output wire [5:0] led
);

	wire reset_sync_n;
	wire roll_sync_n;
	wire roll_pressed;
	wire roll_released;
	wire roll_step_ce;
	wire lfsr_enable;
	wire [2:0] random_state;
	wire [2:0] dice_value;

	button_sync reset_button_sync (
		.clk(clk),
		.button_n_async(btn_reset_n),
		.button_n_sync(reset_sync_n)
	);

	button_sync roll_button_sync (
		.clk(clk),
		.button_n_async(btn_roll_n),
		.button_n_sync(roll_sync_n)
	);

	button_debounce #(
		.CLOCK_HZ(CLOCK_HZ),
		.DEBOUNCE_MS(DEBOUNCE_MS)
	) roll_button_debounce (
		.clk(clk),
		.reset_n(reset_sync_n),
		.button_n_sync(roll_sync_n),
		.button_n( ),
		.pressed_pulse(roll_pressed),
		.released_pulse(roll_released)
	);

	clock_enable #(
		.CLOCK_HZ(CLOCK_HZ),
		.ENABLE_HZ(ROLL_STEP_HZ)
	) roll_rate_enable (
		.clk(clk),
		.reset_n(reset_sync_n),
		.enable_pulse(roll_step_ce)
	);

	dice_controller controller (
		.clk(clk),
		.reset_n(reset_sync_n),
		.roll_pressed(roll_pressed),
		.roll_released(roll_released),
		.roll_step_ce(roll_step_ce),
		.random_state(random_state),
		.lfsr_enable(lfsr_enable),
		.dice_value(dice_value)
	);

	lfsr_3bit random_generator (
		.clk(clk),
		.reset_n(reset_sync_n),
		.enable(lfsr_enable && roll_step_ce),
		.state(random_state)
	);

	dice_decoder display_decoder (
		.value(dice_value),
		.led(led)
	);

endmodule


// Two-flop synchronizer for an asynchronous active-low button input.
module button_sync (
	input  wire clk,
	input  wire button_n_async,
	output reg  button_n_sync
);
	reg button_n_meta;

	always @(posedge clk) begin
		button_n_meta <= button_n_async;
		button_n_sync <= button_n_meta;
	end
endmodule


// Debounces a synchronized active-low button and emits one-cycle edge events.
module button_debounce #(
	parameter integer CLOCK_HZ = 27000000,
	parameter integer DEBOUNCE_MS = 20,
	parameter integer DEBOUNCE_CYCLES = (CLOCK_HZ / 1000) * DEBOUNCE_MS
) (
	input  wire clk,
	input  wire reset_n,
	input  wire button_n_sync,
	output reg  button_n,
	output reg  pressed_pulse,
	output reg  released_pulse
);
	localparam integer COUNT_WIDTH = (DEBOUNCE_CYCLES <= 1)
		? 1 : $clog2(DEBOUNCE_CYCLES);

	reg [COUNT_WIDTH-1:0] stable_count;

	always @(posedge clk) begin
		if (!reset_n) begin
			button_n <= 1'b1;
			stable_count <= {COUNT_WIDTH{1'b0}};
			pressed_pulse <= 1'b0;
			released_pulse <= 1'b0;
		end else begin
			pressed_pulse <= 1'b0;
			released_pulse <= 1'b0;

			if (button_n_sync == button_n) begin
				stable_count <= {COUNT_WIDTH{1'b0}};
			end else if (stable_count == DEBOUNCE_CYCLES - 1) begin
				button_n <= button_n_sync;
				stable_count <= {COUNT_WIDTH{1'b0}};
				if (button_n_sync == 1'b0)
					pressed_pulse <= 1'b1;
				else
					released_pulse <= 1'b1;
			end else begin
				stable_count <= stable_count + 1'b1;
			end
		end
	end
endmodule


// Produces a one-cycle enable at the requested rate without making a new clock.
module clock_enable #(
	parameter integer CLOCK_HZ = 27000000,
	parameter integer ENABLE_HZ = 1000,
	parameter integer DIVISOR = CLOCK_HZ / ENABLE_HZ
) (
	input  wire clk,
	input  wire reset_n,
	output reg  enable_pulse
);
	localparam integer COUNT_WIDTH = (DIVISOR <= 1) ? 1 : $clog2(DIVISOR);
	reg [COUNT_WIDTH-1:0] divider_count;

	always @(posedge clk) begin
		if (!reset_n) begin
			divider_count <= {COUNT_WIDTH{1'b0}};
			enable_pulse <= 1'b0;
		end else if (divider_count == DIVISOR - 1) begin
			divider_count <= {COUNT_WIDTH{1'b0}};
			enable_pulse <= 1'b1;
		end else begin
			divider_count <= divider_count + 1'b1;
			enable_pulse <= 1'b0;
		end
	end
endmodule


// Controls rolling, capturing a valid random state, and retaining the result.
module dice_controller (
	input  wire       clk,
	input  wire       reset_n,
	input  wire       roll_pressed,
	input  wire       roll_released,
	input  wire       roll_step_ce,
	input  wire [2:0] random_state,
	output wire       lfsr_enable,
	output reg  [2:0] dice_value
);
	localparam [1:0] IDLE = 2'b00;
	localparam [1:0] ROLLING = 2'b01;
	localparam [1:0] DISPLAY = 2'b10;

	reg [1:0] state;

	assign lfsr_enable = (state == ROLLING) && roll_step_ce;

	always @(posedge clk) begin
		if (!reset_n) begin
			state <= IDLE;
			dice_value <= 3'b001;
		end else begin
			case (state)
				IDLE: begin
					if (roll_pressed)
						state <= ROLLING;
				end

				ROLLING: begin
					if (roll_released) begin
						if ((random_state >= 3'b001) && (random_state <= 3'b110))
							dice_value <= random_state;
						else
							dice_value <= 3'b001;
						state <= DISPLAY;
					end
				end

				DISPLAY: begin
					if (roll_pressed)
						state <= ROLLING;
				end

				default: begin
					state <= IDLE;
					dice_value <= 3'b001;
				end
			endcase
		end
	end
endmodule


// Six-state LFSR sequence. The 111 transition is skipped, so state is always
// a directly usable dice value from 001 through 110 after reset.
module lfsr_3bit (
	input  wire       clk,
	input  wire       reset_n,
	input  wire       enable,
	output reg  [2:0] state
);
	reg [2:0] candidate;

	always @* begin
		candidate = {state[1:0], state[2] ^ state[0]};
		if (candidate == 3'b111)
			candidate = {candidate[1:0], candidate[2] ^ candidate[0]};
		if (candidate == 3'b000)
			candidate = 3'b001;
	end

	always @(posedge clk) begin
		if (!reset_n)
			state <= 3'b001;
		else if (enable)
			state <= candidate;
	end
endmodule


// Maps dice values to physical LED positions. LED order is laid out as:
// LED0 LED1 / LED2 LED3 / LED4 LED5. Change only this table for board wiring.
module dice_decoder (
	input  wire [2:0] value,
	output reg  [5:0] led
);
	always @* begin
		case (value)
			3'd1: led = 6'b111110;
			3'd2: led = 6'b111100;
			3'd3: led = 6'b111000;
			3'd4: led = 6'b110000;
			3'd5: led = 6'b100000;
			3'd6: led = 6'b000000;
			default: led = 6'b111111;
		endcase
	end
endmodule
