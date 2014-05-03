module Pg
type Conn
    handle :: Ptr{Void}
    auto_discover_oid :: Bool
end
type Res
    conn :: Conn
    handle :: Ptr{Void}
    ncol :: Int
    singlecol :: Bool # true if explicitely asked one column
    out_ncol_sum :: Vector{Int}
    out_types :: Vector{Union(Type,Nothing)}
end
Res(c,h,s,out_ncol,out_types) = Res(c,h,sum(out_ncol),s,vcat(0,cumsum(out_ncol)), out_types)

function Base.print(io::IO, r :: Res)
    stat = status(r)
    stat_str = isempty(stat[2]) ? string(stat[1]) : string(stat[1], ": ", stat[2])
    println(io, "(", stat_str, ", $(r.ncol) [", join(fields(r), " "), "], ", length(r), " rows) :")
    for row in r[1:min(2, end)]
        println(io, "- ", typeof(row), ": ", row)
    end
end

function connect(opts :: Dict{String, String}; auto_discover_oid = true)
    c = ccall((:PQconnectdbParams, "libpq"), Ptr{Void}, (Ptr{Ptr{Uint8}}, Ptr{Ptr{Uint8}}, Int), collect(keys(opts)), collect(values(opts)), 0)
    Conn(c, auto_discover_oid)
end

connect(f, opts; kws...) = task_local_storage(f, :pg_connection, connect(opts; kws...))
conn() = task_local_storage(:pg_connection)

function status(c :: Conn)
    stat = ccall((:PQstatus, "libpq"), Int, (Ptr{Void},), c.handle)
    [0 => :ok,
     1 => :bad,
     2 => :started,
     3 => :made,
     4 => :awaiting_response,
     5 => :auth_ok,
     6 => :setenv,
     7 => :ssl_startup,
     8 => :needed][stat]
end

function status(r :: Res)
    stat = ccall((:PQresultStatus, "libpq"), Int, (Ptr{Void},), r.handle)
    reason =
    [0 => :empty,
     1 => :ok,
     2 => :tuples_ok,
     3 => :copy_out,
     4 => :copy_in,
     5 => :bad_response,
     6 => :nonfatal_error,
     7 => :fatal_error][stat]
    text = bytestring(ccall((:PQresultErrorMessage, "libpq"), Ptr{Uint8}, (Ptr{Void},), r.handle))
    (reason, text)
end

function fields(r :: Res)
    UTF8String[ bytestring(ccall((:PQfname, "libpq"), Ptr{Uint8}, (Ptr{Void}, Int), r.handle, col)) for col = 0:r.ncol-1 ]
end

field_table_oid(r :: Res, j :: Int) = ccall((:PQftable, "libpq"), Oid, (Ptr{Void}, Int), r.handle, j-1)

function finalize(r :: Res)
    ccall((:PQclear, "libpq"), Void, (Ptr{Void},), r.handle)
end

function pqres(c, r, onecol, out_ncols = nothing,out_types=nothing)
    ncol = ccall((:PQnfields, "libpq"), Int, (Ptr{Void},), r)
    out_ncols = out_ncols == nothing ? fill(1, ncol) : out_ncols
    out_types = out_types == nothing ? fill(nothing, ncol) : out_types
    @assert ncol == sum(out_ncols) string("Failed : ", ncol, " ", out_ncols)
    res = Res(c, r, onecol, out_ncols, out_types)
    finalizer(res, finalize)
    err_msg = status(res)[2]
    isempty(err_msg) || error("Postgres said : $err_msg")
    res
end

#function run(c :: Conn, code :: String)
#    r = ccall((:PQexec, "libpq"), Ptr{Void}, (Ptr{Void},Ptr{Uint8}), c.handle, code)
#    pqres(c, r)
#end

function run(c :: Conn, code :: String, params :: Vector)
#    types = int(map(x -> julia_to_oid[typeof(x)], params))
    vals = convert(Vector{Vector{Uint8}},
                   map(x -> convert(Vector{Uint8}, utf8(string(x))),
                       params))
    r = ccall((:PQexecParams, "libpq"),
              Ptr{Void}, (Ptr{Void}, Ptr{Uint8}, Int,
                         Ptr{Oid}, Ptr{Ptr{Uint8}}, Ptr{Int}, Ptr{Int}, Int),
              c.handle, code, length(params),
              0, pointer(map(pointer, vals)), pointer(map(length, vals)), pointer(zeros(length(params))), 1)
    pqres(c, r, false)
