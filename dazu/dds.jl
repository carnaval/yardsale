type Image
    format :: Symbol
    w :: Int
    h :: Int
    data :: Vector{Vector{Uint8}}
end

# used by header.flags
DDS_FLAGS1 =
{
 (:DDSD_CAPS,         0x1)
 (:DDSD_HEIGHT,       0x2)
 (:DDSD_WIDTH,        0x4)
 (:DDSD_PITCH,        0x8)
 (:DDSD_PIXELFORMAT,  0x1000)
 (:DDSD_MIPMAPCOUNT,  0x20000)
 (:DDSD_LINEARSIZE,   0x80000)
 (:DDSD_DEPTH,        0x800000)
}
#used by header.pixf.flags
DDS_FLAGS2 =
{
 (:DDPF_ALPHAPIXELS,  0x1)
 (:DDPF_ALPHA,        0x2)
 (:DDPF_FOURCC,       0x4)
 (:DDPF_RGB,          0x40)
 (:DDPF_YUV,          0x200)
 (:DDPF_LUMINANCE,    0x20000)
}

function read_dds_flags(io::IOStream, table)
    flag_bits = read(io, Uint32)
    flags = Set{Symbol}()
    for (s,v) in table
        if (v & flag_bits) != 0 push!(flags, s) end
    end
    flags
end

function read_dds_pixformat(io::IOStream)
    size = read(io, Uint32)
    flags = read_dds_flags(io, DDS_FLAGS2)
    fcc = bytestring(read(io, Uint8, 4))
    rgb_width = read(io, Uint32)
    masks = read(io, Uint32, 4)

#    assert(contains(flags, :DDPF_FOURCC) && fcc == "DXT1", "Unknown image format : $(fcc)")
    { "DXT1" => :DXT1, "DXT3" => :DXT3, "DXT5" => :DXT5 } [fcc]
end

function read_dds(io::IOStream)
    magic = read(io, Uint8, 4)
    @assert bytestring(magic) == "DDS " "Invalid DDS file"
    size = read(io, Uint32)
    flags = read_dds_flags(io, DDS_FLAGS1)
    needed = Set({:DDSD_WIDTH, :DDSD_HEIGHT, :DDSD_PIXELFORMAT})
    @assert isempty(setdiff(needed, flags)) "Incomplete header"
    
    h, w = read(io, Uint32), read(io, Uint32)
    _ = read(io, Uint32) # pitch
    depth = read(io, Uint32)
    num_mips = read(io,Uint32)
    if !(:DDSD_MIPMAPCOUNT in flags)
        num_mips = 1
    end
    _ = read(io, Uint32, 11) # reserved space
    pixf = read_dds_pixformat(io)
    caps = read(io, Uint32, 4)
    _ = read(io, Uint32, 1) # reserved
    
    mw = w
    mh = h
    data = [Uint8[] for i in 1:num_mips]
    cumu = 0
    F = if pixf == :DXT1 8 else 16 end
    for i=1:num_mips
        img_size = int(floor((mw+3)/4)*floor((mh+3)/4)*F) # DXT1 specific
        cumu += img_size
        data[i] = read(io, Uint8, img_size)
        mw >>= 1
        mh >>= 1
    end
    #assert(eof(io), "Unknown data at the end of the file $pixf")
    Image(pixf, w, h, data)
end

#println(read_dds(open("Annie.dds")))
