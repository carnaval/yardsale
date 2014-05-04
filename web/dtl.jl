# <3 php
macro echo(stx)
    :(print($(esc(:io)), $stx))
end

const OPEN_P = "("[1] # dont ask
const CLOSE_P = ")"[1]

rec(x :: Symbol) = Set({x})
rec(x :: Expr) = if x.head != :line && !isa(x, LineNumberNode) Set{Symbol}(reduce(union, map(rec, x.args))) else Set{Symbol}() end
rec(x) = Set{Symbol}()

function freevars(lsd :: LambdaStaticData)
    ast = Base.uncompressed_ast(lsd)
    capt = ast.args[2][1]
    code = ast.args[3]
    vars = setdiff(rec(code), Set(capt))
    filter!(x -> !isdefined(x), vars)
end

freevars(stx) = (println(stx); freevars(eval(:(()->($stx))).code))

function dtl2jl(funname, stx)
    idx = 0
    source = IOBuffer()
    write(source, "begin;")
    echoed = 1
    while true
        dollar_idx = search(stx, '$', idx+1)
        while stx[dollar_idx+1] == '$'
            dollar_idx = search(stx, '$', dollar_idx+2)
        end
        pound_idx = search(stx, '#', idx+1)
        while stx[pound_idx+1] == '#'
            pound_idx = search(stx, '#', pount_idx+2)
        end
        if dollar_idx == 0 dollar_idx = typemax(Int) end
        if pound_idx == 0 pound_idx = typemax(Int) end
        idx = min(dollar_idx, pound_idx)
        literal = stx[echoed:(idx == typemax(Int) ? length(stx) : (idx-1))]
        if length(literal) > 0
            write(source, "@echo ")
            show(source, replace(literal, "\$\$", "\$"))
            write(source, ";")
        end
        idx < length(stx) || break
        echoed = idx-1
        if stx[idx+1] == OPEN_P
            level = 0
            interp_end = idx
            while true
                next_open = search(stx, OPEN_P, interp_end+1)
                if next_open == 0 next_open = typemax(Int) end
                next_close = search(stx, CLOSE_P, interp_end+1)
                if next_close == 0 next_close = typemax(Int) end
                if next_open < next_close
                    interp_end = next_open
                    level += 1
                elseif next_open > next_close
                    interp_end = next_close
                    level -= 1
                else
                    error()
                end
                level > 0 || break
            end
            @assert level == 0
            expr_end = interp_end-1
            expr_begin = idx + 2
            interp_end += 1
        else
            interp_end = idx+1
            while isalnum(stx[interp_end]) || stx[interp_end] in ('_',)
                interp_end = nextind(stx, interp_end)
            end
            expr_begin = idx+1
            expr_end = prevind(stx, interp_end)
        end
        if stx[idx] == '$'
            write(source, "@echo ")
        elseif stx[idx] == '#'
        end
        write(source, stx[expr_begin:expr_end])
        write(source, ";")
        echoed = interp_end
        idx = echoed
    end
    write(source, "end")
    seekstart(source)
    src = readall(source)
    result = parse(src)
    args = {freevars(result)...}
    map!(args) do a
        str = string(a)
        Expr(:kw, a, :(error("Parameter ", $str, " required")))
    end
    quote
        function $funname(;$(args...))
            $result
        end
    end
end

function include_dtl(fn; prefix="view")
    eval(dtl2jl(:haha, open(readall, fn)))
end

function dtl(fn; kwargs...)
    io = IOBuffer()
    eval(dtl2jl(gensym(), open(readall, string(fn) * ".dtl")))(;io = io, kwargs...)
    seekstart(io)
    io
end