end

run(c :: Conn, code, ps...) = run(c, code, collect(ps))

type Prepared
    query :: String
    name :: String
    prepared :: Bool
    singlecol :: Bool
    singlerow :: Bool
    outs :: Vector
    out_ncols :: Vector{Int}
    out_types :: Vector{Union(Type, Nothing)}
end
Prepared(query, singlecol, singlerow, outs) = begin
    Prepared(query, "q_" * hex(hash(query)) * string(time()), false, singlecol, singlerow, outs, Int[], Type[])
end

function prepare(c :: Conn, p :: Prepared)
    p.prepared && return
    out_ncols_types = map(p.outs) do out
        if isa(out, Expr) && out.head == :. && out.args[2] == :*
            (length(Main.tablefields(out.args[1])), get(Main.rev_bindings, out.args[1], nothing))
        else
            (1,nothing)
        end
    end
    p.out_ncols = map(first, out_ncols_types)
    p.out_types = [x[2] for x in out_ncols_types]
    cs = run(c, "select count(*) from pg_prepared_statements where name = \$1", {p.name})[1][1]
    if cs == 0
        r = ccall((:PQprepare, "libpq"), Ptr{Void}, (Ptr{Void}, Ptr{Uint8}, Ptr{Uint8}, Int, Ptr{Oid}),
                  c.handle, p.name, p.query, 0, 0)
        pqres(c, r, false)
    end
    p.prepared = true
end

function run(c :: Conn, code :: Prepared, params :: Vector)
    prepare(c, code)
#    println("SQL: $(code.query) | \$=$params")
    vals = convert(Vector{Vector{Uint8}},
                   map(x -> convert(Vector{Uint8}, utf8(string(x))),
                       params))
    r = ccall((:PQexecPrepared, "libpq"),
              Ptr{Void}, (Ptr{Void}, Ptr{Uint8}, Int,
                          Ptr{Ptr{Uint8}}, Ptr{Int}, Ptr{Int}, Int),
              c.handle, code.name, length(params),
              pointer(map(pointer, vals)), pointer(map(length, vals)), pointer(zeros(length(params))), 1)
    res = pqres(c, r, code.singlecol, code.out_ncols, code.out_types)
    code.singlerow ? res[1] : res
end

typealias Oid Uint32
oid(a) = uint(a)

const oid_to_julia =
    [oid(16) => Bool,
     oid(17) => Vector{Uint8},
     oid(18) => Char,
     oid(19) => String,
     oid(20) => Int64,
     oid(21) => Int16,
     oid(23) => Int32,
     oid(25) => String,
     oid(26) => Oid,
     oid(705) => String,
     oid(1005) => Vector{Int16},
     oid(1007) => Vector{Int32},
     oid(1028) => Vector{Oid}]
const julia_to_oid = [ v => k for (k,v) in oid_to_julia ]

function field_type_oid(r :: Res, i :: Int)
    ccall((:PQftype, "libpq"), Oid, (Ptr{Void}, Int), r.handle, i-1)
end

field_type(r :: Res, i :: Int) = oid_type(r.conn, field_type_oid(r, i))

function oid_type(c, i)
    o = oid(i)
    if !haskey(oid_to_julia, o)
        c.auto_discover_oid || error("Unknown type OID $o")
        Main.discover_oid(c, o)
    end
    oid_to_julia[o]
end
oid_type(i) = oid_type(conn(), i)

parse(::Type{String}, res :: Res, i :: Int, j :: Int, io::IOBuffer) = bytestring(readuntil(io, '\0'))
parse(::Type{Bool}, res :: Res, i :: Int, j :: Int, x::Ptr{Uint8}) = error()#bytestring(x)[1] == 't'
parse{T <: Integer}(::Type{T},res :: Res, i :: Int, j :: Int, io::IOBuffer) = hton(read(io, T))
parse(::Type{Char}, res :: Res, i :: Int, j :: Int, x::Ptr{Uint8}) = error()#bytestring(x)[1]
function parse{T <: (Any...)}(::Type{T}, res :: Res, i :: Int, j :: Int, io :: IOBuffer)
    nfields = parse(Uint32, res, i, j, io)
    ntuple(nfields, i -> begin
        ty = parse(Oid, res, i, j, io)
        len = parse(Int32, res, i, j, io)
        if len == -1
            nothing
        else
            parse(T[i], res, i, j, io)
        end
           end)
