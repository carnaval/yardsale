
type Node
    transform :: Aff
    
    world_transform :: Aff
    world_transform_dirty :: Bool # TODO remove this flag in release build
    
    name :: Union(String, Nothing)

    parent :: Union(Node, Nothing)
    children :: Vector{Node}
    
    depth :: Int

    last_tree_size :: Int
    
    Node(; name = nothing) = new(Aff_id, Aff_id, false, name, nothing, Node[], 0)
end



type Scene
    root :: Node
    objects :: Vector{Any} # TODO can change Any into something like GameObject
    renderers :: Vector # bookeeping to update them of object addition/deletion
end

function add_object(scene :: Scene, object)
    push!(scene.objects, object)
    n = node(object)
    if n != nothing
        reparent(n, scene.root)
    end
    for r in scene.renderers
        add_object(r, object)
    end
end

type Renderer
    scene :: Scene
    # dest :: FrameBuffer
    proj :: Mat4
    view :: Mat4
    camera_node :: Node
    rq :: Vector{Any}
    
    function Renderer(scene :: Scene, camera_node :: Node)
        r = new(scene, lin_id, lin_id, camera_node, {})
        push!(scene.renderers, r)
        for o in scene.objects
            add_object(r, o)
        end
        r
    end
end

function add_object(renderer :: Renderer, object)
    push!(renderer.rq, object)
end

function prepare(r :: Renderer, proj_mode = :perspective)
    cam_transform = world_transform(r.camera_node)
    if proj_mode == :perspective
        r.proj = proj(float32(pi/4), float32(W/H), 10f0, 20000f0)
    elseif proj_mode == :ortho
        r.proj = Mat4(1f0, 0f0, 0f0, 0f0,
                      0f0, 1f0, 0f0, 0f0,
                      0f0, 0f0, -2/(10000f0 - 10f0), -(10000f0 + 10f0)/(10000f0 - 10f0),
                      0f0, 0f0, 0f0, 1f0)
    else
        error(proj_mode)
    end
    r.view = aff_to_mat(inv(cam_transform))
end

function render(r :: Renderer)
    for o in r.rq
        render(r, o)
    end
end


function update_depth!(n :: Node)
    if n.parent != nothing
        n.depth = n.parent.depth + 1
        for child in n.children
            update_depth!(child)
        end
    end
end

function mark_world_transform_dirty!(n :: Node)
    n.world_transform_dirty = true
    for nn in n.children
        mark_world_transform_dirty!(nn)
    end
end
const q = Node[]

# TODO put some perf metrics around this
# if it becomes bottleneck it will be probably easy to refactor into something more efficient
function update_world_transform!(n :: Node)
    @assert(n.parent == nothing || !n.parent.world_transform_dirty)
    push!(q, n)
    i = 1
    while i <= length(q)
        nn = q[i]
        if nn.parent == nothing
            nn.world_transform = nn.transform
        else
            nn.world_transform = nn.parent.world_transform * nn.transform
        end
        nn.world_transform_dirty = false
        append!(q, nn.children)
        i += 1
    end
    resize!(q, 0) # from napkin experiment it doesn't seem to dealloc memory
end

function reparent(n :: Node, new_parent :: Node)
    if n.parent != nothing
        filter!(nn -> nn != n, n.parent.children)
        # TODO this is stupid if they where not in the same tree which might be worth checking
        n.transform = inv(world_transform(new_parent))*world_transform(n.parent)*n.transform
    end
    
    n.parent = new_parent

    mark_world_transform_dirty!(n)
    update_depth!(n)
    push!(new_parent.children, n)
end

function Node(parent :: Node; name = nothing)
    n = Node(name = name)
    reparent(n, parent)
    update_world_transform!(n) # this is cheap because no children
    n
end

function transform(n :: Node, a :: Aff)
    n.transform * a
end

pretransform!(n :: Node, t :: Aff) = (n.transform = a * n.transform; mark_world_transform_dirty!(n); n.transform)
transform!(n :: Node, t :: Aff) = (n.transform = n.transform*t; mark_world_transform_dirty!(n); n.transform)
transform!(n :: Node, v :: Vec3) = transform!(n, Aff(v))
transform!(n :: Node, q :: Quat) = transform!(n, Aff(q))

function world_transform(n :: Node)
    assert(!n.world_transform_dirty)
    n.world_transform
end

# this walks up the hierarchy and consequently is slow
# if you are already walking the tree from top to bottom
# you'd better accumulate the transforms yourself

# it answers the transform sending rel_to to n
function rel_transform(n :: Node, rel_to :: Node)
    n_xform = Aff_id
    m_xform = Aff_id
    nn = n
    mm = rel_to
    while nn != mm
        dd = nn.depth - mm.depth
        if dd >= 0
            n_xform = transform(nn, n_xform)
            nn = nn.parent
        end
        if dd <= 0
            m_xform = transform(mm, m_xform)
            mm = mm.parent
        end
        if mm == nothing || nn == nothing
            error("Nodes not in the same tree : $n / $rel_to")
        end
    end
    n_xform * inv(m_xform)
end
