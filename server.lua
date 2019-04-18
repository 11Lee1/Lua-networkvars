util.AddNetworkString("NetVars");
util.AddNetworkString("NetVar Table Update");
local NWVars = { 
    NWStrings = { },        // for players who just connected.
    NWSendStrings = { },    // to update players.
    NWSendNWVars = { },
    NWLogVarEnts = { },     // for players who just connected.
    SendVars = false,
    SendNumEnts = 0;
}

local ENTITY_BITS = 13; // MAX_EDICT_BITS
local NETWORKID_BITS = 12;
local VARAMT_BITS = 7;
local TYPE_BITS = 3;

local function WriteVector(vec)
    net.WriteFloat(vec.x);
    net.WriteFloat(vec.y);
    net.WriteFloat(vec.z);
end

function NWVars.AddNWString(str)
    local strindex = #NWVars.NWStrings + 1;
    NWVars.NWStrings[str] = {index = strindex, string = str};
    NWVars.NWSendStrings[#NWVars.NWSendStrings + 1] = {index = strindex, string = str};
    return strindex;
end

function NWVars.WriteTableUpdate(bWholeTable) // decide where it goes after function call.
    if(bWholeTable)then
        net.Start("NetVar Table Update", false)
        net.WriteUInt(#NWVars.NWStrings, NETWORKID_BITS);
        for k, v in ipairs(NWVars.NWStrings) do
            net.WriteUInt(v.index, NETWORKID_BITS);
            net.WriteString(v.string);
        end
    else
        net.Start("NetVar Table Update", true);
        net.WriteUInt(#NWVars.NWSendStrings, NETWORKID_BITS);
        for i = 1, #NWVars.NWSendStrings do
            net.WriteUInt(NWVars.NWSendStrings[i].index, NETWORKID_BITS);
            net.WriteString(NWVars.NWSendStrings[i].string);
        end
    end
end
function NWVars.GetNWStringIndex(str)
    if(NWVars.NWStrings[str] == nil) then
        return 0;
    else
        return NWVars.NWStrings[str].index;
    end
end


local typeidtoleetype = {} 
typeidtoleetype[TYPE_BOOL] = 0;
typeidtoleetype[TYPE_NUMBER] = 2;
typeidtoleetype[TYPE_STRING] = 3;
typeidtoleetype[TYPE_ENTITY] = 4;
typeidtoleetype[TYPE_VECTOR] = 5;
typeidtoleetype[TYPE_ANGLE] = 6;

local writetype = {}
writetype[0] = function(val) net.WriteUInt(val, 1); end
writetype[1] = function(val) net.WriteFloat(val); end
writetype[2] = function(val) net.WriteFloat(val); end
writetype[3] = function(val) net.WriteString(val); end
writetype[4] = function(ent) net.WriteUInt(ent:EntIndex(), ENTITY_BITS); end
writetype[5] = function(vec) net.WriteFloat(vec.x); net.WriteFloat(vec.y); net.WriteFloat(vec.z); end
writetype[6] = function(ang) net.WriteFloat(ang.x); net.WriteFloat(ang.y); net.WriteFloat(ang.z); end

function NWVars.WriteDataUpdate(bWholeTable,unreliable)
    if(bWholeTable)then
        NWVars.CleanLogTable();
        net.Start("NetVars", unreliable);
        net.WriteUInt(0, 1);                                    // bUninterpolated
        net.WriteUInt(engine.TickCount(),32)                    // Tickcount, only send if bUninterpolated == false
        net.WriteUInt(#NWVars.NWLogVarEnts, ENTITY_BITS);       // num entities
        for k, v in ipairs(#NWVars.NWLogVarEnts) do
            net.WriteUInt(v.ent:EntIndex(), ENTITY_BITS);       // ent index
            net.WriteUInt(#v, VARAMT_BITS);                     // num vars for this ent
            for _k,_v in ipairs(v) do
                net.WriteUInt(NWVars.GetNWStringIndex(_v.string), NETWORKID_BITS);          // NetworkID
                local leetype = typeidtoleetype[TypeID(_v.value)];
                net.WriteUInt(leetype,TYPE_BYTES);              // Type
                writetype[leetype](_v.value);                   // value
            end
        end
    else
        NWVars.CleanSendTable();
        net.Start("NetVars",unreliable);
        net.WriteUInt(0, 1);                                                        // buninterpolated
        net.WriteUInt(engine.TickCount(),32)                                        // Tickcount, only send if bUninterpolated == false
        net.WriteUInt(NWVars.SendNumEnts,ENTITY_BITS)                             // num entities
        for k, v in pairs(NWVars.NWSendNWVars) do
            net.WriteUInt(k:EntIndex(), ENTITY_BITS);                               // ent index
            net.WriteUInt(#v, VARAMT_BITS);                                         // num vars for this ent
            for _k,_v in ipairs(v) do
                net.WriteUInt(NWVars.GetNWStringIndex(_v.string), NETWORKID_BITS);  // NetworkID
                local leetype = typeidtoleetype[TypeID(_v.value)];
                print(leetype);
                net.WriteUInt(leetype,TYPE_BITS);                                   // Type
                writetype[leetype](_v.value);                                       // value
            end
        end
    end
end

function NWVars.CleanLogTable()
    for k, v in pairs(NWVars.NWLogVarEnts) do
        if(!k:IsValid())then
            NWVars.NWLogVarEnts[k] = nil;
        end
    end
end

function NWVars.CleanSendTable()
    for k, v in pairs(NWVars.NWSendNWVars) do
        if(v[1] == nil || v[1].ent:IsValid() == false) then
            NWVars.NWSendNWVars[k] = nil;
            NWVars.SendNumEnts = NWVars.SendNumEnts - 1;
        end
    end
end

hook.Add("Tick", "good enough", function() // whatever the latest hook is before the client gets sent data, this is decent enough for now I guess since I don't want to look harder'
    if(#NWVars.NWSendStrings > 0)then
        NWVars.WriteTableUpdate(false);
        net.Broadcast();
        print("sent string table update");
        PrintTable(NWVars.NWSendStrings);
        NWVars.NWSendStrings = { };
    end
    if(NWVars.SendVars == true)then
        NWVars.WriteDataUpdate(false,true);
        net.Broadcast();
        print("sent nwvar update");
        PrintTable(NWVars.NWSendNWVars);
        NWVars.NWSendNWVars = { };
        NWVars.SendVars = false;
        NWVars.SendNumEnts = 0;
    end
end);

hook.Add("PlayerInitialSpawn","send and update vars", function(pPlayer)
    NWvars.WriteTableUpdate(true);
    net.Send(pPlayer);
    NWvars.WriteDataUpdate(true,false);
    net.Send(pPlayer);
end)


local EntityMetaTbl = FindMetaTable("Entity");

function EntityMetaTbl:SetLNWVar(str,val)
    local StrTblIndex = 0;
    if(NWVars.NWStrings[str] == nil)then
        StrTblIndex = NWVars.AddNWString(str);
    else
        StrTblIndex = NWVars.NWStrings[str].index;
    end
    if(NWVars.NWLogVarEnts[self] == nil) then
        NWVars.NWLogVarEnts[self] = { };
    end
    if(NWVars.NWSendNWVars[self] == nil) then
        NWVars.NWSendNWVars[self] = { };
        NWVars.SendNumEnts = NWVars.SendNumEnts + 1;
    end
    NWVars.NWLogVarEnts[self][str] = {ent = self, string = str, value = val}
    NWVars.NWSendNWVars[self][#NWVars.NWSendNWVars[self] + 1] = {ent = self, string = str, value = val};
    NWVars.SendVars = true;
end
