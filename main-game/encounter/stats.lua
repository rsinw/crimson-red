-- encounter/stats.lua — Stat creation and evaluation helpers

local M = {}

function M.newStat(base)  return {base=base, add=0, mult=1} end
function M.get(s)         return (s.base * s.mult) + s.add end

function M.newStats(hp, atk, def, crit)
    return {
        HP          = M.newStat(hp   or 100),
        maxHP       = M.newStat(hp   or 100),
        RES         = M.newStat(1.0),
        BOOST       = M.newStat(1.0),
        DEF         = M.newStat(def  or 5),
        ATK         = M.newStat(atk  or 10),
        CRIT        = M.newStat(crit or 0.10),
        CRIT_DEF    = M.newStat(0.05),
        MOVE_SPEED  = M.newStat(2.5),
        ATK_SPEED   = M.newStat(1.0),
        STAGGER_RES = M.newStat(1.0),
        MAX_STAGGER = M.newStat(50),
        STAGGER_DUR = M.newStat(3),
    }
end

function M.fromSave(ss)
    return {
        HP          = M.newStat(ss.maxHP or 100),
        maxHP       = M.newStat(ss.maxHP or 100),
        RES         = M.newStat(ss.RES   or 1.0),
        BOOST       = M.newStat(ss.BOOST or 1.0),
        DEF         = M.newStat(ss.DEF   or 5),
        ATK         = M.newStat(ss.ATK   or 10),
        CRIT        = M.newStat(ss.CRIT  or 0.10),
        CRIT_DEF    = M.newStat(ss.CRITDEF  or 0.05),
        MOVE_SPEED  = M.newStat(2.5),
        ATK_SPEED   = M.newStat(ss.ATKSPD  or 1.0),
        STAGGER_RES = M.newStat(ss.STAGGERres or 1.0),
        MAX_STAGGER = M.newStat(ss.maxSTAGGER or 50),
        STAGGER_DUR = M.newStat(ss.STAGGERdur or 3),
    }
end

return M
