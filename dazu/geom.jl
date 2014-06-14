
ns = Vec3[]
ix = Uint16[]

type Face{n}
    vertices :: NTuple{n, Uint16}
end

typealias Tri Face{3}

type CSG
    vs :: Vector{Vec3}
    faces :: Set{Face}
end

type BSP
    faces :: Vector{Face}
    front :: Union(BSP, Nothing)
    back :: Union(BSP, Nothing)
end

BSP() = BSP(Face[], nothing, nothing)

function csg_cube()
    vs = [vec3(-1, 1, 1), vec3(1, 1, 1), vec3(1, 1, -1), vec3(-1, 1, -1),
          vec3(-1, -1, 1), vec3(-1, -1, -1), vec3(1, -1, -1), vec3(1, -1, 1)]
    fs = Set{Face}(Face(0,1,2,3), Face(4, 5, 6, 7), Face(1, 0, 4, 7), Face(3, 2, 6, 5), Face(0, 3, 5, 4), Face(2, 1, 7, 6))
    CSG(vs, fs)
end

wire = false

function triangulate{n}(f :: Face{n})
    n < 3 && error("")
    if n == 3
        fv = f.vertices
        wire ? [fv[1], fv[2], fv[2], fv[end], fv[end], fv[1]] :  [f.vertices...]
    else
        fv = f.vertices
        ff = Face(fv[2:end])
        append!(triangulate(ff), triangulate(Face(fv[1], fv[2], fv[end])))#fv[1], fv[2], fv[2], fv[end], fv[end], fv[1])
    end
end



function normal{n}(csg :: CSG, f :: Face{n})
    n < 3 && error("")
    normalize(cross(csg.vs[f.vertices[2] + 1] - csg.vs[f.vertices[1] + 1], csg.vs[f.vertices[3] + 1] - csg.vs[f.vertices[1] + 1]))
end

function side(o :: Vec3, n :: Vec3, p :: Vec3)
    d = dot(p - o, n)
    if abs(d) < 1e-5
        0
    elseif d > 0
        1
    else
        -1
    end
end

function center(csg :: CSG, f :: Face)
    +(map(x -> csg.vs[x+1], f.vertices)...)/length(f.vertices)
end

function side(csg :: CSG, p :: Vec3, pref)
    min_d = inf(Float32)
    min_s = 0
    for f in csg.faces
        o = csg.vs[f.vertices[1] + 1]
        n = normal(csg, f)
        s = side(o, n, p)
#        s == 0 && return 0
        d = minimum([norm2(p - csg.vs[vi + 1]) for vi in f.vertices])
        if d < min_d || (d == min_d && min_s == -1 && s != 0)
            min_s = s
            min_d = d
        end
    end
    min_s
end

#    n = normal(ref)
#    o = ref.vertices[1]

function splitsegment(o :: Vec3, n :: Vec3, v1 :: Vec3, v2 :: Vec3)
    dl = normalize(v2 - v1)
    # dot(v1 - o + l*dl, n) = 0
    abs(dot(dl, n)) < 1e-15 && return (v1 + v2)/2#error("??")
    l = dot(o - v1, n)/dot(dl, n)
    v1 + l*dl
end

function splitface{nf}(o :: Vec3, n :: Vec3, csg :: CSG, f :: Face{nf})
    sides = map(v -> side(o, n, csg.vs[v+1]), f.vertices)
    c = (count(x -> x == 1, sides), count(x -> x == -1, sides), count(x -> x == 0, sides))
    
    if c[1] == nf || c[2] == 0 # all front
        (f, nothing, nothing)
    elseif c[2] == nf || c[1] == 0 # all back
        (nothing, nothing, f)
    elseif c[3] == nf # all coplanar
        (nothing, f, nothing)
    else # there is at least a vertex front and a vertex back
        res = (Uint16[], Uint16[], Uint16[])
        for i = 1:nf
            sides[i] != -1 && push!(res[1], f.vertices[i])
            sides[i] != 1  && push!(res[3], f.vertices[i])
            ni = (i % nf) + 1
            if sides[i] != 0 && sides[ni] != 0 && sides[i] != sides[ni]
                spv = splitsegment(o, n, csg.vs[f.vertices[i]+1], csg.vs[f.vertices[ni]+1])
                push!(csg.vs, spv)
                push!(res[1], length(csg.vs) - 1)
                push!(res[3], length(csg.vs) - 1)
                push!(res[2], length(csg.vs) - 1)
            end
        end
        f1 = Face(res[1]...)
        f2 = Face(res[3]...)
        push!(csg.faces, f1)
        push!(csg.faces, f2)
        pop!(csg.faces, f)
        (f1, res[2], f2)
    end
end

edge{nf}(f :: Face{nf}, i) = (f.vertices[i], f.vertices[i % nf + 1])
function nh(csg :: CSG, f :: Face, edge_i)
    e = edge(f, edge_i)
    for ff in csg.faces
        for i=1:length(ff.vertices)
            if edge(ff, i) == e
                return (f, i)
            end
        end
    end
    nothing
end

import Base.show
function show(io :: IO, f :: Face)
    println(io, "F($(map(int, f.vertices)) | $(map(x -> vs[x+1], f.vertices)))")
end

Face(v...) = Face(v)
Face(v) = (length(v) < 3 && error("<3"); Face(map(uint16, v)))

cube = csg_cube()

function bis!(csg)
    f_pts = map(x -> x.vertices, csg.faces)
    for f in f_pts, pt_i in f
        o = normalize(csg.vs[pt_i + 1])
        n = -o
        cut_vertices = Uint16[]
        for face in copy(csg.faces)
            front,mid,b = splitface(o, n, csg, face)
            b != nothing && pop!(csg.faces, b)
            if isa(mid, Vector{Uint16})
                append!(cut_vertices, mid)
            end
        end
    end
end

function splitfor(a :: CSG, b :: CSG)
    merge_vertices!(a, b)
    for fb in b.faces
        for fa in copy(a.faces)
            splitface(b.vs[fb.vertices[1] + 1], normal(b, fb), a, fa)
        end
    end
    for fa in a.faces
        for fb in copy(b.faces)
            splitface(a.vs[fa.vertices[1] + 1], normal(a, fa), b, fb)
        end
    end
    for fa in copy(a.faces)
        v = fa.vertices
        s = map(x -> side(b, a.vs[x+1], 1), v)
#        println(s)
        if all(x -> x <= 0, s) && !all(x -> x == 0, s)
            pop!(a.faces, fa)
        end
    end
#    return
#    println("===")
    supf = Set{Face}()
    for fb in b.faces
        v = fb.vertices
        s = map(x -> side(a, b.vs[x+1], -1), v)
#        println(s)
        if !all(x -> x >= 0, s) && !all(x -> x == 0, s)
            fa = Face(reverse(fb.vertices)...)
            push!(supf, fa)
        end
    end
    union!(a.faces, supf)
#    exit()
end

function xf!(csg :: CSG, v :: Vec3)
    for i = 1:length(csg.vs)
        csg.vs[i] += v
    end
end

function xf!(csg :: CSG, m :: Mat4)
    for i = 1:length(csg.vs)
        v = m*vec4(csg.vs[i])
        csg.vs[i] = vec3(v.x, v.y, v.z)
    end
end

# merges the vertice lists, does not touch geometry
function merge_vertices!(a :: CSG, b :: CSG)
    if length(a.vs) < length(b.vs)
        merge_vertices(b, a)
    else
        l = length(a.vs)
        for f in b.faces
            f.vertices = map(x -> uint16(x + l), f.vertices)
        end
        a.vs = append!(a.vs, b.vs)
        b.vs = a.vs
        return
        dup = Dict{Int,Int}()
        p = sortperm(a.vs)
        for i = 1:length(vs)-1
            if vs[p[i]] == vs[p[i+1]]
                if haskey(dup, p[i])
                    dup[p[i+1]] = dup[p[i]]
                else
                    dup[p[i+1]] = p[i]
                end
            end
        end
        filter!((x,y) -> x != y, dup)
    end
end

cube2 = csg_cube()
xf!(cube2, translation(vec4(1, 1, 0))*rotation_x(float32(-pi/3))*rotation_z(float32(pi/3)))
#xf!(cube2, translation(vec4(1, 1, 1)))
splitfor(cube, cube2)
#cube3 = csg_cube()
#xf!(cube3, translation(vec4(-1, 1, 0))*rotation_x(float32(pi/3)))
#csplitfor(cube, cube3)

function upd(cube)
    global ix, ns
    nf = [0 for i in cube.vs]
    ns = [vec3() for i in cube.vs]
    for f in cube.faces
        for v in f.vertices
            nf[v+1] += 1
            ns[v+1] += normal(cube, f)
    end
    end
    for i = 1:length(ns)
        ns[i] /= nf[i]
        ns[i] = normalize(ns[i])
    end
    ix = vcat(map(triangulate, cube.faces)...)
end
upd(cube)
w() = (global wire; wire = !wire; upd(cube))
function rendercsg(p)
    bind(NoVertexBuffer)
    glUseProgram(flat_shader.program)
    set_uniform(flat_shader.uniforms[ :proj ], p*scale(30f0))
    bind_attr(flat_shader.attributes[ :pos ], cube.vs)
    bind_attr(flat_shader.attributes[ :nor ], ns)
    glDrawElements(wire ? GL_LINES : GL_TRIANGLES, length(ix), GL_UNSIGNED_SHORT, ix)
end
