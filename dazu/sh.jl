
type ShaderAttrib
    name :: Symbol
    ty :: Int32
    size :: Int32
    loc :: Int32
    alias_name :: Symbol
    storage_index :: Int
end

ShaderAttrib(n,t,s,l) = ShaderAttrib(n,t,s,l,n,-1)

abstract Uniforms

type Shader
    name :: Symbol
    vs :: Uint32
    fs :: Uint32
    program :: Uint32
    attributes :: Dict{Symbol, ShaderAttrib}
    uniforms :: Type
    instance_count :: Int
    draw_count :: Int
end

import Base.show

function show(io::IO, shader::Shader)
    println(io, "Shader $(shader.name)")
#=    for (_, v) in shader.uniforms
        print(io, "- [U] ")
        show(io, v)
        println()
    end
    for (_, v) in shader.attributes
        print(io, "- [A] ")
        show(io, v)
        println()
    end=#
end

@table lookup_bytetype [ GL_FLOAT => GL_FLOAT,
     GL_FLOAT_VEC2 => GL_FLOAT,
     GL_FLOAT_VEC3 => GL_FLOAT,
     GL_FLOAT_VEC4 => GL_FLOAT,
     GL_FLOAT_MAT2 => GL_FLOAT,
     GL_FLOAT_MAT3 => GL_FLOAT,
     GL_FLOAT_MAT4 => GL_FLOAT,
     GL_UNSIGNED_INT => GL_UNSIGNED_BYTE, # warning here
     GL_UNSIGNED_INT_VEC2 => GL_UNSIGNED_BYTE,
     GL_UNSIGNED_INT_VEC3 => GL_UNSIGNED_BYTE,
     GL_UNSIGNED_INT_VEC4 => GL_UNSIGNED_BYTE,
     GL_SAMPLER_1D => GL_UNSIGNED_BYTE,
     GL_SAMPLER_2D => GL_UNSIGNED_BYTE,
     GL_SAMPLER_3D => GL_UNSIGNED_BYTE,
                        0x8dc1 => GL_UNSIGNED_BYTE]

function attr_bytetype(a :: ShaderAttrib)
     lookup_bytetype(a.ty)
end

@table julia_type_raw [GL_FLOAT => Float32,
                       GL_FLOAT_VEC2 => Vec2,
                       GL_FLOAT_VEC3 => Vec3,
                       GL_FLOAT_VEC4 => Vec4,
                       GL_FLOAT_MAT4 => Mat4,
                       GL_UNSIGNED_INT_VEC2 => Vector2{Uint8},
                       GL_UNSIGNED_INT_VEC3 => Vector3{Uint8},
                       GL_UNSIGNED_INT_VEC4 => Vector4{Uint8},
                       GL_SAMPLER_1D => Int32,
                       GL_SAMPLER_2D => Int32,
                       GL_SAMPLER_3D => Int32,
                       GL_SAMPLER_CUBE => Int32,
                       GL_SAMPLER_2D_ARRAY => Int32]
function julia_type(u :: ShaderAttrib)
    eltype = julia_type_raw(u.ty)
    u.storage_index == -1 || return TypedBuffer{eltype, GpuBuffer}
    u.size == 1 && return eltype
    Vector{eltype}
end

@table lookup_primsize [GL_FLOAT => 1,
     GL_FLOAT_VEC2 => 2,
     GL_FLOAT_VEC3 => 3,
     GL_FLOAT_VEC4 => 4,
     GL_FLOAT_MAT2 => 4,
     GL_FLOAT_MAT3 => 9,
     GL_FLOAT_MAT4 => 16,
#     GL_UNSIGNED_INT => 1
     GL_UNSIGNED_INT_VEC2 => 2,
     GL_UNSIGNED_INT_VEC3 => 3,
     GL_UNSIGNED_INT_VEC4 => 4,
     GL_SAMPLER_1D => 1,
     GL_SAMPLER_2D => 1,
     GL_SAMPLER_3D => 1,
     0x8dc1 => 1]

