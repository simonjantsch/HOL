structure pureSimps :> pureSimps =
struct

open Lib Drule simpLib

val PURE_ss = SIMPSET
    {convs  = [],
     rewrs  = [],
     congs  = [],
     ac     = [],
     filter = SOME Cond_rewr.mk_cond_rewrs,
     dprocs = []}

val pure_ss = mk_simpset [PURE_ss]

end
