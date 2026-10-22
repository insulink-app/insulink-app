# Trash

Deleting a meal, drink, weight, HbA1c, cardio training, workout, routine,
exercise or food product keeps a copy in `TrashStore` (`lib/src/trash/`) for
30 days. Profile → Trash lists them and restores one with a tap.

- **Local to the device.** The copy is the entry's own `toJson()`, written by the
  state's remove method before the entry goes. The account loses the entry on
  the next sync as before; the trash is not synced.
- **Restore = add.** `TrashRestorer` hands the entry back through the state's
  normal add path (`addMeal`, `mergeWeights`, `restoreRoutine`, …), so it is
  saved and pushed to the account like a new entry. Weight and HbA1c, which the
  sync deletes server-side by key, are simply created again.
- **Restore first, then take.** A restore that throws leaves the entry in the
  trash.
- Not covered: routine items inside the editor, inventory items, a rejected
  detected training (never was a training).