function attr_primsize(a :: ShaderAttrib)
    lookup_primsize(a.ty)
end

@table lookup_bytesize [GL_FLOAT => 4, GL_UNSIGNED_BYTE => 1]

function bytesize(a :: ShaderAttrib)
    lookup_primsize(a.ty)*lookup_bytesize(lookup_bytetype(a.ty))
end

function show(io::IO, attr::ShaderAttrib)
    @printf(io, "%s %s:: %s*%d",
            attr.name, (if attr.size != 1 "[$(attr.size)] " else "" end),
            { GL_FLOAT => "float", GL_UNSIGNED_BYTE => "uchar" }[attr_bytetype(attr)],
            attr_primsize(attr))
end

function canon_name(n)
    if length(n) >= 3 && n[end-2:end] == "[0]"
        n[1:end-3]
    else
        n
    end
end

function shader_error(s)
    len = Int32[-1]
    ERR()
    glGetShaderiv(s, GL_INFO_LOG_LENGTH, len)
    if len[1] > 0
        log = string([' ' for i=1:len[1]]...)
        glGetShaderInfoLog(s, len[1], len, log)
        println("Shader log :\n", log)
    else
        println("Unknown shader error : $(len[1]).")
    end
end

function shader_program_error(s)
    len = Int32[-1]
    glGetProgramiv(s, GL_INFO_LOG_LENGTH, len)
    if len[1] > 0
        log = string([' ' for i=1:len[1]]...)
        glGetProgramInfoLog(s, len[1], len, log)
        println("Shader log :\n", log)
    else
        println("Unknown shader program error")
    end
end

function compile_shader(name, vs_source :: String, fs_source :: String, inputs = {}, instance_count = 1, draw_count = 1)
    const PREFIX = "#version 440\n" *
    "#extension GL_ARB_shader_draw_parameters : enable\n"
    const VS_PREFIX = """
    #define VS
    #define gl_DrawID gl_DrawIDARB
    #define gl_InstanceIDX gl_InstanceID
    out flat int _DrawID_frag;
    out flat int _InstanceID_frag;
    void vertex(void);
    void main(void) { _DrawID_frag = gl_DrawID; _InstanceID_frag = gl_InstanceID; vertex(); }
    #define main vertex\n""" # lol todo change this
    const FS_PREFIX = """
    #define FS
    #define gl_DrawID _DrawID_frag
    #define gl_InstanceID _InstanceID_frag
    in flat int _DrawID_frag;
    in flat int _InstanceID_frag;
    void fragment(void);
    void main(void) { fragment(); }
    #define main fragment\n"""
    vs = glCreateShader(GL_VERTEX_SHADER)
    vs_source = PREFIX * VS_PREFIX * vs_source
    glShaderSource(vs, 1, [vs_source], Int32[length(vs_source)])
    glCompileShader(vs)
    vs_status = Int32[-1]
    glGetShaderiv(vs, GL_COMPILE_STATUS, vs_status)

    fs = glCreateShader(GL_FRAGMENT_SHADER)
    fs_source = PREFIX * FS_PREFIX * fs_source
    glShaderSource(fs, 1, [fs_source], Int32[length(fs_source)])
    glCompileShader(fs)
    fs_status = Int32[-1]
    glGetShaderiv(fs, GL_COMPILE_STATUS, fs_status)
