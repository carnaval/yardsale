abstract Buffer

type GpuBuffer <: Buffer
    handle :: Int32
    buf_ty :: Uint16 # some opengl buffer target
    size :: Int
end

Base.size(b :: GpuBuffer) = (length(b),)
Base.length(b :: GpuBuffer) = b.size

type CpuBuffer <: Buffer
    data :: Vector{Uint8}
end

Base.length(b :: CpuBuffer) = length(b.data)
Base.size(b :: CpuBuffer) = size(b.data)
immutable TypedBuffer{ElT, BufferType <: Buffer}
    buf :: BufferType
end

# this is gonna be my doom at some point
Base.size(b :: TypedBuffer) = (length(b),)
Base.length{ElT}(b :: TypedBuffer{ElT}) = div(length(b.buf), sizeof(ElT))

TypedBuffer(t :: Type, b :: Buffer) = TypedBuffer{t, typeof(b)}(b)

typed_cpu_buffer(t :: Type, sz :: Int) = TypedBuffer(t, CpuBuffer(Array(Uint8, sz*sizeof(t))))
function typed_cpu_buffer{T}(t :: Type{T}, v :: Array{T})
    b = typed_cpu_buffer(t, length(v))
    b[:] = v
    b
end

eltype{T}(b :: TypedBuffer{T}) = T
data(buf :: CpuBuffer) = buf.data
data{ElT}(buf :: TypedBuffer{ElT}) = reinterpret(ElT, data(buf.buf))
typed_index{T}(::Type{T}, i) = 1+(first(i)-1)*sizeof(T):last(i)*sizeof(T)
Base.getindex{ElT}(buf :: TypedBuffer{ElT}, i) = reinterpret(ElT, buf.buf[typed_index(ElT, i)])
Base.setindex!{ElT}(buf :: TypedBuffer{ElT}, e, i) = buf.buf[typed_index(ElT, i)] = reinterpret(Uint8, [e])
Base.setindex!(buf :: CpuBuffer, e, i) = buf.data[i] = e
function Base.setindex!(buf :: GpuBuffer, e, i)
    length(buf) >= last(i) || error("out of bounds : ", length(buf), " < ", last(i))
    glNamedBufferSubDataEXT(buf.handle, first(i) - 1, 1 + last(i) - first(i), e)
end
Base.getindex(buf :: CpuBuffer, i) = buf.data[i]
Base.endof(buf :: TypedBuffer) = length(buf)
Base.endof(buf :: GpuBuffer) = length(buf)
Base.endof(buf :: CpuBuffer) = length(buf)

Base.similar{T,BT}(b :: TypedBuffer{T,BT}) = TypedBuffer{T,BT}(similar(b.buf))
Base.similar(b :: GpuBuffer) = alloc_storage(make_gpu_buffer(b.buf_ty), b.size)


const NoVertexBuffer = GpuBuffer(int32(0), GL_ARRAY_BUFFER, 0)
const NoIndexBuffer = GpuBuffer(int32(0), GL_ELEMENT_ARRAY_BUFFER, 0)
function make_gpu_buffer(buf_ty :: Uint16)
    h = Uint32[-1]
    glGenBuffers(1, h)
#    println("Buffer alloc :")
#    Base.show_backtrace(STDOUT, backtrace())
    assert(h[1] != -1)
    GpuBuffer(h[1], buf_ty, 0)
end
bind{T}(b :: TypedBuffer{T,GpuBuffer}) = bind(b.buf)
bind_indexed{T}(b :: TypedBuffer{T, GpuBuffer}, i :: Int) = bind_indexed(b.buf, i)
make_vertex_buffer{T}(::Type{T}, sz :: Int) = alloc_storage(TypedBuffer(T, make_gpu_buffer(GL_ARRAY_BUFFER)), sz)
make_vertex_buffer{T}(::Type{T}, v :: Vector{T}) = (b = make_vertex_buffer(T, length(v)); b[:] = v; b)
make_vertex_buffer{T}(::Type{T}, v :: Vector) = make_vertex_buffer(T, reinterpret(T, v))
make_index_buffer(sz :: Int) = alloc_storage(TypedBuffer(Uint16, make_gpu_buffer(GL_ELEMENT_ARRAY_BUFFER)), sz)
make_index_buffer(is :: Vector{Uint16}) = (b = make_index_buffer(length(is)); b[:] = is; b)
make_shader_buffer{T}(::Type{T}, sz :: Int) = alloc_storage(TypedBuffer(T, make_gpu_buffer(GL_UNIFORM_BUFFER)), sz)

function upload_data(b :: GpuBuffer, data :: Vector{Uint8})
    glNamedBufferDataEXT(b.handle, length(data), data, GL_STATIC_DRAW)
    b.size = length(data)
end

function alloc_storage(b :: GpuBuffer, sz :: Int)
    b.size = sz
    glNamedBufferDataEXT(b.handle, sz, 0, GL_STATIC_DRAW)
    b
