-- Photocopy
-- Copyright (c) 2010 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

------------------------------------------------------------
-- IterativeProcessor
------------------------------------------------------------

local IterativeProcessor = photocopy.CreateClass()
photocopy.IterativeProcessor = IterativeProcessor

-- Constructor.
function IterativeProcessor:__construct(data)
    self.Progress = 0
    self.Finished = false
    self.Error = nil
    self.Warnings = {}
    self.NextThinkTime = 0
    self.NextFunc = nil
end

function IterativeProcessor:OnSuccess() end
function IterativeProcessor:OnError() end

function IterativeProcessor:Start(callback, errback)
    if callback then
        self.OnSuccess = callback
        self.OnError = errback
    end
    
    hook.Add("Think", "PhotocopyIterativeProcessor" .. tostring(self), function()
        if CurTime() < self.NextThinkTime then return end
        if not self:Advance() then
            self:Stop()
            self.Finished = true
        end
    end)
end

function IterativeProcessor:Stop()
    hook.Remove("Think", "PhotocopyIterativeProcessor" .. tostring(self))
end

function IterativeProcessor:SetNext(t, func)
    self.NextThinkTime = CurTime() + t
    if func then self.NextFunc = func end
    if func == false then self.NextFunc = nil end
end

function IterativeProcessor:Advance()
    if self:GetError() then return false end
    
    if self.NextFunc then
        self.NextFunc(self)
        return true
    else
        self.Finished = true
        self:OnSuccess()
        return false
    end
end

function IterativeProcessor:IsFinished()
    return self:GetError() ~= nil or self.Finished
end

function IterativeProcessor:SetFinished(finished)
    self.Finished = finished
end

function IterativeProcessor:Warn(msg, ...)
    table.insert(self.Warnings, string.format(msg, unpack({...})))
end

function IterativeProcessor:SetError(err, ...)
    if not self.Error then
        self:OnError(err)
    end
    self.Error = err
end

function IterativeProcessor:GetError()
    return self.Error
end

function IterativeProcessor:GetWarnings()
    return self.Warnings
end

function IterativeProcessor:Complete()
    self:Stop() -- remove hook
    
    -- Warning: Infinite loop check may trigger
    while self:Advance() do end
    
    if self:GetError() then
        return false, self:GetError()
    else
        return true
    end
end

AccessorFunc(IterativeProcessor, "Progress", "Progress")

------------------------------------------------------------
-- Reader
------------------------------------------------------------

local Reader = photocopy.CreateClass(IterativeProcessor)
photocopy.Reader = Reader

-- Constructor.
function Reader:__construct(data)
    IterativeProcessor.__construct(self)
    
    self.Data = data
    self.Clipboard = nil
end

function Reader:GetName() return nil end
function Reader:GetDescription() return nil end
function Reader:GetCreatorName() return nil end
function Reader:GetSaveTime() return nil end
function Reader:GetOriginPos() return Vector(0, 0, 0) end
function Reader:GetOriginAngle() return Angle(0, 0, 0) end

AccessorFunc(Reader, "Clipboard", "Clipboard")

------------------------------------------------------------
-- Writer
------------------------------------------------------------

local Writer = photocopy.CreateClass(IterativeProcessor)
photocopy.Writer = Writer

-- Constructor.
function Writer:__construct(clipboard)
    IterativeProcessor.__construct(self)
    
    self.Clipboard = clipboard
    self.Output = ""
end

function Writer:SetName(name) end
function Writer:SetDescription(desc) end
function Writer:SetCreatorName(name) end
function Writer:SetSaveTime(t) end
function Writer:SetOriginPos(pos) end
function Writer:SetOriginAngle(pos) end

AccessorFunc(Writer, "Output", "Output")

------------------------------------------------------------
-- Buffer
------------------------------------------------------------

local Buffer = photocopy.CreateClass()
photocopy.Buffer = Buffer

-- Constructor.
function Buffer:__construct()
    -- Strings are immutable
    self.Output = {}
end

function Buffer:Write(str)
    table.insert(self.Output, str)
end

function Buffer:GetValue()
    return table.concat(self.Output, "")
end