#    println(vs_source)
#    println(fs_source)
    if bool(fs_status[1]) && bool(vs_status[1])
        program = glCreateProgram()
        glAttachShader(program, vs)
        glAttachShader(program, fs)
        glLinkProgram(program)
        p_status = Int32[0]
        glGetProgramiv(program, GL_LINK_STATUS, p_status)
        if bool(p_status[1])
            # Get all attributes
            attr_count = Int32[-1]
            glGetProgramiv(program, GL_ACTIVE_ATTRIBUTES, attr_count)
            attributes = Dict{Symbol, ShaderAttrib}()
            attr_name = "                            "
            name_maxl = length(attr_name)
            name_size = Int32[-1]
            attr_type = Uint32[-1]
            attr_size = Int32[-1]
            for i=0:attr_count[1]-1
                glGetActiveAttrib(program, i, name_maxl, name_size, attr_size, attr_type, attr_name)
                n = canon_name(attr_name[1:name_size[1]])
                attributes[symbol(n)] = ShaderAttrib(symbol(n), attr_type[1], attr_size[1], glGetAttribLocation(program, n))
            end

            # Get all uniforms
            unif_count = Int32[-1]
            glGetProgramiv(program, GL_ACTIVE_UNIFORMS, unif_count)
            uniforms = Dict{Symbol, ShaderAttrib}()
            unif_name = "                            "
            name_maxl = length(unif_name)
            name_size = Int32[-1]
            unif_type = Uint32[-1]
            unif_size = Int32[-1]
            for i = 0:unif_count[1]-1
                glGetActiveUniform(program, i, name_maxl, name_size, unif_size, unif_type, unif_name)
                n = canon_name(unif_name[1:name_size[1]])
                uniforms[symbol(n)] = ShaderAttrib(symbol(n), unif_type[1], unif_size[1], glGetUniformLocation(program, n))
            end
            u_typename = symbol(string(name) * "Uniforms")
            not_to_bind = {}
            for decl in inputs
                decl.scope != :thread || continue
                if haskey(uniforms, decl.name)
                    uniforms[decl.name].alias_name = decl.alias_name
                    if decl.storage != nothing
                        uniforms[decl.name].storage_index = glGetUniformBlockIndex(program, string(decl.storage[2]))
                    end
                    continue
                end
                warn("Unused declared uniform : $decl")
                push!(not_to_bind, decl)
            end
            qt = quote type $u_typename <: Uniforms
                $([ :($(u.alias_name) :: $(julia_type(u)))
                   for (u_name, u) in uniforms]...)
                $([ :($(decl.alias_name) :: $(decl.ty))
                   for decl in not_to_bind]...)
                $u_typename() = new()
            end end
#            println("Evaling : ", qt)
            eval(qt)
            u_type = eval(u_typename)
            @eval function bind(us :: $u_typename)
                $([ :(isdefined(us, $(Expr(:quote, u.alias_name))) || error(string("Undefined : ", $(string(u_name)))))
                   for (u_name, u) in uniforms]...) #TODO remove me
                $([ (if u.storage_index == -1
                     :(#println("Binding : ", $(string(u.alias_name)), " to ", us.$(u.alias_name));
                       set_uniform($u, us.$(u.alias_name));
                       )
                     else
                     :(bind_indexed(us.$(u.alias_name), $(u.storage_index)))
                     end)
                   for (u_name, u) in uniforms]...)
            end
            samplers = filter(x -> isa(x, ShaderSampler), inputs)
            fills = {}
            for decl in samplers
                sampler_name = decl.sampler_name
                layer_name = decl.layer_name
                expr = if decl.scope == :all
                    quote
                        us.$sampler_name = findfirst(textures, us.$(decl.name)) - 1
                        us.$layer_name = layers(us.$(decl.name))
                    end
                else
                    # TODO this is slow to do each frame
                    quote
                        texs = Set([findfirst(t -> t.handle == tex.handle, textures) - 1 for tex in (us.$(decl.name))])
                        filter!(x->x!=-1,texs)
                        str = us.$(decl.name)
                        @assert(length(texs) == 1, "Texs : $(texs) : $(str) | $(textures)")
                        us.$sampler_name = first(texs)
