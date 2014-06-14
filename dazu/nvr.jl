try
    include("math.jl")
    include("tex.jl")
end

io = open(nvr_file)
MAX_BLOCK_SIZE = get([1=>60000, 4=>58000, 8=>58000, 10=>49000, 12=>58000], map_id, 60000) # TODO hardcoded blocksize

pls(c) = replace(bytestring(c), "\0", "")
function prettypls(c) ## could be split(bytestring(c),'\0')[1] i suppose
    cc = bytestring(c)
    ccc = ""
    for ch in cc
		if ch == '\0' break end
		ccc *= string(ch)
	end
    ccc
end
println("Nvr file : $nvr_file")
const magic = bytestring(read(io, Uint8, 4))
assert(magic == "NVR\0", "Invalid NVR file")
_ = read(io, Uint16, 2)
assert(_ == [9,1], "Not sure if invalid or i'm just dumb: $_")
const material_count = int(read(io, Uint32))
const pointblock_count = int(read(io, Uint32))
_ = int(read(io,Uint32))
assert(_ == pointblock_count, "The all _ misunderstanding is back, great: $pointblock_count != $_")
const plop = int(read(io, Uint32, 2)) #Still don't know wth is that

println("Loading $nvr_file: nMat = $material_count, nPointBlock = $pointblock_count, plop = $plop")

try
    type TextureBlock
	unk_blend :: Array{Float32}
	filename :: String
	unk_pf :: Array{Float32}
	texture :: Union((),Texture)
    end
    type MaterialBlock
	name :: String
	param1 :: Int
	param2 :: Int
	textures :: Array{TextureBlock}
    end
end
function read_mat(io::IOStream)
    name = pls(read(io, Uint8, 256))
    unk1 = int(read(io, Uint32))
    assert(unk1 == 0, "oO the first parameter is now used: $unk1")
    param1 = int(read(io, Uint32))
    param2 = int(read(io, Uint32)) #Still don't know wtf is that either

    textures = TextureBlock[]
    for i=1:8
	unk_blend = read(io,Float32,4)
	filename = pls(read(io,Uint8,256))
	unk_pf = read(io,Float32,17)
	
	if filename != ""
	    push!( textures, TextureBlock(unk_blend, filename, unk_pf, ()) )
	end
    end
    
    MaterialBlock(name, param1, param2, textures)
end

const mats = [read_mat(io) for i=1:material_count]

type SMesh
    buffer :: Array{Uint8}
    gpu_buffer :: GpuBuffer
    bindings :: Bindings
    shader :: Shader
    
    triangles :: Union((),Array{Uint16})
    material :: Union((), MaterialBlock)
end

