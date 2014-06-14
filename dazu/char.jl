const MAX_BONES = 128

#TODO @scope()
#=
       begin :vertex :instance :aaa
          blah :: Blah
       end
       
=#
const MAX_INSTANCES = 8
@glsl SkinnedMeshShader begin
    @vertex @scope (all) proj :: Mat4
    @vertex @scope (thread) v_posn :: Vec3
    @vertex @scope (thread) begin
        v_texc :: Vec2
        v_bone_ids :: Vector4{Uint8}
        v_bone_ws :: Vec4
        v_norm :: Vec3
    end    
    @fragment @scope (thread) begin
        f_norm :: Vec3
        f_texc :: Vec2
        wp :: Vec3
    end
    @vertex @scope (draw) @storage (buffer) bone_mat :: FixedArray{Mat4, MAX_BONES}
    @fragment @scope (all) begin
        light_world :: Mat4
        light_pos :: Vec3
    end
    @fragment @scope (draw) tex :: Texture
    @vertex """
    void vertex(void) {
      mat4 tr = mat4(0.0);
      vec4 ws = v_bone_ws/(v_bone_ws.x + v_bone_ws.y + v_bone_ws.z + v_bone_ws.w);
      for(int i = 0; i < 4; i++) {
        tr += ws[i]*bone_mat(v_bone_ids[i]);
      }
      gl_Position = proj*tr*vec4(v_posn.xyz, 1.0);
      f_texc = v_texc;
      f_norm = (tr*vec4(v_norm, 0)).xyz;
      wp = (tr*vec4(v_posn.xyz,1)).xyz;
    }
    """
    @fragment """
//    uniform sampler2D shadow_tex;

    void fragment(void) {
      vec4 pos_light = light_world*vec4(wp,1);
      pos_light = pos_light/pos_light.w;
      pos_light = (pos_light + 1)*0.5;

      float f = 1.;//texture2D(shadow_tex, pos_light.xy).z;
      if(f <= pos_light.z - 0.0005) {
        gl_FragColor = vec4(f/2,f/2,f/2,1);
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
      } else {
        gl_FragColor = sample_tex(f_texc);
//        gl_FragColor = texture(tex_sampler, vec3(f_texc, float(gl_DrawID)));
        gl_FragColor = vec4(gl_FragColor.xyz*max(0, dot(normalize(light_pos.xyz - wp.xyz),f_norm)), 1.0);
      }
    }
    """
end

shader = SkinnedMeshShader(draw_count = MAX_INSTANCES)


type Bone
    name :: Symbol
    id :: Union(Uint32, ())
    parent :: Bone
    has_parent :: Bool # ugh
    inv_transform :: Mat4 # this is bind pose absolute transform _inverse_
#    transform :: Aff
    Bone(n::Symbol,i::Union(Uint32,()),t) = (x=new();x.name = n; x.inv_transform = t; x.id = i; x.has_parent = false; x)
end

type Animation
    name :: Symbol
    frame_count :: Uint
    frames :: Vector{Vector{Aff}}
end

function PR(m)
    mm = float32(eye(4, 4))
    mm[1:3, 1:4] = m
    mm
end
type Skeleton
    bones :: Vector{Bone}
    animations :: Dict{Symbol, Animation}
    bones_by_name :: Dict{Symbol, Bone}
end
import Base.show
function show(io :: IO, s :: Skeleton)
    print(io, "Skeleton($(length(s.animations)) animations, $(length(s.bones)) bones)")
end
function show(io :: IO, b :: Bone)
    print(io, "Bone($(b.name), id=$(b.id), ")
    if b.has_parent
        print(io, "parent=$(b.parent.name)")
    else
        print(io, "root bone")
    end
    print(io, ")")
end

function Skeleton(bones :: Vector{Bone}, anm :: Dict{Symbol, Animation})
    Skeleton(bones, anm, [ b.name => b for b in bones ])
end