end
function parse(t::DataType, res :: Res, i :: Int, j :: Int, io :: IOBuffer)
    types = Main.bindings[t].sql_row_type
    mapping = Main.bindings[t].col_map
    vals = parse(types, res, i, j, io)
    mapped = [mapping[i] == 0 ? nothing : vals[mapping[i]] for i = 1:length(mapping)]
    t(mapped...)
end
function parse(::Type{Vector{Uint8}}, res :: Res, i :: Int, j :: Int, io::IOBuffer)
#    len = ccall((:PQgetlength, "libpq"), Int, (Ptr{Void}, Int, Int), res.handle, i-1, j-1)
#    read(io, Uint8, len)
    error()
end
function parse{T}(::Type{Vector{T}}, res :: Res, i :: Int, j :: Int, io :: IOBuffer)
    ndim = parse(Int32, res, i, j, io)
    offs = parse(Int32, res, i, j, io)
    elt_oid = parse(Int32, res, i, j, io)
    elt = oid_type(elt_oid)
    len = parse(Int32, res, i, j, io)
    lb = parse(Int32, res, i, j, io)
    ndim == 1 || error("no multidimensional array yet : $ndim")
    offs == 0 || error("no NULL bitmap yet : $offs")
    # TODO figure out what is this int32 doing here
    T[(read(io, Int32); parse(elt, res, i, j, io)) for _=1:len]
end

Base.length(r::Res) = ccall((:PQntuples, "libpq"), Int, (Ptr{Void},), r.handle)
function Base.getindex(r::Res, i :: Int, j :: Int)
    ptr = ccall((:PQgetvalue, "libpq"), Ptr{Uint8}, (Ptr{Void}, Int, Int), r.handle, i - 1, j - 1)
    len = ccall((:PQgetlength, "libpq"), Int, (Ptr{Void}, Int, Int), r.handle, i-1, j-1)
    buf = IOBuffer(pointer_to_array(ptr, len))
    parse(field_type(r, j), r, i, j, buf)
end
maybetuple(::Nothing, x) = x
maybetuple(::Nothing, xs...) = xs
maybetuple(T,xs...) = T(xs...)
Base.getindex(r::Res, i::Int) = r.singlecol ? r[i, 1] : ntuple(length(r.out_ncol_sum)-1, j -> maybetuple(r.out_types[j], r[i, r.out_ncol_sum[j]+1:r.out_ncol_sum[j+1]]...))
Base.getindex(r::Res, I) = [r[i] for i in I]
Base.getindex(r::Res, I, J) = [r[i,j] for i in I, j in J]
Base.start(r::Res) = 1
Base.next(r::Res,i) = (r[i], i+1)
Base.done(r::Res,i) = i>length(r)
Base.endof(r::Res) = length(r)
end
module Query
using Pg
abstract TableExpr
typealias Stx Union(Symbol, Expr)
type Literal{T} <: TableExpr
    val :: T
end

capt(::Literal) = {}
capt(::Expr) = {}

type JoinExpr <: TableExpr
    tables :: (TableExpr...,)
    condition :: Union(Stx, Nothing)
    way :: Symbol # :left, :right, :in, :out, :cross
end

capt(j::JoinExpr) = vcat(map(capt, j.tables)...)


function join(tables...; condition = Literal(nothing), way = Literal(nothing))
    w = way.val
    cond = condition.val
    if w == nothing
        w = cond == nothing ? :cross : :in
    end
    (w == :cross || length(tables) <= 2) || error("only cross join supports > 2 tables")
    (w == :cross || cond != nothing) || error("only cross join are unconditional")
    JoinExpr(tables, cond, w)
end
type AliasExpr <: TableExpr
    name :: Symbol
    table :: Symbol