#                        us.$sampler_name = findfirst(t->t.handle==tex.handle, textures)
                        us.$layer_name = layers(us.$(decl.name))
                    end
                end
                push!(fills, expr)
            end
            @eval function post_fill(us :: $u_typename, textures :: Vector{Texture})
                $(fills...)
                nothing
            end
            Shader(name, vs, fs, program, attributes, u_type, instance_count, draw_count)
        else
            shader_program_error(program)
            error("failure to link :\n$vs_source\n===\n$fs_source\n")
        end
    else
        if !bool(vs_status[1]) shader_error(vs) end
        if !bool(fs_status[1]) shader_error(fs) end
        error("failure to compile :\n$vs_source\n===\n$fs_source\n")
    end
end

layers(t::Texture) = float32(t.layer)
layers(ts::Vector{Texture}) = length(ts) == 1 ? layers(ts[1]) : float32(map(t -> t.layer, ts))

abstract FixedArray{T, N}

@table _julia_to_glsl [Mat4 => "mat4", Float32 => "float", Vec2 => "vec2", Vec3 => "vec3", Vec4 => "vec4",
                      Vector4{Uint8} => "uvec4"]
julia_to_glsl(x :: Type) = (_julia_to_glsl(x), "")
julia_to_glsl{ElT, sz}(::Type{FixedArray{ElT, sz}}) = (x = julia_to_glsl(ElT); (x[1], x[2] * "[" * string(sz) * "]"))
julia_to_glsl(x :: String) = (x, "")

function instanced_type(t, inst_count)
    if t <: FixedArray
        FixedArray{t.parameters[1], t.parameters[2]*inst_count}
    else
        FixedArray{t, inst_count}
    end
end

immutable ShaderInput
    name :: Symbol
    ty
    stage :: Union(Symbol, Nothing)
    scope :: Union(Symbol, Nothing)
    storage
    alias_name :: Symbol # the name we should use in the Uniform object
end
ShaderInput(n,t,st,sc,sto) = ShaderInput(n,t,st,sc,sto,n)

immutable ShaderSource
    val :: String
    stage :: Union(Symbol, Nothing)
    scope :: Union(Symbol, Nothing)
    storage
end
ShaderSource(val,st,sc) = ShaderSource(val,st,sc,nothing)
immutable ShaderSampler
    name :: Symbol
    sampler_name :: Symbol
    layer_name :: Symbol
    ty
    stage :: Union(Symbol, Nothing)
    scope :: Union(Symbol, Nothing)
    storage
    alias_name :: Symbol
end
ShaderSampler(n,sn,ln,t,st,sc,sto) = ShaderSampler(n,sn,ln,t,st,sc,sto,n)

flatmap(f, vs) = isempty(vs) ? vs : reduce(append!, map(f, vs))

parse_decls(stxs :: Vector, stage = nothing, scope = nothing, storage = nothing) = flatmap(x -> parse_decls(x, stage, scope, storage), stxs)

const STAGES = Set({:fragment, :vertex})
const PREV_STAGE = { :fragment => :vertex, :vertex => nothing}

_storage_uniq = 0

function parse_decls(stx, stage = nothing, scope = nothing, storage = nothing)
    global _storage_uniq
    if isa(stx, Expr) && stx.head == :macrocall
        macro_name = symbol(string(stx.args[1])[2:end])
        if macro_name in STAGES
            return parse_decls(stx.args[2], macro_name, scope, storage)
        elseif stx.args[1] == symbol("@scope")
            return parse_decls(stx.args[3], stage, stx.args[2], storage)
        elseif stx.args[1] == symbol("@storage")
            if stx.args[2] == :buffer
                storage = (:buffer, "ubo_$(_storage_uniq+=1)")
            elseif stx.args[2] == :huge
                storage = (:huge, "ssbo_$(_storage_uniq+=1)")
            else
                error(stx.args[2])
            end
            return parse_decls(stx.args[3], stage, scope, storage)
        end
    end
    (isa(stx, Expr) && stx.head == :line || isa(stx, LineNumberNode)) && return {}
    isa(stx, Expr) && stx.head == :block && return parse_decls(stx.args, stage, scope, storage)
    if isa(stx, Expr) && stx.head == :(::)
        decl = stx
        decl.head == :(::) || error("Bad decl : $decl")
        name = decl.args[1]
        ty = eval(decl.args[2])
        {ShaderInput(name, ty, stage, scope, storage)}
    else
        v = eval(stx)
        v == nothing ? {} : {ShaderSource(string(v), stage, scope)}
    end
