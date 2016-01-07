/* Copyright (c) 2016 by the author(s)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * =============================================================================
 *
 * Control layer between interface and the FIFOs that handles control messages
 * like credits etc.
 *
 * Author(s):
 *   Stefan Wallentowitz <stefan@wallentowitz.de>
 */

module glip_uart_control
  #(parameter FIFO_CREDIT_WIDTH = 1'bx,
    parameter INPUT_FIFO_CREDIT = 1'bx,
    parameter FREQ = 1'bx)
   (
    input 	 clk,
    input 	 rst,

    input [7:0]  ingress_in_data,
    input 	 ingress_in_valid,
    output 	 ingress_in_ready,

    output [7:0] ingress_out_data,
    output 	 ingress_out_valid,
    input 	 ingress_out_ready,

    input [7:0]  egress_in_data,
    input 	 egress_in_valid,
    output 	 egress_in_ready,

    output [7:0] egress_out_data,
    output 	 egress_out_enable,
    input 	 egress_out_done,

    output 	 logic_rst,
    output 	 error
    );

   wire [3:0] 	     mod_error; 	     

   wire 	     transfer_egress;
   wire 	     transfer_ingress;

   wire 	     can_send;
   wire [13:0] 	     debt;
   wire 	     debt_en;

   wire [FIFO_CREDIT_WIDTH-1:0] credit;
   reg 				credit_en;
   wire 			credit_ack;
   reg 				get_credit;
   wire 			get_credit_ack;   
   
   reg 				ctrl_rst;
   wire 			ctrl_rst_en;
   wire 			ctrl_rst_val;
   assign logic_rst = rst | ctrl_rst;
   
   assign error = |mod_error;
   
   reg [FIFO_CREDIT_WIDTH-1:0] 	transfer_counter;
   reg [FIFO_CREDIT_WIDTH-1:0] 	nxt_transfer_counter;
   
   reg 				send_credit_pnd;
   reg 				nxt_send_credit_pnd;
   reg 				nxt_get_credit;
   
   always @(posedge clk) begin
      if (logic_rst) begin
	 transfer_counter <= 0;
	 send_credit_pnd <= 0;
	 get_credit <= 0;
      end else begin
	 transfer_counter <= nxt_transfer_counter;
	 send_credit_pnd <= nxt_send_credit_pnd;
	 get_credit <= nxt_get_credit;
      end
   end
   
   always @(*) begin
      nxt_send_credit_pnd = send_credit_pnd;
      nxt_get_credit = get_credit;
      nxt_transfer_counter = transfer_counter;

      credit_en = 0;
      nxt_get_credit = get_credit;
      
      if (send_credit_pnd) begin
	 if (get_credit) begin
	    if (get_credit_ack) begin
	       nxt_get_credit = 0;
	       credit_en = 1;
	    end
	 end else begin
	    credit_en = 1;
	    if (credit_ack) begin
	       nxt_send_credit_pnd = 0;
	    end
	 end // else: !if(get_credit)

	 if (transfer_counter != 0) begin
	    if (transfer_ingress) begin
	       nxt_transfer_counter = transfer_counter - 1;
	    end
	 end
      end else begin
	 if (transfer_counter == 0) begin
	    nxt_transfer_counter = INPUT_FIFO_CREDIT >> 1;
            nxt_send_credit_pnd = 1;
            nxt_get_credit = 1;
         end

	 if (transfer_ingress) begin
	    nxt_transfer_counter = nxt_transfer_counter - 1;
	 end
      end
   end

   always @(posedge clk) begin
      if (rst) begin
	 ctrl_rst <= 0;
      end else begin
	 if (ctrl_rst_en) begin
	    ctrl_rst <= ctrl_rst_val;
	 end
      end
   end
   
   /* debtor AUTO_TEMPLATE(
    .rst     (logic_rst),
    .owing   (can_send),
    .error   (mod_error[3]),
    .payback (transfer_egress),
    .tranche (debt),
    .lend    (debt_en),
    ); */
   debtor
     #(.WIDTH(15), .TRANCHE_WIDTH(14))
   u_debtor(/*AUTOINST*/
	    // Outputs
	    .owing			(can_send),		 // Templated
	    .error			(mod_error[3]),		 // Templated
	    // Inputs
	    .clk			(clk),
	    .rst			(logic_rst),		 // Templated
	    .payback			(transfer_egress),	 // Templated
	    .tranche			(debt),			 // Templated
	    .lend			(debt_en));		 // Templated

   /* creditor AUTO_TEMPLATE(
    .rst     (logic_rst),
    .payback (transfer_ingress),
    .borrow  (get_credit),
    .grant   (get_credit_ack),
    .error   (mod_error[2]),
    .credit  (credit[FIFO_CREDIT_WIDTH-1:0]),
    ); */
   creditor
     #(.WIDTH(15), .CREDIT_WIDTH(FIFO_CREDIT_WIDTH),
       .INITIAL_VALUE(INPUT_FIFO_CREDIT))
   u_creditor(/*AUTOINST*/
	      // Outputs
	      .credit			(credit[FIFO_CREDIT_WIDTH-1:0]), // Templated
	      .grant			(get_credit_ack),	 // Templated
	      .error			(mod_error[2]),		 // Templated
	      // Inputs
	      .clk			(clk),
	      .rst			(logic_rst),		 // Templated
	      .payback			(transfer_ingress),	 // Templated
	      .borrow			(get_credit));		 // Templated
   
   /* glip_uart_control_egress AUTO_TEMPLATE(
    .in_\(.*\)  (egress_in_\1),
    .out_\(.*\) (egress_out_\1),
    .transfer   (transfer_egress),
    .error      (mod_error[1]),
    .credit     ({{15-FIFO_CREDIT_WIDTH{1'b0}},credit}),
    ); */
   glip_uart_control_egress
     u_egress(/*AUTOINST*/
	      // Outputs
	      .in_ready			(egress_in_ready),	 // Templated
	      .out_data			(egress_out_data),	 // Templated
	      .out_enable		(egress_out_enable),	 // Templated
	      .transfer			(transfer_egress),	 // Templated
	      .credit_ack		(credit_ack),
	      .error			(mod_error[1]),		 // Templated
	      // Inputs
	      .clk			(clk),
	      .rst			(rst),
	      .in_data			(egress_in_data),	 // Templated
	      .in_valid			(egress_in_valid),	 // Templated
	      .out_done			(egress_out_done),	 // Templated
	      .can_send			(can_send),
	      .credit			({{15-FIFO_CREDIT_WIDTH{1'b0}},credit}), // Templated
	      .credit_en		(credit_en));

   /* glip_uart_control_ingress AUTO_TEMPLATE(
    .in_\(.*\)  (ingress_in_\1),
    .out_\(.*\) (ingress_out_\1),
    .credit_val (debt),
    .credit_en  (debt_en),
    .transfer   (transfer_ingress),
    .error      (mod_error[0]),
    .rst_en     (ctrl_rst_en),
    .rst_val    (ctrl_rst_val),
    ); */
   glip_uart_control_ingress
     u_ingress(/*AUTOINST*/
	       // Outputs
	       .in_ready		(ingress_in_ready),	 // Templated
	       .out_data		(ingress_out_data),	 // Templated
	       .out_valid		(ingress_out_valid),	 // Templated
	       .transfer		(transfer_ingress),	 // Templated
	       .credit_en		(debt_en),		 // Templated
	       .credit_val		(debt),			 // Templated
	       .rst_en			(ctrl_rst_en),		 // Templated
	       .rst_val			(ctrl_rst_val),		 // Templated
	       .error			(mod_error[0]),		 // Templated
	       // Inputs
	       .clk			(clk),
	       .rst			(rst),
	       .in_data			(ingress_in_data),	 // Templated
	       .in_valid		(ingress_in_valid),	 // Templated
	       .out_ready		(ingress_out_ready));	 // Templated

endmodule

// Local Variables:
// verilog-library-directories:("." "../../../common/logic/credit/verilog")
// End:
