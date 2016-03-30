signature HM_Cline =
sig

type t = {
  holstate : string option,
  poly : string option,
  polymllibdir : string option,
  poly_not_hol : bool,
  core : HM_Core_Cline.t
}

val option_descriptions : ((string -> unit) * t -> t) GetOpt.opt_descr list

val default_options : t

end
