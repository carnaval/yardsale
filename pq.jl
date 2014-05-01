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
end

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

function pqres(c, r, onecol)
    ncol = ccall((:PQnfields, "libpq"), Int, (Ptr{Void},), r)
    res = Res(c, r, ncol, onecol)
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
end
Prepared(query, singlecol, singlerow) = begin
    Prepared(query, "q_" * hex(hash(query)) * string(time()), false, singlecol, singlerow)
end

function prepare(c :: Conn, p :: Prepared)
    p.prepared && return
    if run(c, "select count(*) from pg_prepared_statements where name = \$1", {p.name})[1][1] == 0
        r = ccall((:PQprepare, "libpq"), Ptr{Void}, (Ptr{Void}, Ptr{Uint8}, Ptr{Uint8}, Int, Ptr{Oid}),
                  c.handle, p.name, p.query, 0, 0)
        pqres(c, r, false)
    end
    p.prepared = true
end

function run(c :: Conn, code :: Prepared, params :: Vector)
    prepare(c, code)
    println("SQL: $(code.query) | \$=$params")
    vals = convert(Vector{Vector{Uint8}},
                   map(x -> convert(Vector{Uint8}, utf8(string(x))),
                       params))
    r = ccall((:PQexecPrepared, "libpq"),
              Ptr{Void}, (Ptr{Void}, Ptr{Uint8}, Int,
                          Ptr{Ptr{Uint8}}, Ptr{Int}, Ptr{Int}, Int),
              c.handle, code.name, length(params),
              pointer(map(pointer, vals)), pointer(map(length, vals)), pointer(zeros(length(params))), 1)
    res = pqres(c, r, code.singlecol)
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
     oid(705) => String]
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

Base.length(r::Res) = ccall((:PQntuples, "libpq"), Int, (Ptr{Void},), r.handle)
function Base.getindex(r::Res, i :: Int, j :: Int)
    ptr = ccall((:PQgetvalue, "libpq"), Ptr{Uint8}, (Ptr{Void}, Int, Int), r.handle, i - 1, j - 1)
    len = ccall((:PQgetlength, "libpq"), Int, (Ptr{Void}, Int, Int), r.handle, i-1, j-1)
    buf = IOBuffer(pointer_to_array(ptr, len))
    parse(field_type(r, j), r, i, j, buf)
end
Base.getindex(r::Res, i::Int) = r.singlecol ? r[i, 1] : ntuple(r.ncol, j -> r[i, j])
Base.getindex(r::Res, I) = [r[i] for i in I]
Base.start(r::Res) = 1
Base.next(r::Res,i) = (r[i], i+1)
Base.done(r::Res,i) = i>length(r)
Base.endof(r::Res) = length(r)
end
module Query
using Pg
abstract TableExpr

type Literal{T} <: TableExpr
    val :: T
end

capt(::Literal) = Set{Symbol}()

type JoinExpr <: TableExpr
    tables :: (TableExpr...,)
    condition :: Union(Literal{Expr}, Nothing)
    way :: Symbol # :left, :right, :in, :out, :cross
end

capt(j::JoinExpr) = union(map(capt, j.tables)...)


function join(tables...; condition = nothing, way = nothing)
    if way == nothing
        way = Literal(condition == nothing ? :cross : :in)
    end
    w = way.val
    (w == :cross || length(tables) <= 2) || error("only cross join supports > 2 tables")
    (w == :cross || condition != nothing) || error("only cross join are unconditional")
    JoinExpr(tables, condition, w)
end
type AliasExpr <: TableExpr
    name :: Symbol
    table :: Symbol
end
capt(a::AliasExpr) = Set({a.name})
in(name :: Literal{Symbol}, table :: Literal{Symbol}) = AliasExpr(name.val, table.val)
function in(name :: Literal{Symbol}, table :: Literal{Expr})
    e = table.val
    if e.head == :.
        AliasExpr(name.val, symbol(string(e.args[1]) * "." * string(eval(e.args[2]))))
    else
        error()
    end