function make_bone_nodes(root :: Node, skel :: Skeleton)
#    bbn = [skel.bones[i].name => i for i=1:length(skel.bones)] # TODO inefficient to rebuild this
    nodes = [Node(root) for bone in skel.bones]
    update_world_transform!(root)
    for bone in skel.bones
        parent = bone.has_parent ? nodes[bone.parent.id + 1] : root
        if bone.id != () && parent != bone
            nodes[bone.id + 1].name = string(bone.name)

            update_world_transform!(nodes[bone.id + 1])
            reparent(nodes[bone.id + 1], parent)

            update_world_transform!(nodes[bone.id + 1])
        end
    end
    update_world_transform!(root)
    nodes
end

type SkinnedMesh
    skel :: Skeleton
    tex :: Texture

    indices# :: TypedBuffer{Uint16, GpuBuffer}
    num_indices :: Int
    bufptr
    bindings

    bone_matrices :: Vector{Mat4}
    bone_nodes :: Vector{Node}
    node :: Node

    uniforms :: SkinnedMeshShaderUniforms
    drawref :: DrawRef{Int}

    SkinnedMesh(s,t,i,ni,b,bs,bn,n) = (new(s,t,i,ni,b,bs, [lin_id for i in 1:length(s.bones)], bn, n))
end

function show(io :: IO, m :: SkinnedMesh)
    print(io, "SkinnedMesh($(m.skel))")
end

const SKINNED_MESH_FORMAT = @buffer_format v_posn v_bone_ids v_bone_ws v_norm v_texc
immutable SkinnedMeshVertex
    v_posn :: Vec3
    v_bone_ids :: Vector4{Uint8}
    v_bone_ws :: Vec4
    v_norm :: Vec3
    v_texc :: Vec2
end


function build_frames(bones :: Vector{Bone}, anm_bones :: Dict{Symbol, AnmBone})
    bbn = [bones[i].name => i for i=1:length(bones)] # TODO inefficient to rebuild this
    frames = [Aff[] for b in bones]
    for (name, anm_bone) in anm_bones
        if haskey(bbn, name)
            aff = [ Aff(Quat(anm_bone.orientations[i, 1:4][:]), vec3(anm_bone.positions[i, 1:3][:]...))
                   for i=1:min(size(anm_bone.positions)[1], size(anm_bone.orientations)[1]) ]

            frames[bbn[name]] = aff
        else
#            println("Fail to find $name")
        end
    end
    frames
end

swap!(xs, i, j) = (a = xs[i]; xs[i] = xs[j]; xs[j] = a)

const g_mesh = ManagedBuffer(make_vertex_buffer(SkinnedMeshVertex,4*1024*1024))
const g_ind = ManagedBuffer(make_index_buffer(4*1024*1024))
#const g_bindings = bindings(shader, g_mesh.buffer, SKINNED_MESH_FORMAT)

function read_riot_char(fskn::IOStream, fskl::IOStream, ftx::IOStream, fanms::Vector{(Symbol,IOStream)})
	skn = read_skn(fskn)
    skl = read_skl(fskl)
	
    tx = make_dds_tex(ftx)
    root = Node()
    anms = [ (s, read_anm(fanm, skl)) for (s,fanm) in fanms ]

    bones = [ Bone(b.name, (if b.bound b.id else () end), inv(if typeof(b.transform) == Aff aff_to_mat(b.transform) else array34_to_mat(b.transform) end)) for b in skl ]

    for i=1:length(bones)
        p = skl[i].parent + 1
        if 1 <= p <= length(bones)
            bones[i].parent = bones[p]
            bones[i].has_parent = true
        end
    end

    sort!(bones, lt = (b1,b2) -> if b1.id == () false elseif b2.id == () true else b1.id < b2.id end)

    max_valid = 0
    for i=1:length(bones)
        if bones[i].id != ()
            assert(bones[i].id == i-1)
            max_valid = i
        else
            bones[i].id = uint32(i-1)
        end
    end
    