end
capt(a::AliasExpr) = {a}
in(name :: Literal{Symbol}, table :: Literal{Symbol}) = AliasExpr(name.val, table.val)
function in(name :: Literal{Symbol}, table :: Literal{Expr})
    e = table.val
    if e.head == :.
        AliasExpr(name.val, symbol(string(e.args[1]) * "." * string(eval(e.args[2]))))
    else
        error()
    end
end

desc(x :: Literal) = Literal(Expr(:desc, x.val))
asc(x) = x

function parse(stx)
    if isa(stx, Expr)
        if stx.head == :call
            args = map(parse, stx.args[2:end])
            if Base.in(stx.args[1], names(Query, true))
                eval(Query, Expr(:call, stx.args[1], args...))
            else
                Literal(Expr(:call, stx.args[1], args...))
            end
        elseif stx.head == :in
            parse(Expr(:call, :in, stx.args...))
        elseif stx.head == :kw
            Expr(:kw, stx.args[1], map(parse, stx.args[2:end])...)
        else
            Literal(stx)
        end
    else
        Literal(stx)
    end
end

#=
type Thing frob :: One{Frob}; end
- for all (blah in some_things_table) in from clause
- all usages blah.frob => blah.frob_id, blah.frob.id => blah.frob_id
- blah.frob.X => _blah_frob.X
- in that case, in the from : (blah in some_things_table) => join(blah in some_things_table, _blah_frob in some_frob_table (which one ?), cond = blah.frob_id = _blah_frob.id)
=#
type One{T,pkT}
    pk :: pkT
    _data :: T
    One(pk) = new(pk)
end



type Select
    from :: TableExpr
    filter :: Union(Expr, Nothing)
    sort :: Union(Stx, Nothing)
    out :: Stx
    singlerow :: Bool
end

type Insert
    
end

capt(s::Select) = capt(s.from)
function select(from :: TableExpr; filter = Literal(nothing), sort = Literal(nothing), out = Literal(:*), single_row=false)
    Select(from, filter.val, sort.val, out.val, single_row)
end
find(from, filter; kws...) = select(from; filter = filter, kws...)
selectone(args...; kws...) = select(args...; single_row = true, kws...)
select(a, b; kws...) = error("What is this $a $b $kws")

type Context
    capt :: Vector
    mappings :: Dict
    last :: Int
    singlecol :: Bool
    singlerow :: Bool
    outs :: Vector
end
sql(c, lit :: Literal{Symbol}) = sql(c, lit.val)
function sql(c, s::Symbol)
    string(s)
end
sql(c, s::Int) = string(s)
sql(c, s::String) = "'$s'" # TODO ESCAPING!
sql(c, s::Char) = "'$s'"
sql(c, alias :: AliasExpr) = "$(alias.table) $(alias.name)"
function sql(c, j :: JoinExpr)
    if j.way == :cross
        Base.join(collect(map(x -> sql(c,x), j.tables)), " cross join ")
    else
        left = sql(c, j.tables[1])
        right = sql(c, j.tables[2])
        cond = sql(c, j.condition)
        join_type = [:in => "inner",
                     :out => "full",
                     :left => "left",
                     :right => "right"][j.way]
        "$left $join_type join $right on $cond"
    end
end

function sql_compare(c, left, op, right)
    o = string((op == :(==) ? :(=) : op))
    "$(sql(c, left)) $o $(sql(c, right))"
end
sql(c, e::Literal{Expr}) = sql(c, e.val)
function sql(c, expr :: Expr)
    if expr.head == :comparison
        length(expr.args) >= 3 || error("??")
        cmp = String[sql_compare(c, expr.args[i:i+2]...)
                     for i=1:2:length(expr.args)-2]
        Base.join(cmp, " and ")
    elseif expr.head == :.
        "$(expr.args[1]).$(eval(expr.args[2]))"
    elseif expr.head == :tuple
        Base.join(map(x -> sql(c, x), expr.args), ", ")
    elseif expr.head == :&&
        "($(sql(c, expr.args[1]))) and ($(sql(c, expr.args[2])))"
    elseif expr.head == :call
        if expr.args[1] == :!
            "not ($(sql(c, expr.args[2])))"
        else # TODO check for allowed functions ?
            "$(expr.args[1])($(sql(c, Expr(:tuple, expr.args[2:end]...))))"
        end
    elseif expr.head == :desc
        "$(sql(c, expr.args[1])) desc"
    elseif expr.head == :$
        num = get!(c.mappings, expr.args[1]) do # wtf
            c.last += 1
            c.last
        end
        "\$$num"
    else
        sql(c, eval(expr))#"?[$expr]"
    end
