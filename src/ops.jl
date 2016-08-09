
## symbolic operations

import Base: +, -, *, /, .+, .-, .*, ./

(+)(ex::Symbolic, v::Numeric) = :($ex + $v)
(+)(v::Numeric, ex::Symbolic) = :($v + $ex)
(+)(ex1::Symbolic, ex2::Symbolic) = :($ex1 + $ex2)

(-)(ex::Symbolic, v::Numeric) = :($ex - $v)
(-)(v::Numeric, ex::Symbolic) = :($v - $ex)
(-)(ex1::Symbolic, ex2::Symbolic) = :($ex1 - $ex2)

(*)(ex::Symbolic, v::Numeric) = :($ex * $v)
(*)(v::Numeric, ex::Symbolic) = :($v * $ex)
(*)(ex1::Symbolic, ex2::Symbolic) = :($ex1 * $ex2)

(/)(ex::Symbolic, v::Numeric) = :($ex / $v)
(/)(v::Numeric, ex::Symbolic) = :($v / $ex)
(/)(ex1::Symbolic, ex2::Symbolic) = :($ex1 / $ex2)

# elemetwise operations

(.+)(ex::Symbolic, v::Numeric) = :($ex .+ $v)
(.+)(v::Numeric, ex::Symbolic) = :($v .+ $ex)
(.+)(ex1::Symbolic, ex2::Symbolic) = :($ex1 .+ $ex2)

(.-)(ex::Symbolic, v::Numeric) = :($ex .- $v)
(.-)(v::Numeric, ex::Symbolic) = :($v .- $ex)
(.-)(ex1::Symbolic, ex2::Symbolic) = :($ex1 .- $ex2)

(.*)(ex::Symbolic, v::Numeric) = :($ex .* $v)
(.*)(v::Numeric, ex::Symbolic) = :($v .* $ex)
(.*)(ex1::Symbolic, ex2::Symbolic) = :($ex1 .* $ex2)

(./)(ex::Symbolic, v::Numeric) = :($ex ./ $v)
(./)(v::Numeric, ex::Symbolic) = :($v ./ $ex)
(./)(ex1::Symbolic, ex2::Symbolic) = :($ex1 ./ $ex2)

## Note: this is also correct, but generates more ugly expressions
## 
## for op in [:(+), :(-), :(*), :(/)]
##     for T in [Number, Array]
##         @eval begin
##             Base.$(op)(ex::Symbolic, v::$T) = :(($$op)($ex,$v))
##             Base.$(op)(v::$T, ex::Symbolic) = :(($$op)($v,$ex))
##             Base.$(op)(ex1::Symbolic, ex2::Symbolic) = :(($$op($ex1,$ex2)))
##         end
##     end
## end
