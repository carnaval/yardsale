
type FileEntry
    hash :: Uint32
    data_offset :: Uint32
    data_size :: Uint32
    pathlist_index :: Uint32
end

function read_file_entry(io :: IO)
    FileEntry(read(io, Uint32), read(io, Uint32), read(io, Uint32), read(io, Uint32))
end

using Zlib

function dump_raf(raf_file :: String, dest_path :: String)
    io = open(raf_file)
    data_io = open(raf_file * ".dat")
    magic = read(io, Uint32)
    @assert(magic == 0x18be0ef0, "Invalid RAF file")
    version = read(io, Uint32)
    @assert(version == 1, "Unkown version $version")
    _ = read(io, Uint32)
    file_list_offset = read(io, Uint32)
    path_list_offset = read(io, Uint32)
    file_count = read(io, Uint32)

    file_entries = [read_file_entry(io) for i = 1:file_count]
    _ = read(io, Uint32)
    path_count = read(io, Uint32)
    for i = 1:path_count
        read(io, Uint32, 2)
    end
        
    path_entries = [readuntil(io, '\0') for i = 1:path_count]
    for file in file_entries
        path = path_entries[file.pathlist_index + 1]
        dest = dest_path * "/" * path
        mkpath(lowercase(dest_path * "/" * dirname(path)))
        seek(data_io, file.data_offset)
        out = open(lowercase(dest), "w")
        raw_data = read(data_io, Uint8, file.data_size)
        d = ()
        try
            d = Zlib.decompress(raw_data)
        catch e
            d = raw_data
        end
        write(out, d)
        close(out)
    end
    file_count
end

function find_raf(base :: String)
    if endswith(base, ".raf")
        {base}
    elseif !isdir(base)
        {}
    else
	children = map(fn -> begin println("Calling : $fn"); x = find_raf(base * "/" * fn); println("Done : '$x'"); x end, readdir(base))
	if length(children) == 0
	   {}
	else
	   vcat(children...)
	end
    end
end

if length(ARGS) < 2
    println("Usage rafdump.jl [lol install path] [dest folder]")
else
    source = ARGS[1]
    dest = ARGS[2]
    println("Dumping : $source raf files to $dest")
    rafs = find_raf(source)
    println("Found $(length(rafs)) raf files. Commencing dump.")
    println(rafs)
    i = 1
    for raf in rafs
        file_count = int(dump_raf(raf, dest))
        println("Done $i/$(length(rafs)) $(basename(raf)) : $file_count files.")
        i += 1
    end
    println("Done.")
end
