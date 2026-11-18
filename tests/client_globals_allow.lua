-- tests/client_globals_allow.lua — the globals this addon's tracked source calls on purpose that the
-- kit's client name sets do not list (clients-§6, tests/_kit/test_client_globals.lua). One row each,
-- `{ name, reason }`, scoped by `path` to the vendored library that calls it.
return {
  { path = "libs/LibRangeCheck-3.0/", name = "GetInventorySlotInfo",
    reason = "LibRangeCheck-3.0 calls the global in the else-branch of a C_PaperDollInfo.GetInventorySlotInfo presence test" },
  { path = "libs/LibRangeCheck-3.0/", name = "IsItemInRange",
    reason = "LibRangeCheck-3.0's developer helpers (checkItems, checkItemsAtRange, updateMeasurements) call the retired global; this addon never calls them, and the checkers it uses go through C_Item.IsItemInRange" },
}