basic_shader = compile_shader(:basic_red,
"uniform mat4 proj;
 in vec2 v_tex1c;
 in vec3 v_posn;
 out vec2 f_tex1c;

 void main(void) {
   gl_Position = proj*vec4(v_posn.xyz, 1.0);
   f_tex1c = v_tex1c;
 }",
"uniform sampler2D tex1;
 in vec2 f_tex1c;
 
 void main(void) {
   gl_FragColor = texture2D(tex1, f_tex1c);
 }")

basic_clamp_shader = compile_shader(:basic_clamp,
"uniform mat4 proj;
 in vec2 v_tex1c;
 in vec3 v_posn;
 
 out vec2 f_tex1c;

 void main(void) {
   gl_Position = proj*vec4(v_posn.xyz, 1.0);
   f_tex1c = v_tex1c;
 }",
"uniform sampler2D tex1;
 in vec2 f_tex1c;
 void main(void) {
   gl_FragColor = texture2D(tex1, clamp(f_tex1c, 0, 1));
 }")

ablend_tx2_shader = compile_shader(:ablend_tx2,
"uniform mat4 proj;
 in vec2 v_tex1c;
 in vec2 v_tex2c;
 in vec3 v_posn;
 in vec3 v_norm;
 out vec2 f_tex1c;
 out vec2 f_tex2c;
 out vec3 f_norm;
 void main(void) {
   gl_Position = proj*vec4(v_posn.xyz, 1.0);
   f_tex1c = v_tex1c;
   f_tex2c = v_tex2c;
   f_norm = v_norm;
 }",
"uniform sampler2D tex1;
 uniform sampler2D tex2;
 uniform sampler2D tex3;
 uniform sampler2D tex4;
 uniform sampler2D tex5;
 in vec2 f_tex1c;
 in vec2 f_tex2c;
 in vec3 f_norm;
 void main(void) {
   gl_FragColor = texture2D(tex1, f_tex1c);
   
   float a = texture2D(tex2, f_tex2c).r;
   gl_FragColor = (1-a)*gl_FragColor + a*texture2D(tex3, f_tex1c);
   
   a = texture2D(tex2, f_tex2c).g;
   gl_FragColor = (1-a)*gl_FragColor + a*texture2D(tex4, f_tex1c);
   
   a = texture2D(tex2, f_tex2c).b;
   gl_FragColor = (1-a)*gl_FragColor + a*texture2D(tex5, f_tex1c);
   
   gl_FragColor.a = 1.0;
 }")

# Vertex formats
# blocktype format
# 255       XYZ
# 3         XYZ NNN UV UV ?
# 0         XYZ NNN UV ??
# 1-2       XYZ NNN UV ?
const PNTXX = @buffer_format v_posn none(12) v_tex1c none(8)
const PNTX =  @buffer_format v_posn none(12) v_tex1c none(4)
const PNTTX = @buffer_format v_posn none(12) v_tex1c v_tex2c none(4)

const vstatic_mesh = {() for i=1:pointblock_count}
materialID = 1
for ii=1:pointblock_count
    blockType = if materialID <= material_count mats[materialID].param1 else 255 end
    if blockType != 255 && mats[materialID].param2 < 16 && blockType != 3 blockType = 1 end
    blockByteSize = int(read(io,Uint32))
    pointBlockSize = if blockType == 0 40 elseif blockType <= 2 36 elseif blockType == 3 44 else 12 end
    blockSize = int(blockByteSize / pointBlockSize)
    
    #println(materialID, " ", blockType, " ", blockSize, " ", blockByteSize, " ")
    
    buf = read(io, Uint8, blockByteSize)
    
    sh = if blockType == 0 basic_shader elseif blockType == 3 ablend_tx2_shader else basic_clamp_shader end
    buf_format = if blockType == 0 PNTXX elseif blockType == 3 PNTTX else PNTX end
    g_buf = make_gpu_buffer()
    upload_data(g_buf, buf)
    vstatic_mesh[ii] = SMesh(buf, g_buf, bindings(sh, g_buf, buf_format), sh, (),
                             (if blockType == 255
                              ()
                              else mats[materialID] end))
							  
    if blockSize < MAX_BLOCK_SIZE
		materialID += 1
    end
end

function read_idxs(io::IOStream)
    (G0,G1) = int(read(io,Uint32,2))
    assert(G1 == 101, "Why the fuck is G1 not 101 ?")
    read(io,Uint16,int(G0/2))
end

for uu in 1:pointblock_count
    vstatic_mesh[uu].triangles = read_idxs(io)
end

##############################################################################################################
### here start the bullshity world where the chosen one try to become the mind of the end of the file

_ = plop[1]
fis = [ 0 for i=1:_ ] # first ints
fls = [ 0f0 for i=1:10*_ ] # floats
lis = [ 0 for i=1:13*_ ]
for current__=1:_ # im loving it
    fis[current__] = int(read(io,Uint32)) # -100 -1 0 1 2 3. I call the great spirit of rainman to help me on my quest
    
    plouf = int(read(io,Uint32))
    assert( plouf == 0, "we will meet were it all began, and we will end were it all began: $plouf" )
    
    fls[10*(current__-1)+1:10*current__] = read(io,Float32,10)
    lis[13*(current__-1)+1:13*current__] = int(read(io,Uint32,13))
end

_ = plop[2]
nii = [ 0 for i=1:10*_ ] # no idea ints
for current__=1:_
    nii[10*(current__-1)+1:10*current__] = read(io,Int32,10)
end

# ----------------8<-------------[ everything ends here ]---------------------------------------------------- #

abs_txfile(x) = lowercase(tex_path * "/" * string(x)[1:end-4] * ".dds")

for material in mats
    try
	for text in material.textures
	    text.texture = make_dds_tex(open(abs_txfile(text.filename)))
	end
    catch x
        println("Error $x while loading texture")
    end
end

function render_static_mesh(mesh::SMesh, mat)
    if mesh.material != ()
        s = mesh.shader
        glUseProgram(s.program)
        
        for iText=1:length(mesh.material.textures)
            bind_tex(mesh.material.textures[iText].texture, int32(iText-1))
            set_uniform(s.uniforms[ symbol("tex$iText") ], iText-1)
        end
        bind(mesh.bindings)
        set_uniform(s.uniforms[:proj], mat)
        glDrawElements(GL_TRIANGLES, length(mesh.triangles), GL_UNSIGNED_SHORT, mesh.triangles)
#        bind(NoBuffer)
    end
end

mxx(uu) = vstatic_mesh[uu].material # TODO Carnaval is retarded ? ... Carnaval is retarded.
mpn(uu) = if mxx(uu) == () 255 else mxx(uu).param1 end


@gl glDepthMask Void (Uint8,)

function render_nvr(mat)
    for current_uu in 1:pointblock_count
	if mpn(current_uu) != 1
	    render_static_mesh(vstatic_mesh[current_uu], mat)
	end
    end
    glDepthMask(0)
    for current_uu in reverse(1:pointblock_count)
	if mpn(current_uu) == 1
	    render_static_mesh(vstatic_mesh[current_uu], mat)
	end
    end
    glDepthMask(1)
end

