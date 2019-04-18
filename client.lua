local ENTITY_BITS = 13; // MAX_EDICT_BITS
local NETWORKID_BITS = 12;
local VARAMT_BITS = 7;
local TYPE_BITS = 3;
local NWVarNames = {}
local NWVarsInternal = {
    NWVars = {}
};

function NWVarsInternal.SetNWVar(Entity,NWID,Value)
    local Ent = getmetatable(Entity);
    local NWString = NWVarNames[NWID];
    if(NWString != nil) then
        if(Ent.NWVars == nil) then
            Ent.NWVars = {};
        end
        Ent.NWVars[NWString] = Value;
    end
end

function NWVarsInternal.ReadNumEnts()
    return net.ReadUInt(ENTITY_BITS)
end

function NWVarsInternal.ReadType()
    return net.ReadUInt(TYPE_BITS);
end

function NWVarsInternal.ReadBool()
    return net.ReadUInt(1) == 1;
end

function NWVarsInternal.ReadVector()
    local x = net.ReadFloat();
    local y = net.ReadFloat();
    local z = net.ReadFloat();
    return Vector(x,y,z);
end

function NWVarsInternal.ReadAngle()
    local p = net.ReadFloat();
    local y = net.ReadFloat();
    local r = net.ReadFloat();
    return Angle(p,y,r);
end

function NWVarsInternal.ReadEntity()
    return Entity(net.ReadUInt(ENTITY_BITS));
end

local ReadTable = {}
ReadTable[0] = function() return NWVarsInternal.ReadBool(); end
ReadTable[1] = function() local iBits = net.ReadUInt(5); return net.ReadInt(iBits); end
ReadTable[2] = function() return net.ReadFloat(); end
ReadTable[3] = function() return net.ReadString(); end
ReadTable[4] = function() return NWVarsInternal.ReadEntity(); end
ReadTable[5] = function() return NWVarsInternal.ReadVector(); end
ReadTable[6] = function() return NWVarsInternal.ReadAngle(); end

function NWVarsInternal.GetValue()
    local iType = net.ReadUInt(TYPE_BITS);
    local Value = ReadTable[iType]();
    return Value;
end
function NWVarsInternal.ReadVar(Entity)
    local bRead = true;
    local iNWID = net.ReadUInt(NETWORKID_BITS);
    local Value = NWVarsInternal.GetValue();
    if(NWVarNames[NWID] == nil) then bRead = false; end
    if(bRead)then
        NWVarsInternal.SetNWVar(Entity,iNWID,Value)
    end
end

local cl_interp = GetConVar("cl_interp");
local function TIME2TICKS(time)
    return math.ceil(time/engine.TickInterval());
end
function NWVarsInternal.ProcessInterpolatedMessage()
    local tickcnt = net.ReadUInt(32);
    local iNumEntities = net.ReadUInt(ENTITY_BITS);
    local NWVars_NWVARSIndex = #NWVarsInternal.NWVars + 1;
    NWVarsInternal.NWVars[NWVars_NWVARSIndex] = { UpdateTick = 0, Ents = {} };
    for i = 1, iNumEntities do
        local EntIndex = net.ReadUInt(ENTITY_BITS);
        NWVarsInternal.NWVars[NWVars_NWVARSIndex].Ents[i] = {entindex = EntIndex, Vars = {} };
        local iNumVars = net.ReadUInt(VARAMT_BITS);
        for _i = 1, iNumVars do
            local iNWID = net.ReadUInt(NETWORKID_BITS);
            local Value = NWVarsInternal.GetValue();
            NWVarsInternal.NWVars[NWVars_NWVARSIndex].Ents[i].Vars[_i] = {
                nwid    = iNWID,
                value   = Value,
            };
        end
    end
    NWVarsInternal.NWVars[NWVars_NWVARSIndex].UpdateTick = tickcnt + TIME2TICKS(cl_interp:GetFloat()); // fix lerptime to be accurate dumbass lmfao
end

function NWVarsInternal.ProcessNoInterpMessage()
    local iNumEntities = net.ReadUInt(ENTITY_BITS);
    for i = 1, iNumEntities do
        local EntIndex = net.ReadUInt(ENTITY_BITS);
        local iNumVars = net.ReadUInt(VARAMT_BITS);
        for i = 1, iNumVars do
            local iNWID = net.ReadUInt(NETWORKID_BITS);
            local Value = NWVarsInternal.GetValue();
            NWVarsInternal.SetNWVar(Entity(EntIndex),iNWID,Value);
        end
    end
end

local EntityMeta = FindMetaTable( "Entity" );

