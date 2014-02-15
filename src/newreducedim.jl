# reduce along dimensions

## auxiliary functions

_rtup(siz::NTuple{1,Int}, d::Int) = (d == 1 ? (true,) : (false,))
 
_rtup(siz::NTuple{2,Int}, d::Int) = (d == 1 ? (false, true) :
                                     d == 2 ? (true, false) : 
                                              (false, false) )
 
_rtup(siz::NTuple{3,Int}, d::Int) = (d == 1 ? (false, false, true) :
                                     d == 2 ? (false, true, false) : 
                                     d == 3 ? (true, false, false) : 
                                              (false, false, false))
 
_rtup{N}(siz::NTuple{N,Int}, d::Int) = (ds = fill(false,N); ds[N+1-d]=true; tuple(ds...))::NTuple{N,Bool}
 
function _rtup{N}(siz::NTuple{N,Int}, dims::Dims)
    ds = fill(false,N)
    for d in dims
        ds[N+1-d] = true
    end
    return tuple(ds...)::NTuple{N,Bool}
end

## main macro

macro compose_reducedim(fun, OT, AN)
    # fun: the function name, e.g. sum
    # BT: the base type, e.g. Number, Real

    fun! = symbol(string(fun, '!'))
    _fun! = symbol(string('_', fun!))
    _funimpl! = symbol(string('_', fun, "impl!"))
    _funimpl2d! = symbol(string('_', fun, "impl2d!"))

    # code-gen preparation

    h = codegen_helper(AN)
    args = h.args
    aparams = h.dense_aparams

    saccumf = AN >= 0 ? :saccum : :saccum_fdiff
    paccumf! = AN >= 0 ? :paccum! : :paccum_fdiff!

    if AN == 0
        imparams2d = [:(a::ContiguousArray), :(ia::Int), :(sa1::Int), :(sa2::Int)]
        imargs2d = [:(parent(a)), :ia, :sa1, :sa2]
        eviewargs = [:(ellipview(a, i))]
        getoffsets = :(ia = offset(a) + 1)
        getstrides1 = :(sa1 = stride(a, 1)::Int)
        getstrides2 = :((sa1, sa2) = strides(a)::(Int, Int))
        contcol = :(sa1 == 1)
        nextcol = :(ia += sa2)
        kargs = [:a, :ia]
        kargs1 = [:a, :ia, :sa1]
    elseif AN == 1
        imparams2d = [:(fun::Functor{1}), :(a::ContiguousArray), :(ia::Int), :(sa1::Int), :(sa2::Int)]
        imargs2d = [:fun, :(parent(a)), :ia, :sa1, :sa2]
        eviewargs = [:fun, :(ellipview(a, i))]
        getoffsets = :(ia = offset(a) + 1)
        getstrides1 = :(sa1 = stride(a, 1)::Int)
        getstrides2 = :((sa1, sa2) = strides(a)::(Int, Int))
        contcol = :(sa1 == 1)
        nextcol = :(ia += sa2)
        kargs = [:fun, :a, :ia]
        kargs1 = [:fun, :a, :ia, :sa1]
    elseif AN == 2 || AN == -2
        FN = AN == 2 ? 2 : 1
        imparams2d = [:(fun::Functor{$FN}), :(a::ContiguousArrOrNum), :(ia::Int), :(sa1::Int), :(sa2::Int), 
                                            :(b::ContiguousArrOrNum), :(ib::Int), :(sb1::Int), :(sb2::Int)]
        imargs2d = [:fun, :(parent(a)), :ia, :sa1, :sa2, 
                          :(parent(b)), :ib, :sb1, :sb2]
        eviewargs = [:fun, :(ellipview(a, i)), :(ellipview(b, i))]
        getoffsets = :(ia = offset(a) + 1; 
                       ib = offset(b) + 1)
        getstrides1 = :(sa1 = stride(a, 1)::Int; 
                        sb1 = stride(b, 1)::Int)
        getstrides2 = :((sa1, sa2) = strides(a)::(Int, Int); 
                       (sb1, sb2) = strides(b)::(Int, Int))
        contcol = :(sa1 == 1 && sb1 == 1)
        nextcol = :(ia += sa2; ib += sb2)
        kargs = [:fun, :a, :ia, :b, :ib]
        kargs1 = [:fun, :a, :ia, :sa1, :b, :ib, :sb1]
    elseif AN == 3
        imparams2d = [:(fun::Functor{3}), :(a::ContiguousArrOrNum), :(ia::Int), :(sa1::Int), :(sa2::Int), 
                                          :(b::ContiguousArrOrNum), :(ib::Int), :(sb1::Int), :(sb2::Int), 
                                          :(c::ContiguousArrOrNum), :(ic::Int), :(sc1::Int), :(sc2::Int)]
        imargs2d = [:fun, :(parent(a)), :ia, :sa1, :sa2, 
                          :(parent(b)), :ib, :sb1, :sb2, 
                          :(parent(c)), :ic, :sc1, :sc2]
        eviewargs = [:fun, :(ellipview(a, i)), :(ellipview(b, i)), :(ellipview(c, i))]
        getoffsets = :(ia = offset(a) + 1; 
                       ib = offset(b) + 1; 
                       ic = offset(c) + 1)
        getstrides1 = :(sa1 = stride(a, 1)::Int; 
                        sb1 = stride(b, 1)::Int;
                        sc1 = stride(c, 1)::Int)
        getstrides2 = :((sa1, sa2) = strides(a)::(Int, Int); 
                       (sb1, sb2) = strides(b)::(Int, Int); 
                       (sc1, sc2) = strides(c)::(Int, Int))
        contcol = :(sa1 == 1 && sb1 == 1 && sc1 == 1)
        nextcol = :(ia += sa2; ib += sb2; ic += sc2)
        kargs = [:fun, :a, :ia, :b, :ib, :c, :ic]
        kargs1 = [:fun, :a, :ia, :sa1, :b, :ib, :sb1, :c, :ic, :sc1]
    else
        error("AN = $(AN) is unsupported.")
    end


    quote
        global $(_funimpl2d!)
        function $(_funimpl2d!)(r2::Bool, r1::Bool, m::Int, n::Int, 
                                dst::ContiguousArray, idst::Int, sdst1::Int, sdst2::Int, 
                                $(imparams2d...))
            if r1
                if r2
                    if $(contcol)
                        s = $(saccumf)($OT, m, $(kargs...))
                        $(nextcol)
                        for j = 2:n
                            s += $(saccumf)($OT, m, $(kargs...))
                            $(nextcol)
                        end
                        dst[idst] += s
                    else
                        s = $(saccumf)($OT, m, $(kargs1...))
                        $(nextcol)
                        for j = 2:n
                            s += $(saccumf)($OT, m, $(kargs1...))
                            $(nextcol)
                        end
                        dst[idst] += s
                    end
                else
                    if $(contcol)
                        for j = 1:n
                            dst[idst] += $(saccumf)($OT, m, $(kargs...))
                            $(nextcol)
                            idst += sdst2
                        end
                    else
                        for j = 1:n
                            dst[idst] += $(saccumf)($OT, m, $(kargs1...))
                            $(nextcol)
                            idst += sdst2
                        end
                    end
                end
            else
                if r2
                    if $(contcol) && sdst1 == 1
                        for j = 1:n
                            $(paccumf!)($OT, m, dst, idst, $(kargs...))
                            $(nextcol)
                        end
                    else
                        for j = 1:n
                            $(paccumf!)($OT, m, dst, idst, sdst1, $(kargs1...))
                            $(nextcol)
                        end
                    end
                else
                    if $(contcol) && sdst1 == 1
                        for j = 1:n
                            $(paccumf!)($OT, m, dst, idst, $(kargs...))
                            $(nextcol)
                            idst += sdst2
                        end
                    else
                        for j = 1:n
                            $(paccumf!)($OT, m, dst, idst, sdst1, $(kargs1...))
                            $(nextcol)
                            idst += sdst2
                        end
                    end
                end
            end            
        end

        global $(_funimpl!)
        function $(_funimpl!)(dst::DenseArray, $(aparams...), r1::Bool)
            n = $(h.inputlen)::Int
            $(getstrides1)
            sdst1 = stride(dst, 1)::Int
            if r1
                if $(contcol)
                    dst[1] = $(saccumf)($OT, n, dst, idst, $(kargs...))
                else
                    dst[1] = $(saccumf)($OT, n, dst, idst, sdst1, $(kargs1...))
                end
            else
                if $(contcol) && (sdst1 == 1)
                    $(paccumf!)($OT, n, dst, idst, $(kargs...))
                else
                    $(paccumf!)($OT, n, dst, idst, sdst1, $(kargs1...))
                end
            end
        end

        function $(_funimpl!)(dst::DenseArray, $(aparams...), r2::Bool, r1::Bool)
            m, n = $(h.inputsize)::(Int, Int)
            $(getstrides2)
            sdst1, sdst2 = strides(dst)::(Int, Int)         
            $(getoffsets)
            idst = offset(dst) + 1
            $(_funimpl2d!)(r2, r1, m, n, parent(dst), idst, sdst1, sdst2, $(imargs2d...))
        end

        function $(_funimpl!)(dst::DenseArray, $(aparams...), rN::Bool, rNm1::Bool, rNm2::Bool, rr::Bool...)
            n = size(a, N)::Int
            if reduc
                _dst = ellipview(dst, 1)
                for i = 1:n
                    $(_fun!)(_dst, $(eviewargs...), rNm1, rNm2, rr...)
                end
            else
                for i = 1:n
                    $(_fun!)(ellipview(dst, i), $(eviewargs...), rNm1, rNm2, rr...)
                end
            end
        end    
         
        global $(_fun!)
        function $(_fun!){S<:Number,N}(dst::DenseArray{S,N}, $(aparams...), insiz::NTuple{N,Int}, dims::Union(Int,Dims))
            $(_funimpl!)(dst, a, _rtup(insiz, dims)...)
            return dst
        end

        global $(fun!)
        function $(fun!)(dst::ContiguousArray, $(aparams...), dims::Union(Int,Dims))
            insiz = $(h.inputsize)
            rsiz = Base.reduced_dims(insiz, dims)
            prod(rsiz) == length(dst) || throw(DimensionMismatch("Incorrect size of dst."))
            $(_fun!)(contiguous_view(dst, rsiz), $(args...), insiz, dims)
        end

        global $(fun)
        function $(fun)($(aparams...), dims::Union(Int,Dims))
            insiz = $(h.inputsize)
            dst = fill(init($OT, $(h.termtype)), Base.reduced_dims(insiz,dims))
            $(_fun!)(dst, $(args...), insiz, dims)
        end
    end
end 
 
@compose_reducedim sum Sum 0

