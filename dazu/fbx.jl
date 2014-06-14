include("math.jl")

type Node
    id :: Uint64
    name :: Symbol
    class :: Symbol
    children :: Vector{(Symbol, Any)}
end
macro eval(x)
    quote
        a = Base.@eval(x)
        println(a)
        a
    end
end
function skipws(io :: IO)
    while !eof(io)
        c = read(io, Char)
        c in (' ', '\t', '\n') && continue
        if c == ';'
            readuntil(io, '\n')
            continue
        end
        skip(io, -1)
        break
    end
end
function read_symbol(io :: IO)
    _io = IOBuffer()
    skipws(io)
    while !eof(io)
        c = read(io, Char)
        if !isalnum(c) && c != '_'
            skip(io, -1)
            break
        end
        write(_io, c)
    end
    seekstart(_io)
    symbol(readall(_io))
end
isnumpart(c :: Char) = isdigit(c) || c == '.' || c == '-' || c == 'e'
function read_num(io :: IO)
    _io = IOBuffer()
    skipws(io)
    while !eof(io)
        c = read(io, Char)
        if !isnumpart(c)
            skip(io, -1)
            break
        end
        write(_io, c)
    end
    seekstart(_io)
    readall(_io)
end


function read_tok(io, c)
    skipws(io)
    if read(io, Char) != c
        skip(io, -1)
        false
    else
        true
    end
end

function peek_tok(io, c)
    skipws(io)
    cc = read(io, Char)
    skip(io, -1)
    c == cc
end

function read_val(io :: IO)
    skipws(io)
    c = read(io, Char)
    if c == '"'
        readuntil(io, '"')[1:end-1]
    elseif c == '*'
        read_num(io)
    elseif c == 'T'
        true
    elseif isnumpart(c)
        skip(io, -1)
        read_num(io)
    else
        skip(io, -1)
        error(readuntil(io, '\n'))
    end
end
function read_csv(io :: IO, term :: Char)
    peek_tok(io, term) && return {}
    vals = {read_val(io)}
    while read_tok(io, ',')
        push!(vals, read_val(io))
    end
    vals
end

function read_body(io :: IO)
    read_tok(io, "{"[1]) || error(readuntil(io, '\n'))
    pairs = {}
    while !read_tok(io, "}"[1])
        push!(pairs, read_pair(io))
    end
    pairs
end

function read_pair(io :: IO)
    pname = read_symbol(io)
    read_tok(io, ':') || error(readuntil(io, '\n'))
    vals = read_csv(io, "{"[1])
    
    if peek_tok(io, "{"[1])
        body = read_body(io)
        if length(vals) == 0
            id,name,class = 0, symbol(""), symbol("")
        elseif length(vals) == 1
            id,name,class = 0, symbol(vals[1]), symbol("")
        elseif length(vals) == 2
            id,name,class = 0, symbol(vals[1]), symbol(vals[2])
        elseif length(vals) == 3
            id,name,class = parseint(vals[1]), symbol(vals[2]), symbol(vals[3])
        else
            error(vals)
        end
        return (pname, Node(id, name, class, body))
    else
        return (pname, vals)
    end
end

function read_fbx(io :: IO)
    root = Node(0, :root, symbol(""), {})
    while !eof(io)
        push!(root.children, read_pair(io))
        skipws(io)
    end
    root
end

Base.getindex(n :: Node, i :: Int) = n.children[i][2]
Base.getindex(n :: Node, k :: Symbol) = map(x -> x[2], filter(x -> x[1] == k, n.children))
Base.getindex(n :: Node, k :: Symbol, J) = n[k][J]
typealias FbxId Uint64
type Geometry
    vertices :: Vector{Vec3}
    indices :: Vector{Uint16}
end
type Model
    name :: Symbol
    
    parent :: Union(Model, Nothing)
    children :: Vector{Model}
    
    pre_rot
    lcl_trn
    lcl_rot
    lcl_scl
    geom :: Geometry
    Model(name) = new(name, nothing, Model[])
