<p align="center">
	<img src=".github/logo.svg" height="180" />
</p>

<p align="center">
	Lightweight, efficient Server → Client state replication for Roblox.
</p>

<p align="center">
	<a href="https://github.com/StackyzDev/Replion/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/StackyzDev/Replion?label=release&style=flat-square" /></a>
	<a href="https://wally.run/package/stackyzdev/replion"><img alt="Wally" src="https://img.shields.io/badge/wally-stackyzdev%2Freplion-blue?style=flat-square" /></a>
	<a href="https://stackyzdev.github.io/Replion"><img alt="Docs" src="https://img.shields.io/badge/docs-moonwave-orange?style=flat-square" /></a>
</p>

---

## Overview

Replion lets you define **channels** of structured data on the server and have them automatically kept in sync on the client. Only changed values are sent over the network, making updates efficient regardless of how large the data table is.

Key features:

- **Typed data** — full Luau generic support (`ServerReplion<D>`, `ClientReplion<D>`)
- **Granular signals** — `Changed`, `Observe`, `DataChanged`, `Inserted`, `Removed`, `KeyAdded`, `KeyRemoved`
- **Bandwidth-efficient** — `:Update` sends only the diff; `:Set` on deep paths is handled atomically
- **Immutable internals** — backed by [Freeze](https://github.com/duckarmor/freeze) for safe data management
- **Flexible targeting** — replicate to a single player, a list of players, or everyone

---

## Installation

### Wally

Add Replion to your `wally.toml`:

```toml
[dependencies]
Replion = "stackyzdev/replion@2.0.1"
```

Then run:

```sh
wally install
```

### Manual

Download the latest `.rbxm` from [Releases](https://github.com/StackyzDev/Replion/releases) and place it in `ReplicatedStorage`.

---

## Quick Start

### Server

```lua
local Players = game:GetService('Players')
local Replion = require(ReplicatedStorage.Replion)

type PlayerData = {
	Coins: number,
	Level: number,
	Inventory: { [string]: boolean },
}

local function onPlayerAdded(player: Player)
	local replion: Replion.ServerReplion<PlayerData> = Replion.Server.new({
		Channel    = 'PlayerData',
		ReplicateTo = player,
		Data = {
			Coins     = 0,
			Level     = 1,
			Inventory = {},
		},
	})

	-- Listen for changes server-side
	replion:Changed('Coins', function(new, old)
		print(player.Name, 'coins:', old, '->', new)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
```

### Client

```lua
local Replion = require(ReplicatedStorage.Replion)

Replion.Client:AwaitReplion('PlayerData', function(replion)
	-- Read current value
	print('Coins:', replion:Get('Coins'))

	-- React to future changes
	replion:Changed('Coins', function(new: number, old: number)
		print('Coins changed:', old, '->', new)
	end)

	-- Observe immediately + on change
	replion:Observe('Level', function(level: number)
		print('Current level:', level)
	end)
end)
```

---

## Mutating Data

All mutations are server-side only. Changes are automatically replicated to subscribed clients.

### `:Set` — set a single value

```lua
replion:Set('Coins', 500)
replion:Set('Inventory.Sword', true)

-- Remove a key by setting it to Replion.None
replion:Set('Inventory.OldItem', Replion.None)
```

### `:Update` — merge-update a dictionary (bandwidth-efficient)

Only the keys that actually changed are sent to the client.

```lua
replion:Update('Inventory', function(inv)
	return Freeze.Dictionary.merge(inv, {
		Sword  = true,
		Shield = true,
		Junk   = Replion.None,  -- removes 'Junk'
	})
end)
```

### `:Increase` / `:Decrease`

```lua
replion:Increase('Coins', 100)
replion:Decrease('Coins', 50)
```

### `:Insert` / `:Remove` / `:Clear` — arrays

```lua
replion:Insert('Queue', 'PlayerA')        -- append
replion:Insert('Queue', 'VIP', 1)         -- prepend

local item = replion:Remove('Queue')      -- pop last
local first = replion:Remove('Queue', 1)  -- pop first

replion:Clear('Queue')                    -- empty the array
```

---

## Signals

### Value signals

| Method | When it fires |
|---|---|
| `:Changed(path, cb)` | Value at `path` changes |
| `:Observe(path, cb)` | Immediately + on every change |
| `:DataChanged(cb)` | Any part of the data changes |

### Array signals

| Method | When it fires |
|---|---|
| `:Inserted(path, cb)` | `:Insert` is called |
| `:Removed(path, cb)` | `:Remove` is called |

### Dictionary signals

| Method | When it fires |
|---|---|
| `:KeyAdded(path, cb)` | A new key appears in the dict at `path` |
| `:KeyRemoved(path, cb)` | A key is removed from the dict at `path` |

`KeyAdded`/`KeyRemoved` fire for `:Update` operations **and** for deep `:Set` paths — e.g. `Set('Inventory.Swords.Current', ...)` fires `KeyAdded` on `'Inventory'` if `Swords` didn't exist before.

---

## Reading Data

```lua
-- Returns nil if not found
local coins: number? = replion:Get('Coins')

-- Throws if not found (optional custom message)
local level: number = replion:GetExpect('Level')
local gems: number  = replion:GetExpect('Gems', 'No gems!')

-- Dictionary helpers
local keys   = replion:GetKeys('Inventory')    -- { 'Sword', 'Bow' }
local values = replion:GetValues('Inventory')  -- { true, true }

-- Array search
local index, item = replion:Find('Queue', 'PlayerA')
```

---

## Subscription Management (Server)

Control which players receive a Replion's data at runtime:

```lua
replion:Subscribe(player)       -- add one player
replion:Unsubscribe(player)     -- remove one player
replion:SubscribeAll()          -- add all currently connected players
replion:UnsubscribeAll()        -- remove everyone
replion:Replicate()             -- set ReplicateTo = 'All' (includes future joiners)

replion:IsSubscribed(player)    -- boolean
replion:GetSubscribers()        -- { Player }

-- React to subscription changes
replion:PlayerSubscribed(function(player) end)
replion:PlayerUnsubscribed(function(player) end)
replion:ObserveSubscribers(function(player) end)  -- immediate + future
```

---

## Lifecycle

```lua
replion:BeforeDestroy(function()
	-- fires synchronously before destruction
	-- Data is still accessible here
end)

replion:AfterDestroy(function()
	-- fires after all signals are disconnected
end)

replion:Destroy()
```

On the server, a Replion is automatically destroyed when `ReplicateTo` is a single player and that player leaves — unless `DisableAutoDestroy = true` is set in the config.

---

## Server Manager

```lua
-- Get a single-player channel
local replion = Replion.Server:GetReplionFor(player, 'PlayerData')

-- Get a shared channel (errors if multiple exist)
local worldReplion = Replion.Server:GetReplion('WorldState')

-- Yield until created
local r = Replion.Server:WaitReplion('WorldState', 10)  -- optional timeout

-- Async callback
Replion.Server:AwaitReplion('WorldState', function(r)
	print('World state ready')
end)

-- Listen for any new Replion
Replion.Server:ReplionAdded(function(channel, replion)
	print('Created:', channel)
end)
```

## Client Manager

```lua
-- Async — preferred
Replion.Client:AwaitReplion('PlayerData', function(replion) end)

-- Yield
local replion = Replion.Client:WaitReplion('PlayerData')

-- Immediate (nil if not yet received)
local replion = Replion.Client:GetReplion('PlayerData')

-- By tag
Replion.Client:ReplionAddedWithTag('Player', function(replion) end)
Replion.Client:ReplionRemovedWithTag('Player', function(replion) end)
```

---

## Documentation

Full API reference: **[stackyzdev.github.io/Replion](https://stackyzdev.github.io/Replion)**

---

## License

MIT
