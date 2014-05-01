



function writeall(io :: IO, in :: IO, sz = typemax(Int))
    i = 0
    while i < sz && !eof(in)
        write(io, read(in, Uint8)) # this is slow
        i += 1
    end
end


module Http
const CRLF = "\r\n"
import Main.writeall, Base.TcpSocket
immutable Header
    name :: ASCIIString
    value :: ASCIIString
end

typealias Headers Vector{Header}

type Req
    method :: Symbol
    path :: ASCIIString
    version :: ASCIIString
    
    headers :: Headers
    body :: IO
end

type Resp
    code :: Int
    status :: ASCIIString
    version :: ASCIIString
    
    headers :: Headers
    body :: IO
end

function read_http_line(io :: IO)
    line = readuntil(io, CRLF)
    if endswith(line, CRLF)
        line[1:end-2]
    else
        line
    end
end

function read_http(io :: IO)
    query = read_http_line(io)
    
    headers = Header[]
    line = read_http_line(io)
    while !isempty(line)
        i = search(line, ':')
        if 1 <= i <= length(line)
            push!(headers, Header(line[1:i-1], strip(line[i+1:end])))
        else
            push!(headers, Header("Unknown", line))
        end
        line = read_http_line(io) 
    end
    (query, headers)
end
function read_http_resp(io :: IO)
    (subject, headers) = read_http(io)
    xs = split(subject, ' ')
    if length(xs) < 2
        ()
    else
        Resp(int(xs[2]), join(xs[3:end], ' '), xs[1][6:end], headers, io)
    end
end

function read_http_req(io :: IO)
    (subject, headers) = read_http(io)
    xs = split(subject, ' ')
    if length(xs) < 2
        ()
    else
        Req(symbol(xs[1]), normalize_path(join(xs[2:end-1], ' ')), xs[end][6:end], headers, io)
    end
end

normalize_path(p) = (while endswith(p, "/"); p = p[1:end-1] end; p) # haha


function parse_uri(x :: ASCIIString)
    i = search(x, "://")
    if isempty(i)
        proto = :http # let's assume
        ls = 1
    else
        proto = symbol(x[1:first(i)-1])
        ls = last(i) + 1
    end
    j = search(x, '/', ls)
    if j <= 0
        (proto, x[ls:end], "/")
    else
        (proto, x[ls:j-1], x[j:end])
    end
end

clen(io) = (p = position(io); seekend(io); l = position(io) - p; seek(io, p); l)
# add Content-Length header
# eventually we can cunk encode & gzip inflate here
function prepare(rq)
    push!(rq.headers, Header("Content-Length", string(clen(rq.body))))
end

function write_prepared(io, rq)
    prepare(rq)
    write(io, rq)
end

function request(method :: Symbol, url :: ASCIIString, body = IOBuffer(), additional_headers = Header[], max_redir = 5)
    (proto, host, path) = parse_uri(url)
    (c,_) = connect(TcpSocket(), host, 80)
    write_prepared(c, Req(method, path, "1.1", vcat([Header("Host", host)], additional_headers), body))
    resp = read_http_resp(c)
    if (resp.code == 301 || resp.code == 302) && max_redir > 0
        close(c)
        request(method, resp.headers["Location"], IOBuffer(), Header[], max_redir - 1)
    else
        resp
    end
end

function response(io :: IO, code :: Int, status :: String, body = IOBuffer(), additional_headers = Header[])
    write_prepared(io,
                   Resp(code, status, "1.1", additional_headers, body))
end


hasheader(rq, name :: String) = !isempty(find(rq.headers) do hd hd.name == name end)

function read_body(rq, into :: IO)
    if hasheader(rq, "Content-Length")
        writeall(into, rq.body, int(rq.headers["Content-Length"]))
    elseif hasheader(rq, "Transfer-Encoding")
        if rq.headers["Transfer-Encoding"] == "chunked"
            chnk_size = -1
            while chnk_size != 0
                chnk_size = parseint(Int, read_http_line(rq.body), 16)
                writeall(into, rq.body, chnk_size)
                assert(bytestring(read(rq.body, Uint8, 2)) == CRLF)
            end
        else
            error("Unsupported transfer-encoding : ", rq.headers["Transfer-Encoding"])
        end
    else
        writeall(into, rq.body)
    end