end

function lower_glsl(src; instance_count = 1, draw_count = 1)
    src.head == :block || error("Expected block got $(src.head)")
    inputs = {}
    src_string = [stage => IOBuffer() for stage in STAGES]
    macros = ""
    decls = parse_decls(src.args)
    
    # lower textures inputs to texture arrays, add accessor macros for textures
    decls = flatmap(decls) do decl
        if isa(decl, ShaderInput) && decl.ty == Texture
            decl.scope != :thread || error("Textures are not allowed as thread-scoped parameters : $decl")
            sampler_name = symbol(string(decl.name) * "_sampler")
            layer_name = symbol(string(decl.name) * "_layer")
            {ShaderSampler(decl.name, sampler_name, layer_name, Texture, decl.stage, decl.scope, decl.storage),
             ShaderInput(sampler_name, "sampler2DArray", decl.stage, :all, nothing),
             ShaderInput(layer_name, Float32, decl.stage, decl.scope, decl.storage),
             ShaderSource("#define sample_$(decl.name)(coord) texture($sampler_name, vec3(coord, $layer_name))\n", decl.stage, decl.scope)}
        else
            {decl}
        end
    end

    # lower instanced inputs to arrays, add accessor macros for instanced & array inputs 
    decls = flatmap(decls) do decl
        if isa(decl, ShaderInput) && (decl.scope in (:instance, :draw) || (isa(decl.ty, Type) &&  decl.ty <: FixedArray))
            real_name = "_x_" * string(decl.name)
            ty = decl.ty
            if decl.scope == :instance
                ty = instanced_type(ty, instance_count)
            elseif decl.scope == :draw
                ty = instanced_type(ty, draw_count)
            end
            scope_id = decl.scope == :instance ? "gl_InstanceID" : decl.scope == :draw ? "gl_DrawID" : "???"
            if decl.ty <: FixedArray
                if decl.scope in (:instance, :draw)
                    alen = decl.ty.parameters[2]
                    macro_src = "#define $(decl.name)(i) $real_name[i + $scope_id*$alen]\n"
                else
                    macro_src = "#define $(decl.name)(i) $real_name[i]\n"
                end
            else
                macro_src = "#define $(decl.name) $real_name[$scope_id]\n"
            end
            {ShaderInput(real_name, ty, decl.stage, decl.scope, decl.storage, decl.name),
             ShaderSource(macro_src, decl.stage, decl.scope)}
        elseif isa(decl, ShaderSampler) && decl.scope in (:instance, :draw)
            {ShaderSampler(decl.name, decl.sampler_name, decl.layer_name, Vector{decl.ty}, decl.stage, decl.scope, decl.storage)}
        else
            {decl}
        end
    end

    decl_by_storage = Dict{Any,Vector}()
    for decl in decls
        push!(get!(decl_by_storage, decl.storage, {}), decl)
    end
    storages = push!(filter!(x -> x != nothing, collect(keys(decl_by_storage))), nothing)
    for storage in storages
        decls = decl_by_storage[storage]
        qual = storage != nothing
        !qual || length(decls) == 1 || error("Single parameter only for buffer storage for now. We need strided buffer views to support multiple uniforms per shader block")
        if qual
            if storage[1] == :buffer
                storage_name = "uniform"
            elseif storage[1] == :huge
                storage_name = "buffer"
            else
                error(storage[1])
            end
            stages = Set(map(d -> d.stage, decls))
            for stage in stages
                println(src_string[stage], "layout(row_major, std430) ", storage_name, " ", storage[2], " {")
            end
        end
        
        for decl in decls
            if isa(decl, ShaderSource)
                print(src_string[decl.stage], decl.val)
            elseif isa(decl, ShaderInput)
                (gl_ty, gl_typost) = julia_to_glsl(decl.ty)
                if decl.scope == :thread
                    qual && error(decl)
                    println(src_string[decl.stage], "in ", gl_ty, " ", decl.name, gl_typost, ";")
                    prev = PREV_STAGE[decl.stage]
                    prev == nothing || println(src_string[prev], "out ", gl_ty, " ", decl.name, gl_typost, ";")
                elseif decl.scope in (:all, :instance, :draw)
                    println(src_string[decl.stage], qual ? "" : "uniform ", gl_ty, " ", decl.name, gl_typost, ";")
                else
                    error(decl)
                end
                push!(inputs, decl)
            elseif isa(decl, ShaderSampler)
                push!(inputs, decl)
            else
                error(decl)
            end
        end
        
        if qual
            for stage in stages
                println(src_string[stage], "};")
            end
        end
    end
    sources = Dict{Symbol, String}(map(src_string) do kv
        k, v = kv
        seekstart(v)
        (k, readall(v))
    end)
    for (k,v) in sources
        println(k, " :\n", v)
    end
    (sources[:vertex], sources[:fragment], inputs, instance_count, draw_count)
