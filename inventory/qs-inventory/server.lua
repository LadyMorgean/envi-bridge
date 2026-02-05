---@diagnostic disable: duplicate-set-field
module 'shared/debug'
module 'shared/resource'
module 'shared/table'

QSInventory = nil

Version = resource.version(Bridge.InventoryName)
Bridge.Debug('Inventory', Bridge.InventoryName, Version)

if not Bridge.InventoryEvent then
    if Bridge.InventoryName == 'ps-inventory' and resource.isMinimalVersion(Bridge.InventoryName, '1.0.5') then
        Bridge.InventoryEvent = 'ps-inventory'
    elseif Bridge.InventoryName == 'qb-inventory' and resource.isMinimalVersion(Bridge.InventoryName, '2.0.0') then
        Bridge.InventoryEvent = 'qb-inventory'
        QBInventory = exports[Bridge.InventoryName]
    elseif Bridge.InventoryName == 'qs-inventory' then
        -- Quasar Advanced Inventory
        Bridge.InventoryEvent = 'inventory'
        QSInventory = exports[Bridge.InventoryName]
    else
        Bridge.InventoryEvent = 'inventory'
    end
end

Framework.OnReady(QBCore, function()
    Framework.Items = {}
    for k, v in pairs(QBCore.Shared.Items) do
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

---Get Stash Items
---@return Item[]
local function GetStashItems(inventory)
    inventory = inventory:gsub("%-", "_")
    local items = {}
    local result = Database.scalar('SELECT items FROM stashitems WHERE stash = ?', { inventory })
    if not result then return items end

    local stashItems = json.decode(result)
    if not stashItems then return items end

    for _, item in pairs(stashItems) do
        local itemInfo = Framework.Items[item.name:lower()]
        if itemInfo then
            items[item.slot] = {
                name = itemInfo.name,
                count = tonumber(item.amount),
                label = itemInfo.label,
                description = itemInfo.description,
                metadata = item.info,
                stack = itemInfo.stack,
                weight = itemInfo.weight,
                close = itemInfo.close,
                image = itemInfo.image,
                type = itemInfo.type,
                slot = item.slot,
            }
        end
    end
    return items
end

---Add Item To Stash
---@param inventory string
---@param item string
---@param count number
---@param metadata? table
---@param slot? number
---@return boolean
local function AddStashItem(inventory, item, count, metadata, slot)
    inventory = inventory:gsub("%-", "_")
    count = tonumber(count) or 1
    local stash = {}
    local result = Database.scalar('SELECT items FROM stashitems WHERE stash = ?', { inventory })
    if result then stash = json.decode(result) end
    local itemInfo = QBCore.Shared.Items[item:lower()]
    metadata = metadata or {}
    metadata.created = metadata.created or os.time()
    metadata.quality = metadata.quality or 100
    if itemInfo['type'] == 'weapon' then
        metadata.serie = metadata.serie or
            tostring(Framework.RandomInteger(2) ..
                Framework.RandomString(3) ..
                Framework.RandomInteger(1) ..
                Framework.RandomString(2) .. Framework.RandomInteger(3) .. Framework.RandomString(4))
    end
    if not itemInfo.unique then
        if type(slot) == "number" and stash[slot] and stash[slot].name == item and table.matches(metadata, stash[slot].info) then
            stash[slot].amount = stash[slot].amount + count
        else
            slot = #stash + 1
            stash[slot] = {
                name = itemInfo["name"],
                amount = count,
                info = metadata or {},
                label = itemInfo["label"],
                description = itemInfo["description"] or "",
                weight = itemInfo["weight"],
                type = itemInfo["type"],
                unique = itemInfo["unique"],
                useable = itemInfo["useable"],
                image = itemInfo["image"],
                slot = slot,
            }
        end
    else
        slot = #stash + 1
        stash[slot] = {
            name = itemInfo["name"],
            amount = count,
            info = metadata or {},
            label = itemInfo["label"],
            description = itemInfo["description"] or "",
            weight = itemInfo["weight"],
            type = itemInfo["type"],
            unique = itemInfo["unique"],
            useable = itemInfo["useable"],
            image = itemInfo["image"],
            slot = slot,
        }
    end
    Database.insert(
        'INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
            ['stash'] = inventory,
            ['items'] = json.encode(stash)
        })
    return true
end

