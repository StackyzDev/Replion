--!nocheck
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)

local expect = JestGlobals.expect
local describe = JestGlobals.describe
local it = JestGlobals.it
local beforeEach = JestGlobals.beforeEach
local jest = JestGlobals.jest

local Replion
local ReplionServer

beforeEach(function()
	jest.resetModules()

	Replion = require(script.Parent.Parent)
	ReplionServer = require(script.Parent)
end)

local function newReplion(channel: string, data: any)
	return ReplionServer.new({
		Data = data,
		Channel = channel,
		ReplicateTo = 'All',
		Tags = {},
	})
end

-- ---------------------------------------------------------------------------

describe('ServerReplion:_serialize', function()
	it('should serialize the Replion', function()
		local r = newReplion('_serialize', {})

		local serialized = r:_serialize()

		expect(type(serialized)).toBe('table')
		expect(serialized).toEqual({
			r._packedId,
			r.Channel,
			r.Data,
			r.ReplicateTo,
			r.Tags,
		})
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Destroy', function()
	it('should destroy the Replion', function()
		local r = newReplion('Destroy', {})

		r:Destroy()

		expect(r.Destroyed).toBe(true)
	end)

	it('should be a no-op when called twice', function()
		local r = newReplion('DestroyTwice', {})

		r:Destroy()
		expect(function()
			r:Destroy()
		end).never.toThrow()
	end)

	it('should error when using a destroyed Replion', function()
		local r = newReplion('DestroyUse', {})

		r:Destroy()

		expect(function()
			r:Set('Foo', true)
		end).toThrow()
	end)

	it('should disconnect all signal connections', function()
		local r = newReplion('DestroyConnections', {})

		local connections = {
			r:Changed('onChange', function() end),
			r:Inserted('onArrayInsert', function() end),
			r:Removed('onArrayRemove', function() end),
			r:DataChanged(function() end),
			r:BeforeDestroy(function() end),
		}

		r:Destroy()

		for _, connection in connections do
			expect(connection.Connected).toBe(false)
		end
	end)

	it('should call BeforeDestroy before Destroyed is set', function()
		local r = newReplion('BeforeDestroyOrder', {})

		local destroyedDuring = nil
		r:BeforeDestroy(function()
			destroyedDuring = r.Destroyed
		end)
		r:Destroy()

		expect(destroyedDuring).toBe(nil)
		expect(r.Destroyed).toBe(true)
	end)

	it('should call AfterDestroy after Destroyed is set', function()
		local r = newReplion('AfterDestroy', {})

		local fnMock = jest.fn()

		r:AfterDestroy(fnMock)
		r:Destroy()

		expect(fnMock).toHaveBeenCalledTimes(1)
		expect(r.Destroyed).toBe(true)
	end)

	it('should call BeforeDestroy callback', function()
		local r = newReplion('BeforeDestroy', {})

		local fnMock = jest.fn()

		r:BeforeDestroy(fnMock)
		r:Destroy()

		expect(fnMock).toHaveBeenCalledTimes(1)
		expect(r.Destroyed).toBe(true)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Get', function()
	it('should get a top-level value', function()
		local r = newReplion('Get', { Foo = true })

		expect(r:Get('Foo')).toBe(true)
	end)

	it('should get a nested value via table path', function()
		local r = newReplion('GetNested', { A = { B = { [1] = 'Bar' } } })

		expect(r:Get({ 'A', 'B', 1 })).toBe('Bar')
	end)

	it('should return nil for a missing key', function()
		local r = newReplion('GetMissing', {})

		expect(r:Get('Missing')).toBeNil()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:GetExpect', function()
	it('should return the value when it exists', function()
		local r = newReplion('GetExpect', { Foo = true, A = { B = { [1] = 'Bar' } } })

		expect(r:GetExpect('Foo')).toBe(true)
		expect(r:GetExpect({ 'A', 'B', 1 })).toBe('Bar')
	end)

	it('should throw when the value does not exist', function()
		local r = newReplion('GetExpectError', {})

		expect(function()
			r:GetExpect('Foo')
		end).toThrow()
	end)

	it('should throw with a custom message', function()
		local r = newReplion('GetExpectCustomMsg', {})

		expect(function()
			r:GetExpect('Foo', 'Custom message')
		end).toThrow('Custom message')
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:GetKeys', function()
	it('should return all keys of a dict', function()
		local r = newReplion('GetKeys', { Items = { Sword = true, Bow = false } })

		local keys = r:GetKeys('Items')
		table.sort(keys)

		expect(keys).toEqual({ 'Bow', 'Sword' })
	end)

	it('should return an empty table for a missing path', function()
		local r = newReplion('GetKeysMissing', {})

		expect(r:GetKeys('Missing')).toEqual({})
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:GetValues', function()
	it('should return all values of a dict', function()
		local r = newReplion('GetValues', { Items = { A = 1, B = 2 } })

		local values = r:GetValues('Items')
		table.sort(values)

		expect(values).toEqual({ 1, 2 })
	end)

	it('should return an empty table for a missing path', function()
		local r = newReplion('GetValuesMissing', {})

		expect(r:GetValues('Missing')).toEqual({})
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Set', function()
	it('should set a top-level value', function()
		local r = newReplion('Set', {})

		r:Set('Foo', true)

		expect(r:Get('Foo')).toBe(true)
	end)

	it('should return the new value', function()
		local r = newReplion('SetReturn', {})

		local result = r:Set('Coins', 42)

		expect(result).toBe(42)
	end)

	it('should set a nested value via dot path', function()
		local r = newReplion('SetNested', { A = { B = { C = true } } })

		r:Set('A.B.C', false)

		expect(r:Get('A.B.C')).toBe(false)
	end)

	it('should create intermediate tables when path does not exist', function()
		local r = newReplion('SetDeep', {})

		r:Set('Inventory.Swords.Current', 5)

		expect(r:Get('Inventory.Swords.Current')).toBe(5)
	end)

	it('should call Changed on the set path', function()
		local r = newReplion('SetChanged', {})

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:Set('Foo', true)

		expect(fnMock).toHaveBeenCalledWith(true, nil)
	end)

	it('should call Changed on an ancestor when a nested value changes', function()
		local r = newReplion('SetChangedNested', { A = { B = { C = true } } })

		local fnMock = jest.fn()

		r:Changed('A', fnMock)
		r:Set('A.B.C', false)

		expect(fnMock).toHaveBeenCalledWith({ B = { C = false } }, { B = { C = true } })
	end)

	it('should call Changed only once when a table is replaced', function()
		local r = newReplion('SetChangedOnce', { A = {} })

		local fnMock = jest.fn()

		r:Changed('A', fnMock)
		r:Set('A', { { 1 } })

		expect(fnMock).toHaveBeenCalledTimes(1)
	end)

	it('should fire KeyAdded when a new top-level key is set', function()
		local r = newReplion('SetKeyAdded', {})

		local fnMock = jest.fn()

		r:KeyAdded('__root', fnMock)
		r:Set('NewKey', 99)

		expect(fnMock).toHaveBeenCalledWith('NewKey', 99)
	end)

	it('should fire KeyAdded for each intermediate table created by a deep path', function()
		local r = newReplion('SetKeyAddedDeep', {})

		local rootMock = jest.fn()
		local invMock = jest.fn()

		r:KeyAdded('__root', rootMock)
		r:KeyAdded('Inventory', invMock)

		r:Set('Inventory.Swords.Current', 5)

		-- 'Inventory' added to root
		expect(rootMock).toHaveBeenCalledWith('Inventory', r:Get('Inventory'))
		-- 'Swords' added inside Inventory
		expect(invMock).toHaveBeenCalledWith('Swords', r:Get('Inventory.Swords'))
	end)

	it('should fire KeyRemoved when a key is set to nil/None', function()
		local r = newReplion('SetKeyRemoved', { Coins = 10 })

		local fnMock = jest.fn()

		r:KeyRemoved('__root', fnMock)
		r:Set('Coins', Replion.None)

		expect(fnMock).toHaveBeenCalledWith('Coins', 10)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Update', function()
	it('should update values via callback', function()
		local r = newReplion('Update', { Items = { Foo = true, ToRemove = 0 } })

		r:Update('Items', function()
			return { Foo = false, Bar = {}, ToRemove = Replion.None }
		end)

		expect(r:Get('Items.Foo')).toBe(false)
		expect(r:Get('Items.Bar')).toEqual({})
		expect(r:Get('Items.ToRemove')).toBeNil()
	end)

	it('should pass the current value to the callback', function()
		local r = newReplion('UpdateCallback', { Items = { Sword = true } })

		local received
		r:Update('Items', function(current)
			received = current
			return current
		end)

		expect(received).toEqual({ Sword = true })
	end)

	it('should call Changed for updated keys', function()
		local r = newReplion('UpdateChanged', { Items = { Foo = true } })

		local fnMock = jest.fn()

		r:Changed('Items.Foo', fnMock)
		r:Update('Items', function()
			return { Foo = false }
		end)

		expect(fnMock).toHaveBeenCalledWith(false, true)
	end)

	it('should fire KeyAdded when a new key is added via Update', function()
		local r = newReplion('UpdateKeyAdded', { Items = {} })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:Update('Items', function()
			return { Sword = true }
		end)

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should fire KeyRemoved when a key is removed via Update with None', function()
		local r = newReplion('UpdateKeyRemoved', { Items = { Sword = true } })

		local fnMock = jest.fn()

		r:KeyRemoved('Items', fnMock)
		r:Update('Items', function()
			return { Sword = Replion.None }
		end)

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should not fire if nothing changed', function()
		local r = newReplion('UpdateNoChange', { Items = { Foo = true } })

		local fnMock = jest.fn()

		r:Changed('Items.Foo', fnMock)
		r:Update('Items', function()
			return { Foo = true }
		end)

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Increase / Decrease', function()
	it('should increase a number value', function()
		local r = newReplion('Increase', { Foo = 1 })

		r:Increase('Foo', 2)

		expect(r:Get('Foo')).toBe(3)
	end)

	it('should decrease a number value', function()
		local r = newReplion('Decrease', { Foo = 10 })

		r:Decrease('Foo', 3)

		expect(r:Get('Foo')).toBe(7)
	end)

	it('should throw if the value is not a number', function()
		local r = newReplion('IncreaseError', { Foo = 'Bar' })

		expect(function()
			r:Increase('Foo', 2)
		end).toThrow()
	end)

	it('should return the new value', function()
		local r = newReplion('IncreaseReturn', { Coins = 5 })

		expect(r:Increase('Coins', 10)).toBe(15)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Insert', function()
	it('should insert at a given index', function()
		local r = newReplion('Insert', { Array = { 1, 3 } })

		r:Insert('Array', 2, 2)

		expect(r:Get('Array')).toEqual({ 1, 2, 3 })
	end)

	it('should append when no index is given', function()
		local r = newReplion('InsertAppend', { Array = { 1, 2 } })

		r:Insert('Array', 3)

		expect(r:Get('Array')).toEqual({ 1, 2, 3 })
	end)

	it('should call Inserted with the index and value', function()
		local r = newReplion('InsertCallback', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Inserted('Array', fnMock)
		r:Insert('Array', 2, 4)

		expect(fnMock).toHaveBeenCalledWith(4, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Remove', function()
	it('should remove at a given index', function()
		local r = newReplion('Remove', { Array = { 1, 2, 3 } })

		r:Remove('Array', 2)

		expect(r:Get('Array')).toEqual({ 1, 3 })
	end)

	it('should remove from the end when no index is given', function()
		local r = newReplion('RemoveLast', { Array = { 1, 2, 3 } })

		local value = r:Remove('Array')

		expect(value).toBe(3)
		expect(r:Get('Array')).toEqual({ 1, 2 })
	end)

	it('should call Removed with the index and value', function()
		local r = newReplion('RemoveCallback', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Removed('Array', fnMock)
		r:Remove('Array', 2)

		expect(fnMock).toHaveBeenCalledWith(2, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Clear', function()
	it('should clear the array', function()
		local r = newReplion('Clear', { Array = { 1, 2, 3 } })

		r:Clear('Array')

		expect(r:Get('Array')).toEqual({})
	end)

	it('should call Changed with an empty table', function()
		local r = newReplion('ClearChanged', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Changed('Array', fnMock)
		r:Clear('Array')

		expect(fnMock).toHaveBeenCalledWith({}, { 1, 2, 3 })
	end)

	it('should be a no-op when already empty', function()
		local r = newReplion('ClearEmpty', { Array = {} })

		local fnMock = jest.fn()

		r:Changed('Array', fnMock)
		r:Clear('Array')

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Find', function()
	it('should return the index and value when found', function()
		local r = newReplion('Find', { Array = { 'Bow', 'Sword' } })

		local index, value = r:Find('Array', 'Sword')

		expect(index).toBe(2)
		expect(value).toBe('Sword')
	end)

	it('should return nil when not found', function()
		local r = newReplion('FindMissing', { Array = { 'Bow' } })

		local index, value = r:Find('Array', 'Sword')

		expect(index).toBeNil()
		expect(value).toBeNil()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Changed', function()
	it('should fire when a value changes', function()
		local r = newReplion('Changed', {})

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:Set('Foo', true)

		expect(fnMock).toHaveBeenCalledWith(true, nil)
	end)

	it('should fire for ancestor when a nested value changes', function()
		local r = newReplion('ChangedNested', { A = { B = { C = true } } })

		local fnMock = jest.fn()

		r:Changed('A', fnMock)

		r:Set('A.B.C', false)
		r:Set('A.B', { D = true })
		r:Set('A.B.D', false)

		expect(fnMock).toHaveBeenCalledWith({ B = { C = false } }, { B = { C = true } })
		expect(fnMock).toHaveBeenCalledWith({ B = { D = true } }, { B = { C = false } })
		expect(fnMock).toHaveBeenCalledWith({ B = { D = false } }, { B = { D = true } })
	end)

	it('should not fire when value does not change', function()
		local r = newReplion('ChangedNoOp', { Foo = true })

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:Set('Foo', true)

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Observe', function()
	it('should call the callback immediately with the current value', function()
		local r = newReplion('Observe', { Coins = 10 })

		local fnMock = jest.fn()

		r:Observe('Coins', fnMock)
		task.wait()

		expect(fnMock).toHaveBeenCalledWith(10, nil)
	end)

	it('should call the callback again when the value changes', function()
		local r = newReplion('ObserveChanged', { Coins = 10 })

		local fnMock = jest.fn()

		r:Observe('Coins', fnMock)
		task.wait()
		r:Set('Coins', 20)

		expect(fnMock).toHaveBeenCalledWith(10, nil)
		expect(fnMock).toHaveBeenCalledWith(20, 10)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Inserted', function()
	it('should call the callback with index and value', function()
		local r = newReplion('Inserted', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Inserted('Array', fnMock)
		r:Insert('Array', 2, 4)

		expect(fnMock).toHaveBeenCalledWith(4, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:Removed', function()
	it('should call the callback with index and value', function()
		local r = newReplion('Removed', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Removed('Array', fnMock)
		r:Remove('Array', 2)

		expect(fnMock).toHaveBeenCalledWith(2, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:KeyAdded', function()
	it('should fire when a key is added via Update', function()
		local r = newReplion('KeyAdded', { Items = {} })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:Update('Items', function()
			return { Sword = true }
		end)

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should fire when Set creates a new key', function()
		local r = newReplion('KeyAddedSet', {})

		local fnMock = jest.fn()

		r:KeyAdded('__root', fnMock)
		r:Set('NewKey', 42)

		expect(fnMock).toHaveBeenCalledWith('NewKey', 42)
	end)

	it('should fire for every intermediate table created by a deep Set', function()
		local r = newReplion('KeyAddedDeep', {})

		local rootMock = jest.fn()
		local invMock = jest.fn()

		r:KeyAdded('__root', rootMock)
		r:KeyAdded('Inventory', invMock)

		r:Set('Inventory.Swords.Current', 5)

		expect(rootMock).toHaveBeenCalledWith('Inventory', r:Get('Inventory'))
		expect(invMock).toHaveBeenCalledWith('Swords', r:Get('Inventory.Swords'))
	end)

	it('should not fire for an existing key that was updated', function()
		local r = newReplion('KeyAddedExisting', { Items = { Sword = false } })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:Update('Items', function()
			return { Sword = true }
		end)

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:KeyRemoved', function()
	it('should fire when a key is removed via Update with None', function()
		local r = newReplion('KeyRemoved', { Items = { Sword = true } })

		local fnMock = jest.fn()

		r:KeyRemoved('Items', fnMock)
		r:Update('Items', function()
			return { Sword = Replion.None }
		end)

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should fire when Set removes a key with None', function()
		local r = newReplion('KeyRemovedSet', { Coins = 10 })

		local fnMock = jest.fn()

		r:KeyRemoved('__root', fnMock)
		r:Set('Coins', Replion.None)

		expect(fnMock).toHaveBeenCalledWith('Coins', 10)
	end)

	it('should not fire for a key that was merely updated', function()
		local r = newReplion('KeyRemovedNoFire', { Items = { Sword = true } })

		local fnMock = jest.fn()

		r:KeyRemoved('Items', fnMock)
		r:Update('Items', function()
			return { Sword = false }
		end)

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:DataChanged', function()
	it('should fire for every mutation', function()
		local r = newReplion('DataChanged', {})

		local fnMock = jest.fn()

		r:DataChanged(fnMock)
		r:Set('Foo', true)
		r:Set('Bar', { Baz = 0 })
		r:Increase('Bar.Baz', 1)

		expect(fnMock).toHaveBeenCalledTimes(3)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ServerReplion:SetReplicateTo', function()
	it('should update the ReplicateTo value', function()
		local r = ReplionServer.new({
			Data = {},
			Channel = 'SetReplicateTo',
			ReplicateTo = {},
			Tags = {},
		})

		r:SetReplicateTo('All')

		expect(r.ReplicateTo).toBe('All')
	end)

	it('should fire _replicateToChanged', function()
		local r = ReplionServer.new({
			Data = {},
			Channel = '_replicateToChanged',
			ReplicateTo = {},
			Tags = {},
		})

		local current = r.ReplicateTo
		local fnMock = jest.fn()

		r._replicateToChanged:Connect(fnMock)
		r:SetReplicateTo('All')

		expect(fnMock).toHaveBeenCalledWith('All', current)
	end)

	it('should remove players that are no longer in the list', function()
		local fakePlayer = newproxy()
		local other = newproxy()

		local r = ReplionServer.new({
			Data = {},
			Channel = 'SetReplicateToCache',
			ReplicateTo = { fakePlayer },
			Tags = {},
		})

		expect(ReplionServer:GetReplionFor(fakePlayer, 'SetReplicateToCache')).toBeDefined()

		r:SetReplicateTo({ other })

		expect(ReplionServer:GetReplionFor(fakePlayer, 'SetReplicateToCache')).toBe(nil)
		expect(ReplionServer:GetReplionFor(other, 'SetReplicateToCache')).toBeDefined()
	end)

	it('should throw if the value is invalid', function()
		local r = ReplionServer.new({
			Data = {},
			Channel = 'SetReplicateToError',
			ReplicateTo = {},
			Tags = {},
		})

		expect(function()
			r:SetReplicateTo('Invalid')
		end).toThrow()
	end)
end)
