const BONE_NAME_LENGTH = 32

type AnmBone
    name :: Symbol
    orientations :: Array{Float32, 2}
    positions :: Array{Float32, 2}
end

function riot_hash(s :: String)
	h = int32(0)
	for i=1:length(s)
		h = int32(lowercase(s[i])) + (h << 4)
		g = h & int32(0xF0000000)
		if g != 0
            h = h $ (h & int32(0xF0000000)) $ ((h & 0xF0000000) >> 24)
		end
		#<h &= ~g
	end
	uint32(h)
end

function riot_hash2(s :: String)
	h = uint32(0)
	
	for i=1:length(s)
		h = (h << 4) + uint32(s[i])
		g = h & 0xf0000000
		if g != 0
			h $= (uint32(g) >> 24)
		end
		h &= ~g
	end
	h
end

function read_anm(io::IOStream, skl)
    magic = bytestring(read(io, Uint8, 8))
    @assert magic == "r3d2anmd" "Invalid anm file"
    version = read(io, Uint32)
    @assert (version == 3 || version == 4) "Unknown anm version : $version"
    bones = Dict{Symbol, AnmBone}()
    if version == 3
	designer_id = read(io, Uint32)
	#assert(magic == 0xda4, "Invalid anm magic (2?)")
	bone_num = read(io, Uint32)
	frame_num = read(io, Uint32)
	fps = read(io, Uint32)
	for i=1:bone_num
	    name = symbol(replace(bytestring(read(io, Uint8, BONE_NAME_LENGTH)), "\0", ""))
	    flag = read(io, Uint32)
	    qs = float32(zeros(frame_num, 4))
	    vs = float32(zeros(frame_num, 3))
	    for i=1:frame_num
		qs[i, :] = read(io, Float32, 4)
		vs[i, :] = read(io, Float32, 3)
	    end
	    bones[name] = AnmBone(name, qs, vs)
	end
	bones
    elseif version == 4
	data_size = read(io, Uint32)
	magic = read(io, Uint32)
#	@assert magic == 0xBE0794D3 "Invalid anm v4 file"
	
	_ = read(io, Uint32, 2)
	
	num_bones = read(io, Uint32)
	num_frames = read(io, Uint32)
	
	fps = read(io, Float32) # we may have to do fps = fps >= 1f0 ? fps : 1/fps 
	fps = 1/fps
	
	_ = read(io, Uint32, 3)
	
	posn_offset = read(io, Uint32)
	ori_offset = read(io, Uint32)
	frames_offset = read(io, Uint32)
	
	num_pos_f = (ori_offset - posn_offset)/12
	@assert round(num_pos_f) == num_pos_f
	num_pos = uint32(num_pos_f)
	
	num_ori_f = (frames_offset - ori_offset)/16
	@assert round(num_ori_f) == num_ori_f
	num_ori = uint32(num_ori_f)
	
	_ = read(io, Uint32, 3)

	positions = read(io, Float32, 3*num_pos)
	orientations = read(io, Float32, 4*num_ori)
	bone_names = [:none for i=1:num_bones]
	for fn = 1:num_frames
	    for bn = 1:num_bones
		name_hash = read(io, Uint32)
		pos_id = read(io, Uint16)
		_ = read(io, Uint16)
		ori_id = read(io, Uint16)
		_ = read(io, Uint16)
		
		if fn == 1
		    for b in skl
			if b.name_hash == name_hash
			    bone_names[bn] = b.name
			    break
			end
		    end
		    qs = float32(zeros(num_frames, 4))
		    vs = float32(zeros(num_frames, 3))
		    #assert(bone_names[bn] != :none, "Bone hash not found : $name_hash")
		    if bone_names[bn] == :none
                        # TODO log this somewhere
                        #						println("Warning : bone hash not found : $name_hash")
		    end
		    bones[bone_names[bn]] = AnmBone(bone_names[bn], qs, vs)
		    #println("FN $fn ", name_hash, " ", pos_id, " ", ori_id)
		end
		bones[bone_names[bn]].positions[fn, :] = positions[3*pos_id+1 : 3*pos_id+3]
		bones[bone_names[bn]].orientations[fn, :] = orientations[4*ori_id+1 : 4*ori_id+4]
	    end
	end
	bones
    end
end

