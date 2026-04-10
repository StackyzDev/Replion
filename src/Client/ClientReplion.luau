local Freeze = require(script.Parent.Parent.Parent.Freeze)

local Utils = require(script.Parent.Parent.Internal.Utils)
local Signal = require(script.Parent.Parent.Parent.Signal)
local _T = require(script.Parent.Parent.Internal.Types)

local Graph = require(script.Parent.Parent.Internal.Graph)

type Dictionary = _T.Dictionary

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

local function fireDictChildKeyEvents(rootNode: Graph.Node, pathTable: { any }, oldData: any, newData: any)
	local eventPath: any = if #pathTable == 0 then '__root' else pathTable

	local oldDict = if #pathTable == 0 then oldData else Freeze.Dictionary.getIn(oldData, pathTable)
	local newDict = if #pathTable == 0 then newData else Freeze.Dictionary.getIn(newData, pathTable)

	local oldIsTable = type(oldDict) == 'table'
	local newIsTable = type(newDict) == 'table'

	if not oldIsTable and not newIsTable then
		return
	end

	if newIsTable then
		for key, value in newDict :: any do
			if not oldIsTable or (oldDict :: any)[key] == nil then
				Graph.fireEvent(rootNode, 'onDictKeyAdded', eventPath, key, value)
			end
		end
	end

	if oldIsTable then
		for key, value in oldDict :: any do
			if not newIsTable or (newDict :: any)[key] == nil then
				Graph.fireEvent(rootNode, 'onDictKeyRemoved', eventPath, key, value)
			end
		end
	end
end

export type ClientReplion<D = any> = {
	Data: D,
	Tags: _T.Tags,
	Destroyed: boolean?,
	ReplicateTo: _T.ReplicateTo,

	_channel: string,
	_rootNode: Graph.Node?,
	_beforeDestroy: Signal.Signal<nil>,
	_afterDestroy: Signal.Signal<nil>,

	new: (serializedReplion: _T.SerializedReplion) -> ClientReplion<D>,
	BeforeDestroy: (self: ClientReplion<D>, callback: () -> ()) -> Signal.Connection,
	AfterDestroy: (self: ClientReplion<D>, callback: () -> ()) -> Signal.Connection,

	DataChanged: (self: ClientReplion<D>, callback: (newData: D, path: _T.Path) -> ()) -> Signal.Connection,
	Changed: <T>(
		self: ClientReplion<D>,
		path: _T.Path,
		callback: (newValue: T, oldValue: T?) -> ()
	) -> Signal.Connection,

	Observe: <T>(
		self: ClientReplion<D>,
		path: _T.Path,
		callback: (newValue: T, oldValue: T?) -> ()
	) -> Signal.Connection,

	Inserted: (self: ClientReplion<D>, path: _T.Path, callback: _T.ArrayCallback) -> Signal.Connection,
	Removed: (self: ClientReplion<D>, path: _T.Path, callback: _T.ArrayCallback) -> Signal.Connection,

	KeyAdded: (self: ClientReplion<D>, path: _T.Path, callback: _T.DictCallback) -> Signal.Connection,
	KeyRemoved: (self: ClientReplion<D>, path: _T.Path, callback: _T.DictCallback) -> Signal.Connection,

	_set: <T>(self: ClientReplion<D>, path: _T.Path, newValue: T) -> T,
	_update: (self: ClientReplion<D>, path: _T.Path | Dictionary, toUpdate: Dictionary?, isUnordered: boolean?) -> (),

	_increase: (self: ClientReplion<D>, path: _T.Path, amount: number) -> number,
	_decrease: (self: ClientReplion<D>, path: _T.Path, amount: number) -> number,

	_insert: <T>(self: ClientReplion<D>, path: _T.Path, value: T, index: number?) -> (),
	_remove: <T>(self: ClientReplion<D>, path: _T.Path, index: number?) -> T,
	_clear: (self: ClientReplion<D>, path: _T.Path) -> (),

	Find: <T>(self: ClientReplion<D>, path: _T.Path, value: T) -> (number?, T?),

	GetKeys: <K>(self: ClientReplion<D>, path: _T.Path) -> { K },
	GetValues: <V>(self: ClientReplion<D>, path: _T.Path) -> { V },

	Get: <T>(self: ClientReplion<D>, path: _T.Path) -> T?,
	GetExpect: <T>(self: ClientReplion<D>, path: _T.Path, message: string?) -> T,

	Destroy: (self: ClientReplion<D>) -> (),

	__tostring: (self: ClientReplion<D>) -> string,
}

--[=[
	@type Path string | { string }
	@within ClientReplion
]=]

--[=[
	@prop Destroyed boolean?
	@readonly
	@within ClientReplion
]=]

--[=[
	@prop Data { [any]: any }
	@readonly
	@within ClientReplion
]=]

--[=[
	@prop Tags { string }?
	@readonly
	@within ClientReplion
]=]

--[=[
	@prop ReplicateTo ReplicateTo
	@within ClientReplion
]=]

