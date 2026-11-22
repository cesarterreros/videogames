--!strict
-- SoundController.luau - the client's sound effects and its one looping music track. Every Sound lives in a
-- client-only folder inside SoundService, so nothing here reaches the server: effects are played locally with
-- PlayLocalSound and the music follows the stored Music setting (snapshot.Settings.Music).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundsConfig = require(Shared.Config.Sounds)
local StateController = require(script.Parent.StateController)

local FOLDER_NAME = "CrystalGroveSounds"
local MUSIC_NAME = "Music"

-- PlaybackSpeed bounds for a pitched effect.
local MIN_PITCH = 0.5
local MAX_PITCH = 2

-- Seconds to ignore incoming snapshots after a music tap, so a lagging StateSync reply cannot undo it.
local HOLD_SECONDS = 1.5

local SoundController = {}

-- The Sound instances built by Init, keyed by their config name, and the clock time until which snapshots
-- are ignored because a tap is still settling.
local sounds: { [string]: Sound } = {}
local holdUntil: number = 0

-- Creates the client-only folder of Sound instances. An ID of 0 means "silent", so nothing is built for it.
-- Must not yield.
function SoundController:Init()
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for name, id in SoundsConfig.Ids do
		if id ~= 0 then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = "rbxassetid://" .. tostring(id)

			if name == MUSIC_NAME then
				sound.Looped = true
				sound.Volume = SoundsConfig.MusicVolume
				sound.Playing = false
			else
				sound.Volume = SoundsConfig.EffectsVolume
			end

			sound.Parent = folder
			sounds[name] = sound
		end
	end

	folder.Parent = SoundService
end

-- Plays one effect at an optional pitch. Unknown names (and the music track) are ignored silently.
function SoundController:Play(name: string, pitch: number?)
	if name == MUSIC_NAME then
		return
	end

	local sound = sounds[name]
	if sound == nil then
		return
	end

	local speed: number = if typeof(pitch) == "number" then pitch else 1
	if speed ~= speed then -- NaN would poison PlaybackSpeed
		speed = 1
	end
	sound.PlaybackSpeed = math.clamp(speed, MIN_PITCH, MAX_PITCH)

	-- A failed local play must never break the caller (which may be mid-animation).
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
end

-- Starts or stops the looping music. Does nothing when the config has no music asset.
function SoundController:SetMusic(on: boolean)
	local music = sounds[MUSIC_NAME]
	if music == nil then
		return
	end

	if on then
		if not music.IsPlaying then
			music:Play()
		end
	else
		music:Stop()
	end
end

-- Applies a player's music tap at once and briefly ignores snapshots for it: the server's StateSync reply
-- arrives a moment later, and fast toggling should not flicker.
function SoundController:SetMusicFromTap(on: boolean)
	SoundController:SetMusic(on)
	holdUntil = os.clock() + HOLD_SECONDS
end

-- Follows the stored Music setting, but only once the first snapshot has arrived: a player who muted the
-- music must never hear a single blip.
function SoundController:Start()
	local function onState(data: any)
		if typeof(data) ~= "table" then
			return
		end

		local snapshot: { [string]: any } = data
		if os.clock() < holdUntil then
			return
		end

		-- Default to music on; only an explicit boolean in the settings can mute it.
		local wanted = true
		local settings = snapshot.Settings
		if typeof(settings) == "table" then
			local value: any = settings.Music
			if typeof(value) == "boolean" then
				wanted = value
			end
		end

		SoundController:SetMusic(wanted)
	end

	StateController.Changed:Connect(onState)

	local existing = StateController:Get()
	if existing ~= nil then
		onState(existing)
	end
end

return SoundController
