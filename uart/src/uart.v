//Assumtion is this is a 9600 
module uart 
  (
   input	clk_i, 
   input	rst_i,
   //
   input [7:0]	data_tx_i,
   input	data_tx_vld_i,
   output	rdy_o,
   //
   output [7:0]	data_rx_o,
   input	data_rx_vld_o,
   //
   output	uart_tx_o, 
   input	uart_rx_i
   );


   parameter	c_BIT_PERIOD     = (100000000/9600);
   parameter	c_BIT_PERIOD_BY2 = c_BIT_PERIOD/2;

   typedef enum logic [2:0] {
			     IDLE_TX,
			     START,
			     SEND_DATA,
			     WAIT_TX,
			     STOP
			     } txstate_t;
   
   typedef enum logic [1:0] {
			     IDLE_RX,
			     WAIT_1BIT_PERIOD,
			     WAIT_HALF_PERIOD,
			     RD_DATA
			     } rxstate_t;

   tx_state_t SM_TX;
   rx_state_t SM_RX;
   
   reg				      uart_rx_1d;
   reg				      uart_rx_2d;
   //
   reg [7:0]			      data_tx;
   //
   reg				      rdy;
   reg				      uart_tx;
   reg [3:0]			      bit_cnt_tx; // Need 4 bits because we are counting till 8
   reg [$clog2(c_BIT_PERIOD) - 1 : 0] cnt_tx;
   reg				      stop;
   //
   reg				      start       ;
   reg [$clog2(c_BIT_PERIOD)-1 : 0]   cnt_rx      ;
   reg [2:0]			      bit_cnt_rx  ;
   reg [7:0]			      data_rx     ;            
   reg				      data_rx_vld ;

   
   

   assign rdy_o         = rdy;
   assign data_rx_o     = data_rx;
   assign data_rx_vld_o = data_rx_vld;
   assign uart_tx_o     = uart_tx;
   


   //------------------------------------------------------------------------------------------
   // double floping the input to prevent metastability.
   // This can be ignored as this is a very slow signals and will be stable when we latch it.
   //------------------------------------------------------------------------------------------   
   always @ (posedge clk_i) begin
      if (rst_i) begin
	 uart_rx_1d <= 1'b0;
	 uart_rx_2d <= 2'b0;
      end
      else begin
	 uart_rx_1d <= uart_rx_i;
	 uart_rx_2d <= uart_rx_1d;
      end
   end

   
   //------------------------------------------------------------------------------------------
   //latching the data in
   //------------------------------------------------------------------------------------------   
   always @(posedge clk_i) begin
      if (rst_i) begin
	 data_tx <= 'd0;
      end
      else begin
	 if (data_tx_vld_i) begin
	    data_tx <= data_tx_i;
	 end
      end
   end
   
   //------------------------------------------------------------------------------------------
   //Generating the Tx. 
   //------------------------------------------------------------------------------------------   
   always @(posedge clk_i) begin
      if (rst_i) begin
	 rdy        <= 1'b1;
	 uart_tx    <= 1'b1;
	 cnt_tx     <= 'd0;
	 bit_cnt_tx <= 'd0;
	 stop       <= 1'b0;
	 SM_TX      <= IDLE_TX;
      end
      else begin
	 case (SM_TX)
	   IDLE_TX :  begin
	      //Nothing to transmit yet.
	      //This block is ready to receive data
	      rdy <= 1'b1;
	      if (data_tx_vld_i) begin
		 SM_TX <= START;
		 rdy   <= 1'b0;
	      end
	      
	   end
	   //------------------------------------------------------------------------------------------   
	   START : begin
	      uart_tx <= 1'b0;
	      //wait for 1 bit period
	      SM_TX <= WAIT_TX;
	   end
	   //------------------------------------------------------------------------------------------   
	   SEND_DATA : begin
	      uart_tx    <= data_tx[bit_cnt_tx];
	      bit_cnt_tx <= bit_cnt_tx + 1'b1;
	      SM_TX      <= WAIT_TX;
	   end
	   //------------------------------------------------------------------------------------------   
	   WAIT_TX : begin
	      cnt_tx <= cnt_tx + 1'b1;
	      if (cnt_tx == c_BIT_PERIOD) begin
		 cnt_tx <= 'd0;

		 SM_TX <= SEND_DATA;
		 // Check whether the transfer has finished.
		 if (bit_cnt_tx == 8) begin
		    SM_TX      <= STOP;
		    bit_cnt_tx <= 'd0;
		 end

		 if (stop == 1'b1)begin
		    SM_TX <= IDLE_TX;
		    stop  <= 1'b0;
		 end	 
	      end
	   end
	   //------------------------------------------------------------------------------------------   
	   //STOP
	   default : begin
	      uart_tx <= 1'b1;
	      stop    <= 1'b1;
	      SM_TX   <= WAIT_TX;
	   end
	 endcase // case SM_TX
	 
      end
   end


    //------------------------------------------------------------------------------------------
   // Reading the data received from Rx pin
   //------------------------------------------------------------------------------------------   
    always @(posedge clk_i) begin
       if (rst_i) begin
	  start         <= 1'b0;
	  cnt_rx        <= 'd0;
	  bit_cnt_rx    <= 'd0;
	  data_rx       <= 'd0;            
	  data_rx_vld   <= 'd0;
	  
	  SM_RX               <= IDLE_RX;
	 
      end
      else begin
	 case (SM_RX)
	   IDLE_RX : begin
	      //making sure that vld is set only for 1 clk cycle.
	      data_rx_vld         <= 1'b0;
	      if (uart_rx_3d == 1'b0  && uart_rx_2d == 1'b1) begin
		 //wait for 1 bit period
		 SM_RX  <= WAIT_1BIT_PERIOD;
		 start  <= 1'b1;
	      end
	   end
	   //------------------------------------------------------------------------------------------   
	   WAIT_1BIT_PERIOD : begin
	      cnt_rx <= cnt_rx + 1'b1;
	      if (cnt_rx == c_BIT_PERIOD) begin
		 cnt_rx  <= 'd0;
		 SM_RX   <= RD_DATA;
		 if (start == 1'b1) begin
		    SM_RX  <= WAIT_HALF_PERIOD;
		    start  <= 1'b0;
		 end
	      end
	   end // case: WAIT_1BIT_PERIOD
	   //------------------------------------------------------------------------------------------   
	   WAIT_HALF_PERIOD : begin
	      cnt_rx <= cnt_rx + 1'b1;
	      if (cnt_rx == c_BIT_PERIOD_BY2)begin
		 cnt_rx <= 'd0;
		 SM_RX  <= RD_DATA;
		 
	      end
	   end
	   //------------------------------------------------------------------------------------------   
	   //LATCH data
	   default : begin
	      data_rx[bit_cnt_rx] <= uart_rx_2d;
	      SM_RX               <= WAIT_1BIT_PERIOD;
	      bit_cnt_rx          <= bit_cnt_rx + 1'b1;

	      //When we received 8 bits, we can go back to IDLE and wait.
	      if (bit_cnt_rx == 'd7) begin
		 bit_cnt_rx          <= 'd0;
		 data_rx_vld         <= 1'b1;
		 SM_RX               <= IDLE_RX;
		 
	      end
	   end
	   
	 endcase // case (SM_RX)
	 
      end
   end
  
endmodule // uart

