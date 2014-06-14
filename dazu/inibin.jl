try
abstract B3
catch
end
import Base.read
read(io, ::Type{B3}) = read(io, Uint8, 3)
const inibin_bitmask_types = [
	                      (0x0001, Uint32),
	                      (0x0002, Float32),
	                      (0x0004, Uint8),
	                      (0x0008, Uint16),
	                      (0x0010, Uint8),
	                      (0x0020, Bool), # boolean flags, single bit
                              (0x0040, B3),
                              (0x0080, Any), # yeah well this is unknown type we should prob assert
	                      (0x0400, Uint32),
	                      (0x1000, Uint16) # string type
                              ]

function read_null_ending_string(io::IO, offset)
    bck_pos = position(io)
    seek(io, offset)
    st = ""
    while (c = char(read(io,Uint8))) != '\0'
	st *= string(c)
    end
    seek(io, bck_pos)
    st
end

function parse_inibin(io::IO)
    version = int(read(io,Uint8))
    @assert version <= 2 "invalid inibin version: $version"
    if version == 2
        end_string_length = read(io,Uint16) # size of the end part containing all the strings*
        format = read(io,Uint16) # bitmask for data types
        rdict = Dict{Uint16,Any}()
        test = format
        for t in inibin_bitmask_types
	    if format & t[1] != 0
                test &= ~t[1]
	        count = read(io,Uint16)
	        k = read(io,Uint32,count)
	        if t[2] != Bool
		    merge!(rdict, {t[1] => {key => read(io,t[2]) for key in k}})
	        else
		    # boolean flags, single bit
		    bdict = Dict{Any,Any}()
		    id = 1
		    for i=1:(1+int((count-1)/8))
		        bits = read(io,Uint8)
		        for b=1:8
			    val = 0x1 & bits
			    merge!(bdict, {k[id] => val})
			    bits = bits >> 1
			    id += 1
			    if id > count
			        break
			    end
		        end
		        if id > count
			    break
		        end
		    end
		    merge!(rdict, {t[1] => bdict})
	        end
	    end
        end
        if test != 0 error("Could not decode inibin fully, unkown flag(s) : $(bin(test))") end
    elseif version == 1
        skip(io, 3)
        entry_count = read(io, Uint32)
        end_string_length = read(io, Uint32)
        rdict = [ 0x1000 => [ read(io, Uint32) => read(io,Uint32) for i = 1:entry_count ] ]           
    end

    rfdict = Dict{Uint32,Any}()
    for t in keys(rdict)
	c = get(rdict, t, :dafuq)
	
	if t == 0x0004
	    newc = {kv[1] => kv[2]*0.1f0 for kv in c}
	    c = newc
	    
	    # read strings threw offsets of keys type 0x1000
	elseif t == 0x1000
	    bck_pos = position(io)
	    seekend(io)
	    file_size = position(io)
	    seek(io, bck_pos)
	    ssoffset = file_size - end_string_length # starting_strings_offset
	    
            newc = {kv[1] => read_null_ending_string(io, ssoffset + kv[2]) for kv in c}
	    c = newc
	end
	
	merge!(rfdict, c)
    end

    rfdict
end

include("inibin_keys.jl")
