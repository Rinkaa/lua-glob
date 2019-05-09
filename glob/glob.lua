local m = require 'lpeglabel'
local matcher = require 'glob.matcher'

local function prop(name, pat)
    return m.Cg(m.Cc(true), name) * pat
end

local function object(type, pat)
    return m.Ct(
        m.Cg(m.Cc(type), 'type') *
        m.Cg(pat, 'value')
    )
end

local function expect(p, err)
    return p + m.T(err)
end

local parser = m.P {
    'Main',
    ['Sp']          = m.S(' \t')^0,
    ['Slash']       = m.S('/\\')^1,
    ['Main']        = m.Ct(m.V'Sp' * m.P'{' * m.V'Pattern' * (',' * expect(m.V'Pattern', 'Miss exp after ","'))^0 * m.P'}')
                    + m.Ct(m.V'Pattern')
                    + m.T'Main Failed'
                    ,
    ['Pattern']     = m.Ct(m.V'Sp' * prop('neg', m.P'!') * expect(m.V'Unit', 'Miss exp after "!"'))
                    + m.Ct(m.V'Unit')
                    ,
    ['NeedRoot']    = prop('root', (m.P'.' * m.V'Slash' + m.V'Slash')),
    ['Unit']        = m.V'Sp' * m.V'NeedRoot'^-1 * expect(m.V'Exp', 'Miss exp') * m.V'Sp',
    ['Exp']         = m.V'Sp' * (m.V'FSymbol' + m.V'Slash' + m.V'Word')^0 * m.V'Sp',
    ['Word']        = object('word', m.Ct((m.V'CSymbol' + m.V'Char' - m.V'FSymbol')^1)),
    ['CSymbol']     = object('*',    m.P'*')
                    + object('?',    m.P'?')
                    + object('[]',   m.V'Range')
                    ,
    ['Char']        = object('char', (1 - m.S',{}[]*?/\\')^1),
    ['FSymbol']     = object('**', m.P'**'),
    ['Range']       = m.P'[' * m.Ct(prop('range', m.V'RangeUnit'^0)) * m.P']'^-1,
    ['RangeUnit']   = m.Ct(- m.P']' * m.C(m.P(1)) * (m.P'-' * - m.P']' * m.C(m.P(1)))^-1),
}

local mt = {}
mt.__index = mt
mt.__name = 'glob'

local function copyTable(t)
    local new = {}
    for k, v in pairs(t) do
        new[k] = v
    end
    return new
end

function mt:addPattern(pat)
    if self.options.ignoreCase then
        pat = pat:lower()
    end
    local states, err = parser:match(pat)
    if not states then
        self.errors[#self.errors+1] = {
            pattern = pat,
            message = err
        }
        return
    end
    for _, state in ipairs(states) do
        if state.neg then
            self.refused[#self.refused+1] = matcher(state)
        else
            self.passed[#self.passed+1] = matcher(state)
        end
    end
end

function mt:parsePattern()
    for _, pat in ipairs(self.pattern) do
        self:addPattern(pat)
    end
end

function mt:__call(path)
    if self.options.ignoreCase then
        path = path:lower()
    end
    for _, refused in ipairs(self.refused) do
        if refused:match(path) then
            return false
        end
    end
    for _, passed in ipairs(self.passed) do
        if passed:match(path) then
            return true
        end
    end
    return false
end

return function (pattern, options)
    local self = setmetatable({
        pattern = copyTable(pattern or {}),
        options = copyTable(options or {}),
        passed  = {},
        refused = {},
        errors  = {},
    }, mt)
    self:parsePattern()
    return self
end
