local process = require('@lune/process')
local fs = require('@lune/fs')

local WALLY_TOML = 'wally.toml'

local function fail(msg: string)
	print(`[release] error: {msg}`)
	process.exit(1)
end

local function bump(version: string, kind: string): string
	local major, minor, patch = string.match(version, '^(%d+)%.(%d+)%.(%d+)$')
	if not (major and minor and patch) then
		fail(`Invalid version format: "{version}"`)
	end

	local maj = tonumber(major) :: number
	local min = tonumber(minor) :: number
	local pat = tonumber(patch) :: number

	if kind == 'major' then
		return `{maj + 1}.0.0`
	elseif kind == 'minor' then
		return `{maj}.{min + 1}.0`
	elseif kind == 'patch' then
		return `{maj}.{min}.{pat + 1}`
	end

	fail(`Unknown release kind "{kind}". Use: patch, minor, major`)
	return version
end

local firstArg = if process.args and #process.args > 0 then process.args[1] else nil
local kind = if firstArg == '--' then process.args[2] else firstArg
if not kind then
	fail('Usage: lune run release -- <patch|minor|major>')
end

if not fs.isFile(WALLY_TOML) then
	fail(`File not found: {WALLY_TOML}`)
end

local content = fs.readFile(WALLY_TOML)

local currentVersion = string.match(content, 'version%s*=%s*"([^"]+)"')
if not currentVersion then
	fail('Could not find version field in wally.toml')
end

local newVersion = bump(currentVersion :: string, kind :: string)
local tag = `v{newVersion}`

local updated = string.gsub(content, '(version%s*=%s*")[^"]+(")', `%1{newVersion}%2`, 1)
fs.writeFile(WALLY_TOML, updated)

print(`Bumped {kind}: {currentVersion} -> {newVersion}`)

local commitResult = process.exec('git', { 'commit', '-am', `chore: release {tag}` }, { stdio = 'forward' })
if commitResult.code ~= 0 then
	fail('git commit failed')
end

local tagResult = process.exec('git', { 'tag', tag }, { stdio = 'forward' })
if tagResult.code ~= 0 then
	fail('git tag failed')
end

print(`Tagged {tag} -- push with: git push && git push --tags`)
