module a(
   // a to b
   output [13:0] a_b_0,
   output        a_b_1,
   // a to c
   output        a_c_0,
   output [1:0]  a_c_1,
   // a to top out    
   output        a_out_0,

   // b to a
   input [3:0]   b_a_0,
   input         b_a_1,
   // c to a
   input [12:0]   c_a_0,
   input         c_a_1
         );
   
endmodule // a

