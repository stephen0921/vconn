`include "fff.sv"
module a(
   // a to b
   a_b_0,
   a_b_1,
   // a to c
   a_c_0,
   a_c_1,
   // a to top out    
   a_out_0,
   a_out_1,

   // b to a
   b_a_0,
   b_a_1,
   // c to a
   c_a_0,
   c_a_1
         );
   //parameter TEST2 = 11;      
   //parameter TEST1 = TEST2 + 1;
   //parameter A_B_0 = TEST1 + 1;  
   parameter TEST3 = 1'b1;      
   parameter TEST2 = 15;      
   parameter TEST1 = TEST2 + 4'h1;
   parameter A_B_0 = TEST1 + 1;  
   
   // a to b
   output [A_B_0:0] a_b_0;
   output        a_b_1;
   // a to c
   output        a_c_0;
   output [1:0]  a_c_1;
   // a to top out    
   output        a_out_0;
   output        a_out_1;

   // b to a
   input [3:0]   b_a_0;
   input         b_a_1;
   // c to a
   input [12:0]  c_a_0;
   input         c_a_1;

endmodule // a