end

flatten_out(s::Symbol) = :($s.(*))
function flatten_out(s::Expr)
    if s.head == :. s
    elseif s.head == :tuple Expr(:tuple, map(flatten_out, s.args)...)
    else s
    end
end
remove_alias(c, s) = s
function remove_alias(capt, s::Expr)
    if s.head == :.
        alias = findfirst(x -> x.name == s.args[1], capt)
        alias > 0 || error("unknown alias $alias")
        Expr(:., capt[alias].table, s.args[2])
    else s end
end

function sql(c, s :: Select)
    singlecol = !(isa(s.out, Expr) && s.out.head == :tuple)
    singlecol &= s.out != :*# || length(c.capt) == 1)
    c.singlecol = singlecol
    c.singlerow = s.singlerow
    if s.out == :*
        c.outs = map(x -> x.name, c.capt)
        s.out = Expr(:tuple, c.outs...)
    elseif isa(s.out, Symbol) || (isa(s.out, Expr) && (s.out.head == :. || s.out.head == :call))
        c.outs = {s.out}
    elseif isa(s.out, Expr) && s.out.head == :tuple
        c.outs = s.out.args
    else
        dump(s.out)
        error("What $(s.out) :: $(typeof(s.out)) is this")
    end
    s.out = flatten_out(s.out)
    map!(flatten_out, c.outs)
    map!(x -> remove_alias(c.capt, x), c.outs)
    q = "select $(sql(c, s.out)) from $(sql(c, s.from))" *
    (s.filter == nothing ? "" : " where $(sql(c, s.filter))") *
    (s.sort == nothing ? "" : " order by $(sql(c, s.sort))")
    q
end
result(q :: Pg.Prepared, args) = Pg.run(Pg.conn(), q, args)
macro sql(stx)
    q = parse(stx)
    c = Context(capt(q), Dict(), 0, false, false, {})
    qs = Pg.Prepared(sql(c, q), c.singlecol, c.singlerow, c.outs)
    vs = collect(keys(c.mappings))
    sort!(vs, by=x->c.mappings[x])
    rx = :(Query.result($qs, {$(map(esc, vs)...)}))
#    println("Expan $rx")
    rx
end

end

using Query.@sql


function discover_oid(c, o)
    r = @sql select(join(join(ty in pg_catalog.pg_type, cl in pg_catalog.pg_class,
                              condition = ty.typrelid == cl.oid),
                         attr in pg_catalog.pg_attribute,
                         condition = cl.oid == attr.attrelid),
                    filter = ty.oid == $o && ty.typtype == 'c' && attr.attnum > 0,
                    out = attr.atttypid)
    if length(r) == 0
        error("Unknown OID $o")
    end
    types = map(x -> Pg.oid_type(c, Pg.oid(x[1])), r |> collect)
    Pg.oid_to_julia[o] = tuple(types...)
end

function tablefields(table_name)
    qp = @sql select(join(attr in pg_catalog.pg_attribute, tbl in pg_catalog.pg_class,
                          condition = attr.attrelid == tbl.oid),
                     filter = tbl.relname == $(string(table_name)) && attr.attnum > 0,
                     sort = attr.attnum,
                     out = (attr.attname, attr.atttypid))
    convert(Vector{(Symbol, Type)}, map(collect(qp)) do t
        name, ty = t
        (symbol(name), Pg.oid_type(ty))
    end)
end
immutable Pk{T}
    val :: T
end
Base.convert{T}(::Type{T}, pk::Pk{T}) = pk.val
Base.convert{pkT}(::Type{Pk{pkT}}, ::Pk) = error()
Base.convert{pkT, T}(::Type{Pk{pkT}}, v::T) = Pk(convert(pkT, v))
type TableBinding
    row_type :: Type
    table :: Symbol
    sql_row_type :: (Any...)
    # col_index => field index in row_type or 0
    field_map :: Vector{Int}
    # reverse
    col_map :: Vector{Int}
    # primary key position in T and table, or 0
    pk_field :: Int
    pk_col :: Int
