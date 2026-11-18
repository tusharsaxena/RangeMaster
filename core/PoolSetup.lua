local _, NS = ...
-- core/PoolSetup.lua — the LibKa0s-Pool-1.0 seam (library-stack-§7).
--
-- The pool serves the renderer (modules/Container.lua): one KEYED pool of container instances, keyed
-- by container id (the plate anchors of plan Task 6 key theirs by plate token the same way), and one
-- ARRAY pool of spell chips per instance (modules/Elements_Spells.lua), positional and re-dressed on
-- every apply. WoW never frees a frame once created, so a renderer that built fresh frames on every
-- apply would leak for the session; the pool is what keeps a re-apply free.
--
-- WHAT A DEGRADED INSTALL GETS: the same eight members, locally, with the library's contract (the
-- array pool parked backward, so position n gets its object back; the keyed pool refusing to
-- overwrite a live key). A call site that branched on the library's presence would be a call site
-- with a memory leak on one of its two paths. tests/test_surface_parity.lua holds this table to the
-- live library member for member.

local Pool = LibStub and LibStub("LibKa0s-Pool-1.0", true)

if Pool then
    NS.Pool = Pool
    return
end

local function take(pool, factory)
    local o = table.remove(pool.free)
    if not o then o = factory() end
    return o
end

NS.Pool = {
    New = function() return { free = {}, active = {} } end,
    NewKeyed = function() return { free = {}, active = {} } end,

    Acquire = function(pool, factory)
        local o = take(pool, factory)
        pool.active[#pool.active + 1] = o
        o:Show()
        return o
    end,

    -- BACKWARD, as the library parks: Acquire pops the free list from the end, so parking the last
    -- object first hands each position back the object it had.
    ReleaseAll = function(pool, before)
        local active = pool.active
        for i = #active, 1, -1 do
            local o = active[i]
            if before then before(o) end
            o:Hide()
            pool.free[#pool.free + 1] = o
            active[i] = nil
        end
    end,

    Counts = function(pool) return #pool.free, #pool.active end,

    AcquireKeyed = function(pool, key, factory)
        local live = pool.active[key]
        if live then return live end
        local o = take(pool, factory)
        pool.active[key] = o
        o:Show()
        return o
    end,

    ReleaseAllKeyed = function(pool, before)
        local active, free = pool.active, pool.free
        for key, o in pairs(active) do
            if before then before(o, key) end
            o:Hide()
            free[#free + 1] = o
            active[key] = nil
        end
    end,

    CountsKeyed = function(pool)
        local n = 0
        for _ in pairs(pool.active) do n = n + 1 end
        return #pool.free, n
    end,
}
