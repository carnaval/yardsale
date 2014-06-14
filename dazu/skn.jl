type SknMat
    name :: String
    start_vx :: Uint32
    num_vx :: Uint32
    start_ix :: Uint32
    num_ix :: Uint32
end

type SknMesh
    materials :: Array{SknMat}
    indices :: Array{Uint16}
    buffer :: Array{Uint8} # Format is [pos bone_ids bone_weights norm txc]
end

const SKN_MAT_NAME_SIZE = 64
const SKN_BONE_COUNT = 4
function read_skn_mat(io::IOStream)
    name = replace(bytestring(read(io, Uint8, SKN_MAT_NAME_SIZE)), "\0", "")
    SknMat(name,
           read(io, Uint32), read(io, Uint32),
           read(io, Uint32), read(io, Uint32))
end

function read_skn(io::IOStream)
    # read header
    magic = read(io, Uint32)
    @assert magic == 0x00112233 "Invalid skn file"
    version = read(io, Uint16)
    @assert version <= 2 "Unknown skn version $version"
    obj_count = read(io, Uint16)
    @assert obj_count == 1 "Dont know how to do multiple objects"
	
    if version != 0
	mat_count = read(io, Uint32)
	materials = [ read_skn_mat(io) for i=0:mat_count-1 ]
    end
    
    num_ix = convert(Int, read(io, Uint32))
    num_vx = convert(Int, read(io, Uint32))

    if version != 0
	@assert num_ix == sum([ mat.num_ix for mat in materials ]) "Invalid skn file header (indice count)"
	@assert num_vx == sum([ mat.num_vx for mat in materials ]) "Invalid skn file header (vertex count)"
    end
    
    ixs = read(io, Uint16, num_ix)
    
    if version == 0
	materials = [SknMat("noMatGG", 0x00000000, uint32(num_vx), 0x00000000, uint32(num_ix))]
    end
    
    SknMesh(materials, ixs, read(io, Uint8, (4*3 + 1*SKN_BONE_COUNT + 4*SKN_BONE_COUNT + 4*3 + 4*2)*num_vx))
end

