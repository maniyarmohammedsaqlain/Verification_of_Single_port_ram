interface ram_if;
  logic [9:0] addr;
  logic [7:0] data;   
  logic rd;
  logic wr;
  logic cs;
  logic clk;
  logic [7:0] d_out;
endinterface

class transaction;
  rand bit [9:0]addr;
  rand bit [7:0]data;
  rand bit oper;
  rand bit cs;
  bit rd;
  bit wr;
  bit [7:0] d_out;
  
  constraint oper_ctrl {
    cs inside {[1:2]};
  }
  
  function void display(string name);
    $display(" %t [%s] addr:%d data:%d oper:%d cs:%d rd:%d wr:%d d_out:%d", $time, name, addr, data, oper, cs, rd, wr, d_out);
  endfunction
endclass

class generator;
  transaction trans;
  mailbox gen2drv;
  event done;
  event ready;
  int count;
  
  function new(mailbox gen2drv, event done, event ready);
    this.gen2drv = gen2drv;
    this.done = done;
    this.ready = ready;
  endfunction
  
  task run();
    repeat(count) begin
      trans = new();
      trans.randomize();
      trans.display("GEN");
      gen2drv.put(trans);
      #2;
      ->done;
      
      @(ready);
//       #20;
    end
  endtask
endclass

class driver;
  transaction trans;
  virtual ram_if inf;
  mailbox gen2drv;
  event done;
  event ready; 
  event drv_done;
  
  function new(mailbox gen2drv, virtual ram_if inf, event done, event ready,event drv_done);
    this.gen2drv = gen2drv;
    this.inf = inf;
    this.done = done;
    this.ready = ready;
    this.drv_done=drv_done;
  endfunction
  
  task write();
    @(posedge inf.clk);
    inf.wr = 1;
    inf.rd = 0;
    inf.cs = trans.cs;
    inf.addr = trans.addr;
    inf.data = trans.data;
    @(posedge inf.clk);
    inf.wr = 0;
    $display("%t [DRV] DATA WRITE DONE %d", $time, inf.data);
  endtask
  
  task read();
    @(posedge inf.clk);
    inf.wr = 0;
    inf.rd = 1;
    inf.cs = trans.cs;
    @(posedge inf.clk);
    inf.rd = 0;
    $display("%t [DRV] DATA READ DONE", $time);
  endtask
  
  task run();
    forever begin
      @(done); 
      gen2drv.get(trans);
      
      if (trans.oper == 1) begin
        write();
      end else begin
        read();
      end
      
      ->drv_done;
      #25;
      ->ready;
    end
  endtask
  
  task main();
    begin
      run();
      $finish();
    end
  endtask
endclass


class monitor;
  transaction trans;
  mailbox mon2scb;
  event drv_done;
  virtual ram_if inf;
  
  function new(mailbox mon2scb,virtual ram_if inf,event drv_done);
    this.mon2scb=mon2scb;
    this.inf=inf;
    this.drv_done=drv_done;
  endfunction
  
  task run();
    forever
      begin
        @(drv_done);
        #1;
        @(posedge inf.clk);
        trans=new();
        trans.addr=inf.addr;
        trans.data=inf.data;
        trans.cs=inf.cs;
        trans.rd=inf.rd;
        trans.wr=inf.wr;
        trans.d_out=inf.d_out;
        mon2scb.put(trans);
        trans.display("MON");
      end
  endtask
endclass


class scoreboard;
  mailbox mon2scb;
  transaction trans;
  bit [7:0] mem [1023:0];
  
  function new(mailbox mon2scb);
    this.mon2scb = mon2scb;
  endfunction
  
  task run();
    forever begin
      trans = new();
      mon2scb.get(trans);
      if (trans.oper == 1) begin
        mem[trans.addr] = trans.data;
        $display("%t [SCO] Write operation: addr = %d, data = %d", $time, trans.addr, trans.data);
      end
      else begin
        if (trans.d_out == mem[trans.addr]) begin
          trans.display("SCO");
          $display("DATA MATCHED at addr = %d", trans.addr);
        end
        else begin
          $display("DATA MISMATCHED at addr = %d: Expected = %d, Got = %d", trans.addr, mem[trans.addr], trans.d_out);
        end
        $display("---------------------------------------------------------------------------------------------------------------");
      end
    end
  endtask
endclass

               
                 

class environment;
  transaction trans;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox gen2drv;
  mailbox mon2scb;
  event done;
  event ready;
  event drv_done;
  
  function new(virtual ram_if inf);
    gen2drv = new();
    mon2scb=new();
    gen = new(gen2drv, done, ready);
    drv = new(gen2drv, inf, done, ready,drv_done);
    mon = new(mon2scb,inf,drv_done);
    sco=new(mon2scb);
  endfunction
  
  task run();
    fork
      gen.run();
      drv.main();
      mon.run();
      sco.run();
    join
  endtask
endclass
        
module tb;
  environment env;
  ram_if inf();
  
  ram r(inf.addr, inf.data, inf.rd, inf.wr, inf.cs, inf.d_out);
  
  initial begin
    inf.clk = 0;
  end
  always #10 inf.clk = ~inf.clk;
  
  initial begin
    env = new(inf);
    env.gen.count = 10;
    env.run();
  end
  
endmodule
