---@diagnostic disable: duplicate-set-field
module 'shared/debug'
module 'shared/resource'

Version = resource.version(Bridge.InventoryName)
Bridge.Debug('Inventory', Bridge.InventoryName, Version)

local origen_inventory = exports[Bridge.InventoryName]

Framework.OnReady(origen_inventory, function() 
    Framework.Items = {}
    for k, v in pairs(origen_inventory:GetItems()) do
        local item = {}
        item.name = k
        item.label = v.label
        item.description = v.description
        item.stack = not v.unique and true
        item.weight = v.weight or 0
        item.close = v.shouldClose == nil and true or v.shouldClose
        item.type = v.type
        Framework.Items[v.name] = item
    end

    setmetatable(Framework.Items, {
        __index = function(table, key)
            error(('^9Item \'%s\' Does Not Exist.^0'):format(tostring(key)), 0)
        end
    })
end)

Framework.AddItem = function(inventory, item, count, metadata, slot)
    return origen_inventory:addItem(inventory, item, count,metadata, slot)
end

Framework.RemoveItem = function(inventory, item, count, metadata, slot)
    return origen_inventory:removeItem(inventory, item, count, metadata, slot)
end

Framework.GetItem = function(inventory, item, metadata, strict)
    local items = {}
    ---@cast items table<number, Item>
    for k, v in pairs(origen_inventory:getItems(inventory)) do
        if v.name ~= item then goto skipLoop end
        if metadata and (strict and not table.matches(v.metadata, metadata) or not table.contains(v.metadata, metadata)) then goto skipLoop end
        items[#items+1] = {
            name = v.name,
            count = tonumber(v.amount),
            label = v.label,
            description = v.description,
            metadata = v.info,
            stack = not v.unique and true,
            weight = v.weight or 0,
            close = v.shouldClose == nil and true or v.shouldClose,
            image = v.image,
            type = v.type,
            slot = v.slot,
        }
        ::skipLoop::
    end
    return items
end

Framework.GetItemCount = function(inventory, item, metadata, strict)
    return origen_inventory:getItemCount(inventory, item, metadata, strict)
end

Framework.HasItem = function(inventory, items, count, metadata, strict)
    if type(items) == "table" then
        if table.type(items) == 'hash' then
            for item, amount in pairs(items) do
                if origen_inventory:getItemCount(inventory, item, metadata, strict) < amount then
                    return false
                end
            end
            return true
        elseif table.type(items) == 'array' then
            for i = 1, #items do
                local item = items[i]
                if origen_inventory:getItemCount(inventory, item, metadata, strict) < count then
                    return false
                end
            end
            return true
        end
    else
        return origen_inventory:getItemCount(inventory, items, metadata, strict) >= count
    end
end

Framework.GetItemMetadata = function(inventory, slot)
    for k, v in pairs(origen_inventory:getItems(inventory)) do
        if v.slot == slot then
            return v.metadata
        end
    end
    return {}
end

Framework.SetItemMetadata = function(inventory, slot, metadata)
    origen_inventory:setMetadata(inventory, slot, metadata)
end

Framework.GetInventory = function(inventory)
    local items = {}
    ---@cast items table<number, Item>
    for k, v in pairs(origen_inventory:getItems(inventory)) do
        items[#items+1] = {
            name = v.name,
            count = tonumber(v.amount),
            label = v.label,
            description = v.description,
            metadata = v.info,
            stack = not v.unique and true,
            weight = v.weight or 0,
            close = v.shouldClose == nil and true or v.shouldClose,
            image = v.image,
            type = v.type,
            slot = v.slot,
        }
    end
    return items
end

Framework.ClearInventory = function(inventory, keep)
    if keep then
        local keepType = type(keep)
        if keepType == "string" then
            for k, v in pairs(origen_inventory:getItems(inventory)) do
                if v.name ~= keep then
                    origen_inventory:removeItem(inventory, v.name, v.amount, false, v.slot, true)
                end
            end
        elseif keepType == "table" and table.type(keep) == "array" then
            for k, v in pairs(origen_inventory:getItems(inventory)) do
                for i = 1, #keep do
                    if v.name ~= keep[i] then
                        origen_inventory:removeItem(inventory, v.name, v.amount, false, v.slot, true)
                    end
                end
            end
        end
    else
        for k, v in pairs(origen_inventory:getItems(inventory)) do
            origen_inventory:removeItem(inventory, v.name, v.amount, false, v.slot, true)
        end
    end
end

local stashes = {}
Framework.RegisterStash = function(name, slots, weight, owner, groups)
    if not stashes[name] then
        stashes[name] = { slots = slots, weight = weight, owner = owner, groups = groups }
    end
    origen_inventory:registerStash(name, { label = name, slots = slots, weight = weight })
end

Framework.CreateCallback(Bridge.Resource .. ':bridge:GetStash', function(source, cb, name)
    cb(stashes[name] and stashes[name] or nil)
end)

local shops = {}
Framework.RegisterShop = function(name, data)
    if shops[name] then return end
    shops[name] = data
end

Framework.CreateCallback(Bridge.Resource .. ':bridge:OpenShop', function(source, cb, name)
    if not shops[name] then cb({}) end
    local isAllowed = false
    local Player = Framework.GetPlayer(source)
    if shops[name].groups and Framework.HasJob(shops[name].groups, Player) then isAllowed = true end
    if shops[name].groups and Framework.HasGang(shops[name].groups, Player) then isAllowed = true end
    if type(shops[name].groups) == "table" and (shops[name].groups and not isAllowed) then cb({}) end
    cb(shops[name])
end)

Framework.ConfiscateInventory = function(source)
    local src = source
    local Player = Framework.GetPlayer(src)
    local inventory = origen_inventory:getItems(src)
    Framework.RegisterStash('Confiscated_' .. Player.Identifier, 41, 120000, true)
    Framework.ClearInventory('Confiscated_' .. Player.Identifier)
    origen_inventory:addItems('Confiscated_' .. Player.Identifier, inventory)
    Framework.ClearInventory(src)
end

Framework.ReturnInventory = function(source)
    local src = source
    local Player = Framework.GetPlayer(src)
    local confiscated = origen_inventory:getItems('Confiscated_' .. Player.Identifier)
    origen_inventory:addItems(src, confiscated)
    Framework.ClearInventory('Confiscated_' .. Player.Identifier)
end