#    println("Bone without id : ", length(bones) - max_valid, "/", length(bones))
#    for i=max_valid+1:length(bones)
#        println("Lonely bone : $(bones[i])")
#    end



    animations = (Symbol=>Animation)[ name => Animation(name, uint(size(anm_bones[first(collect(keys(anm_bones)))].positions)[1]), build_frames(bones, anm_bones)) for (name, anm_bones) in anms ]
    skel = Skeleton(bones, animations)

    bone_nodes = make_bone_nodes(root, skel)

    #buf = make_vertex_buffer(SkinnedMeshVertex, skn.buffer)
    buf = alloc(g_mesh, reinterpret(SkinnedMeshVertex, skn.buffer))
    println("Sz $(length(skn.buffer)) | $(length(bone_nodes)) : $(typeof(skn.buffer))")
    #ixs = make_index_buffer(skn.indices)
    ixs = alloc(g_ind, skn.indices)
    sm = SkinnedMesh(skel, tx, ixs, length(skn.indices), buf, bindings(shader, buffer(buf), SkinnedMeshVertex), bone_nodes, root)
#    sm.uniforms = SkinnedMeshShaderUniforms()
#    sm.uniforms.tex_sampler = int32(0)
#    sm.uniforms.shadow_tex = int32(1)
    sm
end

#const RIOT_DIR = "/home/carnaval/dargonmods/output/data/characters/"
const RIOT_DIR = "/media/data/riotdata/data/characters/"
function read_riot_char(s :: Symbol)
    ss = RIOT_DIR * "/" * string(s) * "/"
    cd(ss) do
        anms = [ (symbol(split(n, ".")[1]), open("animations/"*n)) for n in readdir("animations") ]
        d = string(s)
        read_riot_char(open(d*".skn"), open(d*".skl"), open(lowercase(d)*".dds"), anms)
    end
end
const char_path = RIOT_DIR # lol
include("inibin.jl")

function read_riot_char2(s :: Symbol)
    if isdir(stat(lowercase(char_path * string(s) * "/Skins/")))
	ss = char_path * string(s) * "/Skins/Base/"
	inibin_ = "Base.inibin"
    else
	ss = char_path * string(s) * "/"
	inibin_ = string(s) * ".inibin"
    end
    p = lowercase(ss)
    anms = [ (symbol(split(n, ".")[1]), open(p*"animations/"*lowercase(n))) for n in readdir(p*"animations") ]
	
    inibin = parse_inibin(open(lowercase(ss * inibin_)))
    skn_file = p * lowercase(get(inibin, 0x2ddb452f, :nope))
    skl_file = p * lowercase(get(inibin, 0x70f8094d, :nope))
    dds_file = p * lowercase(get(inibin, 0x9d5e00fb, :nope))
    if !endswith(dds_file, ".dds")
        dds_file = dds_file * ".dds"
    end
    scaling = float32(get(inibin, 0xf46e42ad, 1f0))
    
    if skn_file != :nope && skl_file != :nope && dds_file != :nope
	(read_riot_char(open(skn_file), open(skl_file), open(dds_file), anms), scaling)
    else
	:nope
    end
end


const main_scene = Scene(Node(name = "root"), {}, Renderer[])