---Remove Item From Stash
---@param inventory string
---@param item string
---@param count number
---@param metadata? table
---@param slot? number
---@return boolean
local function RemoveStashItem(inventory, item, count, metadata, slot)
    inventory = inventory:gsub("%-", "_")
    local stash = {}
    local result = Database.scalar('SELECT items FROM stashitems WHERE stash = ?', { inventory })
    if result then stash = json.decode(result) else return false end
    count = tonumber(count) or 1
    if type(slot) == "number" and stash[slot] and stash[slot].name == item then
        if metadata and not table.matches(metadata, stash[slot].info) then return false end
        if stash[slot].amount > count then
            stash[slot].amount = stash[slot].amount - count
        else
            stash[slot] = nil
        end
        Database.insert(
            'INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
                ['stash'] = inventory,
                ['items'] = json.encode(stash)
            })
        return true
    else
        local removed = count
        local newstash = stash
        for _, v in pairs(stash) do
            if v.name == item then
                if metadata and table.matches(metadata, v.info) then
                    if removed >= v.amount then
                        newstash[v.slot] = nil
                        removed = removed - v.amount
                    else
                        newstash[v.slot].amount = newstash[v.slot].amount - removed
                        removed = removed - removed
                    end
                elseif not metadata then
                    if removed >= v.amount then
                        newstash[v.slot] = nil
                        removed = removed - v.amount
                    else
                        newstash[v.slot].amount = newstash[v.slot].amount - removed
                        removed = 0
                    end
                end
            end

            if removed == 0 then
                break
            end
        end

        if removed == 0 then
            Database.insert(
                'INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
                    ['stash'] = inventory,
                    ['items'] = json.encode(newstash)
                })
            return true
        else
            return false
        end
    end
end

Framework.AddItem = function(inventory, item, count, metadata, slot)
    if type(inventory) == "string" then
        if QBInventory then
            return QBInventory:AddItem(inventory, item, count, slot, metadata)
        else
            if QSInventory then
            if inventory:sub(1,6) ~= 'Stash_' then inventory = 'Stash_' .. inventory end
            return QSInventory:AddItemIntoStash(inventory, item, count, slot, metadata) and true or false
        end
        return AddStashItem(inventory, item, count, metadata, slot)
        end
    elseif type(inventory) == "number" then
        if QSInventory then
            return QSInventory:AddItem(inventory, item, count, slot, metadata) and true or false
        end
        local Player = QBCore.Functions.GetPlayer(inventory)
        if Player.Functions.AddItem(item, count, slot, metadata) then
            TriggerClientEvent(Bridge.InventoryEvent .. ':client:ItemBox', inventory, QBCore.Shared.Items[item], 'add', count)
            return true
        end
        return false
    end
    return false
end

