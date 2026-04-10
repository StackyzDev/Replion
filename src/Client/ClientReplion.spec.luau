--!nocheck
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)

local expect = JestGlobals.expect
local describe = JestGlobals.describe
local it = JestGlobals.it
local beforeEach = JestGlobals.beforeEach
local jest = JestGlobals.jest

local Freeze
local ClientReplion

beforeEach(function()
	jest.resetModules()

	Freeze = require(ReplicatedStorage.Packages.Freeze)
	ClientReplion = require(script.Parent.ClientReplion)
end)

-- serialized format: { packedId, channel, data, replicateTo, tags }
local function newReplion(channel: string, data: any)
	return ClientReplion.new({ nil, channel, data, 'All', {} })
end

-- ---------------------------------------------------------------------------

describe('ClientReplion.new', function()
	it('should return a table', function()
		local r = newReplion('new', { Coins = 20 })

		expect(type(r)).toBe('table')
	end)

	it('should store Data, Tags and ReplicateTo from the serialized payload', function()
		local r = ClientReplion.new({ nil, 'newPayload', { Coins = 20 }, 'All', { 'tag1' } })

		expect(r.Data).toEqual({ Coins = 20 })
		expect(r.ReplicateTo).toBe('All')
		expect(r.Tags).toEqual({ 'tag1' })
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:Destroy', function()
	it('should set Destroyed to true', function()
		local r = newReplion('Destroy', { Coins = 20 })

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
	end)

	it('should call BeforeDestroy callback', function()
		local r = newReplion('BeforeDestroy', { Coins = 20 })

		local fnMock = jest.fn()

		r:BeforeDestroy(fnMock)
		r:Destroy()

		expect(fnMock).toHaveBeenCalledTimes(1)
	end)

	it('should disconnect all connections', function()
		local r = newReplion('DestroyConnections', {})

		local connections = {
			r:Changed('key', function() end),
			r:DataChanged(function() end),
			r:BeforeDestroy(function() end),
		}

		r:Destroy()

		for _, connection in connections do
			expect(connection.Connected).toBe(false)
		end
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:Get', function()
	it('should return a top-level value', function()
		local r = newReplion('Get', { Foo = true, A = { B = { [1] = 'Bar' } } })

		expect(r:Get('Foo')).toBe(true)
	end)

	it('should return a nested value via table path', function()
		local r = newReplion('GetNested', { A = { B = { [1] = 'Bar' } } })

		expect(r:Get({ 'A', 'B', 1 })).toBe('Bar')
	end)

	it('should return nil for a missing key', function()
		local r = newReplion('GetMissing', {})

		expect(r:Get('Missing')).toBeNil()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:GetExpect', function()
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

describe('ClientReplion:GetKeys', function()
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

describe('ClientReplion:GetValues', function()
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

describe('ClientReplion:_set', function()
	it('should set a top-level value', function()
		local r = newReplion('Set', {})

		r:_set('Foo', true)

		expect(r:Get('Foo')).toBe(true)
	end)

	it('should set a nested value via dot path', function()
		local r = newReplion('SetNested', { A = { B = { C = true } } })

		r:_set('A.B.C', false)

		expect(r:Get('A.B.C')).toBe(false)
	end)

	it('should call Changed on the set path', function()
		local r = newReplion('SetChanged', {})

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:_set('Foo', true)

		expect(fnMock).toHaveBeenCalledWith(true, nil)
	end)

	it('should fire KeyAdded when a new key is created', function()
		local r = newReplion('SetKeyAdded', {})

		local fnMock = jest.fn()

		r:KeyAdded('__root', fnMock)
		r:_set('NewKey', 42)

		expect(fnMock).toHaveBeenCalledWith('NewKey', 42)
	end)

	it('should fire KeyAdded for each intermediate table created by a deep path', function()
		local r = newReplion('SetKeyAddedDeep', {})

		local rootMock = jest.fn()
		local invMock = jest.fn()

		r:KeyAdded('__root', rootMock)
		r:KeyAdded('Inventory', invMock)

		r:_set('Inventory.Swords.Current', 5)

		expect(rootMock).toHaveBeenCalledWith('Inventory', r:Get('Inventory'))
		expect(invMock).toHaveBeenCalledWith('Swords', r:Get('Inventory.Swords'))
	end)

	it('should fire KeyRemoved when a key is set to None', function()
		local r = newReplion('SetKeyRemoved', { Coins = 10 })

		local fnMock = jest.fn()

		r:KeyRemoved('__root', fnMock)
		r:_set('Coins', Freeze.None)

		expect(fnMock).toHaveBeenCalledWith('Coins', 10)
	end)

	it('should be a no-op when the value has not changed', function()
		local r = newReplion('SetNoOp', { Foo = true })

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:_set('Foo', true)

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:_update', function()
	it('should merge changed values at the root', function()
		local r = newReplion('Update', { Foo = true })

		r:_update({ Foo = false, Bar = 1 })

		expect(r:Get('Foo')).toBe(false)
		expect(r:Get('Bar')).toBe(1)
	end)

	it('should merge changed values at a nested path', function()
		local r = newReplion('UpdateNested', { Items = { Sword = false } })

		r:_update('Items', { Sword = true })

		expect(r:Get('Items.Sword')).toBe(true)
	end)

	it('should remove a key when the value is SerializedNone', function()
		local r = newReplion('UpdateRemove', { Items = { Sword = true } })

		r:_update('Items', { Sword = '\0' })

		expect(r:Get('Items.Sword')).toBeNil()
	end)

	it('should call Changed for updated keys', function()
		local r = newReplion('UpdateChanged', { Foo = true })

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:_update({ Foo = false })

		expect(fnMock).toHaveBeenCalledWith(false, true)
	end)

	it('should fire KeyAdded when a new key arrives via _update', function()
		local r = newReplion('UpdateKeyAdded', { Items = {} })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:_update('Items', { Sword = true })

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should fire KeyRemoved when a key is removed via SerializedNone', function()
		local r = newReplion('UpdateKeyRemoved', { Items = { Sword = true } })

		local fnMock = jest.fn()

		r:KeyRemoved('Items', fnMock)
		r:_update('Items', { Sword = '\0' })

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should not fire KeyAdded for an existing key that changed value', function()
		local r = newReplion('UpdateKeyAddedExisting', { Items = { Sword = false } })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:_update('Items', { Sword = true })

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:_increase / _decrease', function()
	it('should increase a number value', function()
		local r = newReplion('Increase', { Foo = 1 })

		r:_increase('Foo', 2)

		expect(r:Get('Foo')).toBe(3)
	end)

	it('should decrease a number value', function()
		local r = newReplion('Decrease', { Foo = 10 })

		r:_decrease('Foo', 3)

		expect(r:Get('Foo')).toBe(7)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:_insert', function()
	it('should insert at a given index', function()
		local r = newReplion('Insert', { Array = { 1, 3 } })

		r:_insert('Array', 2, 2)

		expect(r:Get('Array')).toEqual({ 1, 2, 3 })
	end)

	it('should append when no index is given', function()
		local r = newReplion('InsertAppend', { Array = { 1, 2 } })

		r:_insert('Array', 3)

		expect(r:Get('Array')).toEqual({ 1, 2, 3 })
	end)

	it('should call Inserted with index and value', function()
		local r = newReplion('InsertCallback', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Inserted('Array', fnMock)
		r:_insert('Array', 2, 4)

		expect(fnMock).toHaveBeenCalledWith(4, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:_remove', function()
	it('should remove at a given index', function()
		local r = newReplion('Remove', { Array = { 1, 2, 3 } })

		r:_remove('Array', 2)

		expect(r:Get('Array')).toEqual({ 1, 3 })
	end)

	it('should remove from the end when no index is given', function()
		local r = newReplion('RemoveLast', { Array = { 1, 2, 3 } })

		local value = r:_remove('Array')

		expect(value).toBe(3)
		expect(r:Get('Array')).toEqual({ 1, 2 })
	end)

	it('should call Removed with index and value', function()
		local r = newReplion('RemoveCallback', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Removed('Array', fnMock)
		r:_remove('Array', 2)

		expect(fnMock).toHaveBeenCalledWith(2, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:_clear', function()
	it('should clear the array', function()
		local r = newReplion('Clear', { Array = { 1, 2, 3 } })

		r:_clear('Array')

		expect(r:Get('Array')).toEqual({})
	end)

	it('should call Changed with an empty table', function()
		local r = newReplion('ClearChanged', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Changed('Array', fnMock)
		r:_clear('Array')

		expect(fnMock).toHaveBeenCalledWith({}, { 1, 2, 3 })
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:Find', function()
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

describe('ClientReplion:Changed', function()
	it('should fire when a value changes', function()
		local r = newReplion('Changed', {})

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:_set('Foo', true)

		expect(fnMock).toHaveBeenCalledWith(true, nil)
	end)

	it('should fire for an ancestor when a nested value changes', function()
		local r = newReplion('ChangedNested', { A = { B = { C = true } } })

		local fnMock = jest.fn()

		r:Changed('A', fnMock)

		r:_set('A.B.C', false)
		r:_set('A.B', { D = true })
		r:_set('A.B.D', false)

		expect(fnMock).toHaveBeenCalledWith({ B = { C = false } }, { B = { C = true } })
		expect(fnMock).toHaveBeenCalledWith({ B = { D = true } }, { B = { C = false } })
		expect(fnMock).toHaveBeenCalledWith({ B = { D = false } }, { B = { D = true } })
	end)

	it('should not fire when value does not change', function()
		local r = newReplion('ChangedNoOp', { Foo = true })

		local fnMock = jest.fn()

		r:Changed('Foo', fnMock)
		r:_set('Foo', true)

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:Observe', function()
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
		r:_set('Coins', 20)

		expect(fnMock).toHaveBeenCalledWith(10, nil)
		expect(fnMock).toHaveBeenCalledWith(20, 10)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:DataChanged', function()
	it('should fire for every mutation', function()
		local r = newReplion('DataChanged', {})

		local fnMock = jest.fn()

		r:DataChanged(fnMock)
		r:_set('Foo', true)
		r:_set('Bar', 1)
		r:_update({ Baz = 2 })

		expect(fnMock).toHaveBeenCalledTimes(3)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:Inserted', function()
	it('should call the callback when a value is inserted', function()
		local r = newReplion('Inserted', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Inserted('Array', fnMock)
		r:_insert('Array', 2, 4)

		expect(fnMock).toHaveBeenCalledWith(4, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:Removed', function()
	it('should call the callback when a value is removed', function()
		local r = newReplion('Removed', { Array = { 1, 2, 3 } })

		local fnMock = jest.fn()

		r:Removed('Array', fnMock)
		r:_remove('Array', 2)

		expect(fnMock).toHaveBeenCalledWith(2, 2)
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:KeyAdded', function()
	it('should fire when a new key arrives via _update', function()
		local r = newReplion('KeyAdded', { Items = {} })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:_update('Items', { Sword = true })

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should fire when _set creates a new top-level key', function()
		local r = newReplion('KeyAddedSet', {})

		local fnMock = jest.fn()

		r:KeyAdded('__root', fnMock)
		r:_set('NewKey', 99)

		expect(fnMock).toHaveBeenCalledWith('NewKey', 99)
	end)

	it('should fire for every intermediate table created by a deep _set', function()
		local r = newReplion('KeyAddedDeep', {})

		local rootMock = jest.fn()
		local invMock = jest.fn()

		r:KeyAdded('__root', rootMock)
		r:KeyAdded('Inventory', invMock)

		r:_set('Inventory.Swords.Current', 5)

		expect(rootMock).toHaveBeenCalledWith('Inventory', r:Get('Inventory'))
		expect(invMock).toHaveBeenCalledWith('Swords', r:Get('Inventory.Swords'))
	end)

	it('should not fire for an existing key that was merely updated', function()
		local r = newReplion('KeyAddedExisting', { Items = { Sword = false } })

		local fnMock = jest.fn()

		r:KeyAdded('Items', fnMock)
		r:_update('Items', { Sword = true })

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)

-- ---------------------------------------------------------------------------

describe('ClientReplion:KeyRemoved', function()
	it('should fire when a key is removed via _update with SerializedNone', function()
		local r = newReplion('KeyRemoved', { Items = { Sword = true } })

		local fnMock = jest.fn()

		r:KeyRemoved('Items', fnMock)
		r:_update('Items', { Sword = '\0' })

		expect(fnMock).toHaveBeenCalledWith('Sword', true)
	end)

	it('should fire when _set removes a key with Freeze.None', function()
		local r = newReplion('KeyRemovedSet', { Coins = 10 })

		local fnMock = jest.fn()

		r:KeyRemoved('__root', fnMock)
		r:_set('Coins', Freeze.None)

		expect(fnMock).toHaveBeenCalledWith('Coins', 10)
	end)

	it('should not fire for a key that was merely updated', function()
		local r = newReplion('KeyRemovedNoFire', { Items = { Sword = true } })

		local fnMock = jest.fn()

		r:KeyRemoved('Items', fnMock)
		r:_update('Items', { Sword = false })

		expect(fnMock).never.toHaveBeenCalled()
	end)
end)