end

desc(x :: Literal{Expr}) = Literal(Expr(:desc, x.val))
asc(x) = x

function parse(stx)
    if isa(stx, Expr)
        if stx.head == :call
            args = map(parse, stx.args[2:end])
            eval(Expr(:call, stx.args[1], args...))
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

type Select
    from :: TableExpr
    filter :: Union(Expr, Nothing)
    sort :: Union(Expr, Nothing)
    out :: Expr
    singlerow :: Bool
end

type Insert
    
end

capt(s::Select) = capt(s.from)
function select(from :: TableExpr; filter = Literal(nothing), sort = Literal(nothing), out = Literal(Expr(:quote, :*)), single_row=false)
    Select(from, filter.val, sort.val, isa(out.val, Symbol) ? Expr(:quote, out.val) : out.val, single_row)
end
find(from, filter; kws...) = select(from; filter = filter, kws...)
selectone(args...; kws...) = select(args...; single_row = true, kws...)
select(a, b; kws...) = error("What is this $a $b $kws")

type Context
    capt :: Set
    mappings :: Dict
    last :: Int
    singlecol :: Bool
    singlerow :: Bool
end
sql(c, lit :: Literal{Symbol}) = sql(c, lit.val)
function sql(c, s::Symbol)
    if !Base.in(s, c.capt)
        warn("'$s' seems unsuned ...")
    end
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
        else
            "??[$expr]"
        end
#    elseif expr.head == :quote
#        sql(c, eval(expr))
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

function sql(c, s :: Select)
    singlecol = !(isa(s.out, Expr) && s.out.head == :tuple)
    singlecol &= s.out != Expr(:quote, :*)
    c.singlecol = singlecol
    c.singlerow = s.singlerow
    "select $(sql(c, s.out)) from $(sql(c, s.from))" *
    (s.filter == nothing ? "" : " where $(sql(c, s.filter))") *
    (s.sort == nothing ? "" : " order by $(sql(c, s.sort))")
end
result(q :: Pg.Prepared, args) = Pg.run(Pg.conn(), q, args)
macro sql(stx)
    q = parse(stx)
    c = Context(push!(capt(q), :*), Dict(), 0, false, false)
    qs = Pg.Prepared(sql(c, q), c.singlecol, c.singlerow)
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

type A
    x :: Int32
    plop :: String
end

type TableBinding
    row_type :: Type
    table :: Symbol
    sql_row_type :: (Any...)
    # col_index => field index in row_type or 0
    field_map :: Vector{Int}
    # reverse
    col_map :: Vector{Int}
end
const bindings = Dict{Type, TableBinding}()
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
    col_map = [findfirst(map(first, tbn), t_field)
               for t_field in tn]
    for i = 1:length(tn)
        col_map[i] > 0 || continue
        colt = tbn[col_map[i]][2]
        if !method_exists(convert, (Type{colt}, t.types[i]))
            error("Binding error: cannot convert $colt ($table) => $(tn[i]) ($t).")
        end
    end
    tn = string(table)
    r = @sql select(join(ty in pg_catalog.pg_type,
                         cl in pg_catalog.pg_class,
                         condition = ty.typrelid == cl.oid),
                    filter = cl.relname == $(string(table)),
                    out = ty.oid)
    ty_oid = Pg.oid(r[1][1])
    Pg.oid_to_julia[ty_oid] = t
    b = TableBinding(t, table, tuple(map(x->x[2], tbn)...), field_map, col_map)
    bindings[t] = b
    b
end

Pg.connect((String=>String)[]) do
    println("Status : ", Pg.status(Pg.conn()))
    u = int32(3)
    x = @sql select(a in aa,
                    filter = a.x == $u,
                    out = (a, a.x))
    print("X $(x)")
    bind(A, :aa)
    x = @sql selectone(a in aa, filter = a.x == $u, out = a)
    println(x)
    x = @sql find(a in aa, a.x == $u, out = (a,a.x,a))
    print(x)
end
