immutable PrimDrawCall
    index_count :: Uint32
    instance_count :: Uint32
    index_offset :: Uint32
    vertex_offset :: Uint32
    instance_offset :: Uint32
end

type DrawCall
    shader :: Shader
    uniforms :: Any
    textures :: Vector{Texture}
    vertices :: AttributeBindings
    indices :: GpuBuffer
    primitives :: Vector{PrimDrawCall}
    prim_type :: Uint32
    prim_offset :: Int
    prim_count :: Int
    total_instances :: Int
end

immutable DrawRef{InstRef, UT}
    dc :: DrawCall # nescessary ?
    uniforms :: UT
    prim_dc :: Int
    instance :: InstRef
end

immutable Mesh
    shader :: Shader
    vertices :: AttributeBindings
    vertices_ptr
    indices# :: ManagedBuffPtr{TypedBuffer{Uint16, GpuBuffer}}
    textures :: Vector{Texture}
end

type RenderQueue
    batch :: Vector{DrawCall}
end
RenderQueue() = RenderQueue(DrawCall[])

function add!(rq :: RenderQueue, mesh :: Mesh, allow_instancing = false)
    texhandles = map(t->t.handle, mesh.textures)
    println("walking renderq")
    shader = mesh.shader
    for drawcall in rq.batch
        drawcall.shader == mesh.shader &&
        map(t -> t.handle, drawcall.textures) == texhandles &&
        drawcall.vertices == mesh.vertices &&
        drawcall.indices == backing(mesh.indices) || continue
        instance_count = 0
        if allow_instancing
            for (i, prim) in enumerate(drawcall.primitives)
                #            break # TODO support instancing
                instance_count += prim.instance_count
                prim.index_count == length(mesh.indices) &&
                prim.index_offset == start(mesh.indices) - 1 &&
                prim.vertex_offset == start(mesh.vertices_ptr) - 1 &&
                prim.instance_count < shader.instance_count || continue
                println("bouuh")
                drawcall.primitives[i] = PrimDrawCall(prim.index_count, prim.instance_count+1, prim.index_offset, prim.vertex_offset, prim.instance_offset)
                drawcall.total_instances += 1
                println("->inst")
                return DrawRef(drawcall, drawcall.uniforms, i, prim.instance_count+1)
            end
        end
        drawcall.prim_count < shader.draw_count || continue
        # cannot instanciate, create new command
        push!(drawcall.primitives, PrimDrawCall(length(mesh.indices), 1, start(mesh.indices)-1, start(mesh.vertices_ptr)-1, 0))
        drawcall.total_instances += 1
        drawcall.prim_count += 1
        println("->batch")
        return DrawRef(drawcall, drawcall.uniforms, drawcall.prim_count, 1)
    end
    # cannot batch with any other drawcall
    u = mesh.shader.uniforms()
    fill_init(u)
    dc = DrawCall(mesh.shader, u,
                  mesh.textures, mesh.vertices, backing(mesh.indices),
                  [PrimDrawCall(length(mesh.indices), 1, start(mesh.indices)-1, start(mesh.vertices_ptr)-1, 0)],
                  GL_TRIANGLES, 0, 1, 1)
    push!(rq.batch, dc)
    println("->new : ", dc.textures)
    return DrawRef(dc, dc.uniforms, 1, 1)
end

fill_init(u) = ()

const counts = Int32[]
const offsets = Int[]
const bases = Int32[]
function perform(r :: Renderer, dc :: DrawCall)
    glUseProgram(dc.shader.program)
    post_fill(dc.uniforms, dc.textures)
    bind(dc.uniforms)
    for i = 1:length(dc.textures)
        bind_tex(dc.textures[i], int32(i-1))
    end
    bind(dc.vertices)
    bind(dc.indices)
    
    # TODO Indirect multi-draw
    
    if dc.total_instances == dc.prim_count
        # Direct multi-draw (doesn't support instancing)
        for prim_id = dc.prim_offset:dc.prim_offset + dc.prim_count - 1
            prim = dc.primitives[prim_id + 1]
            push!(counts, prim.index_count)
            push!(offsets, prim.index_offset*sizeof(Uint16))
            push!(bases, prim.vertex_offset)
        end
        glMultiDrawElementsBaseVertex(dc.prim_type, counts, GL_UNSIGNED_SHORT, offsets, dc.prim_count, bases)
        empty!(counts); empty!(offsets); empty!(bases)
    elseif dc.prim_count == 1
        # Direct single draw
        for prim_id = dc.prim_offset:dc.prim_offset+dc.prim_count-1
            prim = dc.primitives[prim_id + 1]
            index_ofs = prim.index_offset*sizeof(Uint16)
            glDrawElementsInstancedBaseVertexBaseInstance(dc.prim_type, prim.index_count,
                                                          GL_UNSIGNED_SHORT, index_ofs,
                                                          prim.instance_count, prim.vertex_offset,
                                                          prim.instance_offset)
        end
    else
        error("Cannot combine multi & instanced draw for now")
    end
end
