local Players = game:GetService('Players')

local Network = require(script.Parent.Parent.Internal.Network)
local Signal = require(script.Parent.Parent.Parent.Signal)

local Utils = require(script.Parent.Parent.Internal.Utils)
local Graph = require(script.Parent.Parent.Internal.Graph)

local _T = require(script.Parent.Parent.Internal.Types)

local Freeze = require(script.Parent.Parent.Parent.Freeze)

type UpdateCallback<V> = (currentValue: V) -> V

export type ServerReplionData<D = any> = {
	Channel: string,
	Data: D,
	Destroyed: boolean?,
	Tags: { string },
	ReplicateTo: _T.ReplicateTo,

	_beforeDestroy: Signal.Signal<nil>,
	_afterDestroy: Signal.Signal<nil>,
	_rootNode: Graph.Node?,
	_replicateToChanged: Signal.Signal<_T.ReplicateTo, _T.ReplicateTo>,
	_playerSubscribed: Signal.Signal<Player>,
	_playerUnsubscribed: Signal.Signal<Player>,

	_id: number,
	_packedId: string,

	new: <T>(config: ReplionConfig<T>) -> ServerReplion<D>,
	BeforeDestroy: (self: ServerReplion<D>, callback: () -> ()) -> Signal.Connection,
	AfterDestroy: (self: ServerReplion<D>, callback: () -> ()) -> Signal.Connection,

	DataChanged: (self: ServerReplion<D>, callback: (newData: D, path: _T.Path) -> ()) -> Signal.Connection,
	Changed: <T>(
		self: ServerReplion<D>,
		path: _T.Path,
		callback: (newValue: T, oldValue: T?) -> ()
	) -> Signal.Connection,

	Observe: <T>(
		self: ServerReplion<D>,
		path: _T.Path,
		callback: (newValue: T, oldValue: T?) -> ()
	) -> Signal.Connection,

	Inserted: (self: ServerReplion<D>, path: _T.Path, callback: _T.ArrayCallback) -> Signal.Connection,
	Removed: (self: ServerReplion<D>, path: _T.Path, callback: _T.ArrayCallback) -> Signal.Connection,

	KeyAdded: (self: ServerReplion<D>, path: _T.Path, callback: _T.DictCallback) -> Signal.Connection,
	KeyRemoved: (self: ServerReplion<D>, path: _T.Path, callback: _T.DictCallback) -> Signal.Connection,

	Subscribe: (self: ServerReplion<D>, player: Player) -> (),
	SubscribeAll: (self: ServerReplion<D>) -> (),
	Unsubscribe: (self: ServerReplion<D>, player: Player) -> (),
	UnsubscribeAll: (self: ServerReplion<D>) -> (),
	Replicate: (self: ServerReplion<D>) -> (),
	GetSubscribers: (self: ServerReplion<D>) -> { Player },
	IsSubscribed: (self: ServerReplion<D>, player: Player) -> boolean,

	PlayerSubscribed: (self: ServerReplion<D>, callback: (player: Player) -> ()) -> Signal.Connection,
	PlayerUnsubscribed: (self: ServerReplion<D>, callback: (player: Player) -> ()) -> Signal.Connection,
	ObserveSubscribers: (self: ServerReplion<D>, callback: (player: Player) -> ()) -> Signal.Connection,

	Set: <T>(self: ServerReplion<D>, path: _T.Path, newValue: T) -> T,
	Update: <V>(self: ServerReplion<D>, path: _T.Path, callback: UpdateCallback<V>) -> (),

	Increase: (self: ServerReplion<D>, path: _T.Path, amount: number) -> number,
	Decrease: (self: ServerReplion<D>, path: _T.Path, amount: number) -> number,

	Insert: <T>(self: ServerReplion<D>, path: _T.Path, value: T, index: number?) -> (),
	Remove: <T>(self: ServerReplion<D>, path: _T.Path, index: number?) -> T,
	Clear: (self: ServerReplion<D>, path: _T.Path) -> (),
	Find: <T>(self: ServerReplion<D>, path: _T.Path, value: T) -> (number?, T?),

	GetKeys: <K>(self: ServerReplion<D>, path: _T.Path) -> { K },
	GetValues: <V>(self: ServerReplion<D>, path: _T.Path) -> { V },

	Get: <T>(self: ServerReplion<D>, path: _T.Path) -> T?,
	GetExpect: <T>(self: ServerReplion<D>, path: _T.Path, message: string?) -> T,

	Destroy: (self: ServerReplion<D>) -> (),

	SetReplicateTo: (self: ServerReplion<D>, replicateTo: _T.ReplicateTo) -> (),
	_serialize: (self: ServerReplion<D>) -> _T.SerializedReplion,
	__tostring: (self: ServerReplion<D>) -> string,
}