function EntityMeta:GetLNWVar(name)
    local Ent = getmetatable(self);
    local out = Ent.NWVars != nil and Ent.NWVars[name] or nil;
    if(out == nil)then
        return 0;
    else
        return out;
    end
end

local function DeleteFirstKeyAndShiftTable()
    local bFirst = false;
    for i = 1, #NWVarsInternal.NWVars do
        if(bFirst == false) then
            NWVarsInternal.NWVars[1] = nil;
            bFirst = true;
        else
            NWVarsInternal.NWVars[i-1] = NWVarsInternal.NWVars[i];
        end
    end
end

hook.Add("PlayerTick", "good enough I guess", function() // the earliest hook I can think of
    if (NWVarsInternal.NWVars[1] != nil && NWVarsInternal.NWVars[1].UpdateTick != nil && NWVarsInternal.NWVars[1].UpdateTick <= engine.TickCount()) then
        for i = 1, #NWVarsInternal.NWVars[1].Ents do
            local Ent = Entity(NWVarsInternal.NWVars[1].Ents[i].entindex);
            for _i = 1, #NWVarsInternal.NWVars[1].Ents[i].Vars do
                NWVarsInternal.SetNWVar(Ent,NWVarsInternal.NWVars[1].Ents[i].Vars[_i].nwid,NWVarsInternal.NWVars[1].Ents[i].Vars[_i].value);
            end
        end
        DeleteFirstKeyAndShiftTable();
    end
end);


function NWVarsInternal.ReadMessage(len)
    local Type = NWVarsInternal.ReadBool();
    if(type == true)then // no interpolation
        NWVarsInternal.ProcessNoInterpMessage();
    else
        NWVarsInternal.ProcessInterpolatedMessage();
    end
end

net.Receive("NetVars", function(len)
    NWVarsInternal.ReadMessage(len);
end);

net.Receive("NetVar Table Update", function(len)
    local Num = net.ReadUInt(NETWORKID_BITS);
    for i = 1, Num do
        local ID = net.ReadUInt(NETWORKID_BITS);
        local Value = net.ReadString();
        NWVarNames[ID] = Value;
    end
end)








/*



net.Start("NetVars",true);
    net.WriteUInt(0, 1); // bUninterpolated.
    net.WriteUInt(engine.TickCount(),32) // Tickcount, only send if bUninterpolated == false
    net.WriteUInt(1, ENTITY_BITS); // num entities
        net.WriteUInt(1, ENTITY_BITS); // ent index
            net.WriteUInt(2, VARAMT_BITS); // num vars for this ent
                net.WriteUInt(1, NETWORKID_BITS)
                net.WriteUInt(5, TYPE_BITS); // type
                WriteVector(Vector(1337.32112,23.213,312.21));

                net.WriteUInt(2, NETWORKID_BITS)
                net.WriteUInt(3, TYPE_BITS); // type
                net.WriteString("Hello xd");
net.Broadcast();



ReadTable[0] = function() return NWVarsInternal.ReadBool(); end
ReadTable[1] = function() return net.ReadFloat(); end
ReadTable[2] = function() return net.ReadFloat(); end
ReadTable[3] = function() return net.ReadString(); end
ReadTable[4] = function() return NWVarsInternal.ReadEntity(); end
ReadTable[5] = function() return NWVarsInternal.ReadVector(); end
ReadTable[6] = function() return NWVarsInternal.ReadAngle(); end


NWvars.NWSendNWVars[#NWvars.NWSendNWVars + 1] = {ent = self, string = str, value = val};

*/

/*
net.Start("NetVar Table Update",true)
    net.WriteUInt(2, NETWORKID_BITS); // number of table updates.
        net.WriteUInt(1, NETWORKID_BITS); // string ID
        net.WriteString("test");

        net.WriteUInt(2, NETWORKID_BITS); // string ID
        net.WriteString("test12");
net.Broadcast()


net.Start("NetVars",true);
    net.WriteUInt(0, 1); // bUninterpolated.
    net.WriteUInt(engine.TickCount(),32) // Tickcount, only send if bUninterpolated == false
    net.WriteUInt(1, ENTITY_BITS); // num entities
        net.WriteUInt(1, ENTITY_BITS); // ent index
            net.WriteUInt(2, VARAMT_BITS); // num vars for this ent
                net.WriteUInt(1, NETWORKID_BITS)
                net.WriteUInt(5, TYPE_BITS); // type
                WriteVector(Vector(1337.32112,23.213,312.21));

                net.WriteUInt(2, NETWORKID_BITS)
                net.WriteUInt(3, TYPE_BITS); // type
                net.WriteString("Hello xd");
net.Broadcast();
*/