Framework.RemoveItem = function(inventory, item, count, metadata, slot)
    if type(inventory) == "string" then
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            if not inventoryData then return false end
            if slot then
                if metadata then
                    if table.matches(metadata, Framework.GetItemMetadata(inventory, slot)) then
                        return QBInventory:RemoveItem(inventory, item, count, slot)
                    end
                    return false
                else
                    return QBInventory:RemoveItem(inventory, item, count, slot)
                end
            else
                local removed = count
                local removedItems = {}
                for _, v in pairs(inventoryData.items) do
                    if metadata and table.matches(metadata, Framework.GetItemMetadata(inventory, v.slot)) then
                        if removed >= v.amount and QBInventory:RemoveItem(inventory, item, v.amount, v.slot) then
                            removedItems[#removedItems + 1] = v
                            removed = removed - v.amount
                        elseif QBInventory:RemoveItem(inventory, item, removed, v.slot) then
                            removedItems[#removedItems + 1] = v
                            removed = removed - removed
                        end
                    elseif not metadata then
                        if removed >= v.amount and QBInventory:RemoveItem(inventory, item, v.amount, v.slot) then
                            removedItems[#removedItems + 1] = v
                            removed = removed - v.amount
                        elseif QBInventory:RemoveItem(inventory, item, removed, v.slot) then
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
                        Framework.AddItem(inventory, item, v.amount, v.slot, v.info)
                    end
                    return false
                end
            end
        else
            if QSInventory then
            if inventory:sub(1,6) ~= 'Stash_' then inventory = 'Stash_' .. inventory end
            return QSInventory:RemoveItemIntoStash(inventory, item, count, slot, metadata) and true or false
        end
        return RemoveStashItem(inventory, item, count, metadata, slot)
        end
    elseif type(inventory) == "number" then
        if QSInventory then
            return QSInventory:RemoveItem(inventory, item, count, slot, metadata) and true or false
        end
        local Player = QBCore.Functions.GetPlayer(inventory)
        if slot then
            if metadata then
                if table.matches(metadata, Framework.GetItemMetadata(inventory, slot)) then
                    if Player.Functions.RemoveItem(item, count, slot) then
                        TriggerClientEvent(Bridge.InventoryEvent .. ':client:ItemBox', inventory,
                            QBCore.Shared.Items[item], "remove", count)
                        return true
                    else
                        return false
                    end
                end
                return false
            else
                if Player.Functions.GetItemBySlot(slot) and Player.Functions.RemoveItem(item, count, slot) then
                    TriggerClientEvent(Bridge.InventoryEvent .. ':client:ItemBox', inventory, QBCore.Shared.Items[item],
                        "remove", count)
                    return true
                else
                    return false
                end
            end
        else
            local removed = count
            local removedItems = {}
            local items = Player.Functions.GetItemsByName(item)
            for _, v in pairs(items) do
                if metadata and table.matches(metadata, Framework.GetItemMetadata(inventory, v.slot)) then
                    if removed >= v.amount and Player.Functions.RemoveItem(item, v.amount, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - v.amount
                    elseif Player.Functions.RemoveItem(item, removed, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - removed
                    end
                elseif not metadata then
                    if removed >= v.amount and Player.Functions.RemoveItem(item, v.amount, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - v.amount
                    elseif Player.Functions.RemoveItem(item, removed, v.slot) then
                        removedItems[#removedItems + 1] = v
                        removed = removed - removed
                    end
                end
                if removed == 0 then
                    break
                end
            end

            if removed == 0 then
                TriggerClientEvent(Bridge.InventoryEvent .. ':client:ItemBox', inventory, QBCore.Shared.Items[item],
                    "remove", count)
                return true
            else
                for _, v in pairs(removedItems) do
                    Framework.AddItem(inventory, item, v.amount, v.slot, v.info)
                end
                return false
            end
        end
    end
    return false
end

---@diagnostic disable-next-line: duplicate-set-field
Framework.GetItem = function(inventory, item, metadata, strict)
    local items = {}
    ---@cast items table<number, Item>
    if type(inventory) == "string" then
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            if not inventoryData then return items end
            for k, v in pairs(inventoryData.items) do
                if v.name ~= item then goto skipLoop end
                if metadata and (strict and not table.matches(v.info, metadata) or not table.contains(v.info, metadata)) then goto skipLoop end
                items[#items + 1] = v
                ::skipLoop::
            end
        else
            for k, v in pairs(GetStashItems(inventory)) do
                if v.name ~= item then goto skipLoop end
                if metadata and (strict and not table.matches(v.metadata, metadata) or not table.contains(v.metadata, metadata)) then goto skipLoop end
                items[#items + 1] = v
                ::skipLoop::
            end
        end
    elseif type(inventory) == "number" then
        local Player = QBCore.Functions.GetPlayer(inventory)
        for k, v in pairs(Player.PlayerData.items) do
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
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            if not inventoryData then return count end
            for k, v in pairs(inventoryData.items) do
                if v.name ~= item then goto skipLoop end
                if metadata and (strict and not table.matches(v.info, metadata) or not table.contains(v.info, metadata)) then
                    goto skipLoop
                end
                count = count + tonumber(v.amount)
                ::skipLoop::
            end
        else
            for k, v in pairs(GetStashItems(inventory)) do
                if v.name ~= item then goto skipLoop end
                if metadata and (strict and not table.matches(v.metadata, metadata) or not table.contains(v.metadata, metadata)) then
                    goto skipLoop
                end
                count = count + tonumber(v.count)
                ::skipLoop::
            end
        end
    elseif type(inventory) == "number" then
        local Player = QBCore.Functions.GetPlayer(inventory)
        local items = Player.Functions.GetItemsByName(item)
        for k, v in pairs(items) do
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

---@diagnostic disable-next-line: duplicate-set-field
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
    if QSInventory then
        if type(inventory) == "number" then
            local inv = QSInventory:GetInventory(inventory)
            if not inv or not inv[slot] then return {} end
            return inv[slot].info or {}
        elseif type(inventory) == "string" then
            inventory = inventory:gsub("%-", "_")
            if inventory:sub(1,6) ~= 'Stash_' then
                inventory = 'Stash_' .. inventory
            end
            local stashItems = QSInventory:GetStashItems(inventory)
            if not stashItems then return {} end
            for _, v in pairs(stashItems) do
                if v.slot == slot then
                    return v.info or {}
                end
            end
            return {}
        end
    end

    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            if not inventoryData then return {} end
            local item = inventoryData.items[slot]
            return item and item.info or {}
        else
            local stash = GetStash(inventory) or {}
            local item = stash[slot]
            return item and item.info or {}
        end
    elseif type(inventory) == "number" then
        local Player = QBCore.Functions.GetPlayer(inventory)
        if not Player then return {} end
        local item = Player.PlayerData.items and Player.PlayerData.items[slot]
        return item and item.info or {}
    end
    return {}
end

Framework.SetItemMetadata = function(inventory, slot, metadata)
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            for k, v in pairs(inventoryData.items) do
                if v.slot == slot then
                    inventoryData.items[k].info = metadata
                    break
                end
            end
            QBInventory:SetInventory(inventory, inventoryData.items)
        else
            local result = Database.scalar('SELECT items FROM stashitems WHERE stash = ?', { inventory })
            if not result then return end
            local stash = json.decode(result)
            for k, item in pairs(stash) do
                if item.slot == slot then
                    stash[k].info = metadata
                    break
                end
            end
            if not next(stash) then return end
            Database.insert(
                'INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
                    ['stash'] = inventory,
                    ['items'] = json.encode(stash)
                })
        end
    elseif type(inventory) == "number" then
        local Player = QBCore.Functions.GetPlayer(inventory)
        if Player.PlayerData.items[slot] then
            Player.PlayerData.items[slot].info = metadata
            Player.Functions.SetInventory(Player.PlayerData.items)
        end
    end
end

Framework.GetInventory = function(inventory)
    local items = {}

    -- qs-inventory: player inventory + stash inventory via exports
    if QSInventory then
        if type(inventory) == "number" then
            local inv = QSInventory:GetInventory(inventory) -- returns table keyed by slot
            if not inv then return {} end
            for slot, v in pairs(inv) do
                items[#items + 1] = {
                    name = v.name,
                    count = tonumber(v.amount) or 0,
                    label = v.label,
                    description = v.description,
                    metadata = v.info,
                    stack = true,
                    weight = v.weight or 0,
                    close = v.shouldClose == nil and true or v.shouldClose,
                    image = v.image,
                    type = v.type,
                    slot = slot,
                }
            end
            return items
        elseif type(inventory) == "string" then
            inventory = inventory:gsub("%-", "_")
            if inventory:sub(1,6) ~= 'Stash_' then
                inventory = 'Stash_' .. inventory
            end
            local stashItems = QSInventory:GetStashItems(inventory)
            if not stashItems then return {} end
            for _, v in pairs(stashItems) do
                items[#items + 1] = {
                    name = v.name,
                    count = tonumber(v.amount) or 0,
                    label = v.label,
                    description = v.description,
                    metadata = v.info,
                    stack = true,
                    weight = v.weight or 0,
                    close = v.shouldClose == nil and true or v.shouldClose,
                    image = v.image,
                    type = v.type,
                    slot = v.slot,
                }
            end
            return items
        end
    end

    -- default / qb-inventory path (original behavior)
    local items = {}
    if type(inventory) == "string" then
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            for k, v in pairs(inventoryData.items) do
                items[k] = {
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
        else
            local stash = GetStash(inventory) or {}
            for slot, v in pairs(stash) do
                items[slot] = {
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
                    slot = slot,
                }
            end
        end
    elseif type(inventory) == "number" then
        local Player = QBCore.Functions.GetPlayer(inventory)
        if not Player then return {} end
        for slot, v in pairs(Player.PlayerData.items or {}) do
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
                slot = slot,
            }
        end
    end
    return items
end

Framework.ClearInventory = function(inventory, keep)
    if type(inventory) == "string" then
        inventory = inventory:gsub("%-", "_")
        local stash = {}
        
        if QBInventory then
            local inventoryData = QBInventory:GetInventory(inventory)
            if keep then
                local keepType = type(keep)
                if keepType == "string" then
                    for k, v in pairs(inventoryData.items) do
                        if v.name == keep then
                            stash[k] = v
                        end
                    end
                elseif keepType == "table" and table.type(keep) == "array" then
                    for k, v in pairs(inventoryData.items) do
                        for i = 1, #keep do
                            if v.name == keep[i] then
                                stash[k] = v
                            end
                        end
                    end
                end
            end
            QBInventory:SetInventory(inventory, stash)
        else
            local result = Database.scalar('SELECT items FROM stashitems WHERE stash = ?', { inventory })
            if not result then return end
            if keep then
                local stashItems = json.decode(result)
                if not next(stashItems) then return end

                local keepType = type(keep)
                if keepType == "string" then
                    for k, v in pairs(stashItems) do
                        if v.name == keep then
                            stash[k] = v
                        end
                    end
                elseif keepType == "table" and table.type(keep) == "array" then
                    for k, v in pairs(stashItems) do
                        for i = 1, #keep do
                            if v.name == keep[i] then
                                stash[k] = v
                            end
                        end
                    end
                end
            end

            Database.insert(
                'INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
                    ['stash'] = inventory,
                    ['items'] = json.encode(stash)
                })
        end
    elseif type(inventory) == "number" then
        local Player = QBCore.Functions.GetPlayer(inventory)
        Player.Functions.ClearInventory(keep)
    end
end

local stashes = {}
Framework.RegisterStash = function(name, slots, weight, owner, groups)
    name = name:gsub("%-", "_")
    if Bridge.InventoryName == 'qs-inventory' and name:sub(1,6) ~= 'Stash_' then
        name = 'Stash_' .. name
    end
    if not stashes[name] then
        if QSInventory then
            QSInventory:RegisterStash(name, slots, weight)
        elseif QBInventory then
            QBInventory:CreateInventory(name, { maxweight = weight, slots = slots })
        end
        stashes[name] = { slots = slots, weight = weight, owner = owner, groups = groups }
    end
end

RegisterNetEvent(Bridge.Resource .. ':bridge:OpenStash', function(name)
    local src = source
    name = name:gsub("%-", "_")
    local stash = stashes[name]
    if not stash then return end
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    local isAllowed = false
    if stash.groups and Framework.HasJob(stash.groups, Player) then isAllowed = true end
    if stash.groups and Framework.HasGang(stash.groups, Player) then isAllowed = true end
    if stash.groups and not isAllowed then return end
    if stash.owner and type(stash.owner) == 'string' and Player.Identifier ~= stash.owner then return end
    if stash.owner and type(stash.owner) == 'boolean' then name = name .. Player.Identifier end
    QBInventory:OpenInventory(src, name, { maxweight = stash.weight, slots = stash.slots })
end)

Framework.CreateCallback(Bridge.Resource .. ':bridge:GetStash', function(source, cb, name)
    name = name:gsub("%-", "_")
    cb(stashes[name] and stashes[name] or nil)
end)

local shops = {}
Framework.RegisterShop = function(name, data)
    if shops[name] then return end
    if QBInventory then
        local items = {}
        for i = 1, #data.items do
            items[i] = {
                name = data.items[i].name,
                price = data.items[i].price,
                amount = data.items[i].count or 1,
                info = data.items[i].metadata or {},
                slot = i
            }
        end

        QBInventory:CreateShop({
            name = name,
            label = name,
            slots = #items,
            items = items
        })
    end
    shops[name] = data
end

RegisterNetEvent(Bridge.Resource .. ':bridge:OpenShop', function(name)
    local src = source
    if not shops[name] then return end
    local isAllowed = false
    local Player = Framework.GetPlayer(src)
    if not Player then return end
    if shops[name].groups and Framework.HasJob(shops[name].groups, Player) then isAllowed = true end
    if shops[name].groups and Framework.HasGang(shops[name].groups, Player) then isAllowed = true end
    if type(shops[name].groups) == "table" and (shops[name].groups and not isAllowed) then return end
    QBInventory:OpenShop(src, name)
end)

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
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    Player.Functions.SetMetaData("jailitems", Player.PlayerData.items)
    Wait(2000)
    Player.Functions.ClearInventory()
end

Framework.ReturnInventory = function(source)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    for _, item in pairs(Player.PlayerData.metadata['jailitems']) do
        if item ~= nil then
            Player.Functions.AddItem(item.name, item.amount, false, item.info)
            TriggerClientEvent(Bridge.InventoryEvent .. ':client:ItemBox', src, QBCore.Shared.Items[item.name], 'add', item.amount)
        end
    end
    Wait(2000)
    Player.Functions.SetMetaData("jailitems", {})
end