end
const bindings = Dict{Type, TableBinding}()
const rev_bindings = Dict{Symbol, Type}()
function bind(t::Type, table :: Symbol)
    tn = names(t)
    tbn = tablefields(table)
    field_map = [findfirst(tn, table_field[1])
                 for table_field in tbn]
    for i = 1:length(tbn)
        field_map[i] > 0 || continue
        ft = t.types[field_map[i]]
        if !method_exists(convert, (Type{ft}, tbn[i][2]))
            error("Binding error: cannot convert $ft ($t) => $(tbn[i][2]) ($table).")
        end
    end
    t_pk_ind = 0
    col_map = [findfirst(map(first, tbn), t_field)
               for t_field in tn]
    for i = 1:length(tn)
        if t.types[i] <: Pk
            if col_map[i] == 0
                error("Primary key $(tn[i]) in $t does not exist in the table $table.")
            end
            if t_pk_ind > 0
                error("Cannot have more than one primary key. In $t : $(tn[t_pk_ind]) and $(tn[i]).")
            end
            t_pk_ind = i
        end
        col_map[i] > 0 || continue
        colt = tbn[col_map[i]][2]
        if !method_exists(convert, (Type{colt}, t.types[i]))
            error("Binding error: cannot convert $colt ($table) => $(tn[i]) ($t).")
        end
    end

    if t_pk_ind > 0
        res = @sql select(join(cl in pg_catalog.pg_class,
                         cs in pg_catalog.pg_constraint,
                         condition = cl.oid == cs.conrelid),
                    filter = cl.relname == $(string(table)) && cs.contype == 'p',
                    out = cs.conkey)
        length(res) > 0 || error("Table $table has no primary key but $t has one : $(tn[t_pk_ind])")
        pkey = res[1]
        length(pkey) == 1 || error("We do not support yet pkey on multiple columns : $pkey")
        pkey = pkey[1]
        pkey == col_map[t_pk_ind] || error("Mismatch in pkey column. Declaared $(col_map[t_pk_ind]) in $t, got $pkey in $table")
    end

    r = @sql select(join(ty in pg_catalog.pg_type,
                         cl in pg_catalog.pg_class,
                         condition = ty.typrelid == cl.oid),
                    filter = cl.relname == $(string(table)),
                    out = ty.oid)
    ty_oid = Pg.oid(r[1][1])
    Pg.oid_to_julia[ty_oid] = t
    b = TableBinding(t, table, tuple(map(x->x[2], tbn)...), field_map, col_map, t_pk_ind, t_pk_ind > 0 ? col_map[t_pk_ind] : 0)
    bindings[t] = b
    rev_bindings[table] = t
    b
end
type A
    x :: Int
    plop :: String
end
type P
    id :: Pk{Int}
    y :: Int
#    z :: Pk{Int}
end
#=type Ad
    id :: Pk{Int}
    p :: One{P}
    z :: Int
end=#

Pg.connect((String=>String)[]) do
    println("Status : ", Pg.status(Pg.conn()))
    x = Pg.run(Pg.conn(), "select '{1,2,3,4,5}' :: int2[]", {})
    println(x)
    x = Pg.run(Pg.conn(), "select '{1,2,3,4,5}' :: int4[]", {})
    println(x)
    x = Pg.run(Pg.conn(), "select '{1,2,3,4,5}' :: oid[]", {})
    println(x)
    u = int32(3)
    x = @sql select(a in aa,
                    filter = a.x == $u,
                    out = a.x)
    print("X $(x.out_types) $(x)")
    bind(P, :pp2)
    bind(A, :aa)
    x = @sql select(p in pp)
    println(x)
    exit()
    x = @sql selectone(a in aa, filter = a.x == $u)
    println(x)
    x = @sql selectone(a in aa, filter = a.x == $u, out = a)
    println(x)
    x = @sql selectone(a in aa, filter = a.x == $u, out=a)
    println(x)
    for i=1:10
    x = @sql find(a in aa, a.x >= $u, out = (a, least(a.x, 0), a))
    print(x)
    end
end
