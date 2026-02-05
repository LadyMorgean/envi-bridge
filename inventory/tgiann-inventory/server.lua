---@diagnostic disable: duplicate-set-field
module 'shared/debug'
module 'shared/resource'

Version = resource.version(Bridge.InventoryName)
Bridge.Debug('Inventory', Bridge.InventoryName, Version)

local tgiann_inventory = exports[Bridge.InventoryName]
Framework.OnReady(tgiann_inventory, function()
    Framework.Items = {}
    for k, v in pairs(tgiann_inventory:GetItemList()) do
        local item = {}
        if not v.name then v.name = k end
        item.name = v.name
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
    
    -- Temp Fix Until Fixed in Inventory
    if Framework.Items[item].type == "weapon" then
        local serie = (metadata and metadata.serie) or Framework.RandomString(12)
        metadata = table.merge(metadata or {}, { serie = serie, durabilityPercent = 100, ammo = 0, usedTotalAmmo = 0 })
    end 

    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        return tgiann_inventory:AddItemToSecondaryInventory("stash", inventory, item, count, slot, metadata)
    elseif type(inventory) == "number" then
        return tgiann_inventory:AddItem(inventory, item, count, slot, metadata, false)
    end
    return false
end

Framework.RemoveItem = function(inventory, item, count, metadata, slot)
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        return tgiann_inventory:RemoveItemFromSecondaryInventory("stash", inventory, item, count, slot, metadata)
    elseif type(inventory) == "number" then
        if slot then
            if metadata then
                if table.matches(metadata, Framework.GetItemMetadata(inventory, slot)) then
                    return tgiann_inventory:RemoveItem(inventory, item, count, slot)
                end
                return false
            else
                if tgiann_inventory:RemoveItem(inventory, item, count, slot) then
                    return true
                else
                    return false
                end
            end
        else
            local removed = count
            local removedItems = {}
            local items = Framework.GetItem(inventory, item)
            for _, v in pairs(items) do
                if metadata and table.matches(metadata, Framework.GetItemMetadata(inventory, v.slot)) then
                    if removed >= v.count and tgiann_inventory:RemoveItem(inventory, item, v.count, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - v.count
                    elseif tgiann_inventory:RemoveItem(inventory, item, removed, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - removed
                    end
                elseif not metadata then
                    if removed >= v.count and tgiann_inventory:RemoveItem(inventory, item, v.count, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - v.count
                    elseif tgiann_inventory:RemoveItem(inventory, item, removed, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - removed
                    end
                end
                if removed == 0 then
                    break
                end
            end

            if removed == 0 then
                return true
            else
                for _, v in pairs(removedItems) do
                    Framework.AddItem(inventory, item, v.count, v.metadata, v.slot)
                end
                return false
            end
        end
    end
    return false
end

Framework.GetItem = function(inventory, item, metadata, strict)
    local items = {}
    ---@cast items table<number, Item>
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        for k, v in pairs(tgiann_inventory:GetSecondaryInventoryItems("stash", inventory)) do
            if v.name ~= item then goto skipLoop end
            if metadata and (strict and not table.matches(v.info, metadata) or not table.contains(v.info, metadata)) then goto skipLoop end
            items[#items + 1] = {
                name = v.name,
                count = tonumber(v.amount),
                label = v.label,
                description = v.description,
                metadata = v.info,
                stack = v.stack,
                weight = v.weight,
                close = v.close,
                image = v.image,
                type = v.type,
                slot = v.slot,
            }
            ::skipLoop::
        end
    elseif type(inventory) == "number" then
        for k, v in pairs(tgiann_inventory:GetPlayerItems(inventory)) do
            if v.name ~= item then goto skipLoop end
            if metadata and (strict and not table.matches(v.info, metadata) or not table.contains(v.info, metadata)) then goto skipLoop end
            items[#items + 1] = {
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
    end
    return items
end

Framework.GetItemCount = function(inventory, item, metadata, strict)
    local count = 0
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        for k, v in pairs(tgiann_inventory:GetSecondaryInventoryItems("stash", inventory)) do
            if v.name ~= item then goto skipLoop end
            if metadata and (strict and not table.matches(v.info, metadata) or not table.contains(v.info, metadata)) then
                goto skipLoop
            end
            count = count + tonumber(v.amount)
            ::skipLoop::
        end
    elseif type(inventory) == "number" then
        for k, v in pairs(tgiann_inventory:GetPlayerItems(inventory)) do
            if v.name ~= item then goto skipLoop end
            if metadata and (strict and not table.matches(v.info, metadata) or not table.contains(v.info, metadata)) then
                goto skipLoop
            end
            count = count + tonumber(v.amount)
            ::skipLoop::
        end
    end
    return count
end

Framework.HasItem = function(inventory, items, count, metadata, strict)
    if type(items) == "string" then
        local counted = 0
        for _, v in pairs(Framework.GetItem(inventory, items, metadata, strict)) do
            counted += v.count
        end
        return counted >= (count or 1)
    elseif type(items) == "table" then
        if table.type(items) == 'hash' then
            for item, amount in pairs(items) do
                local counted = 0
                for _, v in pairs(Framework.GetItem(inventory, item, metadata, strict)) do
                    counted += v.count
                end
                if counted < amount then return false end
            end
            return true
        elseif table.type(items) == 'array' then
            local counted = 0
            for i = 1, #items do
                local item = items[i]
                for _, v in pairs(Framework.GetItem(inventory, item, metadata, strict)) do
                    counted += v.count
                end
                if counted < (count or 1) then return false end
            end
            return true
        end
    end
end

Framework.GetItemMetadata = function(inventory, slot)
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        for k, item in pairs(tgiann_inventory:GetSecondaryInventoryItems("stash", inventory)) do
            if tonumber(item.slot) == slot then
                return item.info
            end
        end
        return {}
    elseif type(inventory) == "number" then
        return tgiann_inventory:GetItemBySlot(inventory, slot)?.info
    end
    return {}
end

Framework.SetItemMetadata = function(inventory, slot, metadata)
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        for k, item in pairs(tgiann_inventory:GetSecondaryInventoryItems("stash", inventory)) do
            if tonumber(item.slot) == slot then
                tgiann_inventory:UpdateItemMetadata(inventory, item.name, slot, metadata)
                return
            end
        end
    elseif type(inventory) == "number" then
        local item = tgiann_inventory:GetItemBySlot(inventory, slot)
        if item then tgiann_inventory:UpdateItemMetadata(inventory, item.name, slot, metadata) end
    end
end

Framework.GetInventory = function(inventory)
    local items = {}
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        for k, v in pairs(tgiann_inventory:GetSecondaryInventoryItems("stash", inventory)) do
            items[tonumber(k)] = {
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
    elseif type(inventory) == "number" then
        for k, v in pairs(tgiann_inventory:GetPlayerItems(inventory)) do
            items[tonumber(k)] = {
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
    end
    return items
end

Framework.ClearInventory = function(inventory, keep)
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        if keep then
            local keepType = type(keep)
            if keepType == "string" then
                for k, v in pairs(Framework.GetInventory(inventory)) do
                    if v.name ~= keep then
                        tgiann_inventory:RemoveItemFromSecondInventory("stash", inventory, v.name, v.count, v.slot)
                    end
                end
            elseif keepType == "table" and table.type(keep) == "array" then
                for k, v in pairs(Framework.GetInventory(inventory)) do
                    if not table.contains(keep, v.name) then
                        tgiann_inventory:RemoveItemFromSecondInventory("stash",inventory, v.name, v.count, v.slot)
                    end
                end
            end
        else
            for k, v in pairs(Framework.GetInventory(inventory)) do
                tgiann_inventory:RemoveItemFromSecondInventory("stash", inventory, v.name, v.count, v.slot)
            end
        end
    elseif type(inventory) == "number" then
        if keep then
            local keepType = type(keep)
            if keepType == "string" then
                for k, v in pairs(tgiann_inventory:GetPlayerItems(inventory)) do
                    if v.name ~= keep then
                        tgiann_inventory:RemoveItem(inventory, v.name, v.amount, v.slot)
                    end
                end
            elseif keepType == "table" and table.type(keep) == "array" then
                for k, v in pairs(tgiann_inventory:GetPlayerItems(inventory)) do
                    if not table.contains(keep, v.name) then
                        tgiann_inventory:RemoveItem(inventory, v.name, v.amount, v.slot)
                    end
                end
            end
        else
            tgiann_inventory:ClearInventory(inventory)
        end
    end
end

local stashes = {}
Framework.RegisterStash = function(name, slots, weight, owner, groups)
    name = name:gsub("%-", "_")
    if not stashes[name] then
        stashes[name] = { slots = slots, weight = weight, owner = owner, groups = groups }
        tgiann_inventory:RegisterStash(name, name, slots, weight, owner, groups)
    end
end

Framework.CreateCallback(Bridge.Resource .. ':bridge:GetStash', function(source, cb, name)
    cb(stashes[name] and stashes[name] or nil)
end)

local shops = {}
Framework.RegisterShop = function(name, data)
    if shops[name] then return end
    local items = {}
    for i = 1, #data.items do
        items[#items + 1] = {
            name = data.items[i].name,
            amount = data.items[i].count or 1,
            price = data.items[i].price,
            info = data.items[i].metadata or {},
            type = Framework.Items[data.items[i].name].type,
        }
    end
    tgiann_inventory:RegisterShop(name, items)
    shops[name] = data
end

Framework.CreateCallback(Bridge.Resource .. ':bridge:OpenShop', function(source, cb, name)
    if not shops[name] then
        cb({})
        return
    end
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
    local inventory = tgiann_inventory:GetPlayerItems(source)
    Framework.RegisterStash('Confiscated_' .. Player.Identifier, 100, 100000, Player.Identifier)
    tgiann_inventory:DeleteInventory("stash", 'Confiscated_' .. Player.Identifier)
    for _, item in pairs(inventory) do
        tgiann_inventory:AddItemToSecondaryInventory("stash", 'Confiscated_' .. Player.Identifier, item.name, item.amount, item.slot, item.info)
    end
    Framework.ClearInventory(src)
end

Framework.ReturnInventory = function(source)
    local src = source
    local Player = Framework.GetPlayer(src)
    local confiscated = Framework.GetInventory('Confiscated_' .. Player.Identifier)
    for _, item in pairs(confiscated) do
        if item ~= nil then
            Framework.AddItem(src, item.name, item.count, item.metadata, item.slot)
        end
    end
    tgiann_inventory:DeleteInventory("stash", 'Confiscated_' .. Player.Identifier)
end

if Bridge.Framework == 'esx' then
    Framework.CreateUseableItem = function(name, cb)
        ESX.RegisterUsableItem(name, function(source, data)
            cb(source, data.name,
                {
                    weight = Framework.Items[data.name].weight,
                    count = data.amount,
                    slot = data.slot,
                    name = data.name,
                    metadata =
                        data.info or {},
                    label = data.label
                })
        end)
    end
end
