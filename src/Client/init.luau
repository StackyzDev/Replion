local RunService = game:GetService('RunService')

local Utils = require(script.Parent.Internal.Utils)
local Signal = require(script.Parent.Parent.Signal)
local Network = require(script.Parent.Internal.Network)
local ClientReplion = require(script.ClientReplion)
local _T = require(script.Parent.Internal.Types)

export type ClientReplion<D = any> = ClientReplion.ClientReplion<D>
type SerializedReplion = _T.SerializedReplion
type SerializedReplions = { SerializedReplion }
type WaitList = { { thread: thread, async: boolean? } }

export type ReplionClient = {
	ReplionAdded: (
		self: ReplionClient,
		channel: string,
		callback: (replion: ClientReplion) -> ()
	) -> Signal.Connection,
	ReplionAddedWithTag: (
		self: ReplionClient,
		tag: string,
		callback: (replion: ClientReplion) -> ()
	) -> Signal.Connection,

	ReplionRemoved: (
		self: ReplionClient,
		channel: string,
		callback: (replion: ClientReplion) -> ()
	) -> Signal.Connection,
	ReplionRemovedWithTag: (
		self: ReplionClient,
		tag: string,
		callback: (replion: ClientReplion) -> ()
	) -> Signal.Connection,

	GetReplion: (self: ReplionClient, channel: string) -> ClientReplion?,
	WaitReplion: (self: ReplionClient, channel: string, timeout: number?) -> ClientReplion,
	AwaitReplion: (
		self: ReplionClient,
		channel: string,
		callback: (replion: ClientReplion) -> (),
		timeout: number?
	) -> (() -> ())?,
}

local cache: { [string]: ClientReplion? } = {}
local waitingList: { [string]: WaitList? } = {}

local timeouts: { [thread]: thread } = {}

local addedSignal = Signal.new()
local removedSignal = Signal.new()

local function getWaitList(channel: string)
	local list = waitingList[channel]
	if not list then
		list = {}
		waitingList[channel] = list
	end

	return assert(list, 'Invalid wait list')
end

local function cancelWait(waitList: WaitList, thread: thread)
	for index, info in waitList do
		if info.thread ~= thread then
			continue
		end

		table.remove(waitList, index)

		-- if is an await function, just cancel it
		if info.async then
			Utils.safeCancelThread(thread)
		else
			pcall(task.spawn, thread)
		end

		timeouts[thread] = nil

		break
	end
end

local function createTimeout(waitList: WaitList, timeout: number, thread: thread)
	return task.delay(timeout, cancelWait, waitList, thread)
end

local function createReplion(serializedReplion: SerializedReplion)
	local channel = serializedReplion[2]
	if cache[channel] then
		return
	end

	local newReplion = ClientReplion.new(serializedReplion)

	cache[channel] = newReplion
	cache[serializedReplion[1]] = newReplion

	addedSignal:Fire(newReplion)

	local waitList = waitingList[channel]
	if waitList then
		for _, info in waitList do
			if coroutine.status(info.thread) == 'suspended' then
				task.spawn(info.thread, newReplion)
			end
		end

		waitingList[channel] = nil
	end
end

--[=[
	@class Client
	@client

	The client-side manager for all `ClientReplion` instances.
	Require it once via `Replion.Client`.

	```lua
	local Replion = require(path.to.Replion)

	Replion.Client:AwaitReplion('PlayerData', function(replion)
		replion:Observe('Coins', function(coins)
			print('Coins:', coins)
		end)
	end)
	```
]=]
local Client: ReplionClient = {} :: any

--[=[
	Fires when a `ClientReplion` with the given channel is received from the server.

	```lua
	Replion.Client:ReplionAdded('PlayerData', function(replion)
		print('PlayerData ready')
	end)
	```

	@param channel string
	@param callback (replion: ClientReplion) -> ()
	@return RBXScriptConnection
]=]
function Client:ReplionAdded(channel, callback)
	return addedSignal:Connect(function(replion: ClientReplion)
		if replion._channel == channel then
			callback(replion)
		end
	end)
end

--[=[
	Fires when a `ClientReplion` with the given channel is destroyed (server removed it).

	@param channel string
	@param callback (replion: ClientReplion) -> ()
	@return RBXScriptConnection
]=]
function Client:ReplionRemoved(channel, callback)
	return removedSignal:Connect(function(replion: ClientReplion)
		if replion._channel == channel then
			callback(replion)
		end
	end)
end