end
alloc_storage{T}(b :: TypedBuffer{T, GpuBuffer}, sz :: Int) = (alloc_storage(b.buf, sz*sizeof(T)); b)

copy!(b :: GpuBuffer, cpu_data :: CpuBuffer) = upload_data(b, data(cpu_data))
copy!(b :: GpuBuffer, tb :: TypedBuffer) = copy!(b, tb.buf)

immutable type Binding
    attr :: ShaderAttrib
    buf
    offset :: Int32
    stride :: Int32
end

function bind(b :: Binding)
    bind(b.buf)
    bind_attr(b.attr, b.offset, b.stride)
end

#@format PNTXX [:v_posn, :v_norm, :v_tex1c, none(8)]
#@format PNTX  [:v_posn, :v_norm, :v_tex1c, none(4)]
#@format PNTTX [:v_posn, :v_norm, :v_tex1c, :v_tex2c, none(4)]

macro buffer_format(xs...)
    fmt = Symbol[]
    for x in xs
        if typeof(x) == Symbol
            push!(fmt, x)
        elseif typeof(x) == Expr && x.head == :call && x.args[1] == :none
            for i=1:x.args[2]
                push!(fmt, :none)
            end
        end
    end
    fmtq = [Expr(:quote, [x]) for x in fmt]
    :([$(fmtq...)])
end

# VAO in opengl slang
type AttributeBindings
    handle :: Int32
    buffer
end

global_bindings_cache = Dict{(Shader, Any), AttributeBindings}()

