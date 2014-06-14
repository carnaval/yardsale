const BONE_NAME_SIZE = 32

type SklBone
    name :: Symbol
    id :: Uint32
    bound :: Bool
    parent :: Uint32
    scale :: Float32
    transform :: Union(Matrix{Float32}, Aff)
    is_relative :: Bool
    name_hash :: Uint32
end

function read_skl_bone(io::IOStream, bone_id::Uint32, bound :: Bool)
    name = symbol(replace(bytestring(read(io, Uint8, BONE_NAME_SIZE)), "\0", ""))
    #println("red $name")
    parent = read(io, Uint32)
    scale = read(io, Float32)
#println("bone : $name / $parent")
    #    println("Scale : ", scale)
    transform = transpose(reshape(read(io, Float32, 4*3), (4,3)))
    SklBone(name, bone_id, bound, parent, scale, transform, false, riot_hash(string(name)))
end

function read_raw_skl_bone(io :: IO, real_name_hash :: Uint32, name :: String, is_transform_relative :: Bool)
    _ = read(io, Uint16)
    id = read(io, Uint16)
    parent = read(io, Uint16)
    _ = read(io, Uint16)
    #println(_)
    name_hash = read(io, Uint32)
    # TODO log this somewhere
    #assert(name_hash == real_name_hash, "Somethign went horribly wrong : $name_hash != $real_name_hash") # sanity
    if name_hash != real_name_hash
#	println("Warning, wrong hash for $name : $name_hash instead of $real_name_hash")
    end
    _ = read(io, Float32)
    pos = read(io, Float32, 3)
    _ = read(io, Float32, 3)
    q = read(io, Float32, 4)
    _ = read(io, Float32, 3)
    
    a = Aff(Quat(q), vec3(pos...))
    skip(io, 32) # magic don't ask
    SklBone(:none, uint32(id), false, uint32(parent), 1f0, a, is_transform_relative, name_hash)
end

const SKL_VERSION_RHO = 729 # What the actual fuck
function read_skl(io::IOStream)
    magic = read(io, Uint8, 8)
    if bytestring(magic) == "r3d2sklt"
	
        #assert(magic == [0x32643372, 0x746c6b73], "Invalid skl file")
	version = read(io, Uint32)
	@assert (version == 1 || version == 2) "Unknown skl version"
	designer_id = read(io, Uint32)
	num_bones = read(io, Uint32)
        
	bones = [read_skl_bone(io, uint32(i-1), (version == 1)) for i=1:num_bones]
	if version == 2
	    num_indices = read(io, Uint32)
	    index_type = Uint32
	end
    elseif magic[5:8] == [0xc3, 0x4f, 0xfd, 0x22]
	version = SKL_VERSION_RHO
	file_size = read(IOBuffer(magic[1:4]), Uint32)
	
	# sanity check
	p = position(io)
	seekend(io)
	actual_size = position(io)
	seek(io, p)
	@assert actual_size == file_size
	
	_ = read(io, Uint32)
	_ = read(io, Uint16)
	num_bones = read(io, Uint16)
	num_indices = read(io, Uint32)
	header_size = read(io, Uint32)
	@assert header_size == 0x40
	sizes = read(io, Uint32, 5)
	
	seek(io, sizes[5])
	names = [ "" for i=1:num_bones ]
	#skip(io, 1)
	for i=1:num_bones
	    #while !isascii(char(Base.peek(io)))
	    #	skip(io, 1)
	    #end
	    names[i] = readuntil(io, '\0')[1:end-1]
	    while (position(io) % 4) != 0 skip(io, 1) end #please kill me
	end
	
	seek(io, header_size)
	bones = { () for i=1:num_bones }
	for i=1:num_bones
	    bone = read_raw_skl_bone(io, riot_hash(names[i]), names[i], true)
	    bone.name = symbol(names[i])
	    bones[bone.id+1] = bone
	end
        bone_trans = [b.transform for b in bones]
        for i=1:num_bones
            p = i-1
            l = lin_id
            while 0 <= p < num_bones
        	l = aff_to_mat(bone_trans[p+1])*l
        	p = bones[p+1].parent
            end
            bones[i].transform = mat_to_array(l)[1:3, 1:4]
        end
	seek(io, sizes[2])
	index_type = Uint16
	#println(readuntil(io, '\0'))
        #WORD uk2;
        #WORD nbSklBones;
        #int num_bones_foranim;
        #int header_size; // 0x40
        #int size_after_array1;
	#	println("Unk $unk_and_id")
    end
    
    if version == 2 || version == SKL_VERSION_RHO
	
	for idx=1:num_indices
	    i = read(io, index_type)
            bones[i+1].bound && error("Bound twice")
#            println("bone bound : $(bones[i+1].name) to $(idx-1)")
	    bones[i+1].id = uint32(idx - 1)
	    bones[i+1].bound = true
	end
    end

    bones
end