--[=[
	@class ClientReplion
	@client

	The client-side mirror of a `ServerReplion`. Created automatically when the server
	replicates data — never construct this directly.

	Obtain an instance via `Replion.Client:AwaitReplion` or `Replion.Client:WaitReplion`:

	```lua
	local Replion = require(path.to.Replion)

	Replion.Client:AwaitReplion('PlayerData', function(replion)
		print('Coins:', replion:Get('Coins'))

		replion:Changed('Coins', function(new, old)
			print('Coins changed from', old, 'to', new)
		end)
	end)
	```
]=]
local ClientReplionMeta = {}
ClientReplionMeta.__index = ClientReplionMeta

local ClientReplion: ClientReplion = ClientReplionMeta :: any

function ClientReplion.new(serializedReplion)
	local self: ClientReplion = setmetatable({
		Data = serializedReplion[3],
		Tags = serializedReplion[5],
		ReplicateTo = serializedReplion[4],

		_channel = serializedReplion[2],

		_beforeDestroy = Signal.new(),
		_afterDestroy = Signal.new(),
		_rootNode = Graph.createRootNode(),
	}, ClientReplion) :: any

	return self
end

function ClientReplion:__tostring()
	return `Replion<{self._channel}>`
end

--[=[
	Fires synchronously just before the Replion is destroyed.

	@param callback () -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:BeforeDestroy(callback)
	return self._beforeDestroy:Connect(callback)
end

--[=[
	Fires after the Replion has been fully destroyed.

	@param callback () -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:AfterDestroy(callback)
	return self._afterDestroy:Connect(callback)
end

--[=[
	Fires whenever any part of the Replion's data changes.

	```lua
	replion:DataChanged(function(newData, path)
		print('Changed at', table.concat(path, '.'))
	end)
	```

	@param callback (newData: any, path: { string }) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:DataChanged(callback)
	return Graph.connect(self._rootNode, 'onDataChange', '__root', callback)
end

--[=[
	Fires whenever the value at `path` changes.

	```lua
	replion:Changed('Coins', function(new: number, old: number)
		print('Coins:', old, '->', new)
	end)
	```

	@param path Path
	@param callback (newValue: T, oldValue: T) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:Changed<T>(path, callback)
	return Graph.connect(self._rootNode, 'onChange', path, callback)
end

--[=[
	Fires immediately with the current value at `path`, then on every subsequent change.
	`oldValue` is `nil` on the initial call.

	```lua
	replion:Observe('Coins', function(coins: number, old: number?)
		print('Coins:', coins)
	end)
	```

	@param path Path
	@param callback (newValue: T, oldValue: T?) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:Observe<T>(path, callback)
	task.spawn(function()
		callback(self:Get(path), nil)
	end)

	return Graph.connect(self._rootNode, 'onChange', path, callback)
end

--[=[
	Fires when a value is inserted into the array at `path`.

	```lua
	replion:Inserted('Queue', function(index: number, value: any)
		print('Inserted at', index, ':', value)
	end)
	```

	@param path Path
	@param callback (index: number, value: T) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:Inserted(path, callback)
	return Graph.connect(self._rootNode, 'onArrayInsert', path, callback)
end

--[=[
	Fires when a value is removed from the array at `path`.

	```lua
	replion:Removed('Queue', function(index: number, value: any)
		print('Removed at', index, ':', value)
	end)
	```

	@param path Path
	@param callback (index: number, value: T) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:Removed(path, callback)
	return Graph.connect(self._rootNode, 'onArrayRemove', path, callback)
end

function ClientReplion:_set<T>(path, newValue: T): T
	local pathTable = Utils.getPathTable(path)

	local currentValue: T? = Freeze.Dictionary.getIn(self.Data, pathTable)
	if currentValue == newValue then
		return newValue
	end

	local oldData = self.Data
	local newData = if (newValue :: any) == Freeze.None
		then Freeze.Dictionary.removeIn(self.Data, pathTable)
		else Freeze.Dictionary.setIn(self.Data, pathTable, newValue)

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)
	fireDictKeyEvents(self._rootNode, pathTable, oldData, newData)

	return newValue
end

function ClientReplion:_update(path, toUpdate, isUnordered)
	local rawValues = toUpdate or path :: Dictionary
	local pathTable = if toUpdate == nil then {} else Utils.getPathTable(path)

	local oldData = self.Data
	local newData = self.Data
	for rawKey, rawValue in rawValues do
		local key = if isUnordered then tonumber(rawKey) else rawKey
		local keyPath = table.move(pathTable, 1, #pathTable, 1, table.create(#pathTable + 1))
		keyPath[#keyPath + 1] = key
		if rawValue == Utils.SerializedNone then
			newData = Freeze.Dictionary.removeIn(newData, keyPath)
		else
			newData = Freeze.Dictionary.setIn(newData, keyPath, rawValue)
		end
	end

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)
	fireDictChildKeyEvents(self._rootNode, pathTable, oldData, newData)
end

function ClientReplion:_increase(path, amount)
	local currentValue: number = self:GetExpect(path)

	return self:_set(path, currentValue + amount)
end

function ClientReplion:_decrease(path, amount)
	return self:_increase(path, -amount)
end

function ClientReplion:_insert<T>(path, value: T, index)
	local pathTable = Utils.getPathTable(path)

	local array =
		assert(Freeze.Dictionary.getIn(self.Data, pathTable), `"{Utils.getPathString(path)}" is not a valid path!`)
	local targetIndex: number = if index then index else #array + 1

	local newArray = Freeze.List.insert(array, targetIndex, value)

	local oldData = self.Data
	local newData = Freeze.Dictionary.setIn(self.Data, pathTable, newArray)

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireEvent(self._rootNode, 'onArrayInsert', pathTable, targetIndex, value)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)
end

function ClientReplion:_remove<T>(path, index)
	local pathTable = Utils.getPathTable(path)

	local array = self:GetExpect(path, `"{Utils.getPathString(path)}" is not a valid path!`)
	local targetIndex: number = if index then index else #array
	local value = array[targetIndex]

	local newArray = Freeze.List.remove(array, targetIndex)

	local oldData = self.Data
	local newData = Freeze.Dictionary.setIn(self.Data, pathTable, newArray)

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireEvent(self._rootNode, 'onArrayRemove', path, targetIndex, value)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)

	return value
end

function ClientReplion:_clear(path)
	local pathTable = Utils.getPathTable(path)

	local oldData = self.Data
	local newData = Freeze.Dictionary.setIn(self.Data, pathTable, {})

	self.Data = newData

	Graph.fireEvent(self._rootNode, 'onDataChange', '__root', newData, pathTable)
	Graph.fireChange(self._rootNode, pathTable, newData, oldData)
end

--[=[
	Fires when a new key is introduced to the dictionary at `path`.
	Triggered by server-side `:Update` and deep `:Set` calls.

	```lua
	replion:KeyAdded('Inventory', function(key: string, value: any)
		print('Got item:', key)
	end)
	```

	@param path Path
	@param callback (key: any, value: T) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:KeyAdded(path, callback)
	return Graph.connect(self._rootNode, 'onDictKeyAdded', path, callback)
end

--[=[
	Fires when a key is removed from the dictionary at `path`.
	Triggered by server-side `:Update` (key set to `Replion.None`) and deep `:Set` calls.

	```lua
	replion:KeyRemoved('Inventory', function(key: string, value: any)
		print('Lost item:', key, 'was', value)
	end)
	```

	@param path Path
	@param callback (key: any, value: T) -> ()
	@return RBXScriptConnection
]=]
function ClientReplion:KeyRemoved(path, callback)
	return Graph.connect(self._rootNode, 'onDictKeyRemoved', path, callback)
end

--[=[
	Returns all keys of the dictionary at `path`. Returns `{}` if not a table.

	```lua
	local items = replion:GetKeys('Inventory') -- { 'Sword', 'Bow' }
	```

	@param path Path
	@return { K }
]=]
function ClientReplion:GetKeys<K>(path): { K }
	local dict = self:Get(path)
	if type(dict) ~= 'table' then
		return {}
	end
	return table.clone(Freeze.Dictionary.keys(dict)) :: any
end

--[=[
	Returns all values of the dictionary at `path`. Returns `{}` if not a table.

	```lua
	local owned = replion:GetValues('Inventory') -- { true, true }
	```

	@param path Path
	@return { V }
]=]
function ClientReplion:GetValues<V>(path): { V }
	local dict = self:Get(path)
	if type(dict) ~= 'table' then
		return {}
	end
	return table.clone(Freeze.Dictionary.values(dict)) :: any
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
function ClientReplion:Find<T>(path, value: T): (number?, T?)
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
	Returns the value at `path`, or `nil` if not found.
	Use `:GetExpect` when the value is required.

	```lua
	local coins: number? = replion:Get('Coins')
	local sword: boolean? = replion:Get('Inventory.Sword')
	```

	@param path Path
	@return T?
]=]
function ClientReplion:Get<T>(path): T?
	return Freeze.Dictionary.getIn(self.Data, Utils.getPathTable(path))
end

--[=[
	Same as `:Get` but throws if the value is `nil`.

	```lua
	local coins: number = replion:GetExpect('Coins')
	local gems: number = replion:GetExpect('Gems', 'Player has no Gems!')
	```

	@param path Path
	@param message string?
	@return T
	@error "path is not a valid path" -- Thrown when the value is nil.
]=]
function ClientReplion:GetExpect<T>(path, message): T
	assert(path, 'Path is required!')

	message = if message then message else `"{Utils.getPathString(path)}" is not a valid path!`

	local value: T? = self:Get(path)
	if value == nil then
		error(message)
	end

	return value
end

function ClientReplion:Destroy()
	if self.Destroyed then
		return
	end

	self._beforeDestroy:Fire()
	self._beforeDestroy:DisconnectAll()

	Graph.destroyRootNode(self._rootNode)
	self._rootNode = nil

	self.Destroyed = true

	self._afterDestroy:Fire()
	self._afterDestroy:DisconnectAll()
end

return ClientReplion
