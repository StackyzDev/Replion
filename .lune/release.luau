--[[
	Release script for Replion.

	Usage:
		lune run release major   -- 4.0.0 -> 5.0.0
		lune run release minor   -- 4.0.0 -> 4.1.0
		lune run release patch   -- 4.0.0 -> 4.0.1

	What it does:
		1. Reads the current version from wally.toml
		2. Bumps the requested part
		3. Writes the new version back to wally.toml
		4. Commits the version bump
		5. Creates an annotated git tag  vX.Y.Z
		6. Pushes the commit + tag to origin
]]

local process = require('@lune/process')
local fs = require('@lune/fs')

-- ── helpers ──────────────────────────────────────────────────────────────────

local function run(program: string, args: { string }): string
	local result = process.exec(program, args, { stdio = 'forward' })
	if not result.ok then
		error(`Command failed: {program} {table.concat(args, ' ')}\n{result.stderr}`)
	end
	return result.stdout
end

local function readFile(path: string): string
	return fs.readFile(path)
end

local function writeFile(path: string, content: string)
	fs.writeFile(path, content)
end

-- ── version bump ─────────────────────────────────────────────────────────────

local bumpType: string = (process.args[1] or 'patch'):lower()

if bumpType ~= 'major' and bumpType ~= 'minor' and bumpType ~= 'patch' then
	error(`Unknown bump type "{bumpType}". Use: major | minor | patch`)
end

local wallyPath = 'wally.toml'
local wallyContent = readFile(wallyPath)

-- Extract current version
local major, minor, patch = wallyContent:match('version = "(%d+)%.(%d+)%.(%d+)"')
if not major then
	error('Could not find version in wally.toml')
end

major = tonumber(major) :: number
minor = tonumber(minor) :: number
patch = tonumber(patch) :: number

if bumpType == 'major' then
	major += 1
	minor = 0
	patch = 0
elseif bumpType == 'minor' then
	minor += 1
	patch = 0
else
	patch += 1
end

local newVersion = `{major}.{minor}.{patch}`
local newContent = wallyContent:gsub('version = "%d+%.%d+%.%d+"', `version = "{newVersion}"`, 1)

print(`Bumping version to {newVersion}`)
writeFile(wallyPath, newContent)

-- ── git commit + tag + push ───────────────────────────────────────────────────

run('git', { 'add', wallyPath })
run('git', { 'commit', '-m', `chore: release v{newVersion}` })
run('git', { 'tag', '-a', `v{newVersion}`, '-m', `Release v{newVersion}` })
run('git', { 'push', 'origin', 'master' })
run('git', { 'push', 'origin', `v{newVersion}` })

print(`\nReleased v{newVersion} to origin successfully!`)
