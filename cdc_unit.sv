`include "audioport.svh"

import audioport_pkg::*;

module cdc_unit
  (
   input logic 	       clk,
   input logic 	       rst_n,
   input logic 	       test_mode_in,
   input logic [23:0]  audio0_in,
   input logic [23:0]  audio1_in,
   input logic 	       play_in,
   input logic 	       tick_in,
   output logic        req_out,

   input logic 	       mclk,
   output logic        muxclk_out,
   output logic        muxrst_n_out,
   output logic [23:0] audio0_out,
   output logic [23:0] audio1_out, 
   output logic        play_out,
   output logic        tick_out,
   input logic 	       req_in		
   );
   
   logic 	       mrst_n;
//   logic 	       muxrst_n;
//   logic 	       muxclk;
   logic 	       rsync_clk;
   
// =========================================================================
   // FEATURE: TESTMUX
   // Three multiplexers controlled by test_mode_in.
   // Using the ternary operator: (condition) ? (value_if_true) : (value_if_false)
   // =========================================================================

   // MUX A: Selects the main clock for the mclk domain
   assign muxclk_out   = test_mode_in ? clk : mclk;

   // MUX B: Selects the clock specifically for the Reset Synchronizer
   assign rsync_clk    = test_mode_in ? clk : ~mclk;

   // MUX C: Selects the reset signal for the mclk domain
   assign muxrst_n_out = test_mode_in ? rst_n : mrst_n;
// =========================================================================
   // FEATURE: RESET SYNCHRONIZER
   // Safely passes the rst_n signal into the mclk domain.
   // Asynchronous assertion (instant 0), Synchronous de-assertion (delayed 1).
   // =========================================================================
   
   // Declare the intermediate wire for the first flip-flop
   logic mrst_n_sff1;

   always_ff @(posedge rsync_clk or negedge rst_n) begin
      if (!rst_n) begin
         // Asynchronous Reset: Instantly force both flip-flops to 0
         mrst_n_sff1 <= 1'b0;
         mrst_n      <= 1'b0;
      end else begin
         // Synchronous Release: Clock a constant '1' through the flip-flops
         mrst_n_sff1 <= 1'b1;        // First flip-flop grabs a 1
         mrst_n      <= mrst_n_sff1; // Second flip-flop grabs the output of the first
      end
   end
   // =========================================================================
   // FEATURE: 1-BIT SYNCHRONIZER (bit_sync)
   // Safely passes the steady play_in signal into the mclk domain.
   // Uses a standard 2-Flip-Flop synchronizer.
   // =========================================================================
   
   // Declare the intermediate wire for the first flip-flop
   logic play_sff1;

   // Powered by the RECEIVING domain's clock and reset
   always_ff @(posedge muxclk_out or negedge muxrst_n_out) begin
      if (!muxrst_n_out) begin
         // Reset state: clear the flip-flops
         play_sff1 <= 1'b0;
         play_out  <= 1'b0;
      end else begin
         // Shift the data through the two flip-flops
         play_sff1 <= play_in;     // Stage 1 catches the incoming signal
         play_out  <= play_sff1;   // Stage 2 safely outputs it
      end
   end
// =========================================================================
   // FEATURE: PULSE SYNCHRONIZER (req_sync)
   // Safely passes the wide req_in pulse into the fast clk domain.
   // Uses a 2-FF synchronizer + 1-FF delay to create an edge detector.
   // =========================================================================
   
   // Declare the intermediate wires for the three flip-flops
   logic req_sff1; // Stage 1
   logic req_sff2; // Stage 2 (Current safely synchronized state)
   logic req_sff3; // Stage 3 (Previous state, delayed by 1 cycle)

   // Powered by the RECEIVING domain's clock and reset
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         req_sff1 <= 1'b0;
         req_sff2 <= 1'b0;
         req_sff3 <= 1'b0;
      end else begin
         // Shift the data through the three flip-flops
         req_sff1 <= req_in;   // Catch the incoming wide pulse
         req_sff2 <= req_sff1; // Clean it up (Current State)
         req_sff3 <= req_sff2; // Remember it for next time (Previous State)
      end
   end

   // Edge Detection Logic (Combinational)
   // Output is 1 ONLY when Current State is 1 AND Previous State is 0
   assign req_out = req_sff2 & ~req_sff3;

// =========================================================================
   // AUDIO_SYNC: FSM-BASED HANDSHAKE 
   // =========================================================================

   // 1. Internal Registers & States
   typedef enum logic [1:0] {TX_IDLE, TX_REQ, TX_ACK} tx_state_t;
   typedef enum logic [1:0] {RX_IDLE, RX_ACK} tx_rx_t;

   tx_state_t tx_state;
   tx_rx_t    rx_state;

   logic [47:0] tx_r; // Data register in clk domain
   logic [47:0] rx_r; // Data register in muxclk_out domain
   logic        req, sack;
   logic        ack, sreq;

   // 2. Synchronizers (The Yellow Diamonds in your slides)
   logic rff1, rff2; // req -> sreq
   logic aff1, aff2; // ack -> sack

   always_ff @(posedge muxclk_out or negedge muxrst_n_out) begin
      if (!muxrst_n_out) {rff1, rff2} <= 2'b0;
      else               {rff1, rff2} <= {req, rff1};
   end
   assign sreq = rff2;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) {aff1, aff2} <= 2'b0;
      else        {aff1, aff2} <= {ack, aff1};
   end
   assign sack = aff2;

   // 3. TX FSM (clk domain)
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         tx_state <= TX_IDLE;
         req      <= 1'b0;
         tx_r     <= 48'b0;
      end else begin
         case (tx_state)
            TX_IDLE: begin
               if (tick_in && !sack) begin
                  tx_r     <= {audio0_in, audio1_in};
                  req      <= 1'b1;
                  tx_state <= TX_REQ;
               end
            end
            TX_REQ: begin
               if (sack) tx_state <= TX_ACK;
            end
            TX_ACK: begin
               req <= 1'b0;
               if (!sack) tx_state <= TX_IDLE;
            end
            // ADD THIS DEFAULT CASE:
            default: begin
               tx_state <= TX_IDLE;
               req      <= 1'b0;
            end
         endcase
      end
   end

   // 4. RX FSM (muxclk_out domain)
   always_ff @(posedge muxclk_out or negedge muxrst_n_out) begin
      if (!muxrst_n_out) begin
         rx_state <= RX_IDLE;
         ack      <= 1'b0;
         rx_r     <= 48'b0;
         tick_out <= 1'b0;
      end else begin
         tick_out <= 1'b0; // Default
         case (rx_state)
            RX_IDLE: begin
               if (sreq) begin
                  rx_r     <= tx_r;
                  ack      <= 1'b1;
                  rx_state <= RX_ACK;
               end
            end
            RX_ACK: begin
               if (!sreq) begin
                  tick_out <= 1'b1;
                  ack      <= 1'b0;
                  rx_state <= RX_IDLE;
               end
            end
            // ADD THIS DEFAULT CASE:
            default: begin
               rx_state <= RX_IDLE;
               ack      <= 1'b0;
            end
         endcase
      end
   end

   assign {audio0_out, audio1_out} = rx_r;
endmodule





