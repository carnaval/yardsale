
const CLOG_SIZE = 40
const CLOG_WIDTH = 120

type HistEnt
    val :: UTF8String
    edit :: UTF8String # if it is empty we are not editing this history line
end

const history = [HistEnt(utf8(""),utf8(""))]
current_hist = 1
current_line = 1
cursor = 1
const clog = [utf8("") for i=1:CLOG_SIZE]
function clear()
    for i=1:length(clog)
        clog[i] = utf8("")
    end
    nothing
end

clear()

function eval_string(s)
    if isempty(s) return "" end
    try
        res = eval(parse(s))
        if res == nothing
            ""
        else
            string(res)
        end
    catch x
        "$x\naborted $(typeof(x))"
    end
end

function clog_newline()
    global current_line, clog
    current_line = (current_line % CLOG_SIZE) + 1
    clog[current_line] = utf8("")
end

function clog_append(s :: String)
    global current_line, clog
    sp = CLOG_WIDTH - length(clog[current_line])
    if sp >= length(s)
	    clog[current_line] *= s
    else
	    idx = chr2ind(s, sp)
	    clog[current_line] *= s[1:idx]
        clog_newline()
        clog_append(s[nextind(s, idx):end])
    end
    nothing
end

function clog_print(s :: UTF8String)
    lines = split(s, "\n")
    for line in lines[1:end-1]
        clog_append(line)
        clog_newline()
    end
    clog_append(lines[end])
    nothing
end

function clog_line(s :: UTF8String)
    global clog, current_line
    if (!isempty(s) || !isempty(clog[current_line])) clog_print(s * "\n") end
end

function cline()
    global history, current_hist
    if history[current_hist].edit == ""
        history[current_hist].val
    else history[current_hist].edit
    end
end

function cline(s :: UTF8String)
    global history, current_hist
    history[current_hist].edit = s
end
const BKSPACE = uint32('\b')
const SUPPR = uint32(127)
function console_handle_event(ty :: Symbol, d)
    global cursor, history, current_hist
    if ty == :keydown
        if d == uint32('\r') || d == ((1 << 30) | uint32(0x58)) # KP_RETURN
            clog_line(utf8("> ")*cline())
            if !isempty(cline())
                output = utf8(eval_string(cline()))
                clog_line(output)
                history[end].val = history[current_hist].edit
                history[end].edit = utf8("")
                history[current_hist].edit = utf8("")
                
                push!(history, HistEnt(utf8(""), utf8("")))
                #           println(history)
                current_hist = length(history)
                cursor = 1
            end
        elseif d == BKSPACE || d == SUPPR
            offs = d == BKSPACE ? 1 : 0
            if cursor > offs
                cli = cline()
                idx1 = chr2ind(cli, cursor-offs-1)
                if cursor >= length(cli) + offs
                    cline(cli[1:idx1])
                else
                    idx2 = chr2ind(cli, cursor - offs)
                    cline(cli[1:idx1] * cli[idx2:end])
                end
                cursor -= offs
            end
        elseif d == ((1 << 30) | uint32(0x4f)) # right arrow
            cursor = min(cursor + 1, length(history[current_hist].edit) + 1)
        elseif d == ((1 << 30) | uint32(0x50)) # left arrow
            cursor = max(cursor - 1, 1)
        elseif d == uint32('\033') # esc
            exit()
        elseif d == ((1 << 30) | uint32(0x52)) # up arrow
            current_hist = max(1, current_hist-1)
            history[current_hist].edit = cline()
            cursor = length(cline()) + 1
        elseif d == ((1 << 30) | uint32(0x51)) # down arrow
            current_hist = min(length(history), current_hist+1)
            cursor = length(cline()) + 1
        elseif d == ((1 << 30) | uint32(0x4d)) # end
            cursor = length(cline()) + 1
        elseif d == ((1 << 30) | uint32(0x4a)) # begin (home)
            cursor = 1
        else
            #            println("Unknown char $d")
        end
    elseif ty == :txtappend
        cli = cline()
        if cursor > length(cli) 
            cline(cli * d)
        else
            idx = chr2ind(cli, cursor)
            cline(cli[1:idx-1] * d * cli[idx:end])
        end
        cursor += length(d)
    end
end

function render_console()
    global history, current_hist, cursor#, f
    glDisable(GL_DEPTH_TEST)
    render_lines(clog[current_line:end], 0f0, 0f0, current_line + 1)
    render_lines(clog[1:current_line-1], 0f0, 0f0, 2)
    len = length(history) - current_hist
    prefix = utf8((if len <= 9 string(0, len) else string(9, '+') end)*"> ")
    exact_cline = prefix*cline()
    cursor_line = lpad("_", cursor + length(prefix))
    render_lines([exact_cline], 0f0, 0f0, 1)
    #    if int(f/30) % 2 == 0 # TODO renable blinking cursor properly
    render_lines([cursor_line], 0f0, -2f0, 1)
    #    end
    glEnable(GL_DEPTH_TEST)
end

# TODO not do this by default
import Base.print, Base.TTY
function print(io::TTY, x::ASCIIString)
    print(utf8(x))
end
function print(io::TTY, x::Char)
    print(string(x))
end
function print(io::TTY, x::UTF8String)
    write(io, x)
    flush(io)
#    if io == STDOUT clog_print(x) end
    nothing
end
