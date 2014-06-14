const map_id = 1 # SR: 1, oldTT: 4, D: 8, TT: 10, HA: 12
assert(contains([1,4,8,10,12],map_id), "Not a valid map id: $map_id")

//const raf_path = "/home/carnaval/dargonmods/output/"
const raf_path = "/mnt/data/riotdata"

const level_path = lowercase(raf_path * "LEVELS/Map" * string(map_id) * "/")
const scene_path = lowercase(level_path * "Scene/")
const cfg_file = lowercase(scene_path * "CFG/ObjectCFG.cfg")
const tex_path = lowercase(scene_path * "Textures/")
const nvr_file = lowercase(scene_path * "room.nvr")
const mat_file = lowercase(scene_path * "room.mat")

const char_path = raf_path * "DATA/Characters/"


function get_central_point(io::IO)
	while !eof(io)
		line = split(readline(io),"=")
		if length(line) > 1 && line[1] == "CentralPoint"
			return float32(split(strip(line[2])," "))
		end
	end
    return Float32[0,0,0]
	error("plop729")
end

include("ini.jl")
include("inibin.jl")

function read_riot_char2(s :: Symbol)
    if isdir(stat(lowercase(char_path * string(s) * "/Skins/")))
		ss = char_path * string(s) * "/Skins/Base/"
		inibin_ = "Base.inibin"
	else
		ss = char_path * string(s) * "/"
		inibin_ = string(s) * ".inibin"
	end
	
	cd(lowercase(ss)) do
            println("Into : $ss")
	    anms = [ (symbol(split(n, ".")[1]), open("animations/"*lowercase(n))) for n in readdir("animations") ]
		
		inibin = parse_inibin(open(lowercase(inibin_)))
		skn_file = lowercase(get(inibin, 0x2ddb452f, :nope))
		skl_file = lowercase(get(inibin, 0x70f8094d, :nope))
		dds_file = lowercase(get(inibin, 0x9d5e00fb, :nope))
		scaling = float32(get(inibin, 0xf46e42ad, 1.0f))
		
		if skn_file != :nope && skl_file != :nope && dds_file != :nope
			(read_riot_char(open(skn_file), open(skl_file), open(dds_file), anms), scaling)
		else
			:nope
		end
	end
end

function load_thing(char_to_load_name :: String, char_name = (), anim = 1)
	sco_name = 	if char_name == () 	"LevelProp_" * char_to_load_name
				else 				char_to_load_name
				end
	tbitch = Vec4(get_central_point(open(scene_path * sco_name * ".sco")))
	cfg_file_ = read(IniFile(), cfg_file)
	tbitch += Vec4(float32(split(strip(get(cfg_file_, sco_name, "Move", "0 0 0"))," ")))
	roty = 2*pi*float32(split(strip(get(cfg_file_, sco_name, "Rot", "0 0 0"))," ")[1])/360
	rotbitch = rotation_y(float32(roty))
	if char_name == () char_name = char_to_load_name end
	
	rrc = :nope#read_riot_char2(symbol(char_name))
	println( "$char_to_load_name: $(roty)")
	if rrc != :nope
		(rrc[1], translation(tbitch)*rotbitch*scale(rrc[2]), anim)
	else
		:nope
	end
end



if map_id == 12
	pseudo_things = ["HA_AP_Viking", "HA_AP_ShpSouth", "HA_AP_Hermit", "HA_AP_ShpNorth"]
	superthings = [
		("Turret_T1_C_08", "HA_AP_OrderTurret", 2),
		("Turret_T1_C_07", "HA_AP_OrderTurret", 2),
		("Turret_T1_C_09", "HA_AP_OrderTurret", 2),
		("Turret_T1_C_010", "HA_AP_OrderTurret", 2),
		("Turret_T2_L_01", "HA_AP_ChaosTurret", 1),
		("Turret_T2_L_02", "HA_AP_ChaosTurret", 1),
		("Turret_T2_L_03", "HA_AP_ChaosTurret", 1),
		("Turret_T2_L_04", "HA_AP_ChaosTurret", 1),
		("HQ_T1", "OrderNexus", 1),
		("HQ_T2", "ChaosNexus", 1),
		("Barracks_T2_C1", "ChaosInhibitor", 1),
		("Barracks_T1_C1", "OrderInhibitor", 1)
	]

elseif map_id == 1
	pseudo_things = []
	superthings = [
		("Turret_T1_R_03", "OrderTurretNormal", 2),
		("Turret_T1_R_02", "OrderTurretNormal2", 2),
		("Turret_T1_C_07", "OrderTurretDragon", 2),
		("Turret_T2_R_03", "ChaosTurretWorm", 2),
		("Turret_T2_R_02", "ChaosTurretWorm2", 2),
		("Turret_T2_R_01", "ChaosTurretGiant", 2), 
		("Turret_T1_C_05", "OrderTurretNormal", 2),
		("Turret_T1_C_04", "OrderTurretNormal2", 2),
		("Turret_T1_C_03", "OrderTurretDragon", 2),
		("Turret_T1_C_01", "OrderTurretAngel", 2),
		("Turret_T1_C_02", "OrderTurretAngel", 2),
		("Turret_T2_C_05", "ChaosTurretWorm", 2),
		("Turret_T2_C_04", "ChaosTurretWorm2", 2),
		("Turret_T2_C_03", "ChaosTurretGiant", 2), 
		("Turret_T2_C_01", "ChaosTurretNormal", 2),
		("Turret_T2_C_02", "ChaosTurretNormal", 2),
		("Turret_T1_L_03", "OrderTurretNormal", 2),
		("Turret_T1_L_02", "OrderTurretNormal2", 2),
		("Turret_T1_C_06", "OrderTurretDragon", 2),
		("Turret_T2_L_03", "ChaosTurretWorm", 2),
		("Turret_T2_L_02", "ChaosTurretWorm2", 2),
		("Turret_T2_L_01", "ChaosTurretGiant", 2),
		("HQ_T1", "OrderNexus", 1),
		("HQ_T2", "ChaosNexus", 1),
		("Barracks_T2_C1", "ChaosInhibitor", 1),
		("Barracks_T2_R1", "ChaosInhibitor", 1),
		("Barracks_T2_L1", "ChaosInhibitor", 1),
		("Barracks_T1_R1", "OrderInhibitor", 1),
		("Barracks_T1_L1", "OrderInhibitor", 1),
		("Barracks_T1_C1", "OrderInhibitor", 1)
	]
end
	
things = [ load_thing(lowercase(x)) for x in pseudo_things ]
for superthing in superthings 
	push!(things, load_thing(lowercase(superthing[1]), lowercase(superthing[2]), superthing[3]))
end

anim = 1

function render_map(mat)
	render_nvr(mat)
	for thing in things
		if thing != :nope
			render(thing[1], mat*thing[2], f, collect(keys(thing[1].skel.animations))[thing[3]])
		end
	end
end