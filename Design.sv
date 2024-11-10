module ram(addr, data, clk, rd, wr, cs, d_out);
  input [9:0] addr;
  input clk, rd, wr, cs;
  input [7:0] data; 
  output reg [7:0] d_out;
  reg [7:0] mem [1023:0];
  
  assign data = (cs && rd && !wr) ? d_out : 8'bz; 
  
  always @(posedge clk) begin
    if (cs && wr && !rd) begin
      mem[addr] <= data; 
    end
  end
  
  always @(posedge clk) begin
    if (cs && rd && !wr) begin
      d_out <= mem[addr];
    end
  end
endmodule