--[=[
	Fires when a `ClientReplion` that has the given tag is received from the server.
	Tags are set server-side in `ReplionConfig.Tags`.

	```lua
	Replion.Client:ReplionAddedWithTag('Player', function(replion)
		print('Player replion received')
	end)
	```

	@param tag string
	@param callback (replion: ClientReplion) -> ()
	@return RBXScriptConnection
]=]
function Client:ReplionAddedWithTag(tag, callback)
	return addedSignal:Connect(function(replion: ClientReplion)
		local tags: { string }? = replion.Tags

		if tags and table.find(tags, tag) ~= nil then
			callback(replion)
		end
	end)
end

--[=[
	Fires when a `ClientReplion` with the given tag is destroyed.

	@param tag string
	@param callback (replion: ClientReplion) -> ()
	@return RBXScriptConnection
]=]
function Client:ReplionRemovedWithTag(tag, callback)
	return removedSignal:Connect(function(replion: ClientReplion)
		local tags: { string }? = replion.Tags

		if tags and table.find(tags, tag) ~= nil then
			callback(replion)
		end
	end)
end

--[=[
	Returns the `ClientReplion` for `channel` if it has already been received, or `nil`.

	```lua
	local replion = Replion.Client:GetReplion('PlayerData')
	```

	@param channel string
	@return ClientReplion?
]=]
function Client:GetReplion(channel)
	return cache[channel]
end

--[=[
	Yields until the `ClientReplion` for `channel` is received from the server.
	Optionally times out after `timeout` seconds.

	```lua
	local replion = Replion.Client:WaitReplion('PlayerData', 10)
	```

	@param channel string
	@param timeout number?
	@return ClientReplion
	@yields
]=]
function Client:WaitReplion(channel, timeout)
	local replion = cache[channel]
	if replion then
		return replion
	end

	local thread: thread = coroutine.running()
	local waitList = getWaitList(channel)

	if timeout then
		timeouts[thread] = createTimeout(waitList, timeout, thread)
	end

	table.insert(waitList, { thread = thread })

	return coroutine.yield()
end

--[=[
	Calls `callback` asynchronously when the `ClientReplion` for `channel` is received.
	If one is already cached, the callback is called immediately.
	Returns a cancel function.

	```lua
	local cancel = Replion.Client:AwaitReplion('PlayerData', function(replion)
		replion:Observe('Coins', updateCoinsUI)
	end)
	```

	@param channel string
	@param callback (replion: ClientReplion) -> ()
	@param timeout number?
	@return (() -> ())?
]=]
function Client:AwaitReplion(channel, callback, timeout)
	local replion = cache[channel]
	if replion then
		return callback(replion)
	end

	local waitList = getWaitList(channel)
	local newThread = coroutine.create(callback)

	if timeout then
		timeouts[newThread] = createTimeout(waitList, timeout, newThread)
	end

	table.insert(waitList, { thread = newThread, async = true })

	return function()
		cancelWait(waitList, newThread)
	end
end

if not Utils.ShouldMock and RunService:IsClient() then
	local addedRemote = Network.get('Added')
	local removedRemote = Network.get('Removed')
	local updateRemote = Network.get('Update')
	local setRemote = Network.get('Set')
	local updateReplicateTo = Network.get('UpdateReplicateTo')
	local arrayUpdate = Network.get('ArrayUpdate')

	addedRemote.OnClientEvent:Connect(function(serializedReplions: any)
		if type(serializedReplions[1]) == 'table' then
			for _, serializedReplion in serializedReplions do
				createReplion(serializedReplion)
			end
		else
			createReplion(serializedReplions)
		end
	end)

	removedRemote.OnClientEvent:Connect(function(id: string)
		local replion = cache[id]
		if replion then
			cache[id] = nil
			cache[replion._channel] = nil

			removedSignal:Fire(replion)

			replion:Destroy()
		end
	end)

	updateRemote.OnClientEvent:Connect(
		function(id: string, path: _T.Path | _T.Dictionary, toUpdate: _T.Dictionary?, isUnoredered: boolean?)
			local replion = cache[id]

			if replion then
				replion:_update(path, toUpdate, isUnoredered)
			end
		end
	)

	updateReplicateTo.OnClientEvent:Connect(function(id: string, replicateTo: _T.ReplicateTo)
		local replion = cache[id]

		if replion then
			replion.ReplicateTo = replicateTo
		end
	end)

	setRemote.OnClientEvent:Connect(function(id: string, path: _T.Path, newValue: any)
		local replion = cache[id]

		if replion then
			replion:_set(path, newValue)
		end
	end)

	arrayUpdate.OnClientEvent:Connect(function(id: string, action: string, ...: any)
		local replion = cache[id]
		if replion then
			if action == 'i' then
				replion:_insert(...)
			elseif action == 'r' then
				replion:_remove(...)
			elseif action == 'c' then
				replion:_clear(...)
			end
		end
	end)
end

return table.freeze(Client)
