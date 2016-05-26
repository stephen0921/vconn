module b(
         // a to b
         input [13:0]  a_b_0,
         input         a_b_1,
         // c to b
         input [134:0] i_c_b_0,
         input         c_b_1,
         // b to a
         output [3:0]  b_a_0,
         output        b_a_1,
         // b to c
         output        b_c_0,
         output [5:0]  b_c_1,
         // top input to b
         input [10:0]  b_in_0
         );
endmodule // b

