bitstype 8*64 PngMsg

type PngImage
    _ :: Ptr{Void}
    version :: Uint32
    width :: Uint32
    height :: Uint32
    format :: Uint32
    flags :: Uint32
    colormap_entries :: Uint32
    warning_or_error :: Uint32
    message :: PngMsg
end

PngImage() = PngImage(0, 1, 0, 0, 0, 0, 0, 0, reinterpret(PngMsg, zeros(Uint8, 64))[1])
cptr(x) = pointer_from_objref(x)+sizeof(Int)
function Base.show(io :: IO, img :: PngImage)
    bytes = reinterpret(Uint8, [img.message])
    l = findfirst(bytes, 0)
    msg = bytestring(bytes[1:(l == 0 ? end : l-1)])
    show(io, "Png(v$(img.version), dim=$(img.width)x$(img.height), fmt=$(img.format), flags=$(img.flags), err=$(img.warning_or_error), msg=$msg, data=$(img._))")
end

function check_error(img :: PngImage)
    if img.warning_or_error != 0
        error("fail : $img")
    end
end

const PNG_FORMAT_RGBA = 3 # :)
png_image_size(img) = (((((img).format)&0x08) != 0 ?1:(((((img).format) & 0x04) >> 2)+1))*(img).height*((((((img).format) & 0x08) != 0?1:((((img).format) & (0x02 | 0x01))+1)) * (img).width))) #taken from cc macro expansion
function png_from_file(fn)
    img = PngImage()
    ccall( (:png_image_begin_read_from_file, "libpng"), Int, (Ptr{Void}, Ptr{Uint8}), cptr(img), bytestring(fn))
    check_error(img)
    img.format = PNG_FORMAT_RGBA
    data = Array(Uint8, png_image_size(img))
    ccall( (:png_image_finish_read, "libpng"), Int, (Ptr{Void}, Ptr{Void}, Ptr{Void}, Int32, Ptr{Void}), cptr(img), 0, data, 0, 0)
    check_error(img)
    (img, data)
end

function make_png_tex(fn)
    img, data = png_from_file(fn)
end

png_from_file("./hahaa.png")
println()
