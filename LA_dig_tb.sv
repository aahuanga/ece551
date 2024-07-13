///////////////////////////////////////////////////////////////////////
// Logic Analyzer testbench to verify cmd, triggering, read, write, //
// and dump functionality using UART and SPI trigger protocols.    //
////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps
module LA_dig_tb();

  /******************************
  *        DECLARATIONS         *
  ******************************/
  // testing variables
  integer test_counter = 0;
  integer tests_passed = 0;
  logic success = 1;
  logic [7:0] test_match, test_mask;
  logic [15:0] tx_baud;
  reg [7:0] test_baud_rates_HIGH[5] = {8'h00, 8'h00, 8'h00, 8'h00, 8'hFF};
  reg [7:0] test_baud_rates_LOW[5] = {8'h6C, 8'h95, 8'hA3, 8'h00, 8'hFF};
  reg [7:0] test_registers[17] = {8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F, 8'h10};
  integer reg_cnt;
  logic [15:0] SPI_tx_data = 16'hABCD;
  logic SPI_edge, SPI_width8;

  //// Interconnects to DUT/support defined as type wire /////
  wire clk400MHz, locked;			                                         // PLL output signals to DUT
  wire clk;						                                                 // 100MHz clock generated at this level from clk400MHz
  wire VIH_PWM, VIL_PWM;			                                         // connect to PWM outputs to monitor
  wire CH1L, CH1H, CH2L, CH2H, CH3L;	                                 // channel data inputs from AFE model
  wire CH3H, CH4L, CH4H, CH5L, CH5H;	                                 // channel data inputs from AFE model
  wire RX, TX;						                                             // interface to host
  wire cmd_sent, resp_rdy;			                                       // from master UART, monitored in test bench
  wire [7:0] resp;				                                             // from master UART,  reponse received from DUT
  wire tx_prot;					                                               // UART signal for protocol triggering
  wire SS_n, SCLK, MOSI;			                                         // SPI signals for SPI protocol triggering
  wire CH1L_mux, CH1H_mux;                                             // output of muxing logic for CH1 to enable testing of protocol triggering
  wire CH2L_mux, CH2H_mux;			                                       // output of muxing logic for CH2 to enable testing of protocol triggering
  wire CH3L_mux, CH3H_mux;			                                       // output of muxing logic for CH3 to enable testing of protocol triggering

  ////// Stimulus is declared as type reg ///////
  reg REF_CLK;
  reg RST_n;
  reg [15:0] host_cmd;			                                           // command host is sending to DUT
  reg send_cmd;					                                               // asserted to initiate sending of command
  reg clr_resp_rdy;				                                             // asserted to knock down resp_rdy
  reg [1:0] clk_div;			                                             // counter used to derive 100MHz clk from clk400MHz
  reg strt_tx;					                                               // kick off unit used for protocol triggering
  reg en_AFE;
  reg capture_done_bit;			                                           // flag used in polling for capture_done
  reg [7:0] res;
  reg [7:0] exp;				                                               // used to store result and expected read from files
  wire AFE_clk;

  // dump pointers/vars, more file handles for dumps of other channels???
  integer fptr1;		                                                   // file pointer for CH1 dumps
  integer fexp;		                                                     // file pointer to file with expected results
  integer found_res, found_expected, loop_cnt;
  integer mismatches;	                                                 // number of mismatches when comparing results to expected
  integer sample;		                                                   // sample counter in dump & compare

  // Triggering settings
  logic UART_triggering;	                                             // set to true if testing UART based triggering
  logic SPI_triggering;	                                               // set to true if testing SPI based triggering

  /*************************************
  *        MODULE INSTANTIATIONS       *
  *************************************/
  ///// Instantiate Analog Front End model (provides stimulus to channels) ///////
  AFE iAFE(
    .smpl_clk(AFE_clk), .VIH_PWM(VIH_PWM), .VIL_PWM(VIL_PWM), 
    .CH1L(CH1L), .CH1H(CH1H), .CH2L(CH2L), .CH2H(CH2H), .CH3L(CH3L), 
    .CH3H(CH3H), .CH4L(CH4L), .CH4H(CH4H), .CH5L(CH5L), .CH5H(CH5H)
  );

  ////// Instantiate DUT ////////		  
  LA_dig iDUT(
    .clk400MHz(clk400MHz), .RST_n(RST_n), .locked(locked), 
    .VIH_PWM(VIH_PWM), .VIL_PWM(VIL_PWM), .CH1L(CH1L_mux), .CH1H(CH1H_mux), 
    .CH2L(CH2L_mux), .CH2H(CH2H_mux), .CH3L(CH3L_mux), .CH3H(CH3H_mux), .CH4L(CH4L), 
    .CH4H(CH4H), .CH5L(CH5L), .CH5H(CH5H), .RX(RX), .TX(TX),  .LED()
  );

  ///// Instantiate PLL to provide 400MHz clk from 50MHz ///////
  pll8x iPLL(
    .ref_clk(REF_CLK), .RST_n(RST_n), .out_clk(clk400MHz), .locked(locked)
  );

  //// Instantiate Master UART (mimics host commands) //////
  ComSender iSNDR(
    .clk(clk), .rst_n(RST_n), .RX(TX), .TX(RX),
    .cmd(host_cmd), .send_cmd(send_cmd),
    .cmd_sent(cmd_sent), .resp_rdy(resp_rdy),
    .resp(resp), .clr_resp_rdy(clr_resp_rdy)
  );
            
  // Instantiate UART transmitter as source for UART protocol triggering
  UART_tx_cfg_bd iTX(
    .clk(clk), .rst_n(RST_n), .TX(tx_prot), .trmt(strt_tx),
    .tx_data(8'h96), .tx_done(), .baud(tx_baud)
  ); // 921600 Baud
            
  // Instantiate SPI transmitter as source for SPI protocol triggering
  SPI_TX iSPI(
    .clk(clk), .rst_n(RST_n), .SS_n(SS_n), .SCLK(SCLK), .wrt(strt_tx), .done(done), 
    .tx_data(SPI_tx_data), .MOSI(MOSI), .pos_edge(SPI_edge), .width8(SPI_width8)
  );

  /*****************************************
  *        CONTINUOUS ASSIGNMENTS          *
  *****************************************/
  assign AFE_clk = en_AFE & clk400MHz;
  assign test_mode = UART_triggering ? 2 :
                     SPI_triggering ? 1 : 
                     0;
      
  //// Mux for muxing in protocol triggering for CH1 /////
  assign {CH1H_mux, CH1L_mux} = (UART_triggering) ? {2{tx_prot}} :		 // assign to output of UART_tx used to test UART triggering
                                (SPI_triggering) ? {2{SS_n}} : 			   // assign to output of SPI SS_n if SPI triggering
                                {CH1H, CH1L};

  //// Mux for muxing in protocol triggering for CH2 /////
  assign {CH2H_mux, CH2L_mux} = (SPI_triggering) ? {2{SCLK}} : 			   // assign to output of SPI SCLK if SPI triggering
                                {CH2H, CH2L};	

  //// Mux for muxing in protocol triggering for CH3 /////
  assign {CH3H_mux, CH3L_mux} = (SPI_triggering) ? {2{MOSI}} : 			   // assign to output of SPI MOSI if SPI triggering
                                {CH3H, CH3L};					  
  
  // drive reference clock
  always #200 REF_CLK = ~REF_CLK;

  // divide 400MHz clock to obtain system clock
  always @(posedge clk400MHz, negedge locked) begin
    if (~locked) clk_div <= 2'b00;
    else clk_div <= clk_div + 1;
  end
  assign clk = clk_div[1];

  // check for negack at all times
  always @(posedge clk) begin
    if (resp === 8'hEE && success) begin
      $display("ERR: Negative acknowledgement received with host_cmd 0x%4h and host_cmd[13:8] b%6b.", host_cmd, host_cmd[13:8]);
      success = 0;
    end
  end

  /*********************
  *        TASKS       *
  *********************/
  task init_test();
    begin
      test_counter = test_counter + 1;
      if (!UART_triggering && !SPI_triggering) $display("\nNow initiating test %0d using default triggering...", test_counter);
      else if (UART_triggering && !SPI_triggering) $display("\nNow initiating test %0d using UART-based triggering...", test_counter);
      else if (SPI_triggering && !UART_triggering) $display("\nNow initiating test %0d using SPI-based triggering...", test_counter);
      else $display("Unknown test mode.");
    end
  endtask

  task send_command_and_wait_for_response();
    begin
      // display facts about the command
      case (host_cmd[15:14])
          2'b00: $display("Read command initiated...");
          2'b01: $display("Write command initiated...");
          2'b10: $display("Dump command initiated...");
          default: $display("ERR: undefined command type."); 
      endcase

      @(posedge clk);
      send_cmd = 1;
      @(posedge clk);
      send_cmd = 0;
      @(posedge cmd_sent);
      @(posedge clk);
      if (host_cmd[15:14] != 2'b10) @(posedge resp_rdy);

      // if a write, make sure that a positive acknowledgement is received
      if (host_cmd[15:14] == 2'b01) begin
          if (resp !== 8'hA5) $display("Positive acknowledgement expected, received %2h.", resp);
          else $display("Command executed with 0xA5 response.");
      end
    end
  endtask

  task wait_for_capture_done();
    begin
      $display("Waiting for capture done to be set, will time out after 200 loops...");

      // Now read trig config polling for capture_done bit to be set
      capture_done_bit = 1'b0;			                                                        // capture_done not set yet
      loop_cnt = 0;

      // POLLING LOOP
      while (!capture_done_bit) begin
        repeat (400) @(posedge clk);		                                                    // delay a while between reads
        loop_cnt = loop_cnt + 1;
        if (loop_cnt > 200) begin // change later once it works
            $display("ERROR: capture done bit never set.");
            $stop();
        end

        host_cmd = {8'h00, 8'h00};
        send_command_and_wait_for_response();

        // is capture_done bits set?
        if (resp & 8'h20) capture_done_bit = 1'b1;                                              // check the sixth bit of resp, which is TrigCfg
        else if (!(loop_cnt % 5)) $display("Loop count %0d: response received was %8b, waiting for sixth bit to be 1...", loop_cnt, resp);

        clr_resp_rdy = 1;
        @(posedge clk);
        clr_resp_rdy = 0;
      end
      $display("Capture done bit has been set.");
      if (UART_triggering || SPI_triggering) tests_passed = tests_passed + 1;
    end
  endtask

  task collect_dump();
    begin
      $display("Requesting CH1 dump...");

      // Now collect CH1 dump into a file
      $display("Collecting CH1 dump into file...");
      for (sample = 0; sample < 384; sample++) fork
        begin: timeout1
          repeat (6000) @(posedge clk);
          $display("ERROR: Timeout (only received %0d of 384 bytes on dump).", sample);
          $stop();
          sample = 384;		                                                                // break out of loop
        end
        begin
          @(posedge resp_rdy);
          disable timeout1;
          $fdisplay(fptr1, "%h", resp);	                                                    // write to CH1dmp.txt
          clr_resp_rdy = 1;
          @(posedge clk);
          clr_resp_rdy = 0;
          if (sample % 32 == 0) $display("At sample %0d of dump... ", sample);
        end
      join
      repeat(10) @(posedge clk);
      $fclose(fptr1);
    end
  endtask

  task compare_dump();
    begin
      $display("Now comparing dump to expected results...");
        fexp = $fopen("test1_expected.txt","r");
        fptr1 = $fopen("CH1dmp.txt","r");
        found_res = $fscanf(fptr1, "%h", res);
        found_expected = $fscanf(fexp, "%h", exp);
        $display("Starting comparison for CH1...");
        sample = 1;
        mismatches = 0;
        while (found_expected == 1) begin
          if (res !== exp) mismatches = mismatches + 1;
          sample = sample + 1;
          found_res = $fscanf(fptr1, "%h", res);
          found_expected = $fscanf(fexp, "%h", exp);
        end
        if (mismatches > 0) $display("*** Test %0d failed with %0d mismatches! ***", test_counter, mismatches);
        else tests_passed = tests_passed + 1;
    end
  endtask
  
  task read_all_registers();
    begin
      $display("Now reseting all register...");
      // reset
      RST_n = 0;
      repeat (2) @(posedge REF_CLK);
      @(negedge REF_CLK);
      RST_n = 1;
      @(negedge REF_CLK);
      mismatches = 0;
      
      $display("Now reading all register...");
      for (reg_cnt = 6'h00; reg_cnt < 6'h11; reg_cnt++) begin
      host_cmd = {2'h0, reg_cnt, 8'h00};
      send_command_and_wait_for_response();
      
      case(reg_cnt)
          6'h00: if(resp != 6'h03) mismatches = mismatches + 1; 
          6'h01: if(resp != 5'h01) mismatches = mismatches + 1; 
          6'h02: if(resp != 5'h01) mismatches = mismatches + 1;
          6'h03: if(resp != 5'h01) mismatches = mismatches + 1;
          6'h04: if(resp != 5'h01) mismatches = mismatches + 1;
          6'h05: if(resp != 5'h01) mismatches = mismatches + 1;
          6'h06: if(resp != 4'h0)  mismatches = mismatches + 1;
          6'h07: if(resp != 8'hAA) mismatches = mismatches + 1;
          6'h08: if(resp != 8'h55) mismatches = mismatches + 1;
          6'h09: if(resp != 8'h00) mismatches = mismatches + 1;
          6'h0A: if(resp != 8'h00) mismatches = mismatches + 1;
          6'h0B: if(resp != 8'h00) mismatches = mismatches + 1;
          6'h0C: if(resp != 8'h00) mismatches = mismatches + 1;
          6'h0D: if(resp != 8'h06) mismatches = mismatches + 1;
          6'h0E: if(resp != 8'hC8) mismatches = mismatches + 1;
          6'h0F: if(resp != 8'h00) mismatches = mismatches + 1;
          6'h10: if(resp != 8'h01) mismatches = mismatches + 1;
      endcase
      
      end

      if (mismatches > 0) $display("*** Test %0d failed with %0d mismatches! ***", test_counter, mismatches);
      else tests_passed = tests_passed + 1;

    end
  endtask

  /********************************
  *        TESTING SEQUENCE       *
  ********************************/
  initial begin
    $display("Beginning test sequence...");
    en_AFE = 0;
    strt_tx = 0; 	
    REF_CLK = 1'b0;
    send_cmd = 1'b0;
    tx_baud = 16'h006C;

    // reset
    RST_n = 0;
    repeat (2) @(posedge REF_CLK);
    @(negedge REF_CLK);
    RST_n = 1;
    @(negedge REF_CLK);

    $display("\n**************************************************\nNow running Hoffman's test...\n**************************************************");

    /**************************************
    *       TEST 1: HOFFMAN's TEST        *
    **************************************/
    begin : hoffman_test

      logic UART_triggering = 1'b0;
      logic SPI_triggering = 1'b0;	

      init_test();

      fptr1 = $fopen("CH1dmp.txt", "w");			                                                 // open file to write CH1 dumps to
      // writing command: set ch1trig to 0x10, set for CH1 triggering on positive edge expected resp 0xA5
      host_cmd = {8'h41, 8'h10};
      send_command_and_wait_for_response();

      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h13};
      send_command_and_wait_for_response();                                      // expected resp: 0xA5
  
      wait_for_capture_done();                                                                 // wait for 6th bit of trigcfg

      // Now request CH1 dump
      host_cmd = {8'h81, 8'h00};
      send_command_and_wait_for_response();                                      // expected resp: trigCfg
      collect_dump();
      
      // Now compare CH1dmp.txt to expected results
      compare_dump();
    end

    $display("\n**************************************************\nNow running UART-based triggering tests...\n**************************************************");

    // set mode
    UART_triggering = 1'b1;
    SPI_triggering = 1'b0;

    // writing command: turn off CH1
    host_cmd = {8'h41, 8'h01};
    send_command_and_wait_for_response();

    // writing command: turn on protocol triggering with trigcfg
    en_AFE = 1;
    host_cmd = {8'h40, 8'h12};
    send_command_and_wait_for_response();

    // writing command: set baud rate of the receiver's upper byte
    host_cmd = {8'h4D, 8'h00};
    send_command_and_wait_for_response();

    /******************************
    *       UART TESTS 1-3        *
    ******************************/

    // iterate through baud rates and alternate the mask used
    foreach (test_baud_rates_HIGH[i]) begin

      // writing command: set baud rate of the receiver's lower byte
      host_cmd = {8'h4D, test_baud_rates_HIGH[i]};
      send_command_and_wait_for_response();
      host_cmd = {8'h4E, test_baud_rates_LOW[i]};
      send_command_and_wait_for_response();
      tx_baud = {test_baud_rates_HIGH[i], test_baud_rates_LOW[i]};
      $display("Updated UART_prot and sender module to have a baud rate of %0d.", {test_baud_rates_HIGH[i], test_baud_rates_LOW[i]});

      // regular uart test involving a sent signal that is intended to match 

      init_test();

      $display("Not masked (0x00).");
      // writing command: write 96 to matchL (9)
      test_match = 8'h96;
      host_cmd = {8'h4A, test_match};
      send_command_and_wait_for_response();

      // writing command: write 00 to maskL
      test_mask = 8'h00;
      host_cmd = {8'h4C, test_mask};
      send_command_and_wait_for_response();

      // send the existing tx data which is 8'h96
      $display("Sending 0x96, with match data 0x%h and mask 0x%h.", test_match, test_mask);
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();

      $display("Low byte is masked (0x0F).");
      // writing command: write 9F to matchL (9); this will match the data we send below after being masked
      test_match = 8'h9F;
      host_cmd = {8'h4A, test_match};
      send_command_and_wait_for_response();

      // writing command: write 0F to maskL
      test_mask = 8'h0F;
      host_cmd = {8'h4C, test_mask};
      send_command_and_wait_for_response();

      // send the existing tx data which is 8'h96
      $display("Sending 0x96, with match data 0x%h and mask 0x%h.", test_match, test_mask);
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();

      $display("High byte is masked (0xF0).");
      // writing command: write 9F to matchL (9); this will match the data we send below after being masked
      test_match = 8'h06;
      host_cmd = {8'h4A, test_match};
      send_command_and_wait_for_response();

      // writing command: write F0 to maskL
      test_mask = 8'hF0;
      host_cmd = {8'h4C, test_mask};
      send_command_and_wait_for_response();

      // send the existing tx data which is 8'h96
      $display("Sending 0x06, with match data 0x%h and mask 0x%h.", test_match, test_mask);
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end

    $display("\n**************************************************\nNow running SPI-based triggering tests...\n**************************************************");

    // set mode
    UART_triggering = 1'b0;
    SPI_triggering = 1'b1;

    /********************************
    *       TEST 7: SPI TEST        *
    ********************************/
    begin : test4
      SPI_width8 = 0;
      SPI_edge = 0;
      SPI_tx_data = 16'hABCD;

      init_test();

      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h11}; 
      send_command_and_wait_for_response();                                      // expected resp: 0xA5
      
      // writing command: set matchH to AB
      host_cmd = {8'h49, 8'hAB};
      send_command_and_wait_for_response();   

      // writing command: set matchL to CD
      host_cmd = {8'h4A, 8'hCD};
      send_command_and_wait_for_response(); 

      // assert and deassert wrt in SPI TX
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end
 /*   
 
    /********************************
    *       TEST 8: SPI TEST       *
    ********************************/
    begin : test5 
      SPI_width8 = 1;
      SPI_tx_data = 16'hAB00;

      init_test();

      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h15}; 
      send_command_and_wait_for_response();                                      // expected resp: 0xA5

      // writing command: set matchH to 00
      host_cmd = {8'h49, 8'h00};
      send_command_and_wait_for_response(); 
      
      // writing command: set matchL to AB
      host_cmd = {8'h4A, 8'hAB};
      send_command_and_wait_for_response(); 

      // assert and deassert wrt in SPI TX
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end
    
    /********************************
    *       TEST 6: SPI TEST        *
    ********************************/
    begin : test6
      SPI_width8 = 0;
      SPI_tx_data = 16'hABCD;

      init_test();

      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h11}; 
      send_command_and_wait_for_response();                                      // expected resp: 0xA5
      
      // writing command: set matchH to AB
      host_cmd = {8'h49, 8'h0B};
      send_command_and_wait_for_response();   

      // writing command: set matchL to CD
      host_cmd = {8'h4A, 8'h0D};
      send_command_and_wait_for_response(); 
      
      // writing command: write F0 to maskH
      host_cmd = {8'h4B, 8'hF0};
      send_command_and_wait_for_response();
      
      // writing command: write F0 to maskL
      host_cmd = {8'h4C, 8'hF0};
      send_command_and_wait_for_response();

      // assert and deassert wrt in SPI TX
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end
    
    /********************************
    *       TEST 7: SPI TEST        *
    ********************************/
    begin : test7
      SPI_width8 = 1;
      SPI_tx_data = 16'hCD00;

      init_test();

      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h15}; 
      send_command_and_wait_for_response();                                      // expected resp: 0xA5
      
      // writing command: set matchH to 00
      host_cmd = {8'h49, 8'h00};
      send_command_and_wait_for_response();   

      // writing command: set matchL to CD
      host_cmd = {8'h4A, 8'h81};
      send_command_and_wait_for_response(); 

      // writing command: write 7E to maskL
      host_cmd = {8'h4C, 8'h7E};
      send_command_and_wait_for_response();

      // assert and deassert wrt in SPI TX
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end
    
    /********************************
    *       TEST 8: SPI TEST        *
    ********************************/
    begin : test8
      SPI_width8 = 0;
      SPI_edge = 1;
      SPI_tx_data = 16'hABCD;

      init_test();
      
      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h19}; 
      send_command_and_wait_for_response();                                      // expected resp: 0xA5
      
      // writing command: set matchH to AB
      host_cmd = {8'h49, 8'h0B};
      send_command_and_wait_for_response();   

      // writing command: set matchL to CD
      host_cmd = {8'h4A, 8'h0D};
      send_command_and_wait_for_response(); 
      
      // writing command: write F0 to maskH
      host_cmd = {8'h4B, 8'hF0};
      send_command_and_wait_for_response();
      
      // writing command: write F0 to maskL
      host_cmd = {8'h4C, 8'hF0};
      send_command_and_wait_for_response();

      // assert and deassert wrt in SPI TX
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end
    
    /********************************
    *       TEST 9: SPI TEST        *
    ********************************/
    begin : test9
      SPI_width8 = 1;
      SPI_edge = 1;
      SPI_tx_data = 16'hCD00;

      init_test();

      // writing command: set the run bit of trigcfg, keep protocol triggering off
      en_AFE = 1; // leave all other registers at their default and set RUN bit, but enable AFE first
      host_cmd = {8'h40, 8'h1D}; 
      send_command_and_wait_for_response();                                      // expected resp: 0xA5
      
      // writing command: set matchH to 00
      host_cmd = {8'h49, 8'h00};
      send_command_and_wait_for_response();   

      // writing command: set matchL to CD
      host_cmd = {8'h4A, 8'h81};
      send_command_and_wait_for_response(); 

      // writing command: write 7E to maskL
      host_cmd = {8'h4C, 8'h7E};
      send_command_and_wait_for_response();

      // assert and deassert wrt in SPI TX
      @(negedge clk);
      strt_tx = 1;
      @(negedge clk);
      strt_tx = 0;

      wait_for_capture_done();
    end
    
    /*******************************
    *   ADDED TEST FOR COVERAGE    *
    *******************************/
    
    read_all_registers();

    /*******************************
    *        TESTING RESULTS       *
    *******************************/
    if (tests_passed < test_counter) $display("\nPassed %0d out of %0d tests.", tests_passed, test_counter);
    else $display("\n**************************************************\nYAHOO!! All %0d tests passed!\n**************************************************", 
                  test_counter);
    $stop();
  end

endmodule	