end
macro glsl(name, src)
    quote
        function $(esc(name))(;params...)
            compile_shader($(Expr(:quote, name)), lower_glsl($(Expr(:quote, src)); params...)...)
        end
    end
end


bind_attr(attr :: ShaderAttrib, buff) = bind_attr(attr, buff, int32(0))
function bind_attr(attr :: ShaderAttrib, buff, stride :: Int32)
    glEnableVertexAttribArray(attr.loc)
    if attr_bytetype(attr) == GL_UNSIGNED_BYTE
        glVertexAttribIPointer(attr.loc, attr_primsize(attr), attr_bytetype(attr), stride, buff)
    else
        glVertexAttribPointer(attr.loc, attr_primsize(attr), attr_bytetype(attr), 0, stride, buff)
    end
end

function unbind_attr(attr :: ShaderAttrib)
    glDisableVertexAttribArray(attr.loc)
end

function set_uniform(attr :: ShaderAttrib, x :: Int)
    glUniform1i(attr.loc, x)
end
set_uniform(attr, x :: Int32) = set_uniform(attr, int(x))

function set_uniform(attr :: ShaderAttrib, x :: Matrix{Float32})
    assert(size(x) == (4,4), "To implement")
    glUniformMatrix4fv(attr.loc, 1, 0, x)
end
function set_uniform(attr :: ShaderAttrib, x :: Mat4)
    glUniformMatrix4fv(attr.loc, 1, 1, reinterpret(Float32, [x]))
end
set_uniform(attr :: ShaderAttrib, x :: Vec4) = glUniform4f(attr.loc, x.x, x.y, x.z, x.w)
set_uniform(attr :: ShaderAttrib, v :: Vec3) = glUniform3f(attr.loc, v.x, v.y, v.z)
set_uniform(attr :: ShaderAttrib, v :: Vec2) = glUniform2f(attr.loc, v.x, v.y)
set_uniform(attr :: ShaderAttrib, x :: Float32) = glUniform1f(attr.loc, x)

function set_uniform(attr :: ShaderAttrib, xs :: Vector{Float32})
    glUniform1fv(attr.loc, length(xs), xs)
end
set_uniform(attr, x :: Vector) = set_uniform_array(attr, x)
function set_uniform_array(attr :: ShaderAttrib, x :: Vector{Mat4})
    glUniformMatrix4fv(attr.loc, length(x), 1, reinterpret(Float32, x))
end
function set_uniform(attr :: ShaderAttrib, xs :: Vector{Vec4})
    glUniform4fv(attr.loc, length(xs), reinterpret(Float32, xs))
end