export type ReplionConfig<D = any> = {
	Channel: string,

	Data: D,
	ReplicateTo: _T.ReplicateTo,

	DisableAutoDestroy: boolean?,

	Tags: { string }?,
}

-- Used by Set: walks each segment of pathTable and fires Added/Removed when a
-- key appears or disappears at that level (covers intermediate table creation).
local function fireDictKeyEvents(rootNode: Graph.Node, pathTable: { any }, oldData: any, newData: any)
	local oldCursor = oldData
	local newCursor = newData

	for i = 1, #pathTable do
		local key = pathTable[i]

		local parentPath: any = if i == 1 then '__root' else table.move(pathTable, 1, i - 1, 1, table.create(i - 1))

		local oldIsTable = type(oldCursor) == 'table'
		local newIsTable = type(newCursor) == 'table'

		if oldIsTable or newIsTable then
			local hadKey = oldIsTable and (oldCursor :: any)[key] ~= nil
			local hasKey = newIsTable and (newCursor :: any)[key] ~= nil

			if not hadKey and hasKey then
				Graph.fireEvent(rootNode, 'onDictKeyAdded', parentPath, key, (newCursor :: any)[key])
			elseif hadKey and not hasKey then
				Graph.fireEvent(rootNode, 'onDictKeyRemoved', parentPath, key, (oldCursor :: any)[key])
			end
		end

		oldCursor = if oldIsTable then (oldCursor :: any)[key] else nil
		newCursor = if newIsTable then (newCursor :: any)[key] else nil
	end
end

-- Used by Update: fires Added/Removed for keys that appeared or disappeared
-- inside the dict located at pathTable (the merge target).
local function fireDictChildKeyEvents(rootNode: Graph.Node, pathTable: { any }, oldData: any, newData: any)
	local eventPath: any = if #pathTable == 0 then '__root' else pathTable

	local oldDict = if #pathTable == 0 then oldData else Freeze.Dictionary.getIn(oldData, pathTable)
	local newDict = if #pathTable == 0 then newData else Freeze.Dictionary.getIn(newData, pathTable)

	local oldIsTable = type(oldDict) == 'table'
	local newIsTable = type(newDict) == 'table'

	if not oldIsTable and not newIsTable then
		return
	end

	-- Check for added keys (present in new, absent in old)
	if newIsTable then
		for key, value in newDict :: any do
			if not oldIsTable or (oldDict :: any)[key] == nil then
				Graph.fireEvent(rootNode, 'onDictKeyAdded', eventPath, key, value)
			end
		end
	end

	-- Check for removed keys (present in old, absent in new)
	if oldIsTable then
		for key, value in oldDict :: any do
			if not newIsTable or (newDict :: any)[key] == nil then
				Graph.fireEvent(rootNode, 'onDictKeyRemoved', eventPath, key, value)
			end
		end
	end
end

local ID_LIMIT = 65535
local MIN_IDS_TO_RECYCLE = 16

local currentId = 0
local availableIds: { number } = {}
local warnsSent = {}

--[=[
	@type Path string | { any }

	@within ServerReplion
]=]

--[=[
	@type ReplicateTo Player | { Player } | 'All'

	@within ServerReplion
]=]

--[=[
	@type SerializedReplion { any }

	@within ServerReplion
]=]

--[=[
	@prop Channel string
	@readonly

	@within ServerReplion
]=]

--[=[
	@prop Data { [any]: any }
	@within ServerReplion
]=]

--[=[
	@prop Destroyed boolean?
	@readonly

	@within ServerReplion
]=]

--[=[
	@prop Tags { string }
	@readonly

	@within ServerReplion
]=]

--[=[
	@prop ReplicateTo ReplicateTo
	@readonly

	@within ServerReplion
]=]

--[=[
	@prop DisableAutoDestroy boolean?
	@readonly

	@within ServerReplion
]=]

--[=[
	@class ServerReplion
	@server

	Holds state for a single channel and handles replication to clients.
	Created via `Replion.Server.new(config)`.

	```lua
	local replion = Replion.Server.new({
		Channel    = 'PlayerData',
		ReplicateTo = player,
		Data       = { Coins = 0, Inventory = {} },
	})

	replion:Set('Coins', 100)
	replion:Update('Inventory', function(inv)
		return Freeze.Dictionary.merge(inv, { Sword = true })
	end)
	```
]=]
local ServerReplion = {}
ServerReplion.__index = ServerReplion