function bindings(s :: Shader, buf, format :: Vector{Symbol})
    if haskey(global_bindings_cache, (s, buf))
        println("Cache hit ")
        exit()
        return global_bindings_cache[(s,buf)]
    else
        println("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
        println(s, " ", buf)
        println(global_bindings_cache)
    end
    size = 0
    bs = {}
    for i=1:length(format)
        a = format[i]
        if a == :none
            size += 1
        else
            attr = s.attributes[a]
            push!(bs, (attr, size))
            size += bytesize(attr)
        end
    end
    bs = [Binding(x[1], buf, int32(x[2]), int32(size)) for x in bs]
    bnds = make_bindings()
    bind(bnds)
    bnds.buffer = buf
    for b in bs
        bind(b)
    end
    bind(NoAttributeBindings)
    global_bindings_cache[(s,buf)] = bnds
    bnds
end

#TODO cleanup this, remove the Binding type, support multiple buffers, remove the above
function bindings(s :: Shader, buf, format :: Type)
    if haskey(global_bindings_cache, (s, buf))
        return global_bindings_cache[(s,buf)]
    end
    size = 0
    bs = {}
    flds = names(format)
    for i=1:length(flds)
        a = flds[i]
        if haskey(s.attributes, a)
            attr = s.attributes[a]
            push!(bs, (attr, size))
        else
            warn("ignored attribute $a in $(s.name)")
        end
        size += sizeof(format.types[i])
    end
    bs = [Binding(x[1], buf, int32(x[2]), int32(size)) for x in bs]
    bnds = make_bindings()
    bind(bnds)
    for b in bs
        bind(b)
    end
    bind(NoAttributeBindings)
    global_bindings_cache[(s,buf)] = bnds
    bnds
end


const NoAttributeBindings = AttributeBindings(0, nothing)

function make_bindings()
    h = Uint32[-1]
    glGenVertexArrays(1, h)
    AttributeBindings(h[1], nothing)
end

function bind(b :: GpuBuffer)
    glBindBuffer(b.buf_ty, b.handle)
end
function bind_indexed(b :: GpuBuffer, i :: Int)
    glBindBufferRange(b.buf_ty, uint32(i), b.handle, 0, length(b))
end

function bind(bs :: AttributeBindings)
    glBindVertexArray(bs.handle)
end

# Doesn't take into account seek position in the buffer
# also relying on implementation but well
function upload_data(b :: GpuBuffer, io :: IOBuffer)
    upload_data(b, io.data)
end

const BATCH_MIN_SZ = 100*1024
const BATCH_MAX_SZ = 5*1024*1024
type BufferBatch{T, BufTy}
    buffers :: Vector{TypedBuffer{T, BufTy}}
    freemap :: Vector{BitArray{1}}
    free_lb :: Vector{Int}
end

type ManagedBuffer{BufTy}
    buffer :: BufTy
    allocs :: Vector{(Int, Int)}
    next :: Union(ManagedBuffer{BufTy}, Nothing)
end

ManagedBuffer{T}(buf :: T) = ManagedBuffer(buf, (Int,Int)[], nothing)

immutable ManagedBuffPtr{BufTy}
    buffer :: ManagedBuffer{BufTy}
    alloc_index :: Int
    index :: Int
    len :: Int
end

Base.length(p::ManagedBuffPtr) = p.len
Base.start(p::ManagedBuffPtr) = p.index
Base.start(::TypedBuffer) = 1

#TODO deprecate this
buffer(p::ManagedBuffPtr) = p.buffer.buffer

backing(p::ManagedBuffPtr) = backing(p.buffer.buffer)
backing(t::TypedBuffer) = t.buf
backing(b::CpuBuffer) = b
backing(b::GpuBuffer) = b

function alloc(buf :: ManagedBuffer, sz :: Int)
    i = 1
    alloc_i = 1
    n = length(buf.buffer)
    for (beg, len) in buf.allocs
        if i + sz - 1 < beg
            insert!(buf.allocs, alloc_i, (i, sz))
            return ManagedBuffPtr(buf, alloc_i, i, sz)
        end
        i = beg + len
        alloc_i += 1
    end
    if i + sz - 1 > n
        if buf.next == nothing
            buf.next = ManagedBuffer(similar(buf.buffer))
        end
        return alloc(buf.next, sz)
    end
    push!(buf.allocs, (i, sz))
    ManagedBuffPtr(buf, alloc_i, i, sz)
end

function alloc{T, BufTy}(buf :: ManagedBuffer{TypedBuffer{T, BufTy}}, data :: Vector{T})
    n = length(data)
    ptr = alloc(buf, n)
    buffer(ptr)[ptr.index:ptr.index+ptr.len-1] = data
    ptr
end

function free(buf :: ManagedBuffer, ptr)
    deleteat!(buf.allocs, ptr.alloc_index)
end

BufferBatch{T}(::Type{T}) = BufferBatch(TypedBuffer{T, GpuBuffer}[],
                                        BitArray{1}[],
                                        Int[])

immutable BuffPtr{T, BufTy}
    batch :: BufferBatch{T, BufTy}
    buf_index :: Int
    index :: Int
    len :: Int
end

buffer(b::BuffPtr) = b.batch.buffers[b.buf_index]

# allocate n contiguous Ts in a buffer
function alloc{T, BufTy}(batch :: BufferBatch{T, BufTy}, n :: Int)
    for i = 1:length(batch.buffers)
        buf = batch.buffers[i]
        fm = batch.freemap[i]
        maybe_free = findnext(fm, true, batch.free_lb[i])
        batch.free_lb[i] = maybe_free
        while maybe_free <= length(buf)
            if all(fm[maybe_free:maybe_free+n])

                fm[maybe_free:maybe_free+n-1] = false
                return BuffPtr(batch, i, maybe_free, n)
            end
            maybe_free = findnext(fm, true, maybe_free)
        end
    end
    # no free space
    # TODO make the buffers start at MIN_SZ and resize here
    # if every buffer is >= MAX_SZ :
    ty_buf = make_vertex_buffer(T, BATCH_MAX_SZ)#BufTy(BATCH_MAX_SZ))#TODO make this work for any buffer
    push!(batch.buffers, ty_buf)
    fm = trues(length(ty_buf))
    fm[1:n] = false
    push!(batch.freemap, fm)
    push!(batch.free_lb, n+1)
    BuffPtr(batch, 1, 1, n)
end
# not tested
function free{T}(ptr :: BuffPtr{T})
    i = ptr.index
    n = ptr.len
    ptr.batch.freemap[ptr.buf_index][i:i+n-1] = true
    # TODO debug
    ptr.ty_buf[i:i+n-1] = zeros(Uint8, sizeof(T)*n)
    ptr.batch.free_lb[ptr.buf_index] = min(ptr.batch.free_lb[ptr.buf_index], i)
end

function show_free(b :: BufferBatch)
    for i = 1:length(b.buffers)
        println("Buffer $i :\n")
        fm = b.freemap[i]
        c = fm[1]
        n = 0
        for j = 1:length(fm)
            if fm[j] == c && j != length(fm)
                n += 1
            else
                print("[$c x $n]")
                c = fm[j]
                n = 1
            end
        end
        println()
    end
end
    @table map_buffer_mode [ :rw => GL_READ_WRITE,
                            :r => GL_READ_ONLY,
                            :w => GL_WRITE_ONLY ]
function mmap{T}(buf :: TypedBuffer{T,GpuBuffer}, mode = :rw)
    ptr = glMapNamedBufferEXT(buf.buf.handle, map_buffer_mode(mode))
    TypedBuffer(T, CpuBuffer(reinterpret(Uint8, pointer_to_array(convert(Ptr{T}, ptr), size(buf)))))
end
function munmap{T}(buf :: TypedBuffer{T,GpuBuffer})
    glUnmapNamedBufferEXT(buf.buf.handle)
end
const batch = BufferBatch(Vec3)
#=
show_free(batch)
println("===")
alloc(batch, 4)
show_free(batch)
println("===")
alloc(batch, 8)
show_free(batch)
println("===")
alloc(batch, 1)
show_free(batch)
println("===")

=#