const excludes = ["anivia", "elisespider", "ezreal_cyber_1", "ezreal_cyber_2", "ezreal_cyber_3", "ghostward", "graves", "blue_minion_caster", "blue_minion_healer", "blue_minion_melee", "blue_minion_siege", "blue_minion_superminion", "calderaboss1", "calderaboss2", "calderaelderlizard", "destroyednexus", "destroyedtower", "destroyedinhibitor", "brush_b_sr", "brush_c_sr", "brush_d_sr", "brush_e_sr", "brush_f_sr", "chaosturrettutorial", "chaosturretworm2", "ha_ap_chains_long", "ha_ap_chaosturret2", "ha_ap_chaosturret3", "ha_ap_chaosturretrubble", "ha_ap_chaosturretshrine", "ha_ap_chaosturrettutorial"]# "chogath", "corki", "crystal_platform", "darius", "diana"]
function read_all_riot()
    x = Dict{Symbol,SkinnedMesh}()
    i = 0
    league_node = Node(name = "league")
    #l = readdir(RIOT_DIR)[1:5]#["warwick", "zilean", "aatrox"]
    l = readdir(RIOT_DIR)#[1:MAX_INSTANCES]#["ezreal", "heimerdinger", "diana", "zilean"]
    filter!(x -> !(x in excludes), l)
    #l = ["aatrox"]
    NUM = 3
    for d in l
#        d in ("ahri", "aatrox", "anivia") && continue
        i >= NUM && break
#        d in ("ezreal", "heimerdinger") || continue
#        try
#            x[symbol(d)], scaling = read_riot_char2(symbol(d))
        println(d, "(", i, ")")
            sm, _ = read_riot_char2(symbol(d))
#            reparent(sm.node, league_node)
            transform!(sm.node, vec3(i*400 - (NUM-1)*200, 0, 0))
            add_object(main_scene, sm)
        add!(sm)
#            @schedule
        animate!(sm, collect(keys(sm.skel.animations)))
            i += 1
#        catch _
#            println("Failed $d ", _)
#            rethrow(_)
#        end
    end
    x
end

function update_bones!(sm :: SkinnedMesh, anm :: Symbol, fn :: Int)
    for i=1:length(sm.bone_matrices)
        if sm.skel.animations[anm].frames[i] != Aff[]
            sm.bone_nodes[i].transform = sm.skel.animations[anm].frames[i][fn]
        end
    end
    update_world_transform!(sm.node)
    for i=1:length(sm.bone_matrices)
        sm.bone_matrices[i] = aff_to_mat(world_transform(sm.bone_nodes[i]))*sm.skel.bones[i].inv_transform
    end
end

node(sm :: SkinnedMesh) = nothing#sm.node


function animate!(sm :: SkinnedMesh, anms)
    try
        f = 1
        n = 1
        
        while true
            update_bones!(sm, anms[n], f)
            f += 1
            if f >= sm.skel.animations[anms[n]].frame_count
                f = 1
                n += 1
                if n >= length(anms) n = 1 end
            end
#            for i=1:20
            yield(); return
#            end
        end
    catch x
        println("Failed because of $x")
    end
end

function fill_frame(sm :: SkinnedMesh, r :: Renderer, uniforms :: SkinnedMeshShaderUniforms, i)
    uniforms.proj = r.proj*r.view
    ofs = (i-1)*MAX_BONES
   @assert length(sm.bone_matrices) <= MAX_BONES
    uniforms.bone_mat[1 + ofs:ofs + length(sm.bone_matrices)] = sm.bone_matrices
    uniforms.light_world = m2
    uniforms.light_pos = vec3()#world_transform(light_node).t
    uniforms.tex[i] = sm.tex
end

function fill_frame(::Type{SkinnedMesh},r)
    for sm in skinned_meshes
        fill_frame(sm, r, sm.drawref.uniforms, sm.drawref.prim_dc)
    end
end

const skinned_meshes = SkinnedMesh[]

function fill_init(uniforms :: SkinnedMeshShaderUniforms)
    uniforms.tex = fill(NoTexture, MAX_INSTANCES)
    uniforms.bone_mat = make_shader_buffer(Mat4, MAX_INSTANCES*MAX_BONES)
end

function add!(sm :: SkinnedMesh)
    push!(skinned_meshes, sm)
    add!(sm_rq, sm)
end
const sm_rq = RenderQueue()
function add!(rq :: RenderQueue, sm :: SkinnedMesh)
    sm.drawref = add!(rq, Mesh(shader, sm.bindings, sm.bufptr, sm.indices, [sm.tex]))
end
