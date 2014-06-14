function read_scb(_filename)

	io = open("scbs3/"*_filename*".scb")
	#io = open("scbs/Barracks_T1_R1.SCB")
	#io = open("scbs/HQ_T1.SCB")

	pls(c) = split(bytestring(c),'\0')[1]

	const magic = bytestring(read(io, Uint8, 8))
	assert(magic == "r3d2Mesh", "Invalid SCB file")
	const version = int(read(io,Uint16,2))
	assert(version == [2,2], "Version isnt 2.2 ? v$version")
	const name = pls(read(io, Uint8, 128))
	const vert_count = int(read(io,Uint32))
	const face_count = int(read(io,Uint32))
	_ = int(read(io,Uint32))
	assert(_ == 1, "The _ weirdiness is back")

	const central_point = read(io,Float32,3)
	const dafuq = read(io,Float32,3)
	verts = [ read(io,Float32,3) for i=1:vert_count ]
	# println(sum(verts)/vert_count)
	# for i=1:vert_count
		# verts[i][2] += 100f0
	# end
	verts_ = [ 0f0 for i=1:3*vert_count ]
	for i=1:vert_count
		verts_[3*(i-1)+1:3*i] = verts[i]
	end

	_ = read(io,Float32,3)
	assert(_ == verts[end], "Something i didn't quite understood: $(verts[end]) != $_")

	println("Loading SCB: $name, nVert=$vert_count, nFace=$face_count, central_point=$central_point")
	# for v in verts println(v) end
	
	function read_face(io::IOStream)
		idxs = int(read(io, Uint32, 3))
		fname = pls(read(io, Uint8, 64))
		floats = read(io, Float32, 6)
		(fname, idxs, floats)
	end

	faces = [ read_face(io) for i=1:face_count ]
	#for f in faces println(f) end
	faces_ = [ uint16(0) for i=1:3*face_count ]
	for i=1:face_count
		faces_[3*(i-1)+1:3*i] = uint16(faces[i][2])
	end

	# WHO THE FUCK DOES THAT
	texs = [ 0f0 for i=1:2*vert_count ]
	for face in reverse(faces)
		for i=1:3
			id = face[2][i]+1 #starting at 1 for julia arrays blablabla
			texs[2*id-1:2*id] = [face[3][i],face[3][i+3]]
		end
	end

	# complete rework ?
	verts_ = [ 0f0 for i=1:9*face_count ]
	faces_ = [ uint16(i) for i=0:3*face_count-1 ]
	texs = [ 0f0 for i=1:6*face_count ]
	for iFace=1:face_count
		face = faces[iFace]
		for i=1:3
			verts_[9*(iFace-1)+3*(i-1)+1:9*(iFace-1)+3*i] = verts[face[2][i]+1]
		end
		texs[6*(iFace-1)+1:6*iFace] = face[3][[1,4,2,5,3,6]]
	end


	main_material = faces[1][1]

	txfile = open("room5.mat")
	function find_tx(txname)
		seekstart(txfile)
		while !eof(txfile)
			line = split(readline(txfile), "=")
			if length(line) >= 2 && line[1] == "Name" && strip(line[2]) == txname
				while !eof(txfile)
					line2 = split(readline(txfile), "=")
					if strip(line2[1]) == "[MaterialEnd]"
						return :non
					elseif length(line2) >= 2 && line2[1] == "Texture"
						return strip(line2[2])[1:end-4]
					end
				end
			end
		end
		return :non
	end

	#break

	main_texture_file = find_tx(main_material)
	if strip(name) == "LevelProp_HA_AP_Hermit"
		main_texture_file = "non2"
		println("plopppp")
	else
		println(name)
		main_texture_file = :non
	end
	main_texture = 	if main_texture_file != :non 
						make_dds_tex(open("txs/"*main_texture_file*".dds"))
					else 
						:stillnon
						#make_dds_tex(open("txs/non.dds"))
					end
	
	(verts_, texs, faces_, main_texture)
end

scbs = Any[]
dsc_io = open("room5.dsc")
while !eof(dsc_io)
	line = split(readline(dsc_io), ".")
	if length(line) >= 2
		push!(scbs,read_scb(line[1]))
	end
end

function render_scb(scb_block, mat)
	glUseProgram(basic_shader.program)
	
	bind_attr(basic_shader.attributes[ :v_posn ], scb_block[1])
	bind_attr(basic_shader.attributes[ :v_texc ], scb_block[2])
	set_uniform(basic_shader.uniforms[:proj], mat)
	set_uniform(basic_shader.uniforms[:tex], 0)
	bind_tex(scb_block[4], 0)

	glDrawElements(GL_TRIANGLES, length(scb_block[3]), GL_UNSIGNED_SHORT, scb_block[3])
end

function render_all_scb(mat)
	for scb_block in scbs
		if scb_block[4] != :stillnon
			render_scb(scb_block, mat)
		end
	end
end