export type ServerReplion<D = any> = typeof(setmetatable({} :: ServerReplionData<D>, ServerReplion))

function ServerReplion.new<D>(config: ReplionConfig<D>): ServerReplion<D>
	assert(type(config.Channel) == 'string', `"Channel" expected string, got {type(config.Channel)}`)
	assert(config.ReplicateTo, 'ReplicateTo is required!')

	local replicateTo = config.ReplicateTo
	local selectedId

	if currentId + 1 > ID_LIMIT or #availableIds >= MIN_IDS_TO_RECYCLE then
		selectedId = table.remove(availableIds, 1)
	else
		currentId += 1

		selectedId = currentId
	end

	assert(selectedId, 'No available ID!')
	assert(selectedId <= ID_LIMIT, `ID limit reached! You already have {ID_LIMIT} ServerReplions!`)

	local self: ServerReplion<D> = setmetatable({
		Data = config.Data,
		Channel = config.Channel,
		Tags = if config.Tags then config.Tags else {},
		ReplicateTo = replicateTo,

		DisableAutoDestroy = config.DisableAutoDestroy,

		_id = selectedId,
		_packedId = utf8.char(selectedId),
		_beforeDestroy = Signal.new(),
		_afterDestroy = Signal.new(),
		_rootNode = Graph.createRootNode(),
		_replicateToChanged = Signal.new(),
		_playerSubscribed = Signal.new(),
		_playerUnsubscribed = Signal.new(),
	}, ServerReplion) :: any

	Network.sendTo(replicateTo, 'Added', self:_serialize())

	return self
end

function ServerReplion:__tostring()
	local channel = self.Channel
	local replicateTo = self.ReplicateTo

	local replicatingTo
	if type(replicateTo) == 'table' then
		local names = {}

		for i, player in replicateTo do
			names[i] = player.Name
		end

		replicatingTo = table.concat(names, ', ')
	elseif typeof(replicateTo) == 'Instance' then
		replicatingTo = replicateTo.Name
	else
		replicatingTo = replicateTo
	end

	return `Replion<{channel}:{replicatingTo}>`
end

--[=[
	@return SerializedReplion
	@private

	Serializes the data to be sent to the client.
]=]
function ServerReplion:_serialize(): _T.SerializedReplion
	-- The initial data that is sent to the client, probably will be the most expensive part of the replication.
	-- But it's only done once, so it's not that bad. We can optimize this later if needed, but for now it's fine.

	return { self._packedId, self.Channel, self.Data, self.ReplicateTo, self.Tags }
end