end
type FbxDoc
    geom :: Dict{FbxId, Geometry}
    models :: Dict{FbxId, Model}
    
    objects :: Dict{FbxId, Any}
    
    FbxDoc(g, m) = (d = new(g, m); d.objects = Dict(union(g, m)); d)
end

function Base.print(io::IO, f::FbxDoc)
    vcount = sum(map(g -> length(g.vertices), values(f.geom)))
    tricount = sum(map(g -> length(g.indices), values(f.geom)))/3
    print(io, "Fbx(", length(f.models), " models, ", length(f.geom), " geometries, ",  vcount, " vertices, ", tricount, " tris)")
end

Base.print(io::IO, g::Geometry) = print(io, "Geom(v: ", length(g.vertices), ", i: ", length(g.indices), ")")
function Base.print(io::IO, m::Model)
    print(io, "Model(", m.name)
    if m.parent != nothing
        print(io, ", parent=", m.parent.name)
    end
    if !isempty(m.children)
        print(io, ", children={", join(map(x->x.name, m.children), ", "), "}")
    end
    if isdefined(m, :geom)
        print(io, ", geometry=", m.geom)
    end
    print(io, ")")
end

function parse_geom(n :: Node)
    vx = map(parsefloat, n[:Vertices, 1][:a, 1])
    @assert length(vx) % 3 == 0
    ix = map(parseint, n[:PolygonVertexIndex, 1][:a, 1])
    (n.id, Geometry([vec3(vx[i:i+2]...) for i=1:3:length(vx)], ix))
end

function parse_model(n :: Node)
    model = Model(n.name)
    props = n[:Properties70, 1][:P]
    for prop in props
        pn = prop[1]
        if pn == "PreRotation"
            model.pre_rot = map(parsefloat, prop[5:7])
        elseif pn == "Lcl Translation"
            model.lcl_trn = map(parsefloat, prop[5:7])
        elseif pn == "Lcl Rotation"
            model.lcl_rot = map(parsefloat, prop[5:7])
        elseif pn == "Lcl Scaling"
            model.lcl_scl = map(parsefloat, prop[5:7])
        end
    end
    (n.id, model)
end

function parse_fbx(n :: Node)
    obj = n[:Objects, 1]
    geoms = map(parse_geom, obj[:Geometry])
    models = map(parse_model, obj[:Model])
    doc = FbxDoc(Dict{FbxId, Geometry}(geoms),
                 Dict{FbxId, Model}(models))
    
    conns = n[:Connections, 1][:C]
    for conn in conns
        if conn[1] == "OO"
            link_objects(doc, parseint(FbxId, conn[2]), parseint(FbxId, conn[3]))
        elseif conn[1] == "OP"
            link_prop(doc, conn[2], conn[3], conn[4])
        else
            error(conn[1])
        end
    end
    doc
end

function link_objects(doc :: FbxDoc, id_child :: FbxId, id_parent :: FbxId)
    child = get(doc.objects, id_child, nothing)
    parent = get(doc.objects, id_parent, nothing)
    child != nothing && parent != nothing || return
    link_objects(doc, child, parent)
end

function link_objects(doc :: FbxDoc, c :: Geometry, p :: Model)
    isdefined(p, :geom) && error("Two geometry for model $p")
    p.geom = c
end
function link_objects(doc :: FbxDoc, c :: Model, p :: Model)
    c.parent != nothing && error("Two parents for model $c")
    c.parent = p
    c in p.children && error("Model $c is already a child of $p")
    push!(p.children, c)
end
link_objects(doc :: FbxDoc, c, p) = println("Unknown link type $c -> $p")

function link_prop(doc :: FbxDoc, id_child, id_parent, prop_name)
    
end
println(ARGS)
@time x = open(read_fbx, ARGS[1])
@time f = parse_fbx(x)
f |> println
map(x -> x[2] |> println, f.models)