end

function bodystring(rq)
    b = IOBuffer()
    read_body(rq, b)
    seekstart(b)
    readall(b)
end

get(url) = request(:GET, url)

function get_string(url :: ASCIIString)
    resp = get(url)
    (resp, bodystring(resp))
end

function get_file(url :: ASCIIString, fn)
    resp = get(url)
    open(fn, "w") do f
        read_body(resp, f)
    end
    resp
end

function ok(c, s, mime)
    response(c, 200, "OK", s, [Header("Content-Type", mime)])
end

function internal_error(c, s::String)
    response(c, 500, "Internal server error", IOBuffer(s))
end

function ok(c, s::String; mime = "text/plain")
    ok(c, IOBuffer(s), mime)
end

function not_found(c, s::String)
    response(c, 404, "Not found", IOBuffer(s))
end

routes = {}

function serve_conn(c)
    while !eof(c)
        req = read_http_req(c)
        found = false
        for route in routes
            m = match(route[1], req.path)
            if m != nothing && route[2] == req.method
                try
                    route[3](c, req, m.captures...)
                    found = true
                catch x
                    internal_error(c, "Exception : $x")
                end
                break
            end
        end
        found || not_found(c, "Not found : $(req.path).\nNo matching route.\n$routes")
        close(c)
        break
    end
end

function serve(port :: Int)
    s = listen(port)
    while true
        c = accept(s)
        @async serve_conn(c)
    end
end

import Base.write, Base.show, Base.getindex

function write(io :: IO, hd :: Http.Header)
    write(io, hd.name)
    write(io, ": ")
    write(io, hd.value)
    write(io, CRLF)
end

function write(io :: IO, req :: Http.Req)
    write(io, string(req.method))
    write(io, ' ')
    write(io, req.path)
    write(io, " HTTP/")
    write(io, req.version)
    write(io, CRLF)
    write(io, req.headers)
    write(io, CRLF)
    writeall(io, req.body)
end

function write(io :: IO, resp :: Http.Resp)
    write(io, "HTTP/")
    write(io, resp.version)
    write(io, ' ')
    write(io, string(resp.code))
    write(io, ' ')
    write(io, resp.status)
    write(io, CRLF)
    write(io, resp.headers)
    write(io, CRLF)
    writeall(io, resp.body)
end

function show(io :: IO, hds :: Http.Headers)
    print(io, "($(length(hds)) headers)")
end


function getindex(hds :: Http.Headers, name :: ASCIIString)
    for hd in hds
        if hd.name == name
            return hd.value
        end
    end
    error("Header not found $name")
end

end


regex_for = { :Int => "\\d+", :String => "[[a-zA-Z0-9]\-_]*" }
function_for = {:Int => parseint,
                :String => identity}
macro resource(stx...)
    method = stx[1]
    path = stx[2:end-1]
    code = stx[end]
    prelude = Expr[]
    args = Expr[]
    arg_names = Symbol[]
    ps = "^"
    for p in path
        if typeof(p) <: String
            ps *= p
        elseif typeof(p) == Expr && p.head == :(::)
            ps *= "(" * regex_for[p.args[2]] * ")"
            push!(args, p)
            push!(arg_names, gensym(string(p.args[1])))
            unshift!(prelude, :($p = $(function_for[p.args[2]])($(last(arg_names)))))
        else
            error("Invalid argument $p")
        end
    end
    ps *= "\$"
    quote
        function res(io, req, $(arg_names...))
            $(prelude...)
            $code
        end
        push!(Http.routes, (Regex($ps), $(Expr(:quote, method)), res))
    end
end

macro html_mstr(x)
    println(parse("\"" * x * "\""))
    x
end

@resource GET "/" begin
    Http.ok(io, "We good : $(Http.routes) $req")
end

include("dtl.jl")

@resource GET "/c/" x::Int begin
    Http.ok(io,
            dtl(:index,
                page_title = string(x),
                routes = Http.routes),
            "text/html")
end

Http.serve(8080)
exit()

Http.get_file("http://88.178.16.94/a.out.js", "xx")
t0 = time()
for i = 1:10
    Http.get_file("http://localhost/a.out.data", "xx")
    println("Done $i : $(time() - t0)")
end
println("Total : $(time() - t0)")