--[=[
	Fires synchronously just before the Replion is destroyed — useful for cleanup that
	still needs access to `self.Data` or subscriptions.

	@param callback () -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:BeforeDestroy(callback)
	return self._beforeDestroy:Connect(callback)
end

--[=[
	Fires after the Replion has been fully destroyed and all connections cleaned up.

	@param callback () -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:AfterDestroy(callback)
	return self._afterDestroy:Connect(callback)
end

--[=[
	Fires whenever any part of the Replion's data changes.
	The callback receives the entire new data table and the path that was changed.

	```lua
	replion:DataChanged(function(newData, path)
		print('Data changed at', table.concat(path, '.'))
	end)
	```

	@param callback (newData: any, path: { string }) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:DataChanged(callback)
	return Graph.connect(self._rootNode, 'onDataChange', { '__root' }, callback)
end

--[=[
	Fires whenever the value at `path` changes.

	```lua
	replion:Changed('Coins', function(newCoins: number, oldCoins: number)
		print('Coins changed from', oldCoins, 'to', newCoins)
	end)
	```

	@param path Path
	@param callback (newValue: T, oldValue: T) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:Changed<V>(path, callback)
	return Graph.connect(self._rootNode, 'onChange', path, callback)
end

--[=[
	Fires immediately with the current value at `path`, then fires on every subsequent change.
	Useful for initializing UI or state that must always reflect the current value.

	```lua
	replion:Observe('Coins', function(coins: number, oldCoins: number?)
		-- oldCoins is nil on the first call
		print('Coins:', coins)
	end)
	```

	@param path Path
	@param callback (newValue: T, oldValue: T?) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:Observe<V>(path, callback)
	task.spawn(function()
		callback(self:Get(path), nil)
	end)

	return Graph.connect(self._rootNode, 'onChange', path, callback)
end

--[=[
	Fires when a value is inserted into the array at `path` via `:Insert`.

	```lua
	replion:Inserted('Queue', function(index: number, value: any)
		print('Inserted', value, 'at index', index)
	end)
	```

	@param path Path
	@param callback (index: number, value: T) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:Inserted(path, callback)
	return Graph.connect(self._rootNode, 'onArrayInsert', path, callback)
end

--[=[
	Fires when a value is removed from the array at `path` via `:Remove`.

	```lua
	replion:Removed('Queue', function(index: number, value: any)
		print('Removed', value, 'at index', index)
	end)
	```

	@param path Path
	@param callback (index: number, value: T) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:Removed(path, callback)
	return Graph.connect(self._rootNode, 'onArrayRemove', path, callback)
end

--[=[
	Fires when a new key is introduced to the dictionary at `path`.
	This fires for keys added via `:Update` **and** for intermediate tables created by `:Set` on a deep path.

	```lua
	replion:KeyAdded('Inventory', function(key: string, value: any)
		print('New item:', key, value)
	end)
	```

	@param path Path
	@param callback (key: any, value: T) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:KeyAdded(path, callback)
	return Graph.connect(self._rootNode, 'onDictKeyAdded', path, callback)
end

--[=[
	Fires when a key is removed from the dictionary at `path`.
	This fires for keys removed via `:Update` (set to `Replion.None`) **and**
	for tables deleted by `:Set` on a deep path.

	```lua
	replion:KeyRemoved('Inventory', function(key: string, value: any)
		print('Removed item:', key, 'was', value)
	end)
	```

	@param path Path
	@param callback (key: any, value: T) -> ()
	@return RBXScriptConnection
]=]
function ServerReplion:KeyRemoved(path, callback)
	return Graph.connect(self._rootNode, 'onDictKeyRemoved', path, callback)
end

--[=[
	Returns all keys of the dictionary at `path`. Returns an empty table if the value is not a table.

	```lua
	local keys = replion:GetKeys('Inventory') -- { 'Sword', 'Bow' }
	```

	@param path Path
	@return { K }
]=]
function ServerReplion:GetKeys<K>(path): { K }
	local dict = self:Get(path)
	if type(dict) ~= 'table' then
		return {}
	end
	return table.clone(Freeze.Dictionary.keys(dict)) :: any
end

--[=[
	Returns all values of the dictionary at `path`. Returns an empty table if the value is not a table.

	```lua
	local values = replion:GetValues('Inventory') -- { true, true }
	```

	@param path Path
	@return { V }
]=]
function ServerReplion:GetValues<V>(path): { V }
	local dict = self:Get(path)
	if type(dict) ~= 'table' then
		return {}
	end
	return table.clone(Freeze.Dictionary.values(dict)) :: any
end

--[=[
	@param player Player

	Subscribes a single player to this Replion. The player will receive the current data
	and all future updates until unsubscribed or the Replion is destroyed.
]=]
function ServerReplion:Subscribe(player: Player)
	assert(typeof(player) == 'Instance' and player:IsA('Player'), '"player" must be a Player')

	local replicateTo = self.ReplicateTo

	if replicateTo == 'All' then
		return
	end

	if typeof(replicateTo) == 'Instance' then
		-- already a single player
		if replicateTo == player then
			return
		end
		self:SetReplicateTo({ replicateTo, player })
	elseif type(replicateTo) == 'table' then
		if table.find(replicateTo, player) then
			return
		end
		local newList = table.clone(replicateTo)
		table.insert(newList, player)
		self:SetReplicateTo(newList)
	end
end

--[=[
	Subscribes all currently connected players to this Replion.
	Players who join after this call are NOT automatically added.
	Use :Replicate() if you want to include future players as well.
]=]
function ServerReplion:SubscribeAll()
	self:SetReplicateTo(Players:GetPlayers())
end

--[=[
	@param player Player

	Unsubscribes a single player from this Replion.
]=]
function ServerReplion:Unsubscribe(player: Player)
	assert(typeof(player) == 'Instance' and player:IsA('Player'), '"player" must be a Player')

	local replicateTo = self.ReplicateTo

	if replicateTo == 'All' then
		local players = Players:GetPlayers()
		local newList = {}
		for _, p in players do
			if p ~= player then
				table.insert(newList, p)
			end
		end
		self:SetReplicateTo(newList)
	elseif typeof(replicateTo) == 'Instance' then
		if replicateTo == player then
			self:SetReplicateTo({})
		end
	elseif type(replicateTo) == 'table' then
		local index = table.find(replicateTo, player)
		if not index then
			return
		end
		local newList = table.clone(replicateTo)
		table.remove(newList, index)
		self:SetReplicateTo(newList)
	end
end

--[=[
	Unsubscribes all players from this Replion.
]=]
function ServerReplion:UnsubscribeAll()
	self:SetReplicateTo({})
end

--[=[
	Replicates this Replion to all current and future players by setting ReplicateTo to `'All'`.
	Unlike :SubscribeAll(), players who join after this call will also receive the data automatically.
]=]
function ServerReplion:Replicate()
	self:SetReplicateTo('All')
end

--[=[
	Returns all players currently subscribed to this Replion as a table.
	If ReplicateTo is `'All'`, returns all currently connected players.
]=]
function ServerReplion:GetSubscribers(): { Player }
	local replicateTo = self.ReplicateTo

	if replicateTo == 'All' then
		return Players:GetPlayers()
	elseif type(replicateTo) == 'table' then
		return table.clone(replicateTo)
	elseif typeof(replicateTo) == 'Instance' and replicateTo:IsA('Player') then
		return { replicateTo }
	end

	return {}
end

--[=[
	@param player Player

	Returns whether the given player is currently subscribed to this Replion.
]=]
function ServerReplion:IsSubscribed(player: Player): boolean
	assert(typeof(player) == 'Instance' and player:IsA('Player'), '"player" must be a Player')

	local replicateTo = self.ReplicateTo

	if replicateTo == 'All' then
		return player:IsDescendantOf(Players)
	elseif typeof(replicateTo) == 'Instance' then
		return replicateTo == player
	elseif type(replicateTo) == 'table' then
		return table.find(replicateTo, player) ~= nil
	end

	return false
end

--[=[
	@param callback (player: Player) -> ()

	@return RBXScriptConnection

	Calls the callback when a player subscribes to this Replion.
]=]
function ServerReplion:PlayerSubscribed(callback)
	return self._playerSubscribed:Connect(callback)
end

--[=[
	@param callback (player: Player) -> ()

	@return RBXScriptConnection

	Calls the callback when a player unsubscribes from this Replion.
]=]
function ServerReplion:PlayerUnsubscribed(callback)
	return self._playerUnsubscribed:Connect(callback)
end

--[=[
	@param callback (player: Player) -> ()

	@return RBXScriptConnection

	Calls the callback immediately for each currently subscribed player,
	then connects to future subscriptions.
]=]
function ServerReplion:ObserveSubscribers(callback)
	task.defer(function()
		for _, player in self:GetSubscribers() do
			callback(player)
		end
	end)
	return self._playerSubscribed:Connect(callback)
end

--[=[
	@param replicateTo ReplicateTo

	Sets the players to which the data should be replicated.
	@private
]=]
function ServerReplion:SetReplicateTo(replicateTo)
	assert(
		replicateTo == 'All'
			or type(replicateTo) == 'table'
			or typeof(replicateTo) == 'Instance' and replicateTo:IsA('Player'),
		'ReplicateTo must be a Player, a table of Players or "All"'
	)

	local oldReplicateTo = self.ReplicateTo
	if oldReplicateTo == replicateTo then
		return
	end

	local oldReplicateToPlayers = if oldReplicateTo == 'All'
		then Players:GetPlayers()
		elseif type(oldReplicateTo) == 'table' then oldReplicateTo
		else { oldReplicateTo }

	local newReplicateToPlayers = if replicateTo == 'All'
		then Players:GetPlayers()
		elseif type(replicateTo) == 'table' then replicateTo
		else { replicateTo }

	-- Send Removed event for old players that are not in the new list
	for _, player in oldReplicateToPlayers do
		if table.find(newReplicateToPlayers, player) then
			continue
		end

		Network.sendTo(player, 'Removed', self._packedId)
		self._playerUnsubscribed:Fire(player)
	end

	-- Send Added event for new players that are not in the old list
	for _, player in newReplicateToPlayers do
		if table.find(oldReplicateToPlayers, player) then
			continue
		end

		Network.sendTo(player, 'Added', self:_serialize())
		self._playerSubscribed:Fire(player)
	end

	self.ReplicateTo = replicateTo
	self._replicateToChanged:Fire(replicateTo, oldReplicateTo)

	Network.sendTo(replicateTo, 'UpdateReplicateTo', self._packedId, replicateTo)
end

--[=[
	Sets the value at `path` and replicates the change to all subscribed clients.
	Returns the new value.

	Use `Replion.None` as the value to remove a key from its parent dictionary.
	When setting a deep path (e.g. `'Inventory.Swords.Current'`), any intermediate
	tables that are created or destroyed will fire `KeyAdded`/`KeyRemoved` events accordingly.

	:::tip
	When only some keys inside a table change, prefer `:Update` — it sends only the diff,
	reducing bandwidth.
	:::

	```lua
	replion:Set('Coins', 100)
	replion:Set('Inventory.Sword', true)

	-- Remove a key
	replion:Set('Inventory.OldItem', Replion.None)
	```

	@param path Path
	@param newValue T
	@return T
]=]
function ServerReplion:Set<T>(path, newValue: T): T
	local pathTable = Utils.getPathTable(path)

	local currentValue: T? = Freeze.Dictionary.getIn(self.Data, pathTable)
	if Freeze.Dictionary.equals(currentValue :: any, newValue) then
		if _G.__DEV__ and type(currentValue) == 'table' then
			local scriptName, line = debug.info(2, 'sl')
			local lineString = `{scriptName}:{line}`
			local pathString = Utils.getPathString(path)

			if not warnsSent[lineString] then
				if currentValue == newValue then
					warn(
						`Warning: Skipping Replion:Set('{pathString}') due to identical table references.\n`
							.. `Consider using Replion:Update('{pathString}') at {scriptName}:{line} instead.`
					)
				elseif currentValue ~= newValue and type(newValue) == 'table' then
					warn(
						`Warning: Replion:Set('{pathString}') detected a new table reference, but all values inside are identical.\n`
							.. `This may indicate the use of a shallow clone for the table at Replion:Get('{pathString}') without properly cloning nested values. `
							.. `Review your table cloning logic at {scriptName}:{line}.`
					)
				end

				warnsSent[lineString] = true
			end
		end

		return currentValue :: T
	end

	if _G.__DEV__ and type(currentValue) == 'table' and type(newValue) == 'table' then
		-- Check if the value has the exact same keys
		-- otherwise warn about a possible benefit of using Replion:Update
		local currentValueKeys = Freeze.Dictionary.keys(currentValue)
		local newValueKeys = Freeze.Dictionary.keys(newValue)

		if Freeze.List.equals(currentValueKeys, newValueKeys) then
			local scriptName, line = debug.info(2, 'sl')
			local pathString = Utils.getPathString(path)
			local lineString = `{scriptName}:{line}`

			if not warnsSent[lineString] then
				warnsSent[lineString] = true

				local changedValues = Freeze.Dictionary.filter(newValue, function(value, key)
					return not Freeze.Dictionary.equals((currentValue :: any)[key], value)
				end)

				-- Check if all values have changed
				if Freeze.Dictionary.count(changedValues) ~= Freeze.Dictionary.count(newValue) then
					local formatedValue = ''
					for key, value in changedValues do
						formatedValue ..= `\n\t{key} = {value},`
					end

					warn(
						`Warning: Sending a table with identical keys but different values to the client.\n`
							.. `Consider using Replion:Update('{pathString}', \{{formatedValue}\n}) at {scriptName}:{line} for optimized updates.`
					)
				end
			end
		end
	end

	local oldData = self.Data
	local newData = if newValue == Freeze.None
		then Freeze.Dictionary.removeIn(self.Data, pathTable)
		else Freeze.Dictionary.setIn(self.Data, pathTable, newValue)

	self.Data = newData

	Network.sendTo(self.ReplicateTo, 'Set', self._packedId, path, newValue)

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)
	fireDictKeyEvents(self._rootNode, pathTable, oldData, newData)

	return newValue
end

--[=[
	Calls `callback` with the current value at `path`. The callback must return a table
	whose entries will be merged into the existing dictionary. Only changed keys are sent
	to the client, making this more bandwidth-efficient than `:Set` for table updates.

	Set a key to `Replion.None` in the returned table to remove it.

	```lua
	replion:Update('Inventory', function(inv)
		return Freeze.Dictionary.merge(inv, {
			Sword = true,
			OldItem = Replion.None,
		})
	end)
	```

	@param path Path
	@param callback (currentValue: V) -> V
]=]
function ServerReplion:Update<V>(path, callback: UpdateCallback<V>)
	local pathTable = Utils.getPathTable(path)
	local pathCurrentValue: V = Freeze.Dictionary.getIn(self.Data, pathTable) or ({} :: any)

	local targetTable = callback(pathCurrentValue)
	assert(type(targetTable) == 'table', 'Update callback must return a table')

	local changedValues = Freeze.Dictionary.filter(targetTable, function(value, key)
		return not Freeze.Dictionary.equals((pathCurrentValue :: any)[key], value)
	end)

	local nothingChanged = next(changedValues) == nil
	if nothingChanged then
		return
	end

	local oldData = self.Data

	-- Apply changes: set/remove each key individually to avoid relying on
	-- Freeze.None singleton identity across module reloads.
	local newData = self.Data
	for key, value in changedValues do
		local keyPath = table.move(pathTable, 1, #pathTable, 1, table.create(#pathTable + 1))
		keyPath[#keyPath + 1] = key
		if value == Freeze.None then
			newData = Freeze.Dictionary.removeIn(newData, keyPath)
		else
			newData = Freeze.Dictionary.setIn(newData, keyPath, value)
		end
	end

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)
	fireDictChildKeyEvents(self._rootNode, pathTable, oldData, newData)

	-- Fix unordered arrays
	local arraySize = table.maxn(changedValues)
	local isUnordered
	if arraySize > 0 then
		local size = 0

		for i in changedValues do
			size += 1

			if i ~= size then
				isUnordered = true
				break
			end
		end

		-- is an unordered array, transform into dictionary
		isUnordered = isUnordered or size ~= arraySize

		if _G.__DEV__ and isUnordered then
			local scriptName, line = debug.info(2, 'sl')
			local lineString = `{scriptName}:{line}`

			if not warnsSent[lineString] then
				warnsSent[lineString] = true

				warn(
					`Warning: You're trying to send an unordered array to the client, RemotesEvents can't send unordered arrays.\n`
						.. `The array will be transformed into a dictionary to be sent to the client.\n`
						.. `at {scriptName}:{line}`
				)
			end
		end
	end

	local serializedUpdate = Freeze.Dictionary.map(changedValues, function(value, key)
		return if value == Freeze.None then Utils.SerializedNone else value, if isUnordered then tostring(key) else key
	end)

	Network.sendTo(self.ReplicateTo, 'Update', self._packedId, path, serializedUpdate, isUnordered)
end

--[=[
	Adds `amount` to the number at `path` and returns the new value.

	```lua
	local newCoins = replion:Increase('Coins', 10) -- adds 10
	```

	@param path Path
	@param amount number
	@return number
]=]
function ServerReplion:Increase(path, amount)
	assert(type(amount) == 'number', `"amount" expected number, got {type(amount)}`)

	local currentValue = self:GetExpect(path, `"{Utils.getPathString(path)}" is not a valid path!`)
	if amount == 0 then
		return currentValue
	end

	if _G.__DEV__ and type(currentValue) ~= 'number' then
		local scriptName, line = debug.info(2, 'sl')
		local lineString = `{scriptName}:{line}`

		if not warnsSent[lineString] then
			warnsSent[lineString] = true

			warn(
				`Warning: Attempt to increase non-numeric value at "{Utils.getPathString(path)}"\n`
					.. `Check if the path is correct at {scriptName}:{line}.`
			)
		end

		return currentValue
	end

	return self:Set(path, currentValue + amount)
end

--[=[
	Subtracts `amount` from the number at `path` and returns the new value.

	```lua
	local newCoins = replion:Decrease('Coins', 5) -- subtracts 5
	```

	@param path Path
	@param amount number
	@return number
]=]
function ServerReplion:Decrease(path, amount)
	return self:Increase(path, -amount)
end

--[=[
	Inserts `value` into the array at `path`. If `index` is provided the value is
	inserted at that position (shifting later elements); otherwise it is appended.

	:::note Arrays only
	Only works on array-style tables.
	:::

	```lua
	replion:Insert('Queue', 'PlayerA')        -- append
	replion:Insert('Queue', 'VIP', 1)         -- prepend
	```

	@param path Path
	@param value T
	@param index number?
]=]
function ServerReplion:Insert<T>(path, value: T, index)
	local pathTable = Utils.getPathTable(path)

	local array = self:GetExpect(path, `"{Utils.getPathString(path)}" is not a valid path!`)

	local targetIndex = if index then index else #array + 1
	local newArray = table.clone(array)
	table.insert(newArray, targetIndex, value)

	local oldData = self.Data
	local newData = Freeze.Dictionary.setIn(self.Data, pathTable, newArray)

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireEvent(self._rootNode, 'onArrayInsert', pathTable, targetIndex, value)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)

	Network.sendTo(self.ReplicateTo, 'ArrayUpdate', self._packedId, 'i', path, value, index)
end

--[=[
	Removes and returns the value at `index` in the array at `path`.
	If `index` is omitted, removes and returns the last element.

	:::note Arrays only
	Only works on array-style tables.
	:::

	```lua
	local item = replion:Remove('Queue')        -- pop last
	local first = replion:Remove('Queue', 1)    -- pop first
	```

	@param path Path
	@param index number?
	@return T
]=]
function ServerReplion:Remove<T>(path, index): T
	local pathTable = Utils.getPathTable(path)

	local array = self:GetExpect(path, `"{Utils.getPathString(path)}" is not a valid path!`)

	local targetIndex = if index then index else #array
	local value = array[targetIndex]

	local newArray = table.clone(array)
	table.remove(newArray, targetIndex)

	local oldData = self.Data
	local newData = Freeze.Dictionary.setIn(self.Data, pathTable, newArray)

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireEvent(self._rootNode, 'onArrayRemove', path, targetIndex, value)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)

	Network.sendTo(self.ReplicateTo, 'ArrayUpdate', self._packedId, 'r', path, index)

	return value
end

--[=[
	Empties the table at `path`. No-ops if already empty.

	```lua
	replion:Clear('Queue')
	print(replion:Get('Queue')) --> {}
	```

	@param path Path
]=]
function ServerReplion:Clear(path)
	local array = self:GetExpect(path, `"{Utils.getPathString(path)}" is not a valid path!`)

	-- If the array is already empty, don't do anything
	if next(array) == nil then
		return
	end

	local pathTable = Utils.getPathTable(path)
	local oldData = self.Data
	local newData = Freeze.Dictionary.setIn(self.Data, pathTable, {})

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)

	Network.sendTo(self.ReplicateTo, 'ArrayUpdate', self._packedId, 'c', path)
end

--[=[
	Searches the array at `path` for `value` and returns its index and the value.
	Returns `nil, nil` if not found.

	:::note Arrays only
	Only works on array-style tables.
	:::

	```lua
	local index, item = replion:Find('Queue', 'PlayerA')
	```

	@param path Path
	@param value T
	@return (number?, T?)
]=]
function ServerReplion:Find<T>(path, value: T): (number?, T?)
	local array: { T }? = self:Get(path)
	if not array then
		return
	end

	local index: number? = table.find(array, value)
	if not index then
		return
	end

	return index, value
end

--[=[
	Returns the value at `path`, or `nil` if the path does not exist.
	Use `:GetExpect` when the value is required.

	```lua
	local coins: number? = replion:Get('Coins')
	local sword: boolean? = replion:Get('Inventory.Sword')
	```

	@param path Path
	@return T?
]=]
function ServerReplion:Get<T>(path): T?
	assert(path, 'Path is required!')

	local pathTable = Utils.getPathTable(path)
	local value: T? = Freeze.Dictionary.getIn(self.Data, pathTable)

	if _G.__DEV__ and value == nil then
		for i, key in pathTable do
			if type(key) == 'string' then
				local trimmedString = Utils.trimString(key)

				if trimmedString == key then
					continue
				end

				local pathWithoutTrimmedString = Freeze.List.set(pathTable, i, trimmedString)
				local valueWithTrimmedString = Freeze.Dictionary.getIn(self.Data, pathWithoutTrimmedString)

				if valueWithTrimmedString then
					local scriptName, line = debug.info(2, 'sl')

					warn(
						`Warning: the path "{Utils.getPathString(path)}" has a key with leading or trailing whitespaces.\n`
							.. `This is likely a mistake, consider using "{Utils.getPathString(pathWithoutTrimmedString)}" at {scriptName}:{line} instead.`
					)
				end
			end
		end
	end

	return value
end

--[=[
	Same as `:Get` but throws if the value is `nil`.
	Provide an optional custom error message as the second argument.

	```lua
	local coins: number = replion:GetExpect('Coins')
	local gems: number = replion:GetExpect('Gems', 'Player has no Gems!')
	```

	@param path Path
	@param message string?
	@return T
	@error "path is not a valid path" -- Thrown when the value is nil.
]=]
function ServerReplion:GetExpect<T>(path, message): T
	assert(path, 'Path is required!')

	message = if message then message else `"{Utils.getPathString(path)}" is not a valid path!`

	local value: T? = self:Get(path)
	if value == nil then
		error(message)
	end

	return value
end

--[=[
	Destroys the Replion, disconnects all signals, and notifies all subscribed
	clients to remove their local copy. No-ops if already destroyed.
]=]
function ServerReplion:Destroy()
	if self.Destroyed then
		return
	end

	self._beforeDestroy:Fire()
	self._beforeDestroy:DisconnectAll()

	self._replicateToChanged:Destroy()
	self._playerSubscribed:Destroy()
	self._playerUnsubscribed:Destroy()
	Graph.destroyRootNode(self._rootNode)

	self._rootNode = nil
	self.Destroyed = true

	Network.sendTo(self.ReplicateTo, 'Removed', self._packedId)

	table.insert(availableIds, self._id)

	self._afterDestroy:Fire()
	self._afterDestroy:DisconnectAll()
end

return ServerReplion
